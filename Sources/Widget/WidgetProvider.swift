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
    /// 收益页（预留给将来可能的收益小组件）
    static let earningsHost = "earnings"

    /// 拼一个合法的深链；拼不出来返回 nil（`.widgetURL` 接受 nil，等于"这张卡不可点"）
    static func url(host: String) -> URL? {
        return URL(string: scheme + "://" + host)
    }

    /// 简报小组件整卡点击目标
    static let brief = url(host: briefHost)
    /// 红石小组件整卡点击目标
    static let rock = url(host: rockHost)
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
    /// 三条刻意的选择：
    /// 1. **8 秒超时**（比简报的 12 秒短）：天气只决定卡片画什么粒子，是装饰；
    ///    简报才是主体。让装饰多等 4 秒，用户眼里的卡片就晚 4 秒出现，不划算。
    /// 2. **不进快照**：天气是分钟级数据，落盘只会在第二天早上给用户一张昨天的"晴"——
    ///    那是最糟的错误（看起来完全正常，没人会怀疑）。拉失败就 nil，卡片退回无天气形态。
    /// 3. **`ok == false` 也算失败**：服务端业务失败时 HTTP 仍是 200（`{"ok":false}`），
    ///    传输层判不出来，只能看这个字段 —— 否则会把一份空响应当成"天气是空的"。
    ///
    /// 解码用 `WidgetJSON.decoder`（不是 `APIJSON.decoder`）：后者在 `Sources/Services`，
    /// **Widget target 不编译 Services**。两者的 ISO8601 带毫秒策略完全一致，
    /// 这里沿用 Widget 侧唯一那份解码器，避免出现第三份日期策略。
    static func weather() async -> WeatherNow? {
        guard let url = API.weather() else { return nil }
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

    /// 从简报正文里切出前 2 段。
    ///
    /// 服务端的 `body` 是**一整段纯文本**，段落之间空行分隔，中间还夹着 `——————————` 这种分隔线。
    /// 这里做三件事：按空行切段 → 丢掉纯分隔线 → 取前 2 段。
    /// 取不到（`available == false` 的早上）就返回空数组，小组件显示「今天还没有简报」。
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
            if result.count >= 2 { break }
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

    /// 下一场 / 进行中的那一场（没有就 nil）
    var focus: Occurrence? { phase.occurrence }
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
            daylight: SkyLightEntry.make(date: date)
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
            daylight: SkyLightEntry.make(date: date)
        )
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

    /// 预览占位（Xcode 里点开 Widget 时先看到的东西）
    func placeholder(in context: Context) -> RedstoneEntry {
        return RedstoneEntry.empty(date: Date())
    }

    /// 组件库里的快照：不发请求，直接用空态，避免用户在库里翻组件时打一堆请求
    func getSnapshot(in context: Context, completion: @escaping (RedstoneEntry) -> Void) {
        completion(RedstoneEntry.empty(date: Date()))
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
