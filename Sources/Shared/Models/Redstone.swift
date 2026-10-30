import Foundation

// MARK: - 日期 / 时刻工具

/// 红石的日期与时刻换算。
///
/// 为什么单独一个 enum 而不是散在 View 里算：服务端给的 `date` 是**北京时区的自然日**
/// （`"2026-10-03"`），而 `times` 是当天的北京时刻（`"10:08"`）。这两段拼成绝对时刻时，
/// 一旦用设备时区或 `ISO8601DateFormatter` 的默认时区，跨时区用户会看到「昨天 23:08」甚至
/// 场次整体漂到前一天 —— 这是设计文档 §7.1 明确点名的坑。所有换算只走这里，只有一处时区。
///
/// 另一条理由：`DateFormatter` 每次 `string(from:)` 都要建 ICU 对象，日历一格渲染 42 次会明显掉帧。
/// 这里全部用 `Calendar` + `DateComponents` 做整数运算，零 formatter。
enum RedstoneClock {

    /// 北京时间（UTC+8，无夏令时）。`TimeZone(secondsFromGMT:)` 理论上不会返回 nil，
    /// 但绝不 force unwrap —— 拿不到就退回 `Asia/Shanghai`，再拿不到才用设备时区（最后兜底）。
    static let beijing: TimeZone = TimeZone(secondsFromGMT: 8 * 3600)
        ?? TimeZone(identifier: "Asia/Shanghai")
        ?? TimeZone.current

    /// 全工程红石共用的日历（公历 + 北京时区 + 中文）。
    /// `firstWeekday` 保持系统默认（1 = 周日）：月历「周一为首列」的偏移由 `mondayOffset` 自己算，
    /// 不去改日历的语义，免得同一个 Calendar 在不同视图里表现不一致。
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = beijing
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }()

    /// `"2026-10-03"` + `"10:08"` → 绝对时刻。任一段非法返回 nil（脏数据不参与判定，也不崩）。
    ///
    /// 显式 `timeZone = beijing` 是这段代码存在的全部意义：`Calendar.date(from:)` 若不带时区，
    /// 会用日历自身的时区（这里已设），但 `DateComponents` 再写一遍能让「意图」留在调用点。
    static func date(day: String, time: String) -> Date? {
        guard let ymd = parseDay(day), let hm = parseTime(time) else { return nil }
        var components = DateComponents()
        components.year = ymd.year
        components.month = ymd.month
        components.day = ymd.day
        components.hour = hm.hour
        components.minute = hm.minute
        components.second = 0
        components.timeZone = beijing
        return calendar.date(from: components)
    }

    /// 某个自然日的零点（北京）。月历画格子用。
    static func startOfDay(dayKey: String) -> Date? {
        guard let ymd = parseDay(dayKey) else { return nil }
        var components = DateComponents()
        components.year = ymd.year
        components.month = ymd.month
        components.day = ymd.day
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = beijing
        return calendar.date(from: components)
    }

    /// `"2026-10-30"`
    static func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// `"2026-10"`
    static func monthKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 1970, parts.month ?? 1)
    }

    static func monthKey(year: Int, month: Int) -> String {
        return String(format: "%04d-%02d", year, month)
    }

    /// `"2026-10"` → `(2026, 10)`。非法返回 nil。
    static func yearMonth(from monthKey: String) -> (year: Int, month: Int)? {
        let parts = monthKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else { return nil }
        return (year, month)
    }

    /// 月份加减。用 `Calendar.date(byAdding:)` 而不是手写 `month + offset`：
    /// 跨年（12 月 +1 = 次年 1 月）由日历负责，手写一定会漏。
    static func month(adding offset: Int, to monthKey: String) -> String {
        guard let parts = yearMonth(from: monthKey) else { return monthKey }
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month
        components.day = 1
        components.hour = 12          // 中午 12 点：任何时区下都不会因 DST/零点漂移退到上月
        components.timeZone = beijing
        guard let base = calendar.date(from: components),
              let shifted = calendar.date(byAdding: .month, value: offset, to: base) else {
            return monthKey
        }
        return self.monthKey(shifted)
    }

    /// 该月 1 号。
    static func monthStart(_ monthKey: String) -> Date? {
        guard let parts = yearMonth(from: monthKey) else { return nil }
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month
        components.day = 1
        components.hour = 0
        components.timeZone = beijing
        return calendar.date(from: components)
    }

    /// 该月天数（28–31）。
    static func dayCount(in monthKey: String) -> Int {
        guard let start = monthStart(monthKey),
              let range = calendar.range(of: .day, in: .month, for: start) else { return 30 }
        return range.count
    }

    /// 该月 1 号在「周一为首列」网格里的列号（周一 = 0 … 周日 = 6）。
    ///
    /// `Calendar.component(.weekday)` 是 1 = 周日 … 7 = 周六，所以要 +5 再 %7 才能把周一挪到 0。
    static func mondayOffset(ofMonth monthKey: String) -> Int {
        guard let start = monthStart(monthKey) else { return 0 }
        return mondayIndex(of: start)
    }

    /// 任意时刻在「周一为首列」里的列号（周一 = 0 … 周日 = 6）。
    static func mondayIndex(of date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    /// 明天（按北京日算，不用 +86400：`+86400` 在无夏令时的中国也对，但用日历更不容易被后人改坏）
    static func nextDayKey(_ dayKey: String) -> String {
        guard let start = startOfDay(dayKey: dayKey),
              let next = calendar.date(byAdding: .day, value: 1, to: start) else { return dayKey }
        return self.dayKey(next)
    }

    // MARK: - 内部解析

    private static func parseDay(_ raw: String) -> (year: Int, month: Int, day: Int)? {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day) else { return nil }
        return (year, month, day)
    }

    private static func parseTime(_ raw: String) -> (hour: Int, minute: Int)? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }
}

// MARK: - 响应信封

/// `GET /api/app/redstone` 的响应（真实线上响应为准，字段名逐字对齐，不做二次命名）。
///
/// 为什么手写 `init(from:)`：契约里有 4 个「服务端缺省而不是给 null」的字段
/// （`rules` / `warning` / `range` / `coveredRanges`）。合成解码遇到缺键会直接抛错，
/// 整份排期跟着作废；手写之后缺键只让该字段为空，页面照常显示（设计文档 §7.1）。
struct RedstoneResponse: Codable, Sendable {
    let ok: Bool
    let apiVersion: Int?
    /// 服务端当前时刻（带毫秒的 ISO）。App 不拿它算倒计时（倒计时用本地 now），只留作调试
    let serverTime: Date?
    /// KV meta.updated，**毫秒**时间戳。0 = 从未生成
    let updated: Int
    let source: String
    let range: RedstoneRange?
    let coveredMonths: [String]
    let coveredRanges: String
    let hasNextMonth: Bool
    let items: [RedstoneDay]
    /// 只有 `?action=rules`（或 `?rules=1`）才出现；其余请求该键缺省
    let rules: RedstoneRules?
    /// 整月缺时刻时服务端给的人话提示（如「3 天缺场次时刻」），无则缺省
    let warning: String?

    private enum CodingKeys: String, CodingKey {
        case ok
        case apiVersion
        case serverTime
        case updated
        case source
        case range
        case coveredMonths
        case coveredRanges
        case hasNextMonth
        case items
        case rules
        case warning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        apiVersion = try? container.decode(Int.self, forKey: .apiVersion)
        serverTime = try? container.decode(Date.self, forKey: .serverTime)
        // 毫秒时间戳先用 Double 兜一层：某些运行时会把 1.79e12 序列化成浮点，Int 解码会失败
        if let milliseconds = try? container.decode(Double.self, forKey: .updated) {
            updated = Int(milliseconds)
        } else {
            updated = (try? container.decode(Int.self, forKey: .updated)) ?? 0
        }
        source = (try? container.decode(String.self, forKey: .source)) ?? ""
        range = try? container.decode(RedstoneRange.self, forKey: .range)
        coveredMonths = (try? container.decode([String].self, forKey: .coveredMonths)) ?? []
        coveredRanges = (try? container.decode(String.self, forKey: .coveredRanges)) ?? ""
        hasNextMonth = (try? container.decode(Bool.self, forKey: .hasNextMonth)) ?? false
        items = (try? container.decode([RedstoneDay].self, forKey: .items)) ?? []
        rules = try? container.decode(RedstoneRules.self, forKey: .rules)
        warning = try? container.decode(String.self, forKey: .warning)
    }

    /// 供预览 / 测试直接构造（自定义 `init(from:)` 会吃掉自动生成的 memberwise init）
    init(
        ok: Bool,
        apiVersion: Int?,
        serverTime: Date?,
        updated: Int,
        source: String,
        range: RedstoneRange?,
        coveredMonths: [String],
        coveredRanges: String,
        hasNextMonth: Bool,
        items: [RedstoneDay],
        rules: RedstoneRules?,
        warning: String?
    ) {
        self.ok = ok
        self.apiVersion = apiVersion
        self.serverTime = serverTime
        self.updated = updated
        self.source = source
        self.range = range
        self.coveredMonths = coveredMonths
        self.coveredRanges = coveredRanges
        self.hasNextMonth = hasNextMonth
        self.items = items
        self.rules = rules
        self.warning = warning
    }
}

/// 生效范围回显（`{"from":"2026-10-01","to":"2026-10-31"}`）。
struct RedstoneRange: Codable, Sendable, Equatable {
    let from: String
    let to: String

    private enum CodingKeys: String, CodingKey {
        case from
        case to
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = (try? container.decode(String.self, forKey: .from)) ?? ""
        to = (try? container.decode(String.self, forKey: .to)) ?? ""
    }

    init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

// MARK: - 一天

/// 一个自然日的红石条目。
///
/// 命名说明：设计文档的类图把它叫 `RedstoneItem`，本批按「一天一条」的语义命名为 `RedstoneDay`，
/// 并保留 `RedstoneItem` 别名，避免后续批次按类图找类型时找不到。
struct RedstoneDay: Codable, Sendable, Identifiable, Equatable {
    /// `"2026-10-30"`（北京时区自然日）
    let date: String
    /// `"红石"` | `"黑石"`。枚举字符串一律当 `String` 存，未知值不崩（§7.1）
    let type: String
    /// `"霞谷·圆梦村"`；`"待确认"` 表示引擎无数据
    let map: String
    /// `["11:08","17:08","23:08"]`，升序；可能为空数组（该日无场次）
    let times: [String]
    /// 倍率（2 / 2.5 / 3.5）。`nil` 仅当 `map == "待确认"`，此时**不渲染**倍率徽标
    let rate: Double?
    /// 是否待玩家核对。**不参与任何时间计算**，只降可信度
    let needsCheck: Bool
    let note: String

    /// `Identifiable` 用日期做 id：同一天只会有一条（服务端按 date 归一）
    var id: String { date }

    /// 是否红石（含「黑」即黑石，与服务端归一规则一致）
    var isRedstone: Bool { !type.contains("黑") }

    /// 当天场次数（`times` 可能为空）
    var sessionCount: Int { times.count }

    private enum CodingKeys: String, CodingKey {
        case date
        case type
        case map
        case times
        case rate
        case needsCheck
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? container.decode(String.self, forKey: .date)) ?? ""
        type = (try? container.decode(String.self, forKey: .type)) ?? "红石"
        map = (try? container.decode(String.self, forKey: .map)) ?? "待确认"
        times = (try? container.decode([String].self, forKey: .times)) ?? []
        // rate 在 JSON 里是 2 / 2.5 这种数字，Double 解码能吃整数，不需要额外分支
        rate = try? container.decode(Double.self, forKey: .rate)
        needsCheck = (try? container.decode(Bool.self, forKey: .needsCheck)) ?? false
        note = (try? container.decode(String.self, forKey: .note)) ?? ""
    }

    init(date: String, type: String, map: String, times: [String], rate: Double?, needsCheck: Bool, note: String) {
        self.date = date
        self.type = type
        self.map = map
        self.times = times
        self.rate = rate
        self.needsCheck = needsCheck
        self.note = note
    }
}

/// 类图里的名字（见 `RedstoneDay` 的命名说明）
typealias RedstoneItem = RedstoneDay

// MARK: - 场次

/// 一场具体的红石落地（date + time 摊平成绝对时刻）。
///
/// 为什么不直接用 `RedstoneDay.times` 算倒计时：`times` 是字符串，每次比较都要重新拼时刻；
/// 摊平成 `Occurrence` 之后「进行中 / 下一场 / 今日剩余」都是纯时间比较，Widget 侧也能直接复用。
struct Occurrence: Sendable, Identifiable, Equatable {
    /// 所属自然日（`"2026-10-30"`）
    let date: String
    /// 落地时刻（北京时区解析出的绝对时刻）
    let startAt: Date
    /// 结束时刻 = `startAt + 52 分钟`（单场约 52 分钟，PRD §5.1）
    let endAt: Date
    /// `"11:08"`（原样保留，展示用）
    let time: String
    let map: String
    let rate: Double?
    let needsCheck: Bool
    let type: String

    /// 同一天同一时刻只可能有一场，拼起来天然唯一
    var id: String { date + " " + time }

    /// 该场是否属于「今天」（北京日）
    func isOn(dayKey: String) -> Bool { date == dayKey }
}

// MARK: - 规律

/// `?action=rules` 附带的规律摘要。
///
/// 全部字段都做兜底：规律页取不到数据时用本地内置文案（PRD P05），
/// 所以这里的空值语义是「这条规律没有服务端版本」，不是错误。
struct RedstoneRules: Codable, Sendable, Equatable {
    let version: String
    /// 日期规律的一句话描述
    let date: String
    /// `{"周六": "10:08 / 14:08 / 22:08", …}`
    let times: [String: String]
    /// 大池 5 个点位
    let big5: [String]
    /// 小池点位
    let smallPool: [String]
    /// `{"2.0": [...地图], "2.5": [...], "3.5": [...]}` —— 键是**一位小数字符串**
    let rates: [String: [String]]
    let rateValues: [Double]
    let sundayRing: String
    let monthEquiv: [String]
    let anchorCount: Int
    /// `{"2027-02-07": "云野·圣岛"}` —— 玩家校准过的种子
    let seeds: [String: String]

    private enum CodingKeys: String, CodingKey {
        case version
        case date
        case times
        case big5
        case smallPool
        case rates
        case rateValues
        case sundayRing
        case monthEquiv
        case anchorCount
        case seeds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decode(String.self, forKey: .version)) ?? ""
        date = (try? container.decode(String.self, forKey: .date)) ?? ""
        times = (try? container.decode([String: String].self, forKey: .times)) ?? [:]
        big5 = (try? container.decode([String].self, forKey: .big5)) ?? []
        smallPool = (try? container.decode([String].self, forKey: .smallPool)) ?? []
        rates = (try? container.decode([String: [String]].self, forKey: .rates)) ?? [:]
        rateValues = (try? container.decode([Double].self, forKey: .rateValues)) ?? []
        sundayRing = (try? container.decode(String.self, forKey: .sundayRing)) ?? ""
        monthEquiv = (try? container.decode([String].self, forKey: .monthEquiv)) ?? []
        anchorCount = (try? container.decode(Int.self, forKey: .anchorCount)) ?? 0
        seeds = (try? container.decode([String: String].self, forKey: .seeds)) ?? [:]
    }

    init(
        version: String,
        date: String,
        times: [String: String],
        big5: [String],
        smallPool: [String],
        rates: [String: [String]],
        rateValues: [Double],
        sundayRing: String,
        monthEquiv: [String],
        anchorCount: Int,
        seeds: [String: String]
    ) {
        self.version = version
        self.date = date
        self.times = times
        self.big5 = big5
        self.smallPool = smallPool
        self.rates = rates
        self.rateValues = rateValues
        self.sundayRing = sundayRing
        self.monthEquiv = monthEquiv
        self.anchorCount = anchorCount
        self.seeds = seeds
    }

    /// 倍率 → 查表键。
    ///
    /// **不能用 `String(rate)`**：`String(2.0)` 得到 `"2.0"`，但 `String(2)` 得到的会是 `"2"`，
    /// 而服务端把键统一成一位小数（`2.0` / `2.5` / `3.5`）。`String(format: "%.1f", …)` 是唯一稳的写法。
    static func rateKey(_ rate: Double) -> String {
        return String(format: "%.1f", rate)
    }

    /// 某倍率对应的点位列表（查不到就是空数组，页面不渲染这一段）
    func maps(forRate rate: Double) -> [String] {
        return rates[RedstoneRules.rateKey(rate)] ?? []
    }

    /// 倍率展示文案（`2.5×`）。`nil` 不展示，绝不显示 `—`
    static func rateText(_ rate: Double?) -> String? {
        guard let rate = rate else { return nil }
        return String(format: "%.1f", rate) + "×"
    }
}
