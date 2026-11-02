import Foundation
import SwiftUI
import WidgetKit

// MARK: - 深链（点小组件 → 跳进 App 对应页面）

/// 小组件深链的唯一出处。
///
/// 为什么集中在一个 enum 里：scheme / host 是**跨 target 的契约** ——
/// 这头是 `Info.plist` 的 `CFBundleURLTypes` + 小组件的 `.widgetURL(...)`，
/// 那头是 `RootView.onOpenURL`。三处各写一份字符串，改一处忘两处就会出现
/// "点了没反应"这种最难查的 bug。Widget 侧只从这里取 URL，不允许再写字面量。
///
/// 注意 App target **不能**引用本类型（它属于 Widget target），所以 `RootView` 里
/// 有一份只含 scheme + host 映射的同构实现，两边靠注释互相指认。
enum WidgetDeepLink {

    /// URL scheme，必须与 `Resources/Info.plist` 的 `CFBundleURLSchemes` 逐字一致
    static let scheme = "skyapp"

    /// 简报小组件 → 简报 Tab
    static let briefHost = "brief"
    /// 红石小组件 → 红石 Tab
    static let rockHost = "rock"
    /// 沉浸式天光页（3.11.0）。**不是 Tab** —— App 侧会全屏呈现 `SkyRoomView`。
    ///
    /// 为什么把天光 / 日弧 / 月相 / 风 四张卡一起改成它：这四张卡画的都是"此刻的天"
    /// （同一片天空、同一颗太阳、同一轮月亮、同一阵风），点开就该进那个更大的同一片天；
    /// 而 `brief` 是"今天有什么事"，与看天是两件事（用户原话："这个页面就从相关的小组件
    /// 和概览-第二个小组件可以点击今日"）。
    /// App 侧同一份契约在 `RootView.swift` 的 `AppDeepLink.skyHost`，两边必须逐字一致。
    static let skyHost = "sky"

    /// 拼一个合法的深链；拼不出来返回 nil（`.widgetURL` 接受 nil，等于"这张卡不可点"）
    static func url(host: String) -> URL? {
        return URL(string: scheme + "://" + host)
    }

    /// 简报小组件整卡点击目标
    static let brief = url(host: briefHost)
    /// 红石小组件整卡点击目标
    static let rock = url(host: rockHost)
    /// 天光页（天光 / 日弧 / 月相 / 风 四张卡共用）
    static let sky = url(host: skyHost)
}

// MARK: - Timeline 时间刻度

/// Timeline 的「时间刻度」工具。
///
/// 为什么要按刻度铺 entry，而不是"只给一条、靠 `.atEnd` 反复重取"：
/// 简报卡的天色由 `SkyPhase` 的七档决定（夜 / 蓝调 / 日出 / 黄金 / 白天 / 日落 / 蓝调），
/// 档与档之间**没有插值** —— 想让天空"随时间自然过渡"，唯一的办法是让 entry 跟着时间走，
/// 让系统到点自己换上下一帧。Timeline 里的多个 entry 是**预渲染帧**，
/// 不消耗刷新预算（预算算的是「重新跑一次 getTimeline、又发一轮网络请求」），
/// 所以这里是"多帧、少请求"：一天 40 多帧，但真正发请求的只有 2 次。
enum WidgetTimeline {

    /// 简报卡的刻度：**60 分钟**。
    ///
    /// 为什么从 30 分钟放宽到 60 分钟（V3.7）：这张卡的底色不再随时段变色，而是跟着
    /// **当天的天气**走（一天只变一次脸），真正还在"走"的只有轨迹上那颗光点。
    /// WidgetKit 的刷新预算按"每天几十次"算，30 分钟一帧铺 24 小时就是 48 帧 ——
    /// 预算会被这种"看不出差别"的帧吃光，代价是用户在早上 8 点看不到当天的新简报。
    /// 而云要"飘"根本不需要更高频的唤醒：位移是靠**预排帧**做的（每帧的云位置由这一帧的
    /// 时刻算出来，见 `BriefFace` 的 `BriefWeatherLayer.drift`），到点系统自己换画面。
    static let briefStep: TimeInterval = 60 * 60

    /// 简报卡的视野：**24 小时**（24 帧）。到点 `.atEnd` 再取一轮（含两次网络请求：
    /// 简报 + 天气），一天 1 次，离 iOS 每天 40–70 次的预算上限差着两个数量级。
    ///
    /// 为什么铺满一整天而不是 12 小时：天气一天只有"白天/夜里"和"变天"这几次变化，
    /// 视野短于一天就会出现"用户在晚上 11 点看不到明天早上那一帧"的断档，
    /// 而多出来的帧全是预渲染，不发请求。
    static let briefHorizon: TimeInterval = 24 * 3600

    /// 红石卡的刻度：30 分钟（与简报统一 —— 两张卡并排放在桌面上，刷新节奏不该有两个脾气）
    static let rockStep: TimeInterval = 30 * 60

    /// 红石卡的视野：24 小时（红石一天只变几次，视野放长，请求更省）
    static let rockHorizon: TimeInterval = 24 * 3600

    /// 从 `now` 起按 `step` 等距铺到 `horizon`（含 `now` 本身）。
    ///
    /// 显式防死循环：`step <= 0` 直接退回单帧，游标每轮必须严格前进。
    static func stamps(now: Date, horizon: TimeInterval, step: TimeInterval) -> [Date] {
        guard step > 0, horizon > 0 else { return [now] }
        var result: [Date] = [now]
        var cursor = now.addingTimeInterval(step)
        let limit = now.addingTimeInterval(horizon)
        while cursor < limit {
            result.append(cursor)
            cursor = cursor.addingTimeInterval(step)
        }
        return result
    }
}

// MARK: - JSON 解码器（Widget 自己一份）

/// Widget 进程用的解码器。
///
/// 为什么不复用 `APIJSON.decoder`：那个在 Services 层的网络客户端里，
/// **不属于 Shared，也不该属于**（Widget 不需要整个网络客户端）。
/// 这里只复制「ISO8601 带毫秒」这一条策略 —— 它与服务端 `new Date().toISOString()` 对齐，
/// 少这条会导致简报的 `savedAt` / `pushedAt` 全部解不出来。
enum WidgetJSON {

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()

        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        withFractional.timeZone = TimeZone(secondsFromGMT: 0)

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        plain.timeZone = TimeZone(secondsFromGMT: 0)

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = withFractional.date(from: raw) { return date }
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "无法解析的时间字符串: \(raw)"
                )
            )
        }
        return decoder
    }()

    /// 快照编解码用的编码器/解码器：**不含**自定义日期策略。
    /// 快照是本进程写、本进程读，编解码必须严格对称（用自定义策略反而会读不回自己的 Date）。
    static let cacheEncoder = JSONEncoder()
    static let cacheDecoder = JSONDecoder()
}

// MARK: - 本地快照

/// Widget 的本地快照（`UserDefaults`，**不用 App Group**）。
///
/// 设计文档 §1.2.3 的决策：`/api/app/*` 已豁免为匿名可读，Widget 自己请求即可，
/// 不需要主 App 与扩展共享容器。所以快照只服务一个目的 ——
/// **本次刷新失败时，还能画出上一次成功的内容**（PRD §5.3：失败不显示错误，保留旧 entry）。
enum WidgetSnapshot {

    /// 红石快照
    static let redstoneKey = "widget.redstone.snapshot.v1"
    /// 简报快照
    static let briefKey = "widget.brief.snapshot.v1"
    /// 天光"实际日出日落"缓存（3.10.0，无 App Group，用 Widget 进程自己的 `UserDefaults.standard`）
    static let skylightSunTimesKey = "widget.skylight.sunTimes.v1"
    /// 天气三卡（日弧 / 月相 / 风）的载荷缓存（3.10.0）
    static let weatherCardKey = "widget.weathercard.snapshot.v1"

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? WidgetJSON.cacheEncoder.encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? WidgetJSON.cacheDecoder.decode(type, from: data)
    }
}

/// 红石快照的内容（只存需要的，不存整份响应：模型改了也不会让快照整体失效）
struct RedstoneCachePayload: Codable {
    let days: [RedstoneDay]
    /// 服务端 `updated`（毫秒）
    let updated: Int
    let savedAt: Date
}

/// 天光"实际日出日落"的缓存内容（3.10.0）。
///
/// 为什么只存这一对值：天光卡的主视觉（阶段 / 倒计时 / 太阳位置）由 `SunClock`
/// 纯函数现算（±3 分钟，足够驱动颜色），**只有"显示给用户看的两个时刻"值得落盘** ——
/// 用户原话："每天的日落时间都不一样，天光小组件应该显示当天实际的日落时间"。
/// 网络失败时先用它顶上（PRD §5.3：失败不显示错误，保留旧值）；
/// `dayKey` 保证跨天后旧值作废（宁可回退 SunClock，也不把昨天的日落标成今天的）。
struct SunTimesCachePayload: Codable {
    /// `"2026-11-01"`（北京时间，与 `RedstoneClock.dayKey` 同一格式）
    let dayKey: String
    let sunrise: Date
    let sunset: Date
    let savedAt: Date
}

/// 简报快照的内容
struct BriefCachePayload: Codable {
    /// `"2026-10-30"`
    let date: String
    /// 已切好的前 2 段正文
    let paragraphs: [String]
    let pushedToday: Bool
    let pushedAt: Date?
    let savedAt: Date
    /// 生日文案（`07-17` / `1995-07-17` / `7月17日` 三种都见过）。
    /// 可选：旧缓存里没有这个字段，解码时给 nil（渲染层退回农历 / 首句）。
    let birthday: String?
    /// 宜（服务端扁平字段 `brief.yi[]`，权威契约，非 `sections[]` 的便利视图）
    let yi: [String]
    /// 忌
    let ji: [String]
    /// 服务端给的日出时刻文案（`06:44`）。缺省时由 `SunClock` 现算，绝不编造。
    let sunrise: String?
    /// 服务端给的日落时刻文案（`17:33`）
    let sunset: String?

    init(date: String,
         paragraphs: [String],
         pushedToday: Bool,
         pushedAt: Date?,
         savedAt: Date,
         birthday: String?,
         yi: [String] = [],
         ji: [String] = [],
         sunrise: String? = nil,
         sunset: String? = nil) {
        self.date = date
        self.paragraphs = paragraphs
        self.pushedToday = pushedToday
        self.pushedAt = pushedAt
        self.savedAt = savedAt
        self.birthday = birthday
        self.yi = yi
        self.ji = ji
        self.sunrise = sunrise
        self.sunset = sunset
    }

    /// 手写 `init(from:)`：`savedAt` 缺省时回退到当前时间，
    /// `birthday` / `yi` / `ji` / `sunrise` / `sunset` 缺省（老缓存）回退空值，
    /// 任何字段坏掉都不让整个 widget 崩。
    private enum CodingKeys: String, CodingKey {
        case date, paragraphs, pushedToday, pushedAt, savedAt, birthday
        case yi, ji, sunrise, sunset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? container.decode(String.self, forKey: .date)) ?? ""
        paragraphs = (try? container.decode([String].self, forKey: .paragraphs)) ?? []
        pushedToday = (try? container.decode(Bool.self, forKey: .pushedToday)) ?? false
        pushedAt = try? container.decode(Date.self, forKey: .pushedAt)
        savedAt = (try? container.decode(Date.self, forKey: .savedAt)) ?? Date()
        birthday = try? container.decode(String.self, forKey: .birthday)
        yi = (try? container.decode([String].self, forKey: .yi)) ?? []
        ji = (try? container.decode([String].self, forKey: .ji)) ?? []
        sunrise = try? container.decode(String.self, forKey: .sunrise)
        sunset = try? container.decode(String.self, forKey: .sunset)
    }
}

// MARK: - 请求

/// Widget 侧的极简请求层（零依赖、零状态）。
enum WidgetFetch {

    /// 单个 GET + 解码。失败一律返回 nil（Widget 不做错误展示，失败就退回快照）
    ///
    /// - Parameter timeout: 超时秒数。默认 12 秒（简报这种"主体内容"值得等）；
    ///   装饰性数据（天气）传更短的值 —— 见 `weather()`。
    static func get<T: Decodable>(_ type: T.Type, url: URL, timeout: TimeInterval = 12) async -> T? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try WidgetJSON.decoder.decode(type, from: data)
        } catch {
            return nil
        }
    }

    /// 拉一次天气实况（`GET /api/app/weather`，匿名只读）。
    ///
    /// 四条刻意的选择：
    /// 1. **8 秒超时**（比简报的 12 秒短）：天气只决定卡片画什么粒子，是装饰；
    ///    简报才是主体。让装饰多等 4 秒，用户眼里的卡片就晚 4 秒出现，不划算。
    /// 2. **不进快照**：天气是分钟级数据，落盘只会在第二天早上给用户一张昨天的"晴"——
    ///    那是最糟的错误（看起来完全正常，没人会怀疑）。拉失败就 nil，卡片退回无天气形态。
    /// 3. **`ok == false` 也算失败**：服务端业务失败时 HTTP 仍是 200（`{"ok":false}`），
    ///    传输层判不出来，只能看这个字段 —— 否则会把一份空响应当成"天气是空的"。
    /// 4. **坐标来自服务端中转的「家」坐标**（3.17.0 起为**单条记录**）：App 定位一拿到就把坐标
    ///    `POST /api/app/home`，Widget `GET` **同一条**记录读回来（见 `HomeCoordinate`）。
    ///    服务端只有一条记录、不需要任何设备标识（不要用 IDFV：侧载安装下
    ///    主程序与扩展推导出的值不同，App 报的坐标 Widget 永远读不到且完全静默），
    ///    所以桌面小组件与 App 显示同一个城市 —— 这正是
    ///    用户「app和小组件天气和可见度都应该在同一个地区啊！」的修法。
    ///    从没上报过（或缓存过期且网络失败）时 `home == nil`，请求不带 `lat/lon`，
    ///    服务端回落自己的默认坐标 —— 与 3.16.0 及之前的行为一致。
    ///
    /// 解码用 `WidgetJSON.decoder`（不是 `APIJSON.decoder`）：后者在 `Sources/Services`，
    /// **Widget target 不编译 Services**。两者的 ISO8601 带毫秒策略完全一致，
    /// 这里沿用 Widget 侧唯一那份解码器，避免出现第三份日期策略。
    static func weather() async -> WeatherNow? {
        // 坐标来自 App 上报的共享记录（见 `HomeCoordinate`）；拿不到就交给服务端默认值。
        // 为什么先取坐标再取天气、不做并发：weather 的 URL 依赖坐标，这是唯一一处
        // 真正串行的依赖。`HomeCoordinate` 有 45 分钟本地缓存，绝大多数刷新只多一次内存读取。
        let home = await HomeCoordinate.resolved()
        guard let url = API.weather(lat: home?.lat, lon: home?.lon) else { return nil }
        guard let response = await get(WeatherNow.self, url: url, timeout: 8) else { return nil }
        return response.ok ? response : nil
    }

    /// 需要拉哪几个月。
    ///
    /// 只拉「今天所在月」；如果今天已经接近月末（最后 3 天），连下个月一起拉 ——
    /// 否则 10 月 31 日 23:08 那一场结束后，小组件会以为"今天没场次了"，
    /// 而实际上明天 07:08 就有一场（PRD 验收第 8 条：结束后 1 分钟内要变成下一场）。
    static func monthKeys(around now: Date) -> [String] {
        let current = RedstoneClock.monthKey(now)
        let day = RedstoneClock.calendar.component(.day, from: now)
        let total = RedstoneClock.dayCount(in: current)
        guard day >= total - 2 else { return [current] }
        return [current, RedstoneClock.month(adding: 1, to: current)]
    }

    /// 拉红石排期（成功则写快照；失败则读快照）
    static func redstone(now: Date = Date()) async -> RedstoneCachePayload? {
        let keys = monthKeys(around: now)
        var days: [RedstoneDay] = []
        var updated: Int = 0
        var succeeded = false

        for key in keys {
            guard let url = API.redstone(month: key) else { continue }
            guard let response = await get(RedstoneResponse.self, url: url), response.ok else { continue }
            days.append(contentsOf: response.items)
            updated = max(updated, response.updated)
            succeeded = true
        }

        if succeeded {
            let payload = RedstoneCachePayload(days: dedupe(days), updated: updated, savedAt: now)
            WidgetSnapshot.save(payload, key: WidgetSnapshot.redstoneKey)
            return payload
        }

        // 失败：用上次成功的快照（PRD §5.3：容许旧 1 场，不显示错误）
        return WidgetSnapshot.load(RedstoneCachePayload.self, key: WidgetSnapshot.redstoneKey)
    }

    /// 拉简报（成功则写快照；失败则读快照）
    static func brief(now: Date = Date()) async -> BriefCachePayload? {
        guard let url = Endpoint.url(base: Endpoint.briefBase, path: Endpoint.briefPath) else {
            return WidgetSnapshot.load(BriefCachePayload.self, key: WidgetSnapshot.briefKey)
        }

        guard let response = await get(BriefResponse.self, url: url), response.ok else {
            return WidgetSnapshot.load(BriefCachePayload.self, key: WidgetSnapshot.briefKey)
        }

        let brief = response.brief
        let payload = BriefCachePayload(
            date: response.date,
            paragraphs: paragraphs(from: brief?.body),
            // `pushedToday` 是服务端明确给出的，缺省按「未推送」处理（PRD 的两种文案都基于它）
            pushedToday: brief?.pushedToday ?? false,
            pushedAt: brief?.pushedAt,
            savedAt: now,
            birthday: brief?.birthday,
            // 宜忌与日出日落都读**扁平字段**（服务端权威契约），
            // 不读 `sections[]` —— 那是同一批数据的便利视图，读它就会出现「以谁为准」的第二次判断。
            yi: brief?.yi ?? [],
            ji: brief?.ji ?? [],
            sunrise: brief?.sunrise,
            sunset: brief?.sunset
        )
        WidgetSnapshot.save(payload, key: WidgetSnapshot.briefKey)
        return payload
    }

    /// 同一天可能同时出现在两个月的数据里（月末跨月请求），按 `date` 去重
    static func dedupe(_ days: [RedstoneDay]) -> [RedstoneDay] {
        var seen = Set<String>()
        var result: [RedstoneDay] = []
        for day in days where !seen.contains(day.date) {
            seen.insert(day.date)
            result.append(day)
        }
        return result.sorted { $0.date < $1.date }
    }

    /// 从简报正文里切出前 N 段（N = `WidgetTheme.largeParagraphLimit`，3.12.0 起是 4）。
    ///
    /// 服务端的 `body` 是**一整段纯文本**，段落之间空行分隔，中间还夹着 `——————————` 这种分隔线。
    /// 这里做三件事：按空行切段 → 丢掉纯分隔线 → 取前 N 段。
    /// 取不到（`available == false` 的早上）就返回空数组，小组件显示「今天还没有简报」。
    ///
    /// **为什么从 2 段提到 4 段**：中号只渲染首句，2 段本来就够；但大号要 **4–5 行正文**
    /// （用户原话："大的小组件因为它大也可以显示更多内容啊"），2 段拼起来常常只有 2 行，
    /// 下半张卡就空了。切段上限提高后，渲染层各取所需：小/中号取首句，大号取前 4 段。
    static func paragraphs(from body: String?) -> [String] {
        guard let body = body else { return [] }
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n")
        var result: [String] = []
        for chunk in normalized.components(separatedBy: "\n\n") {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // 纯分隔线段（整段只有破折号/横线/空格）不算正文
            let isSeparator = trimmed.allSatisfy { character in
                character == "—" || character == "-" || character == "·" || character.isWhitespace
            }
            guard !isSeparator else { continue }
            result.append(trimmed)
            if result.count >= WidgetTheme.largeParagraphLimit { break }
        }
        return result
    }
}

// MARK: - 红石 entry

/// 红石小组件的一条 Timeline entry。
///
/// 为什么把 `phase` / `todayOccurrences` 在**生成 entry 时**就算好、而不是在 View 里算：
/// entry 的 `date` 就是"这一条被渲染的时刻"，而 View 里拿不到时间机器 ——
/// 直接把结论带进去，View 只负责画，不会出现「View 用 `Date()` 现算」导致
/// 预渲染与真实显示不一致的经典小组件 bug。
struct RedstoneEntry: TimelineEntry {
    let date: Date
    /// 有没有排期数据（false = 显示「暂无排期」，绝不显示 00:00 或假地图）
    let hasData: Bool
    /// 数据最后生成时间（过期提示用；nil 时不提示）
    let updatedAt: Date?
    let phase: RockPhase
    /// 今日全部场次（含已过），中号右半用它画列表
    let todayOccurrences: [Occurrence]
    /// 今日场次数
    let todayCount: Int
    /// 今日是否有待核对场次
    let needsCheck: Bool
    /// 空窗期（`focus == nil`）时整卡切换的天光帧。
    ///
    /// 为什么由 Provider 在生成 entry 时顺带算好、而不是视图里现造：红石卡面只能在
    /// **自己的 entry** 上画（provider 契约一张卡一个 Provider，视图里再起一个
    /// `SkyLightProvider` 会破坏这条契约），而 `SkyLightFace` 吃的是 `SkyLightEntry`。
    /// 同进程同 target，直接用 `SkyLightEntry.make(date:)`（纯函数、零网络）造一帧
    /// 带在身上即可。有场次的日子它根本不会被读到，成本只是几次日出日落三角函数。
    let daylight: SkyLightEntry?

    /// 「本周排期」（3.11.0，大号卡下半部那 3–4 行）。
    ///
    /// 为什么新增字段而不是让 `RedstoneFace` 自己算：entry 是**预渲染帧**，
    /// 而 `days` 只活在 Provider 手里 —— 视图里拿不到整月排期（也不该拿，
    /// 那会让视图依赖"数据怎么来的"）。这里在造 entry 时顺手折好，
    /// 视图只负责画。空数组 = 没有未来场次，大号卡下半部整块不渲染。
    let weekRows: [RedstoneWeekRow]

    /// 下一场 / 进行中的那一场（没有就 nil）
    var focus: Occurrence? { phase.occurrence }
}

// MARK: - 本周排期行

/// 红石大号卡「本周排期」的一行：一天一条。
///
/// 只带**展示需要的三个字符串**（不塞 `[Occurrence]`）：entry 会进 Timeline 缓存，
/// 让每行背着整天的场次对象既没必要，也让"哪天开始多带一个字段"变得难以察觉。
struct RedstoneWeekRow: Identifiable, Equatable {
    /// `"2026-11-01"`
    let dayKey: String
    /// `"今天"` / `"明天"` / `"周三"`
    let dayLabel: String
    /// `"11:08 · 17:08 · 23:08"`
    let timesLabel: String
    /// `"霞谷·圆梦村"`；空串 = 待确认（渲染层照样不编地名）
    let map: String

    var id: String { dayKey }
}

extension RedstoneEntry {

    /// 用一份排期数据 + 指定时刻造一条 entry
    static func make(date: Date, days: [RedstoneDay], updated: Int) -> RedstoneEntry {
        let occurrences = RedstoneTimeline.occurrences(in: days)
        let todayKey = RedstoneClock.dayKey(date)
        let today = occurrences.filter { $0.date == todayKey }
        let phase = RedstoneTimeline.phase(in: days, now: date)
        let updatedAt: Date? = updated > 0
            ? Date(timeIntervalSince1970: TimeInterval(updated) / 1000)
            : nil

        return RedstoneEntry(
            date: date,
            hasData: !occurrences.isEmpty,
            updatedAt: updatedAt,
            phase: phase,
            todayOccurrences: today,
            todayCount: today.count,
            needsCheck: today.contains { $0.needsCheck },
            daylight: SkyLightEntry.make(date: date),
            weekRows: weekRows(from: occurrences, now: date)
        )
    }

    /// 空态 entry（没数据 / 首次安装）。同样带上天光帧：空窗期整卡换成天光面
    static func empty(date: Date) -> RedstoneEntry {
        return RedstoneEntry(
            date: date,
            hasData: false,
            updatedAt: nil,
            phase: .notGenerated,
            todayOccurrences: [],
            todayCount: 0,
            needsCheck: false,
            daylight: SkyLightEntry.make(date: date),
            weekRows: []
        )
    }

    /// 组件库 / 占位专用的**样例帧**（3.12.0，修「红石小组件没有最大版」）。
    ///
    /// ## 为什么必须有它（这是 3.11.0 那个 bug 的真正根因）
    ///
    /// 3.11.0 的 `placeholder(in:)` 与 `getSnapshot(in:)` 都返回 `RedstoneEntry.empty(date:)`，
    /// 而 `empty` 的 `focus` 恒为 `nil` —— 于是 `RedstoneWidgetView` 走进"空窗期整卡换天光面"
    /// 那条分支，**三个尺寸的预览全部画成天光卡**。
    /// 用户在组件库里看到的是：小/中/大 三张都长成天光（大号更是与"天光"组件完全同款），
    /// 结论自然就是"红石没有最大版"。也就是说 —— 版式代码是对的（`largeFace` 一直在），
    /// 但**组件库从来没让他看见过它**。
    ///
    /// 所以占位路径必须给一帧"有场次"的样例：三档各自走自己的版式，
    /// 大号就能看到 hero 倒计时 + 本周排期。样例**不是真实数据**（Apple 对 placeholder 的定义
    /// 就是"sample data"），它只出现在组件库预览与系统占位窗口里；桌面上真正渲染的永远是
    /// `getTimeline` 产出的真实 entry（没数据就诚实地切天光面）。
    ///
    /// ## 为什么按 family 造
    ///
    /// 大号下半部是「本周排期」4 行、小/中号只有 1–2 行位子。让样例帧按 family 决定行数，
    /// 三个尺寸的预览才各自"长得对"（DESIGN-RULES §3：一档一版式，不是一套硬缩放）。
    static func preview(date: Date, family: WidgetFamily) -> RedstoneEntry {
        // 场次放在 90 分钟后：倒计时一定为正（`Text(timerInterval:)` 的区间必须合法）
        let start = date.addingTimeInterval(90 * 60)
        let sample = Occurrence(date: RedstoneClock.dayKey(start),
                                startAt: start,
                                endAt: start.addingTimeInterval(52 * 60),
                                time: Formatters.timeHHmm(start),
                                map: "暮土·失落方舟",
                                rate: 2.5,
                                needsCheck: false,
                                type: "红石")
        let todayKey = RedstoneClock.dayKey(date)
        let rowLimit = family == .systemLarge ? WidgetTheme.Redstone.largeRowLimit : 2
        // 四行样例的时刻串：形状与真实数据一致（`"11:08 · 17:08"`），值本身是示例
        let sampleTimes = ["11:08", "11:08 · 17:08", "07:08 · 15:08 · 23:08", "09:08 · 21:08"]
        let rows = (0..<max(1, rowLimit)).map { offset -> RedstoneWeekRow in
            let dayKey = offset == 0
                ? todayKey
                : RedstoneClock.dayKey(date.addingTimeInterval(86_400 * Double(offset)))
            return RedstoneWeekRow(
                dayKey: dayKey,
                dayLabel: dayLabel(dayKey: dayKey, todayKey: todayKey),
                timesLabel: sampleTimes[offset % sampleTimes.count],
                map: sample.map
            )
        }

        return RedstoneEntry(
            date: date,
            hasData: true,
            updatedAt: date,
            phase: .upcoming(sample, seconds: 90 * 60),
            todayOccurrences: [sample],
            todayCount: 1,
            needsCheck: false,
            daylight: SkyLightEntry.make(date: date),
            weekRows: rows
        )
    }

    /// 「本周排期」：从**已加载的场次**里取"还没结束"的那些，按天归组，最多 4 行。
    ///
    /// 三条取舍：
    /// - 用 `endAt > now` 而不是"今天的场次"：一场进行中时它仍然属于"接下来要发生的事"，
    ///   从这一场开始读才对（用户看排期是看"接下来"）；
    /// - 不跨月补数据：Provider 只拉当月（+ 月末的最后 3 天会多拉下月），
    ///   所以这里也**只报拿到的东西**，绝不写"下周再看"这种承诺；
    /// - 行数上限来自 `WidgetTheme.Redstone.largeRowLimit`：大号卡下半部放得下 4 行 12pt，
    ///   第 5 行就会顶到卡片底边。
    static func weekRows(from occurrences: [Occurrence], now: Date) -> [RedstoneWeekRow] {
        let todayKey = RedstoneClock.dayKey(now)
        var byDay: [String: [Occurrence]] = [:]
        for occurrence in occurrences where occurrence.endAt > now {
            byDay[occurrence.date, default: []].append(occurrence)
        }
        let orderedDays = byDay.keys.sorted()
        guard !orderedDays.isEmpty else { return [] }

        return orderedDays.prefix(WidgetTheme.Redstone.largeRowLimit).compactMap { dayKey in
            guard let list = byDay[dayKey], !list.isEmpty else { return nil }
            let times = list.sorted { $0.startAt < $1.startAt }.map { $0.time }
            return RedstoneWeekRow(
                dayKey: dayKey,
                dayLabel: dayLabel(dayKey: dayKey, todayKey: todayKey),
                timesLabel: times.joined(separator: " · "),
                map: list.first?.map ?? ""
            )
        }
    }

    /// 「今天 / 明天 / 周三」—— 两个相对日给相对词，其余给星期（想不起几号也能对上号）
    private static func dayLabel(dayKey: String, todayKey: String) -> String {
        if dayKey == todayKey { return "今天" }
        if dayKey == RedstoneClock.nextDayKey(todayKey) { return "明天" }
        let weekday = Formatters.weekdayLabel(dayKey: dayKey)
        return weekday.isEmpty ? Formatters.dayTitle(dayKey) : weekday
    }
}

// MARK: - 简报 entry

struct BriefEntry: TimelineEntry {
    let date: Date
    let hasData: Bool
    /// `"10月30日"`
    let dateText: String
    /// `"周四"`
    let weekdayText: String
    /// 前 2 段
    let paragraphs: [String]
    let pushedToday: Bool
    let pushedAt: Date?
    /// 生日文案（`07-17` / `1995-07-17` / `7月17日` 三种都见过），`nil` = 服务端没给
    let birthday: String?
    /// 宜（服务端 `brief.yi[]`，已按服务端顺序排好）
    let yi: [String]
    /// 忌
    let ji: [String]
    /// 服务端给的日出文案；nil 时渲染层退回 `SunClock` 现算（**不编造**）
    let sunrise: String?
    /// 服务端给的日落文案
    let sunset: String?
    /// 今天的天气实况（`GET /api/app/weather`）。
    ///
    /// **拉失败就是 nil** —— 卡片退回无天气形态（不画粒子、底色回到原来那张夜纸），
    /// 绝不猜一个晴天出来。天气只决定"氛围"，简报正文才是这张卡的主体：
    /// 一次网络抖动不该让整张卡变成错误态。
    ///
    /// 为什么整份 `WeatherNow` 带进 entry 而不是只带一个 `WeatherKind`：
    /// 除了画什么粒子，卡片迟早要显示温度 / 天气文案（"阴 21°"），
    /// 而 entry 是**预渲染帧**，View 里现取 `Date()` 或现发请求都会导致帧错位。
    /// 这是纯追加字段，`BriefEntry` 原有的 12 个字段一个都没动。
    let weather: WeatherNow?

    /// 页脚文案：「今日已推送 07:02」/「今日未推送」。没有简报数据时整条页脚不画
    var footerText: String? {
        guard hasData else { return nil }
        if pushedToday {
            guard let pushedAt = pushedAt else { return "今日已推送" }
            return "今日已推送 " + Formatters.timeHHmm(pushedAt)
        }
        return "今日未推送"
    }

    /// 地平线**以下**那行注脚：`宜 打猎、散步 · 忌 店铺开业`。
    ///
    /// 为什么放在地面区而不是天空区：地平线是硬的，任何正文越过它都会被那条亮边切开，
    /// 宜忌属于"历书注脚"，只有落在地平线以下才不会被打断（与 App 内 `SkyCard` 的 `note` 位同理）。
    ///
    /// 空则返回 nil —— 调用方整行不画。**取不到就空着，绝不编一条"今日宜出行"出来**。
    /// 数量上限与 App 内简报卡一致（宜取 2 条、忌取 1 条）：这一行只有 10pt，多了会被截。
    var ritualText: String? {
        var parts: [String] = []
        if !yi.isEmpty {
            parts.append("宜 " + yi.prefix(2).joined(separator: "、"))
        }
        if !ji.isEmpty {
            parts.append("忌 " + ji.prefix(1).joined(separator: "、"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 日出 / 日落文案：优先服务端值（它按当地算过，比 App 自己算的准），
    /// 缺了才回落到 `SunClock`（天文计算，误差 ±3 分钟，不是编造内容）。
    /// 两头都拿不到就返回 nil，地面区那一侧整个不画。
    func sunTexts() -> (rise: String?, set: String?) {
        if let rise = nonEmpty(sunrise), let set = nonEmpty(sunset) {
            return (rise, set)
        }
        guard let times = SunClock.times(on: date) else {
            return (nonEmpty(sunrise), nonEmpty(sunset))
        }
        return (nonEmpty(sunrise) ?? Formatters.timeHHmm(times.sunrise),
                nonEmpty(sunset) ?? Formatters.timeHHmm(times.sunset))
    }

    private func nonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func make(date: Date, payload: BriefCachePayload?, weather: WeatherNow? = nil) -> BriefEntry {
        guard let payload = payload else {
            return BriefEntry(
                date: date,
                hasData: false,
                dateText: Formatters.dayTitle(RedstoneClock.dayKey(date)),
                weekdayText: Formatters.weekdayCN(date),
                paragraphs: [],
                pushedToday: false,
                pushedAt: nil,
                birthday: nil,
                yi: [],
                ji: [],
                sunrise: nil,
                sunset: nil,
                weather: weather
            )
        }
        return BriefEntry(
            date: date,
            hasData: !payload.paragraphs.isEmpty,
            dateText: Formatters.dayTitle(payload.date),
            weekdayText: Formatters.weekdayLabel(dayKey: payload.date),
            paragraphs: payload.paragraphs,
            pushedToday: payload.pushedToday,
            pushedAt: payload.pushedAt,
            birthday: payload.birthday,
            yi: payload.yi,
            ji: payload.ji,
            sunrise: payload.sunrise,
            sunset: payload.sunset,
            weather: weather
        )
    }
}

// MARK: - 红石 Provider

/// 红石 / 简共用的刷新预算（PRD §5.3：iOS 每天 40–70 次，必须省着用）。
///
/// 生成规则：**每小时 1 条**（24 条）+ **每场落地 1 条 + 每场结束 1 条**（3 场 = 6 条）≈ 30 条/天。
/// 倒计时本身不靠刷新 —— View 里用 `Text(timerInterval:)` 让系统自绘走时，秒级在动但零刷新成本。
struct RedstoneProvider: TimelineProvider {

    /// 预览占位（组件库 / 系统占位窗口）。
    ///
    /// **3.12.0 修**：这里原来是 `RedstoneEntry.empty(date:)` —— `focus == nil` 于是整卡走
    /// "空窗期换天光面"分支，三个尺寸的预览全画成天光卡（用户因此认为"红石没有最大版"）。
    /// 现在给按 family 生成的**样例帧**：小 / 中 / 大各自渲染自己的版式，
    /// 大号在组件库里就能看到 hero 倒计时 + 本周排期。理由详见 `RedstoneEntry.preview`。
    func placeholder(in context: Context) -> RedstoneEntry {
        return RedstoneEntry.preview(date: Date(), family: context.family)
    }

    /// 组件库里的快照。
    ///
    /// 三条路径，按"能给出多真实的内容"排序：
    /// 1. `context.isPreview`（组件库预览）→ 样例帧（按 family 分档，三档都能看到自己的版式）；
    /// 2. 本地有快照（用户确实用过，桌面上已有真实排期）→ 用快照算真实 entry；
    /// 3. 什么都没有 → 同样退到样例帧（**不能**退到空态：空态会整卡变天光面，
    ///    组件库里就会看起来"这个尺寸没有红石版式"）。
    ///
    /// 为什么不发网络请求：用户只是划组件库，为每一档预览打一次请求既慢又浪费预算；
    /// 预览要的是"版式长什么样"，不是"此刻的数据对不对"。
    func getSnapshot(in context: Context, completion: @escaping (RedstoneEntry) -> Void) {
        if context.isPreview {
            completion(RedstoneEntry.preview(date: Date(), family: context.family))
            return
        }
        if let payload = WidgetSnapshot.load(RedstoneCachePayload.self, key: WidgetSnapshot.redstoneKey),
           !payload.days.isEmpty {
            completion(RedstoneEntry.make(date: Date(),
                                          days: payload.days,
                                          updated: payload.updated))
            return
        }
        completion(RedstoneEntry.preview(date: Date(), family: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RedstoneEntry>) -> Void) {
        Task {
            let now = Date()
            let payload = await WidgetFetch.redstone(now: now)
            let days = payload?.days ?? []
            let updated = payload?.updated ?? 0

            guard !days.isEmpty else {
                // 彻底没有数据：一条空态 entry，1 小时后再试（不刷屏、也不假装有排期）
                let entry = RedstoneEntry.empty(date: now)
                completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(3600))))
                return
            }

            let entries = RedstoneProvider.entries(days: days, updated: updated, now: now)
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    /// 生成 entry 序列（导出成 static 便于自检与将来写单测）
    ///
    /// 时间点集合 = 「现在」+ 未来 24 小时里每 30 分钟一格 + 未来 26 小时里每场落地/结束时刻。
    /// 去重后升序，约 50 条。
    ///
    /// 为什么刻度从「每小时」改成「每 30 分钟」：红石卡的文字里有两处在走的状态 ——
    /// 「今日已结束」的判定、以及已过场次的 30% 灰。整点网格会让这两处最多晚 30 分钟才变
    /// （比如 23:08 那一场结束后，卡片可能到 00:00 才承认"今天没场次了"）。
    /// 半小时网格把这条误差压到 30 分钟以内，和简报卡同频 —— 两张卡并排放在桌面上，
    /// 刷新节奏不该有两个脾气。
    ///
    /// 预算：这些都是**预渲染帧**，唯一发请求的是 `.atEnd` 触发的那一次 getTimeline，
    /// 24 小时 1 次，离 iOS 的 40–70 次/天预算差着两个数量级。
    static func entries(days: [RedstoneDay], updated: Int, now: Date) -> [RedstoneEntry] {
        var stamps: Set<Date> = Set(
            WidgetTimeline.stamps(now: now,
                                  horizon: WidgetTimeline.rockHorizon,
                                  step: WidgetTimeline.rockStep)
        )

        // 每场「落地」「结束」各 1 条（这两刻是内容真正变化的地方，必须精确）
        let occurrences = RedstoneTimeline.occurrences(in: days)
        let occurrenceLimit = now.addingTimeInterval(26 * 3600)
        for occurrence in occurrences {
            if occurrence.startAt > now, occurrence.startAt < occurrenceLimit {
                stamps.insert(occurrence.startAt)
            }
            if occurrence.endAt > now, occurrence.endAt < occurrenceLimit {
                stamps.insert(occurrence.endAt)
            }
        }

        let ordered = stamps.sorted()
        return ordered.map { stamp in
            RedstoneEntry.make(date: stamp, days: days, updated: updated)
        }
    }
}

// MARK: - 简报 Provider

/// 简报小组件（中号 / 小号）。
///
/// 刷新策略：**每 60 分钟一条 entry，铺满未来 24 小时**（24 帧），`.atEnd` 再取一轮。
///
/// 为什么从"30 分钟一帧铺 12 小时"放宽（V3.7）：V3.3 那张卡的底色跟着**时段**变
/// （`SkyPhase` 七档），必须靠密集的帧去推进日出日落；V3.7 起底色跟着**当天的天气**走，
/// 一天只变一次脸，真正还在"走"的只有轨迹上那颗光点。60 分钟一帧把它压到 24 帧：
/// WidgetKit 的刷新预算按"每天几十次"算，30 分钟一帧铺 24 小时是 48 帧，
/// 会把预算吃光 —— 代价是用户早上 8 点看不到当天的新简报，那才是真问题。
/// 而云"飘"靠的是**预排帧**（每帧云位置由这一帧时刻算出，见 `BriefWeatherLayer.drift`），
/// 与唤醒频率无关，所以放宽帧距不会让云停住。
///
/// 会不会被限流：不会。Timeline 里的多条 entry 是**预渲染帧**，系统到点直接换帧，不发请求；
/// 真正吃预算的是 `getTimeline`（一次要打 `/api/app/brief` + `/api/app/weather`）。
/// 24 小时一轮 `.atEnd`，一天约 1 次，而 iOS 给的是 40–70 次/天。
struct BriefProvider: TimelineProvider {

    func placeholder(in context: Context) -> BriefEntry {
        return BriefEntry.make(date: Date(), payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BriefEntry) -> Void) {
        completion(BriefEntry.make(date: Date(), payload: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BriefEntry>) -> Void) {
        Task {
            let now = Date()

            // 并发而不是串行：两个请求互不依赖，串行会让卡片多等一个 RTT。
            // `async let` 的 `weather` 分支**永不抛错**（`WidgetFetch.weather()` 内部把
            // 超时 / 解码失败 / `ok == false` 全部吞成 nil），所以天气挂了不会拖累整条 timeline ——
            // 主题是简报正文，天气只是氛围。
            async let briefPayload: BriefCachePayload? = WidgetFetch.brief(now: now)
            async let currentWeather: WeatherNow? = WidgetFetch.weather()

            let payload = await briefPayload
            let weather = await currentWeather

            let entries = BriefProvider.entries(payload: payload, weather: weather, now: now)
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    /// 生成 entry 序列（导出成 static 便于自检与将来写单测）
    ///
    /// 时间点 = 60 分钟网格，铺满未来 24 小时（含 `now`），去重后升序，约 24 条。
    ///
    /// 每一条 entry 都带**同一个** `weather`：一天之内天气不会半小时变一次，
    /// 而每帧各拉一次意味着 24 次网络请求 —— 那是把"装饰"的成本做到比"主体"还高。
    /// 新数据靠下一次 `getTimeline`（一小时到一天后）带进来；
    /// 用户想看最新的，点一下卡片进 App，那边有下拉刷新。
    ///
    /// V3.7 起**不再插天色切档时刻**：那张卡的底色已经不跟 `SkyPhase` 走了（跟天气走），
    /// 切档时刻的帧渲染出来与相邻网格帧一模一样 —— 那是纯粹的浪费帧。
    static func entries(payload: BriefCachePayload?, weather: WeatherNow?, now: Date) -> [BriefEntry] {
        let stamps = WidgetTimeline.stamps(now: now,
                                           horizon: WidgetTimeline.briefHorizon,
                                           step: WidgetTimeline.briefStep)

        // 去重后升序，并保证不出现过去的帧
        let ordered = Array(Set(stamps.filter { $0 >= now })).sorted()
        return ordered.map { stamp in
            BriefEntry.make(date: stamp, payload: payload, weather: weather)
        }
    }
}
