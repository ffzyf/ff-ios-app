import AVFoundation
import Combine
import Foundation

/// 天气朗读：把一段中文播报稿交给服务端合成，再用 `AVPlayer` 播出来。
///
/// ## 为什么是"服务端合成"而不是 `AVSpeechSynthesizer`
///
/// 用户的诉求是"用我的阿里云百炼额度播报天气"，音色质量是重点。
/// 系统 TTS 的中文音色在这类"读一小段散文"的场景里明显干瘪，而且没法跟着用户的额度走。
/// 所以合成放在服务端（密钥不出服务端），App 只负责发文本、放音频。
///
/// ## 三条纪律
///
/// 1. **不落盘**：返回的是 24 小时有效的预签名直链，`AVPlayer(url:)` 直接流式取。
///    缓存到磁盘只会在第二天早上播一段"昨天的天气"——那是最糟的一类错误（听起来完全正常）。
/// 2. **同一时刻只播一段**：`speak` 开头先 `stop()`，两次点击不会叠成两个声音。
/// 3. **失败说人话**：网络错误 → 「朗读暂时不可用」；服务端给了 `error.message` 就原样用它
///    （后端已经写好人话，App 不要二次翻译）。文案直接可以上屏，调用方不做映射。
///
/// ## 只在主 App 里
///
/// Widget target 只编译 `Sources/Widget` + `Sources/Shared`，而 `Sources/Services` 整个目录
/// 不在它的 sources 里 —— 所以本文件里的 `AVAudioSession` / `AVPlayer` 不会被小组件拖进去。
@MainActor
final class SpeechStore: ObservableObject {

    /// 全 App 唯一实例。写作方式与 `WeatherStore.shared` / `LocationStore.shared` 一致：
    /// 页面用 `@ObservedObject` 观察它，不依赖环境对象注入（`SkyRoomView` 是模态呈现的）。
    static let shared = SpeechStore()

    // MARK: - 状态

    enum State: Equatable {
        /// 没在播
        case idle
        /// 已请求、等服务端合成
        case preparing
        /// 正在播
        case playing
        /// 失败。关联值是一句直接可上屏的中文
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// 这一句是不是用户主动点出来的（用于按钮态：喇叭 ↔ 停止）
    var isBusy: Bool { state == .preparing || state == .playing }

    /// 失败文案（没有失败就是 nil）。给页面一行小字用，不用自己 switch
    var failureText: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    // MARK: - 常量

    /// 音色。与后端约定的默认值（阿里云百炼的 Cherry）
    private static let voice = "Cherry"
    /// 请求超时（秒）。比普通 GET 长：服务端要跑一次合成，12 秒是"该回来了"的分界
    private static let timeout: TimeInterval = 12
    /// 稿件字符上限。后端超过 600 字会拒，这里先夹住 —— 用户听到 600 字之前早就走了，
    /// 但夹一次能保证"再怎么也不会因为超长而失败"
    private static let maxCharacters = 600
    /// 播报稿的字符预算（`script(...)` 用）。超过它听感就散了
    static let scriptCharacterLimit = 120
    /// 播放失败的自检延迟（秒）。见 `scheduleStatusCheck()`
    private static let statusCheckDelay: TimeInterval = 1.5

    // MARK: - 内部

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var statusCheck: Task<Void, Never>?
    /// 代次：`stop()` / 新的 `speak()` 都会 +1。
    /// 合成是异步的，用户可能在"等音频"的那几秒里又点了一次停止 —— 回来后必须发现自己已经过期，
    /// 否则会出现"点了停止，2 秒后声音却响起来"这种最让人困惑的 bug。
    private var generation: Int = 0

    // MARK: - 播报

    /// 播一段文本。空文本直接返回（不报错：调用方已经做了"缺什么就不说那句"）。
    ///
    /// `await` 在**开始播放**那一刻返回，不等音频放完 —— 按钮的点击任务不该挂 30 秒。
    func speak(_ text: String) async {
        let spoken = String(text.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Self.maxCharacters))
        guard !spoken.isEmpty else { return }

        // 上一段（含还在合成的）先收掉
        stop()
        generation += 1
        let token = generation
        state = .preparing

        do {
            let url = try await requestAudioURL(for: spoken)
            // 等音频的这段时间里用户可能已经点了停止 / 已经开了新的一段
            guard token == generation, state == .preparing else { return }
            start(url: url)
        } catch let error as SpeechFailure {
            guard token == generation else { return }
            state = .failed(error.message)
            deactivateSession()
        } catch {
            guard token == generation else { return }
            state = .failed("朗读暂时不可用")
            deactivateSession()
        }
    }

    /// 停止（暂停 + 清播放器 + 回到空闲）。重复调用安全。
    func stop() {
        generation += 1
        teardown()
        state = .idle
        deactivateSession()
    }

    // MARK: - 请求

    /// 一个只在本文件里用的失败类型：`message` 已经是人话，直接上屏
    private struct SpeechFailure: Error {
        let message: String
    }

    /// `POST /api/app/tts` → 预签名直链
    /// - Parameter text: 已 trim 过的播报稿（非空、不超过 600 字）
    private func requestAudioURL(for text: String) async throws -> URL {
        guard let endpoint = API.tts() else {
            throw SpeechFailure(message: "朗读暂时不可用")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 合成结果与"这一句文本"绑定：任何中间层缓存都只会拿到别人的音频
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard let body = try? JSONEncoder().encode(RequestBody(text: text, voice: Self.voice)) else {
            throw SpeechFailure(message: "朗读暂时不可用")
        }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // 超时 / 断网 / 取消：对用户是同一件事 —— 这一句没念出来
            throw SpeechFailure(message: "朗读暂时不可用")
        }

        // 业务信封优先：4xx / 5xx 时后端也常常带 `{ok:false, error:{message}}`，
        // 那句 message 比"朗读暂时不可用"精确得多，能读到就用它
        let envelope = try? JSONDecoder().decode(Response.self, from: data)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if let message = Self.cleanMessage(envelope?.error?.message) {
                throw SpeechFailure(message: message)
            }
            throw SpeechFailure(message: "朗读暂时不可用")
        }

        if let message = Self.cleanMessage(envelope?.error?.message) {
            throw SpeechFailure(message: message)
        }
        guard let envelope, envelope.ok,
              let raw = envelope.url,
              let url = URL(string: raw),
              !raw.isEmpty else {
            throw SpeechFailure(message: "朗读暂时不可用")
        }
        return url
    }

    // MARK: - 播放

    /// 起播：开会话 → 造播放器 → 挂通知 → play
    private func start(url: URL) {
        activateSession()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        observe(item: item)
        player.play()
        state = .playing
        scheduleStatusCheck()
    }

    /// 播完 / 播挂的通知。两条都挂在**这一个 item** 上：换一段音频时旧通知随 item 一起作废。
    private func observe(item: AVPlayerItem) {
        let center = NotificationCenter.default

        endObserver = center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                        object: item,
                                        queue: .main) { [weak self] _ in
            // 通知闭包不是 `@MainActor` 的，显式跳一次再改状态（本类是 @MainActor）
            Task { @MainActor in
                self?.finishPlayback()
            }
        }

        failureObserver = center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                                            object: item,
                                            queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.failPlayback()
            }
        }
    }

    /// `AVPlayerItem.status` 在 `play()` 那一刻还是 `.unknown`，所以延迟一秒半再看一眼。
    ///
    /// 预签名直链过期、403、音频编码解不开 —— 这三种都不会发"播到结尾"的通知，
    /// 状态会静默停在 `.failed`，界面上就是"点了喇叭，没声音，按钮还一直显示停止"。
    /// 一次延迟检查就够，不引入 KVO（`observe(\.status)` 要管生命周期，收益不值那个复杂度）。
    private func scheduleStatusCheck() {
        statusCheck?.cancel()
        statusCheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.statusCheckDelay))
            guard !Task.isCancelled, let self else { return }
            guard case .playing = self.state else { return }

            if let item = self.player?.currentItem, item.status == .failed {
                self.failPlayback()
                return
            }
            // 时间一个都没往前走 = 根本没起来（`currentTime()` 解不开时是 NaN，比较恒为 false，安全）
            if let player = self.player,
               player.timeControlStatus == .paused,
               player.currentTime().seconds <= 0 {
                self.failPlayback()
            }
        }
    }

    /// 正常播完
    private func finishPlayback() {
        teardown()
        state = .idle
        deactivateSession()
    }

    /// 播放失败
    private func failPlayback() {
        teardown()
        state = .failed("播放失败")
        deactivateSession()
    }

    /// 拆播放器与通知（不动 `state`，由调用方决定是 `.idle` 还是 `.failed`）
    private func teardown() {
        statusCheck?.cancel()
        statusCheck = nil

        player?.pause()
        player = nil

        let center = NotificationCenter.default
        if let observer = endObserver {
            center.removeObserver(observer)
            endObserver = nil
        }
        if let observer = failureObserver {
            center.removeObserver(observer)
            failureObserver = nil
        }
    }

    // MARK: - 音频会话

    /// 播报期间的会话：`.playback` + `.spokenAudio`。
    ///
    /// **这两条是必须的**：`.playback` 让声音不受静音键影响（播报类 App 的通行做法，
    /// 用户按了静音也期待"我主动点的朗读"能出声）；`.spokenAudio` 告诉系统这是人声，
    /// 打断策略、音量曲线按语音处理，而不是按音乐。
    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true, options: [])
    }

    /// 播完把会话还回去：`.ambient` 不打断别人，用户自己的音乐能继续响。
    /// 顺序是"先释放激活、再改分类"—— 反过来会把别人刚恢复的音频再抢一次。
    private func deactivateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        try? session.setCategory(.ambient, mode: .default, options: [])
    }

    // MARK: - 请求体 / 响应信封

    /// `{"text": "...", "voice": "Cherry"}`
    private struct RequestBody: Encodable {
        let text: String
        let voice: String
    }

    /// `{"ok":true,"url":"…","chars":123}` / `{"ok":false,"error":{"code":"…","message":"…"}}`
    ///
    /// 全部可选（`ok` 除外）：服务端"空值不占位"，缺字段是正常形态，不是错误。
    /// `chars` 我们不关心，所以不解 —— 少一个字段就少一处会漂的契约。
    private struct Response: Decodable {
        let ok: Bool
        let url: String?
        let error: Err?

        struct Err: Decodable {
            let code: String?
            let message: String?
        }

        private enum CodingKeys: String, CodingKey {
            case ok
            case url
            case error
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // `ok` 缺失按失败算：拿不准成功就不播，避免把一份空响应当成"合成好了"
            ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
            url = try? container.decode(String.self, forKey: .url)
            error = try? container.decode(Err.self, forKey: .error)
        }
    }

    // MARK: - 播报稿（纯函数）

    /// 拼一段口语播报稿：天气 + 天光阶段 + 红石下一场 + 今日宜忌。
    ///
    /// ## 纪律
    ///
    /// 1. **缺什么就不说那句**（绝不编）：没有天气就不提天气，没有红石数据就不提红石；
    /// 2. **纯函数**：不读 `Date()`、不读任何 Store、不碰网络 —— 入参就是全部输入，
    ///    所以这条规则可以被预览和自检直接调（`now` 显式传入，就是为了这个）；
    /// 3. **总长 ≤ 120 字**（`scriptCharacterLimit`）：超过这个长度用户就听不下去了。
    ///    实现是"按优先级往句子里加，加不下就停在上一句"，而不是按字数硬切 ——
    ///    硬切会把最后一句切成半个词，念出来更糟。
    ///
    /// 优先级就是句子的顺序：天光 → 天气 → 高低温 → 红石 → 宜忌。
    ///
    /// - Parameters:
    ///   - now: 播报的参照时刻（算"还有多少分钟日落"用）
    ///   - phase: 此刻的天光阶段。**必须已过天气门控**
    ///     （`SunClock.phase(at:).effective(viewing:)`）—— 阴天念出「现在是蓝调时刻」
    ///     和顶栏写「蓝调剩余」是同一种假话，本函数只负责按给定阶段说话，不做第二套判定
    ///   - viewing: 那份天气判定本身（`nil` = 没有数据）。只服务一件事：**换词**。
    ///     `phase` 过完门控只能解决"配色骗人"，解决不了"词骗人" —— 阴天蓝调不降级
    ///     （天色仍是蓝灰），于是 `phase` 还是 `.blueDusk`，照原文念就是「现在是蓝调时刻」。
    ///     所以判定要一起传进来，念稿才和顶栏的「入夜剩余」对上。
    ///   - weather: 天气实况（nil = 还没拿到；此时整句天气都不说）
    ///   - sunTimes: 今天的日出日落（nil = 算不出；天光那句就只说阶段名）
    ///   - nextRedstone: 下一场红石（label = 「今日」/「周六」/「11月6日」，time = `"10:08"`
    ///     —— 两种都是现成的展示串，不再二次加工）
    ///   - yi: 今日宜（前两项会上屏）
    ///   - ji: 今日忌（只取第一项：忌说太多像在念条文）
    ///   - place: 地名（`"郑州"`；nil 就不说地名，直接报温度）
    /// - Returns: 一段可以直接交给 `speak(_:)` 的中文
    static func script(now: Date,
                       phase: SkyPhase,
                       viewing: SkyViewing.Verdict? = nil,
                       weather: WeatherNow?,
                       sunTimes: (sunrise: Date?, sunset: Date?)?,
                       nextRedstone: (label: String, time: String, map: String)?,
                       yi: [String],
                       ji: [String],
                       place: String? = nil) -> String {

        let sentences: [String] = [
            phaseSentence(now: now, phase: phase, viewing: viewing, sunTimes: sunTimes),
            weatherSentence(weather, place: place),
            rangeSentence(weather),
            redstoneSentence(nextRedstone),
            luckSentence(yi: yi, ji: ji)
        ].compactMap { $0 }

        return trimmed(sentences)
    }

    // MARK: ① 天光

    /// "现在是黄金时刻，还有 42 分钟日落。"
    ///
    /// 只在天光阶段上说人话：阶段名本身已经是中文（`SkyPhase.label`），
    /// 但"距离日落"那几个字在各档的语义不一样（白天数是日落、夜里数是日出），
    /// 所以这里逐档写死，而不是拼一句通用模板 —— 模板会写出"距离日落还有 8 小时"以外的怪话。
    ///
    /// 蓝调两档多一道换词：阴天蓝调**不降级**
    /// （见 `SkyPhase.effective` —— 天色仍是蓝灰，错只在那个词），所以 `phase`
    /// 还是 `.blueDusk`，照原文念就会把「蓝调时刻」念出来。这里换成纯事件的说法：
    /// 太阳几点落山、暮光几点结束，阴天照样成立，耳朵也能用日历验证。
    ///
    /// - Parameter viewing: 天气判定。判据复用 `SkyPhase.claimsColor(viewing:)` ——
    ///   **白名单**（通透了才敢说颜色），`nil`（没有数据）归到"不说颜色"那一边。
    ///   这里不再自己写一遍 `viewing == .blocked`：屏幕上的词与耳朵里的词必须是
    ///   同一个判据算出来的，否则就成了"同一句话两套标准"。
    private static func phaseSentence(now: Date,
                                      phase: SkyPhase,
                                      viewing: SkyViewing.Verdict?,
                                      sunTimes: (sunrise: Date?, sunset: Date?)?) -> String {
        let sunrise = sunTimes?.sunrise
        let sunset = sunTimes?.sunset
        // 天是通的（通透 / 有多云轻霾）→ 敢说颜色；被封死或没数据 → 只说时间
        let colorOK = phase.claimsColor(viewing: viewing)

        switch phase {
        case .night:
            if let minutes = remainingMinutes(to: sunrise, from: now) {
                return "现在是夜间，距离日出还有 \(spokenMinutes(minutes))。"
            }
            return "现在是夜间。"
        case .blueDawn:
            if colorOK {
                if let minutes = remainingMinutes(to: sunrise, from: now) {
                    return "天边正蓝，还有 \(spokenMinutes(minutes)) 日出。"
                }
                return "天边正蓝，天快亮了。"
            }
            // 换词不换时间：日出的时刻与阴晴无关
            if let minutes = remainingMinutes(to: sunrise, from: now) {
                return "天快亮了，还有 \(spokenMinutes(minutes)) 日出。"
            }
            return "天快亮了。"
        case .sunrise:
            if let minutes = remainingMinutes(to: sunset, from: now) {
                return "太阳刚出来，距离日落还有 \(spokenMinutes(minutes))。"
            }
            return "太阳刚出来。"
        case .golden:
            // 「黄金」是在承诺颜色。只有确认通透才敢念；其余（多云 / 阴 / 还没数据）
            // 退到 `.day` 那一句 —— 与 `effective` 把 golden 降成 day 的结果**同一句话**，
            // 于是屏幕上的词与嘴里的词不会各说一套
            guard viewing == .clear else {
                return phaseSentence(now: now, phase: .day, viewing: viewing, sunTimes: sunTimes)
            }
            if let minutes = remainingMinutes(to: sunset, from: now) {
                return "现在是黄金时刻，还有 \(spokenMinutes(minutes)) 日落。"
            }
            return "现在是黄金时刻，天边正在变暖。"
        case .day:
            if let minutes = remainingMinutes(to: sunset, from: now) {
                return "现在是白天，距离日落还有 \(spokenMinutes(minutes))。"
            }
            return "现在是白天。"
        case .sunset:
            if let minutes = remainingMinutes(to: sunset, from: now) {
                return "太阳快落了，还有 \(spokenMinutes(minutes)) 日落。"
            }
            return "太阳快落了。"
        case .blueDusk:
            if colorOK {
                return "太阳已经落山，天边还是蓝的。"
            }
            return "太阳已经落山，天正在黑下来。"
        }
    }

    // MARK: ② 天气

    /// "郑州 15 度，晴间多云，风不大。"
    private static func weatherSentence(_ weather: WeatherNow?, place: String?) -> String? {
        guard let weather, weather.ok else { return nil }

        var head: [String] = []
        if let place = cleanText(place) {
            head.append(place)
        }
        if let temp = weather.temp, temp.isFinite {
            head.append("\(Int(temp.rounded())) 度")
        }

        var details: [String] = []
        // 服务端的中文描述比八档类型细一档（"晴间多云" vs "多云"），优先用它
        if let phrase = cleanText(weather.text) ?? weather.kind?.title {
            details.append(phrase)
        }
        if let wind = weather.wind, wind.isFinite {
            details.append(windPhrase(wind))
        }

        guard !head.isEmpty || !details.isEmpty else { return nil }

        var sentence = head.joined(separator: " ")
        if !details.isEmpty {
            sentence += (sentence.isEmpty ? "" : "，") + details.joined(separator: "，")
        }
        return sentence + "。"
    }

    /// 风力三档。用 `wind`（m/s）而不是风向：播报里"风不大"比"西西北风"有用得多
    private static func windPhrase(_ wind: Double) -> String {
        if wind < 3 { return "风不大" }
        if wind < 8 { return "有点风" }
        return "风挺大"
    }

    /// "今天最低 10 度，最高 16 度。"（缺一头就整句不说）
    private static func rangeSentence(_ weather: WeatherNow?) -> String? {
        guard let weather, weather.ok,
              let low = weather.tMin, let high = weather.tMax,
              low.isFinite, high.isFinite, high >= low else { return nil }
        return "今天最低 \(Int(low.rounded())) 度，最高 \(Int(high.rounded())) 度。"
    }

    // MARK: ③ 红石

    /// "下一次红石在周六上午 10 点 08 分，禁阁的星漠水母湾。"
    private static func redstoneSentence(_ next: (label: String, time: String, map: String)?) -> String? {
        guard let next, let clock = spokenClock(next.time) else { return nil }
        let label = cleanText(next.label) ?? ""
        var sentence = "下一次红石在" + label + clock
        if let map = cleanText(next.map) {
            sentence += "，" + map
        }
        return sentence + "。"
    }

    /// `"10:08"` → `"上午 10 点 08 分"`。解不开（脏数据）返回 nil，整句不说
    private static func spokenClock(_ raw: String) -> String? {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        let period: String
        switch hour {
        case 0..<6: period = "凌晨"
        case 6..<12: period = "上午"
        case 12: period = "中午"
        case 13..<18: period = "下午"
        default: period = "晚上"
        }

        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        if minute == 0 { return "\(period) \(displayHour) 点" }
        return "\(period) \(displayHour) 点 \(String(format: "%02d", minute)) 分"
    }

    // MARK: ④ 宜忌

    /// "宜散步，忌熬夜。"
    private static func luckSentence(yi: [String], ji: [String]) -> String? {
        let good = yi.compactMap { cleanText($0) }.prefix(2)
        let bad = ji.compactMap { cleanText($0) }.prefix(1)

        var parts: [String] = []
        if !good.isEmpty {
            parts.append("宜" + good.joined(separator: "、"))
        }
        if !bad.isEmpty {
            parts.append("忌" + bad.joined(separator: "、"))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "，") + "。"
    }

    // MARK: ⑤ 小工具

    /// 按顺序拼句子，超预算就停在上一句（见 `script(...)` 纪律 3）
    private static func trimmed(_ sentences: [String]) -> String {
        var result = ""
        for sentence in sentences {
            let candidate = result + sentence
            if candidate.count > scriptCharacterLimit && !result.isEmpty {
                break
            }
            result = candidate
        }
        return result
    }

    /// 距某个时刻还有几分钟。已过点 / 太远（≥ 24 小时）/ 没有这个时刻 → nil（那句话就不说）
    private static func remainingMinutes(to date: Date?, from now: Date) -> Int? {
        guard let date else { return nil }
        let minutes = Int(date.timeIntervalSince(now) / 60)
        guard minutes > 0, minutes < 24 * 60 else { return nil }
        return minutes
    }

    /// `42 分钟` / `1 小时 5 分钟` / `2 小时`
    private static func spokenMinutes(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) 分钟" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分钟"
    }

    /// 空白一律当作"没有这个字段"（服务端清洗过一遍，这里再兜一层）
    private static func cleanText(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 服务端错误文案：空白 → nil（那就用兜底的人话）
    private static func cleanMessage(_ raw: String?) -> String? {
        return cleanText(raw)
    }
}
