import Combine
import Foundation

// MARK: - 一条账目

/// 本地账本的一条记录。
///
/// **口径**：这是「我自己记的账」，与 `EarningsSummary`（平台后台抓来的收益）是两套数，
/// 永远不相加、不互相覆盖。所以这个类型刻意不复用 `EarningsActivity / EarningsPlatform`：
/// 复用会诱导后来的人把两边混在同一个列表里算总额。
///
/// **金额**：一律 `Int` 存「分」。全工程不允许用 `Double` 参与金额运算 —— 分是最小货币单位，
/// 用整数存就不会出现 `0.1 + 0.2 = 0.30000000000000004` 这种对不上账的事。
struct LedgerEntry: Codable, Identifiable, Equatable {

    /// 收支方向。方向只存在这里，金额自己恒为非负（见 `signedCents`）。
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case income
        case expense

        var id: String { rawValue }

        var title: String {
            switch self {
            case .income: return "收入"
            case .expense: return "支出"
            }
        }

        /// 记账方向：收入 +1，支出 −1
        var sign: Int {
            switch self {
            case .income: return 1
            case .expense: return -1
            }
        }
    }

    /// 唯一标识（也是列表 `Identifiable` 的 id）
    let id: UUID
    /// 记账日期（用户可改，默认今天）
    var date: Date
    /// 金额，单位「分」，恒为非负；正负由 `kind` 决定
    var amountCents: Int
    /// 收入 / 支出
    var kind: Kind
    /// 分类（取值来自 `LedgerStore.categories(for:)`）
    var category: String
    /// 单行备注，允许空
    var note: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        amountCents: Int,
        kind: Kind,
        category: String,
        note: String = ""
    ) {
        self.id = id
        self.date = date
        // 金额恒为非负：传负数（例如误用符号）时取绝对值，方向交给 kind，绝不出现「负的收入」
        self.amountCents = amountCents < 0 ? -amountCents : amountCents
        self.kind = kind
        self.category = category
        self.note = note
    }

    /// 带符号金额（收入为正、支出为负），给"当天合计 / 结余"这类需要相加的地方用
    var signedCents: Int {
        return amountCents * kind.sign
    }
}

// MARK: - 月度小结 / 按天分组

/// 一个月的小结（单位统一「分」）。
struct LedgerMonthSummary: Equatable {
    /// 收入合计
    var incomeCents: Int = 0
    /// 支出合计
    var expenseCents: Int = 0

    /// 结余 = 收入 − 支出，可能为负
    var balanceCents: Int { incomeCents - expenseCents }
}

// MARK: - 分类 / 日历（不挂在 Store 上：展示层也要用，别把 View 牵连进 actor 隔离）

/// 分类常量。
///
/// 放这里而不是散在各 View 里：分类是**数据口径**，散出去就会长出「稿费 / 稿酬」两种叫法，
/// 月底按分类看的时候才发现对不上。
enum LedgerCategory {
    /// 收入分类
    static let income: [String] = ["稿费", "广告", "赞助", "周边", "订阅", "打赏", "其他收入"]
    /// 支出分类
    static let expense: [String] = ["设备", "素材", "外包", "推广", "税费", "其他支出"]

    static func list(for kind: LedgerEntry.Kind) -> [String] {
        switch kind {
        case .income: return income
        case .expense: return expense
        }
    }

    /// 新建时的默认分类（表单打开就有选中项，少一次点击）
    static func defaultName(for kind: LedgerEntry.Kind) -> String {
        return list(for: kind).first ?? ""
    }
}

/// 记账用的日历：固定北京时间，与 `Formatters` 的展示口径一致。
///
/// 为什么不在 `LedgerStore` 里挂一个 `static let`：`LedgerStore` 是 `@MainActor` 的，
/// 把只读常量挂在它身上会让 `LedgerLabel`（纯展示、非 MainActor）的读取变成跨 actor 访问。
/// 常量本来就是全局的，放在这里最省事也最安全。
enum LedgerCalendar {
    static let shared: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Formatters.beijing
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }()
}

/// 同一天的账目（列表按天分组用）。
struct LedgerDayGroup: Identifiable {
    /// 当天零点（北京时间）
    let day: Date
    /// 当天的账目，已按时间倒序
    let entries: [LedgerEntry]

    var id: Date { day }

    /// 当天带符号合计（收入 − 支出）
    var totalCents: Int {
        return entries.reduce(0) { $0 + $1.signedCents }
    }
}

// MARK: - 金额换算（唯一的「分 → 元」「元 → 分」入口）

/// 金额的解析与展示。
///
/// 全程整数运算：展示用 `/100` + `%100` 拼字符串，解析按「元」「分」两段逐位取数，
/// 一次 `Double` 都不出现（金额运算里出现浮点 = 迟早对不上账）。
enum LedgerMoney {

    /// 分 → `¥1,234.05`（负数前加 `−`）
    static func format(cents: Int) -> String {
        let value = Int64(cents)
        let negative = value < 0
        let magnitude = negative ? -value : value
        let body = "¥" + grouped(magnitude / 100) + "." + twoDigits(Int(magnitude % 100))
        return negative ? "−" + body : body
    }

    /// 带符号展示：收入 `+¥12.50`、支出 `−¥12.50`（0 显示 `+¥0.00`）
    static func formatSigned(cents: Int) -> String {
        let value = Int64(cents)
        let magnitude = value < 0 ? -value : value
        let body = format(cents: Int(magnitude))
        return (value < 0 ? "−" : "+") + body
    }

    /// 分 → 输入框回填用的裸数字：`1250` → `12.5`，`1200` → `12`（末尾的 0 省掉，改起来更省事）
    static func plainAmount(cents: Int) -> String {
        let value = Int64(cents)
        let magnitude = value < 0 ? -value : value
        let yuan = magnitude / 100
        let fen = Int(magnitude % 100)
        if fen == 0 {
            return String(yuan)
        }
        if fen % 10 == 0 {
            return String(yuan) + "." + String(fen / 10)
        }
        return String(yuan) + "." + twoDigits(fen)
    }

    /// 输入框文字 → 分。`"12.5"` → `1250`，`"12"` → `1200`，`"0.05"` → `5`。
    ///
    /// 解析规则（够用且可解释，不做汇率那种复杂事）：
    /// - 容忍粘贴进来的 `¥` / `￥` / 千分位 `,` / 空格；
    /// - 小数点后最多取 2 位，第 3 位按四舍五入进到「分」；
    /// - 负数、多个小数点、夹字母一律返回 `nil`（金额方向由收入/支出决定，不需要负号）。
    static func parseAmount(_ text: String) -> Int? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        for symbol in ["¥", "￥", ",", " ", "\u{00A0}", "+"] {
            body = body.replacingOccurrences(of: symbol, with: "")
        }
        guard !body.isEmpty, !body.hasPrefix("-") else { return nil }

        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }

        let yuanText = String(parts[0])
        let fenText = parts.count == 2 ? String(parts[1]) : ""
        guard yuanText.allSatisfy({ $0.isNumber }), fenText.allSatisfy({ $0.isNumber }) else { return nil }

        // 整数部分：空串合法（".5" = 5 毛）；上限 1 亿，防溢出也防手滑多按几个 0
        var yuan = 0
        if !yuanText.isEmpty {
            guard let parsed = Int(yuanText), parsed <= 100_000_000 else { return nil }
            yuan = parsed
        } else if fenText.isEmpty {
            return nil
        }

        // 小数部分：逐位取数后拼成「分」，不经过浮点
        let digits = Array(fenText).map { Int(String($0)) ?? 0 }
        let jiao = digits.count > 0 ? digits[0] : 0
        let fen = digits.count > 1 ? digits[1] : 0
        let extra = digits.count > 2 ? digits[2] : 0
        var fenTotal = jiao * 10 + fen
        if extra >= 5 {
            fenTotal += 1 // 第三位四舍五入进「分」
        }

        let total = yuan * 100 + fenTotal
        return total >= 0 ? total : nil
    }

    // MARK: - 内部格式化

    /// 千分位分组（`1234567` → `1,234,567`）。手写而不是 `NumberFormatter`：
    /// `NumberFormatter` 的入参是 `Double`/`NSNumber`，在金额链路上没必要引入浮点。
    private static func grouped(_ value: Int64) -> String {
        let digits = String(value)
        guard digits.count > 3 else { return digits }
        var result = ""
        var counter = 0
        for character in digits.reversed() {
            if counter > 0 && counter % 3 == 0 {
                result.append(",")
            }
            result.append(character)
            counter += 1
        }
        return String(result.reversed())
    }

    /// 补足两位（`5` → `05`）
    private static func twoDigits(_ value: Int) -> String {
        return value < 10 ? "0" + String(value) : String(value)
    }
}

// MARK: - 账本

/// 本地账本的唯一数据源。
///
/// 为什么自己写一个而不是丢进 `UserDefaults` / SwiftData：
/// 1. 账目会一直增长，`UserDefaults` 存数组是反模式（每次读都要整段反序列化，且没有原子性保证）；
/// 2. SwiftData 会绑死 iOS 17+ 的模型容器与迁移路径，而这一份数据只有「一个 `Codable` 数组」
///    这么简单的形状，一个 JSON 文件就够，出问题还能直接打开看。
///
/// **落盘策略**：任何写操作（`add` / `update` / `delete`）立刻整份原子写盘（`.atomic`）。
/// 账本量级是每月几十条、一年几百条，整份重写成本可以忽略，换来的是"杀进程重开数据还在"。
///
/// **读失败不崩**：文件缺失 / 内容损坏 / 换机型后解不开，一律当作空账本启动。
/// 账本丢了是遗憾，崩溃是事故 —— 这个取舍是刻意的。
@MainActor
final class LedgerStore: ObservableObject {

    /// 全 App 共用一份（`EarningsView` 与弹出的表单读写同一实例，不需要传 Binding）
    static let shared = LedgerStore()

    /// 账本文件名（放在 Application Support 下，不进 Documents）
    static let fileName = "ledger.json"

    /// 分组 / 月度边界用的日历（转发到 `LedgerCalendar`，保持"账本口径只有一处"的读法）
    nonisolated static var calendar: Calendar { LedgerCalendar.shared }

    /// 收入分类
    nonisolated static var incomeCategories: [String] { LedgerCategory.income }

    /// 支出分类
    nonisolated static var expenseCategories: [String] { LedgerCategory.expense }

    /// 全部账目，按时间倒序（新的在前）
    @Published private(set) var entries: [LedgerEntry] = []

    /// 上一次写盘是否失败。失败时页面给一行提示 —— 让用户知道"这笔可能存不住"，
    /// 比静默丢数据好（本 App 没有账号体系，账本只在这台手机上，丢了就真没了）。
    @Published private(set) var saveFailed: Bool = false

    /// 账本文件位置
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultFileURL()
        self.fileURL = url
        self.entries = Self.loadEntries(from: url)
    }

    // MARK: - 分类

    nonisolated static func categories(for kind: LedgerEntry.Kind) -> [String] {
        return LedgerCategory.list(for: kind)
    }

    /// 新建时的默认分类（表单打开就有选中项，少一次点击）
    nonisolated static func defaultCategory(for kind: LedgerEntry.Kind) -> String {
        return LedgerCategory.defaultName(for: kind)
    }

    // MARK: - 写

    /// 新增一笔。落盘失败不回滚内存（本次会话仍能看到这笔），只把 `saveFailed` 亮起来
    func add(_ entry: LedgerEntry) {
        entries = Self.sorted(entries + [entry])
        persist()
    }

    /// 改一笔（按 id 定位）。找不到就当作新增，避免"改了但没存上"这种沉默失败
    func update(_ entry: LedgerEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            add(entry)
            return
        }
        entries[index] = entry
        entries = Self.sorted(entries)
        persist()
    }

    /// 删一笔
    func delete(id: UUID) {
        let remaining = entries.filter { $0.id != id }
        guard remaining.count != entries.count else { return }
        entries = remaining
        persist()
    }

    // MARK: - 读

    /// 某个月的全部账目（时间倒序）
    func entries(in month: Date) -> [LedgerEntry] {
        guard let interval = Self.calendar.dateInterval(of: .month, for: month) else { return [] }
        return entries.filter { interval.contains($0.date) }
    }

    /// 某个月的小结（收入 / 支出 / 结余，单位分）
    func monthSummary(of month: Date) -> LedgerMonthSummary {
        var summary = LedgerMonthSummary()
        for entry in entries(in: month) {
            switch entry.kind {
            case .income: summary.incomeCents += entry.amountCents
            case .expense: summary.expenseCents += entry.amountCents
            }
        }
        return summary
    }

    /// 某个月的账目按天分组（天新的在前，天内时间新的在前）
    func dayGroups(in month: Date) -> [LedgerDayGroup] {
        var order: [Date] = []
        var buckets: [Date: [LedgerEntry]] = [:]
        for entry in entries(in: month) {
            let day = Self.calendar.startOfDay(for: entry.date)
            if buckets[day] == nil {
                order.append(day)
                buckets[day] = []
            }
            buckets[day]?.append(entry)
        }
        // 不依赖字典的遍历顺序：分组顺序由 `order`（已经是倒序）决定
        return order.map { LedgerDayGroup(day: $0, entries: buckets[$0] ?? []) }
    }

    // MARK: - 落盘

    /// 账本文件：`Application Support/ledger.json`
    ///
    /// 为什么是 Application Support 而不是 Documents：Documents 默认进 iCloud 备份，
    /// 账本是"这台手机上的私人草稿"，没必要跟着备份走；而 Caches 会被系统回收，不行。
    private static func defaultFileURL() -> URL {
        let manager = FileManager.default
        let base: URL
        if let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            base = support
        } else {
            // 极少数沙盒异常情况下退回临时目录：宁可能用，也不要因为没有路径而拿不到账本
            base = manager.temporaryDirectory
        }
        if !manager.fileExists(atPath: base.path) {
            try? manager.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func loadEntries(from url: URL) -> [LedgerEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([LedgerEntry].self, from: data) else {
            // 文件损坏：当成空账本，绝不让解码失败把 App 带崩
            return []
        }
        return sorted(decoded)
    }

    /// 整份原子写盘。`.atomic` 保证「要么是旧文件，要么是新文件」，不会写出半个 JSON
    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
            if saveFailed {
                saveFailed = false
            }
        } catch {
            saveFailed = true
        }
    }

    /// 排序：日期新的在前；同一天保持录入顺序
    ///
    /// 为什么要自己带原序号：`Array.sorted` 不保证稳定，同一天的几笔金额一样时顺序会随机跳动，
    /// 列表就会在每次刷新后自己重排。带上原序号后顺序完全确定。
    /// （用闭包取 `offset` / `entry` 而不是 `\.element` 这类 key path —— Swift 的 key path
    /// 不支持元组成员，写 `\.element` 直接编译不过。）
    private static func sorted(_ list: [LedgerEntry]) -> [LedgerEntry] {
        var indexed: [(offset: Int, entry: LedgerEntry)] = []
        indexed.reserveCapacity(list.count)
        for (offset, entry) in list.enumerated() {
            indexed.append((offset: offset, entry: entry))
        }
        indexed.sort { lhs, rhs in
            if lhs.entry.date != rhs.entry.date {
                return lhs.entry.date > rhs.entry.date
            }
            return lhs.offset < rhs.offset
        }
        return indexed.map { $0.entry }
    }
}
