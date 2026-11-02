import Foundation

// MARK: - 时间解析（本文件专用）

/// 监控接口的时间解析。
///
/// 为什么不直接用 `Date` + `APIJSON.decoder`：同一份 `MonitorResponse` 会走**两条解码路径**——
/// ①`APIClient` 走 `APIJSON.decoder`（ISO8601 策略）；
/// ②`CachedLoader` 的磁盘快照走 `JSONDecoder()`（默认 `.deferredToDate`，Date 会被读成 Double）。
/// 两条路径对 `Date` 的期待不同，谁读到对方写的数据都会得到 nil，而 nil 在页面上会被读成
/// 「尚未检查」—— 一个纯粹的假信息。
///
/// 所以本文件的时间字段**一律保留服务端原始字符串**，再用这一个函数解析：
/// 无论从网络还是从快照来，结果都一致；解析不出来就是 nil，由 UI 决定怎么说话（绝不显示「未知」）。
enum MonitorTime {

    /// 带毫秒的 ISO（服务端 `new Date(ms).toISOString()` 的实际形态）
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// 不带毫秒的 ISO（历史写入 / 手工测试数据）
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// 解析失败一律 nil（不编时间）
    static func parse(_ raw: String?) -> Date? {
        guard let raw = raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let date = fractional.date(from: trimmed) { return date }
        if let date = plain.date(from: trimmed) { return date }
        return nil
    }
}

// MARK: - 推送时段

/// 推送时段（服务端 `pushWindow`）。
///
/// 纯展示用：App 不参与任何「现在该不该推」的判断，节奏由服务端的推送任务决定，
/// App 只把服务端的话原样转述（PRD P12 底部说明）。
struct PushWindow: Codable, Sendable, Equatable {
    /// `"06:30"`
    let dayStart: String
    /// `"22:30"`
    let dayEnd: String
    /// 服务端给人看的一句话；缺省时客户端自己拼
    let note: String

    private enum CodingKeys: String, CodingKey {
        case dayStart
        case dayEnd
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayStart = (try? container.decode(String.self, forKey: .dayStart)) ?? ""
        dayEnd = (try? container.decode(String.self, forKey: .dayEnd)) ?? ""
        note = (try? container.decode(String.self, forKey: .note)) ?? ""
    }

    init(dayStart: String, dayEnd: String, note: String) {
        self.dayStart = dayStart
        self.dayEnd = dayEnd
        self.note = note
    }

    /// 时段说明。服务端给了 note 就用服务端的原话，否则用两段时间自己拼。
    ///
    /// 两个都空 → 空串（调用方整行不渲染），绝不返回「时段未知」这种假信息。
    var displayText: String {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty { return trimmedNote }
        let start = dayStart.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = dayEnd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !start.isEmpty, !end.isEmpty else { return "" }
        return "\(start)–\(end) 即时推送，\(end) 后合并到次日 \(start)"
    }
}

// MARK: - 单服版本

/// 一个服的监控行（国服 / 国际服）。
///
/// 字段名逐字对齐 `GET /api/app/monitor` 的线上响应；
/// `POST /api/app/monitor/check` 的字段名**不同**（`status` / `error` 而非 `hasNew` / `lastError`），
/// 所以那个响应用单独的 `MonitorCheckReceipt` 接，绝不复用本类型（见 `MonitorStore.checkNow`）。
///
/// 为什么 `checkedAt` 存成 `String`（属性名 `checkedAtRaw`）而不是 `Date`：
/// 见 `MonitorTime` 的注释 —— 磁盘快照与网络两条解码路径对 `Date` 的策略不同。
/// 因为属性名与 JSON 键名不再一致，`encode(to:)` 手写（否则会把 `checkedAtRaw` 这个
/// 客户端内部名字写进快照，人与工具都没法直接对照线上 JSON）。
struct MonitorAppVersion: Codable, Sendable, Equatable, Identifiable {

    /// App Store 数字 id，天然唯一，直接做 `Identifiable`
    let appId: String
    /// `"光遇国服"`
    let name: String
    /// `"cn"` / `"us"`
    let country: String
    /// 当前版本号。从未成功检查过时服务端可能给 null
    let version: String?
    let previousVersion: String?
    /// 上一版自己的发布日期（date-only `"2026-10-21"`，可能为 null）。
    ///
    /// 服务端 v2.3.0 起由 `app_monitor_versions` 版本流水补上（旧 KV 里还没有历史时给 null，
    /// 此时「上一版本」也一定是 null —— 两者同源）。同样**不转 Date**：时区会把 21 号漂成 20 号。
    /// 可空 + `try?` 解码：老快照（`CachedLoader` 磁盘里 3.15.x 写下的 JSON）没有这个键，
    /// 缺键必须只是"这个字段没有值"，不能让整页解码失败。
    let previousReleaseDate: String?
    /// date-only 字符串（`"2026-10-21"`）。**不转 Date**：时区会把 21 号漂成 20 号
    let releaseDate: String?
    /// 是否有新版本（服务端判定，客户端不做版本号比较）
    let hasNew: Bool
    /// 上次**成功**检查的时刻（原始 ISO 字符串，由 `MonitorTime` 解析）
    let checkedAtRaw: String?
    /// 上次检查的错误信息；有值就是「这次失败了，卡片要显示上次成功时间」
    let lastError: String?

    var id: String { appId }

    /// 上次成功检查时刻
    var checkedAt: Date? { MonitorTime.parse(checkedAtRaw) }

    /// 展示用版本号，永不为空（空则 `—`，与全项目一致）
    var displayVersion: String {
        guard let version = version else { return "—" }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    /// 地区中文名：优先看服务端给的 `name`，兜底按国家码
    var regionText: String {
        if name.contains("国际") { return "国际服" }
        if name.contains("国服") { return "国服" }
        switch country.lowercased() {
        case "cn": return "国服"
        case "us": return "国际服"
        default: return country.uppercased()
        }
    }

    private enum CodingKeys: String, CodingKey {
        case appId
        case name
        case country
        case version
        case previousVersion
        case previousReleaseDate
        case releaseDate
        case hasNew
        case checkedAt
        case lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appId = (try? container.decode(String.self, forKey: .appId)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        country = (try? container.decode(String.self, forKey: .country)) ?? ""
        version = try? container.decode(String.self, forKey: .version)
        previousVersion = try? container.decode(String.self, forKey: .previousVersion)
        // 缺键 / 值非法一律 nil（`try?`）；老快照没有这个键也照常解码
        previousReleaseDate = try? container.decode(String.self, forKey: .previousReleaseDate)
        releaseDate = try? container.decode(String.self, forKey: .releaseDate)
        hasNew = (try? container.decode(Bool.self, forKey: .hasNew)) ?? false
        // `checkedAt` 在 JSON 里是 ISO 字符串；用 String 接住，两条解码路径结果一致
        checkedAtRaw = try? container.decode(String.self, forKey: .checkedAt)
        lastError = try? container.decode(String.self, forKey: .lastError)
    }

    /// 手写 `encode(to:)`：把 `checkedAtRaw` 写回 JSON 的 `checkedAt` 键，
    /// 保证磁盘快照与线上 JSON 结构逐字一致。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appId, forKey: .appId)
        try container.encode(name, forKey: .name)
        try container.encode(country, forKey: .country)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(previousVersion, forKey: .previousVersion)
        try container.encodeIfPresent(previousReleaseDate, forKey: .previousReleaseDate)
        try container.encodeIfPresent(releaseDate, forKey: .releaseDate)
        try container.encode(hasNew, forKey: .hasNew)
        try container.encodeIfPresent(checkedAtRaw, forKey: .checkedAt)
        try container.encodeIfPresent(lastError, forKey: .lastError)
    }

    /// 供预览 / 测试直接构造（自定义 `init(from:)` 会吃掉自动生成的 memberwise init）
    ///
    /// `previousReleaseDate` 带默认值 `nil`：这个文件之外的构造点（预览 / 调试数据）
    /// 不必为了一个新字段全部改一遍。
    init(
        appId: String,
        name: String,
        country: String,
        version: String?,
        previousVersion: String?,
        previousReleaseDate: String? = nil,
        releaseDate: String?,
        hasNew: Bool,
        checkedAtRaw: String?,
        lastError: String?
    ) {
        self.appId = appId
        self.name = name
        self.country = country
        self.version = version
        self.previousVersion = previousVersion
        self.previousReleaseDate = previousReleaseDate
        self.releaseDate = releaseDate
        self.hasNew = hasNew
        self.checkedAtRaw = checkedAtRaw
        self.lastError = lastError
    }
}

// MARK: - 监控总响应

/// `GET /api/app/monitor` 的响应。
///
/// 手写 `init(from:)` 的理由与全项目一致：缺字段只让该字段为空，不让整页跟着作废
/// （`pending` / `lastPushAt` / `pushWindow` 在部分部署里可能缺省）。
struct MonitorResponse: Codable, Sendable, Equatable {

    let ok: Bool
    let apiVersion: Int?
    /// 服务端当前时刻（原始 ISO 字符串，解析见 `serverTime`）
    let serverTimeRaw: String?
    /// 国服 + 国际服，顺序即展示顺序
    let apps: [MonitorAppVersion]
    /// 待推送的更新条数（`> 0` 时「更多」Tab 可以出提示点）
    let pending: Int
    /// 最近一次推送成功的时刻（原始 ISO 字符串，解析见 `lastPushAt`）
    let lastPushAtRaw: String?
    let pushWindow: PushWindow?

    /// 服务端当前时刻
    var serverTime: Date? { MonitorTime.parse(serverTimeRaw) }
    /// 最近一次推送成功的时刻
    var lastPushAt: Date? { MonitorTime.parse(lastPushAtRaw) }

    /// 是否有任一服出现新版本
    var hasAnyNewVersion: Bool { apps.contains { $0.hasNew } }

    /// 是否存在「检查失败」的服（卡片要显示上次成功时间）
    var hasAnyFailure: Bool { apps.contains { $0.lastError != nil } }

    /// 最近一次成功检查的时刻（两张卡里取最大）
    var latestCheckedAt: Date? {
        apps.compactMap { $0.checkedAt }.max()
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case apiVersion
        case serverTime
        case apps
        case pending
        case lastPushAt
        case pushWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        apiVersion = try? container.decode(Int.self, forKey: .apiVersion)
        serverTimeRaw = try? container.decode(String.self, forKey: .serverTime)
        apps = (try? container.decode([MonitorAppVersion].self, forKey: .apps)) ?? []
        pending = (try? container.decode(Int.self, forKey: .pending)) ?? 0
        lastPushAtRaw = try? container.decode(String.self, forKey: .lastPushAt)
        pushWindow = try? container.decode(PushWindow.self, forKey: .pushWindow)
    }

    /// 手写 `encode(to:)`：把内部属性名写回线上键名（理由同 `MonitorAppVersion`）
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ok, forKey: .ok)
        try container.encodeIfPresent(apiVersion, forKey: .apiVersion)
        try container.encodeIfPresent(serverTimeRaw, forKey: .serverTime)
        try container.encode(apps, forKey: .apps)
        try container.encode(pending, forKey: .pending)
        try container.encodeIfPresent(lastPushAtRaw, forKey: .lastPushAt)
        try container.encodeIfPresent(pushWindow, forKey: .pushWindow)
    }

    init(
        ok: Bool,
        apiVersion: Int?,
        serverTimeRaw: String?,
        apps: [MonitorAppVersion],
        pending: Int,
        lastPushAtRaw: String?,
        pushWindow: PushWindow?
    ) {
        self.ok = ok
        self.apiVersion = apiVersion
        self.serverTimeRaw = serverTimeRaw
        self.apps = apps
        self.pending = pending
        self.lastPushAtRaw = lastPushAtRaw
        self.pushWindow = pushWindow
    }
}

// MARK: - 手动检查的回执

/// `POST /api/app/monitor/check` 的回执。
///
/// **注意**：这个端点的响应结构与 `GET /api/app/monitor` **不一样**（线上实测 2026-10-30）：
///   · 有：`checkedAt` / `feed{ok,mode,ageMin}` / `apps[{…,status,error}]`
///   · 没有：`pending` / `lastPushAt` / `pushWindow`
///   · `apps[]` 里用的是 `status` / `error`，不是 `hasNew` / `lastError`
///
/// 设计文档写的是「同结构 + 两个字段」，实测不是。所以这里只接**确实存在**的字段：
/// 回执只用来判断「这次检查成功了吗」，真正的展示状态一律回来源接口重新拉一次，
/// 不拿两种形状的数据硬拼（拼错了就是给用户看假版本号）。
///
/// 本类型只解码不编码（`Decodable`），避免为「快照里永远不会出现的东西」写 `encode(to:)`。
struct MonitorCheckReceipt: Decodable, Sendable {
    let ok: Bool
    let apiVersion: Int?
    /// 本次检查的服务端时刻（原始 ISO 字符串）
    let checkedAtRaw: String?
    /// 上游 App Store 数据源的状态；缺省即「服务端没给」
    let feed: MonitorCheckFeed?

    var checkedAt: Date? { MonitorTime.parse(checkedAtRaw) }

    private enum CodingKeys: String, CodingKey {
        case ok
        case apiVersion
        case checkedAt
        case feed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        apiVersion = try? container.decode(Int.self, forKey: .apiVersion)
        checkedAtRaw = try? container.decode(String.self, forKey: .checkedAt)
        feed = try? container.decode(MonitorCheckFeed.self, forKey: .feed)
    }

    init(ok: Bool, apiVersion: Int?, checkedAtRaw: String?, feed: MonitorCheckFeed?) {
        self.ok = ok
        self.apiVersion = apiVersion
        self.checkedAtRaw = checkedAtRaw
        self.feed = feed
    }
}

/// 检查回执里的上游数据源状态（`{"ok":true,"mode":"api","ageMin":13}`）
struct MonitorCheckFeed: Decodable, Sendable {
    let ok: Bool
    /// `"api"` / `"kv"`（服务端用哪种方式读到的版本）
    let mode: String
    /// 这份数据的「年龄」（分钟）。偏大说明服务端用的是兜底快照
    let ageMin: Int

    private enum CodingKeys: String, CodingKey {
        case ok
        case mode
        case ageMin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        mode = (try? container.decode(String.self, forKey: .mode)) ?? ""
        ageMin = (try? container.decode(Int.self, forKey: .ageMin)) ?? 0
    }

    init(ok: Bool, mode: String, ageMin: Int) {
        self.ok = ok
        self.mode = mode
        self.ageMin = ageMin
    }
}
