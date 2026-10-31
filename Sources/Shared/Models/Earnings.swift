import Foundation

// MARK: - 收益模块数据模型（批次 D · 任务 4）

/// 收益总览的「三态 + 统计」汇总。
///
/// 字段严格对齐线上 `GET /api/app/earnings` 的 `summary`（已线上验证，字段名以此为准）：
/// `pending`（待发）/ `receivedUnclosed`（已到账未结清）/ `closed`（已结清）/ `total`（三态之和）。
/// 不变量（服务端已保证）：`pending + receivedUnclosed + closed == total`。
struct EarningsSummary: Codable, Sendable {
    /// 待发放（未到账）金额（单位：分）
    let pending: Int
    /// 已到账但未结清金额（分）
    let receivedUnclosed: Int
    /// 已结清金额（分）
    let closed: Int
    /// 总金额（分）≡ pending + receivedUnclosed + closed
    let total: Int
    /// 本月新增（按 entry.time 归属当前自然月，分）
    let monthAdded: Int
    /// 活动总数
    let activityCount: Int
    /// 待结算活动数（未结清）
    let pendingActivityCount: Int
    /// 平台数
    let platformCount: Int
    /// 各平台金额占比（用于占比条），按金额降序
    let platformBreakdown: [EarningsPlatformBreakdown]

    private enum CodingKeys: String, CodingKey {
        case pending, receivedUnclosed, closed, total, monthAdded
        case activityCount, pendingActivityCount, platformCount, platformBreakdown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 服务端缺键时给 0：列表/统计缺失不该让整份总览崩掉
        pending = (try? c.decode(Int.self, forKey: .pending)) ?? 0
        receivedUnclosed = (try? c.decode(Int.self, forKey: .receivedUnclosed)) ?? 0
        closed = (try? c.decode(Int.self, forKey: .closed)) ?? 0
        total = (try? c.decode(Int.self, forKey: .total)) ?? 0
        monthAdded = (try? c.decode(Int.self, forKey: .monthAdded)) ?? 0
        activityCount = (try? c.decode(Int.self, forKey: .activityCount)) ?? 0
        pendingActivityCount = (try? c.decode(Int.self, forKey: .pendingActivityCount)) ?? 0
        platformCount = (try? c.decode(Int.self, forKey: .platformCount)) ?? 0
        platformBreakdown = (try? c.decode([EarningsPlatformBreakdown].self, forKey: .platformBreakdown)) ?? []
    }

    /// 供乐观更新时整体替换 summary 用（手写 memberwise，因自定义了 init(from:)）
    init(
        pending: Int,
        receivedUnclosed: Int,
        closed: Int,
        total: Int,
        monthAdded: Int,
        activityCount: Int,
        pendingActivityCount: Int,
        platformCount: Int,
        platformBreakdown: [EarningsPlatformBreakdown]
    ) {
        self.pending = pending
        self.receivedUnclosed = receivedUnclosed
        self.closed = closed
        self.total = total
        self.monthAdded = monthAdded
        self.activityCount = activityCount
        self.pendingActivityCount = pendingActivityCount
        self.platformCount = platformCount
        self.platformBreakdown = platformBreakdown
    }

    /// 防御性自检：三态恒等式是否成立（不强制，仅供调试参考）
    var isConsistent: Bool { pending + receivedUnclosed + closed == total }
}

/// 平台金额占比（单项）。`ratio` 是该平台金额占 `total` 的比例（0…1），用于横向堆叠条的宽度。
struct EarningsPlatformBreakdown: Codable, Identifiable, Sendable {
    let name: String
    /// 该平台金额（分）
    let amount: Int
    /// 占总额比例（0…1）
    let ratio: Double
    var id: String { name }

    private enum CodingKeys: String, CodingKey { case name, amount, ratio }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? "未分类"
        amount = (try? c.decode(Int.self, forKey: .amount)) ?? 0
        ratio = (try? c.decode(Double.self, forKey: .ratio)) ?? 0
    }

    init(name: String, amount: Int, ratio: Double) {
        self.name = name
        self.amount = amount
        self.ratio = ratio
    }
}

/// 平台聚合（来自响应顶层 `platforms`）。与 `platformBreakdown` 同源、按金额降序。
struct EarningsPlatform: Codable, Identifiable, Sendable {
    let name: String
    let pendingCents: Int
    let receivedCents: Int
    let acts: Int
    var id: String { name }

    private enum CodingKeys: String, CodingKey { case name, pendingCents, receivedCents, acts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? "未分类"
        pendingCents = (try? c.decode(Int.self, forKey: .pendingCents)) ?? 0
        receivedCents = (try? c.decode(Int.self, forKey: .receivedCents)) ?? 0
        acts = (try? c.decode(Int.self, forKey: .acts)) ?? 0
    }

    init(name: String, pendingCents: Int, receivedCents: Int, acts: Int) {
        self.name = name
        self.pendingCents = pendingCents
        self.receivedCents = receivedCents
        self.acts = acts
    }
}

/// 一个活动（如「抖音星图 9 月」）。
struct EarningsActivity: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let platform: String
    /// 活动创建时间（毫秒时间戳）
    let time: Int
    /// 结清时间（毫秒）；有值即视为已结清
    let closedAt: Int?
    let entries: [EarningsEntry]

    private enum CodingKeys: String, CodingKey { case id, name, platform, time, closedAt, entries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "未命名活动"
        platform = (try? c.decode(String.self, forKey: .platform)) ?? "未分类"
        time = (try? c.decode(Int.self, forKey: .time)) ?? 0
        closedAt = try? c.decode(Int.self, forKey: .closedAt)
        entries = (try? c.decode([EarningsEntry].self, forKey: .entries)) ?? []
    }

    init(id: String, name: String, platform: String, time: Int, closedAt: Int?, entries: [EarningsEntry]) {
        self.id = id
        self.name = name
        self.platform = platform
        self.time = time
        self.closedAt = closedAt
        self.entries = entries
    }

    /// 是否已结清（closedAt 命中即视为结清，与 web 端口径一致）
    var isClosed: Bool { closedAt != nil }
    /// 未软删除的条目（deletedAt 命中的不计入）
    var liveEntries: [EarningsEntry] { entries.filter { $0.deletedAt == nil } }
    /// 金额合计（分，仅统计有效条目）
    var totalCents: Int { liveEntries.reduce(0) { $0 + $1.centsValue } }
    /// 有效条目数
    var entryCount: Int { liveEntries.count }
}

/// 平台预设与排序（与网页端的 `FIXED` 逐字一致）。
///
/// 平台**不是独立实体**：服务端没有任何"平台表"，平台名只是活动的一个字段，
/// 平台列表由 `computeSummary` 从活动聚合出来。所以 App 侧也不需要存平台，
/// 只保留两件事：
/// 1. 建活动时给用户 5 个固定平台可以直接点（网页端 `var FIXED=[…]`）；
/// 2. 展示时按「固定 5 个在前、自定义按首次出现」排序 —— 顺序与服务端一致，
///    否则同一个账号在 App 与网页端看到的平台顺序会不一样。
enum EarningsPlatformPreset {

    /// 固定平台（顺序 = 网页端 `FIXED` 的顺序，不要重排）
    static let fixed: [String] = ["抖音", "快手", "小红书", "网易创作酱", "网易光遇追光计划"]

    /// 平台名上限（服务端 `MAX_PLATFORM_NAME`，与网页端 `slice(0,12)` 同口径）
    static let maxNameLength: Int = 12

    /// 活动名上限（服务端 `MAX_ACTIVITY_NAME`，与网页端 `slice(0,30)` 同口径）
    static let maxActivityNameLength: Int = 30

    /// 按「固定 5 个在前，自定义按首次出现」排好的平台列表。
    ///
    /// - Parameter activities: 服务端返回的活动（顺序即服务端数组顺序，最新的在最前）
    /// - Returns: 去重后的平台名；固定平台始终存在（即便当前一个活动都没有）
    static func ordered(from activities: [EarningsActivity]) -> [String] {
        var custom: [String] = []
        var seen = Set(fixed)
        for activity in activities {
            let name = activity.platform
            guard name.isEmpty == false, seen.contains(name) == false else { continue }
            seen.insert(name)
            custom.append(name)
        }
        return fixed + custom
    }

    /// 某个平台下的活动（保持服务端顺序，不重排）
    static func activities(_ activities: [EarningsActivity], in platform: String) -> [EarningsActivity] {
        return activities.filter { $0.platform == platform }
    }
}

/// 一笔收益条目（如「广告分成 +120」）。
///
/// 字段对齐 `GET` 的 `activities[].entries[]` 与 `POST` 返回的 `entry`。
/// `amountCents` 是服务端真实存储值（整数分）；`amount` 是双写的元（兼容展示）。
/// `amountCents` 声明为 `Int?` 而非 `Int`：服务端对**非法金额**的条目会返回 `null`，
/// 若声明为非可选会让整条记录（乃至整个活动）解码失败 —— 这里宁可读成 0 也不断层。
struct EarningsEntry: Codable, Identifiable, Sendable {
    let id: String
    /// 类型 / 标题（如「广告分成」，≤12 字）
    let type: String
    /// 金额（整数分）；非法时为 nil
    let amountCents: Int?
    /// 金额（元，双写）；非法时为 nil
    let amount: Double?
    /// 货币（白名单：CNY/USD/...）
    let currency: String?
    let note: String?
    /// 发生时间（毫秒时间戳）
    let time: Int
    /// 发生日期（'YYYY-MM-DD'）
    let date: String?
    /// 创建时间（毫秒）
    let createdAt: Int
    /// 是否已到账
    let paid: Bool
    /// 到账时间（毫秒）
    let paidAt: Int?
    /// 软删除时间（毫秒）；有值即视为已删除
    let deletedAt: Int?

    private enum CodingKeys: String, CodingKey {
        case id, type, amountCents, amount, currency, note, time, date, createdAt, paid, paidAt, deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        type = (try? c.decode(String.self, forKey: .type)) ?? "未分类"
        amountCents = try? c.decode(Int.self, forKey: .amountCents)
        amount = try? c.decode(Double.self, forKey: .amount)
        currency = try? c.decode(String.self, forKey: .currency)
        note = try? c.decode(String.self, forKey: .note)
        time = (try? c.decode(Int.self, forKey: .time)) ?? 0
        date = try? c.decode(String.self, forKey: .date)
        createdAt = (try? c.decode(Int.self, forKey: .createdAt)) ?? 0
        paid = (try? c.decode(Bool.self, forKey: .paid)) ?? false
        paidAt = try? c.decode(Int.self, forKey: .paidAt)
        deletedAt = try? c.decode(Int.self, forKey: .deletedAt)
    }

    init(id: String, type: String, amountCents: Int?, amount: Double?, currency: String?, note: String?, time: Int, date: String?, createdAt: Int, paid: Bool, paidAt: Int?, deletedAt: Int?) {
        self.id = id
        self.type = type
        self.amountCents = amountCents
        self.amount = amount
        self.currency = currency
        self.note = note
        self.time = time
        self.date = date
        self.createdAt = createdAt
        self.paid = paid
        self.paidAt = paidAt
        self.deletedAt = deletedAt
    }

    /// 金额（分），统一从 `amountCents` 取；为 nil 时按 0 处理（不崩、不显示乱码）
    var centsValue: Int { amountCents ?? 0 }
    /// 是否已软删除
    var isDeleted: Bool { deletedAt != nil }
}

/// `GET /api/app/earnings` 的响应信封。
struct EarningsResponse: Codable, Sendable {
    let ok: Bool
    let apiVersion: Int?
    let serverTime: String?
    let summary: EarningsSummary
    let activities: [EarningsActivity]
    let platforms: [EarningsPlatform]
    /// 金额单位（线上恒为 'fen' 分）。所有展示处靠它决定「÷100 还是原样」，不要硬编码假设
    let amountUnit: String

    private enum CodingKeys: String, CodingKey {
        case ok, apiVersion, serverTime, summary, activities, platforms, amountUnit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        apiVersion = try? c.decode(Int.self, forKey: .apiVersion)
        serverTime = try? c.decode(String.self, forKey: .serverTime)
        // 汇总缺失时给空结构，保证后续解析（activities 等）即便挂了也不连坐
        summary = (try? c.decode(EarningsSummary.self, forKey: .summary))
            ?? EarningsSummary(pending: 0, receivedUnclosed: 0, closed: 0, total: 0, monthAdded: 0, activityCount: 0, pendingActivityCount: 0, platformCount: 0, platformBreakdown: [])
        activities = (try? c.decode([EarningsActivity].self, forKey: .activities)) ?? []
        platforms = (try? c.decode([EarningsPlatform].self, forKey: .platforms)) ?? []
        amountUnit = (try? c.decode(String.self, forKey: .amountUnit)) ?? "fen"
    }

    init(ok: Bool, apiVersion: Int?, serverTime: String?, summary: EarningsSummary, activities: [EarningsActivity], platforms: [EarningsPlatform], amountUnit: String) {
        self.ok = ok
        self.apiVersion = apiVersion
        self.serverTime = serverTime
        self.summary = summary
        self.activities = activities
        self.platforms = platforms
        self.amountUnit = amountUnit
    }
}

/// `POST /api/app/earnings/entry` 的成功响应（`{ok, entry, summary, t, rev}`）。
struct EarningsAddResponse: Codable, Sendable {
    let ok: Bool
    let entry: EarningsEntry
    let summary: EarningsSummary

    private enum CodingKeys: String, CodingKey { case ok, entry, summary }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        entry = (try? c.decode(EarningsEntry.self, forKey: .entry))
            ?? EarningsEntry(id: "", type: "", amountCents: 0, amount: nil, currency: nil, note: nil, time: 0, date: nil, createdAt: 0, paid: false, paidAt: nil, deletedAt: nil)
        summary = (try? c.decode(EarningsSummary.self, forKey: .summary))
            ?? EarningsSummary(pending: 0, receivedUnclosed: 0, closed: 0, total: 0, monthAdded: 0, activityCount: 0, pendingActivityCount: 0, platformCount: 0, platformBreakdown: [])
    }
}

/// 新建活动的请求体（仅出，不用解码）：`{name, platform}`。
///
/// 平台在这里只是活动的一个字段，不是独立实体 —— 服务端的平台列表是从活动的
/// `platform` 聚合出来的（`computeSummary` 里的 `platMap`），所以新建活动只需要这两个字符串。
struct EarningsActivityInput: Encodable, Sendable {
    let name: String
    let platform: String
}

/// `POST /api/app/earnings/activity` 的成功响应（`{ok, activity, summary, t, rev}`）。
///
/// 与 `EarningsAddResponse` 同一套"缺字段不崩"的写法：服务端少给 `summary` 时给 0 结构，
/// 少给 `activity` 时给空活动（调用方仍能拿到 `ok` 与 `summary`，不至于因为有字段对不上就整条失败）。
struct EarningsActivityAddResponse: Codable, Sendable {
    let ok: Bool
    let activity: EarningsActivity
    let summary: EarningsSummary

    private enum CodingKeys: String, CodingKey { case ok, activity, summary }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        activity = (try? c.decode(EarningsActivity.self, forKey: .activity))
            ?? EarningsActivity(id: "", name: "", platform: "", time: 0, closedAt: nil, entries: [])
        summary = (try? c.decode(EarningsSummary.self, forKey: .summary))
            ?? EarningsSummary(pending: 0, receivedUnclosed: 0, closed: 0, total: 0, monthAdded: 0, activityCount: 0, pendingActivityCount: 0, platformCount: 0, platformBreakdown: [])
    }
}

/// 新增一笔 entry 的请求体（仅出，不用解码）。
///
/// 同时带上两套契约字段，保证命中服务端两种解析分支（任务简报 / 设计文档）：
///   · `title` 与 `type` 同值（服务端 type 优先、回退 title）
///   · `amount`（元，Double）与 `amountCents`（分，Int）同值
///   · `date`（'YYYY-MM-DD'）与 `time`（毫秒）同值
struct EarningsEntryInput: Encodable, Sendable {
    let activityId: String
    let type: String
    let amount: Double
    let amountCents: Int
    let currency: String
    let date: String
    let time: Int
    let note: String

    private enum CodingKeys: String, CodingKey {
        case activityId, title, type, amount, amountCents, currency, date, time, note
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(activityId, forKey: .activityId)
        // 两套契约字段都带：type 与 title 同值、amount 与 amountCents 同值、date 与 time 同值
        try c.encode(type, forKey: .type)
        try c.encode(type, forKey: .title)
        try c.encode(amount, forKey: .amount)
        try c.encode(amountCents, forKey: .amountCents)
        try c.encode(currency, forKey: .currency)
        try c.encode(date, forKey: .date)
        try c.encode(time, forKey: .time)
        try c.encode(note, forKey: .note)
    }
}

// MARK: - 金额格式化（唯一入口）

/// 收益金额格式化与单位管理。
///
/// **为什么集中在这里**：金额单位来自响应的 `amountUnit`（线上恒为 'fen' 分），
/// 但「尊重字段、不硬编码假设」是硬约束 —— 所以换算只发生在一处（`formatted(_:unit:)`），
/// 全工程其它任何地方都只调用 `formatCents(_:)`，绝不再出现 `÷100` 或 `×0.01` 散落。
enum EarningsMoney {
    /// 当前金额单位。每次拿到总览响应时由 `EarningsStore` 写回（来自 `response.amountUnit`），
    /// 所有展示处共用这一个来源，避免「分/元」判断散落到各个页面。
    static var currentUnit: String = "fen"

    /// 金额展示唯一入口：内部统一按 `currentUnit` 换算。其余地方不要再做单位换算。
    /// - Parameter cents: 服务端整数金额（单位 = currentUnit，实际恒为 fen 分）
    /// - Returns: 形如 `¥1,234.00`
    static func formatCents(_ cents: Int) -> String {
        return formatted(cents, unit: currentUnit)
    }

    /// 带显式单位的版本（跨响应 / 测试场景）。
    /// 唯一的「分→元」发生地：当 `unit == "fen"` 时 `÷100`；其余单位按原值展示（绝不假设成元）。
    static func formatted(_ cents: Int, unit: String) -> String {
        let value: Double
        if unit == "fen" {
            value = Double(cents) / 100.0   // 全工程唯一发生「分→元」的地方
        } else {
            value = Double(cents)
        }
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        nf.locale = Locale(identifier: "zh_CN")
        let body = nf.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "¥" + body
    }
}

// MARK: - 时间展示

/// 收益时间展示（毫秒时间戳 → 北京时间 `yyyy-MM-dd HH:mm`）。
enum EarningsClock {
    /// 毫秒时间戳 → 北京时间字符串；0 / nil → 占位「—」
    static func format(ms: Int?) -> String {
        guard let ms = ms, ms > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600) // 北京时间，与收益业务一致
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}
