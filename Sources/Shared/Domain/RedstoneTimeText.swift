import Foundation

/// 红石「降落 → 结束」时间的**唯一格式化器**（R3 · 架构 §1.3 / §3.2）。
///
/// ## 三条硬纪律
/// 1. **唯一真值是 `Occurrence.startAt` / `endAt`**。52 分钟这个口径只存在于
///    `RedstoneTimeline.landingMinutes`（那才是生成 `endAt` 的地方）；
///    本文件**绝不重算结束时刻**，只把已经算好的两个绝对时刻读出来显示。
///    `daySheet` 里那句「N 分钟」是 `endAt - startAt` 的读数，不是第二套时长公式。
/// 2. **一律北京时间**：钟面值走 `Formatters.timeHHmm`（UTC+8 已钉死），
///    跨日靠 `RedstoneClock.dayKey` 比较**北京日历日**（含年月，跨月 / 跨年自动覆盖），
///    绝不靠 `endAt.hour < startAt.hour` 这种近似。
/// 3. **`notGenerated` / nil occurrence 返回 nil**：调用方整块不渲染，
///    不出现 `--:--` / `00:00` / 任何占位时间。
///
/// 为什么放在 `Sources/Shared/Domain`：App 的 `RockPhaseText` 与 Widget 的
/// `RedstoneFace` 分属两个 target，只有 Shared 两边都编译，才不会出现
///「手机写 12:00、桌面写 11:08」这种两套文案。
enum RedstoneTimeText {

    // MARK: - 跨日

    /// 起止是否跨了北京的日历日（`23:30 → 次日 00:22`）。
    ///
    /// 用 `dayKey` 而不是「小时数比较」：跨月（`10-31 23:30 → 11-01 00:22`）
    /// 与跨年同理，日键不同即跨日，不依赖任何小时大小关系。
    static func isCrossDay(_ o: Occurrence) -> Bool {
        return RedstoneClock.dayKey(o.startAt) != RedstoneClock.dayKey(o.endAt)
    }

    // MARK: - 架构签名（已确认有 occurrence）

    /// 紧凑区间：`11:08–12:00` / `23:30–次日 00:22`（Q9）
    static func compactRange(_ o: Occurrence) -> String {
        let start = Formatters.timeHHmm(o.startAt)
        let end = Formatters.timeHHmm(o.endAt)
        return isCrossDay(o) ? "\(start)–次日 \(end)" : "\(start)–\(end)"
    }

    /// 详情行：`降落 11:08 · 结束 12:00` / `降落 23:30 · 次日 00:22 结束`（Q9）
    static func detail(_ o: Occurrence) -> String {
        let start = Formatters.timeHHmm(o.startAt)
        let end = Formatters.timeHHmm(o.endAt)
        if isCrossDay(o) {
            return "降落 \(start) · 次日 \(end) 结束"
        }
        return "降落 \(start) · 结束 \(end)"
    }

    /// 只报结束：`12:00 结束` / `次日 00:22 结束`（Widget ongoing / 实时活动用）
    static func endOnly(_ o: Occurrence) -> String {
        let end = Formatters.timeHHmm(o.endAt)
        return isCrossDay(o) ? "次日 \(end) 结束" : "\(end) 结束"
    }


    /// 小号两行的第二行：`至 12:00` / `至 次日 00:22`。
    ///
    /// 与 `endOnly` 的区别只在前缀：小号主数字已经写了 `11:08`，第二行只要
    /// 接一句「至几点」，不必再说一次「结束」。同样只读 `o.endAt`，不重算 52 分钟。
    static func endLine(_ o: Occurrence) -> String {
        let end = Formatters.timeHHmm(o.endAt)
        return isCrossDay(o) ? "至 次日 \(end)" : "至 \(end)"
    }

    /// 日详情 sheet：`11:08 → 12:00（52 分钟）`。
    ///
    /// 分钟数直接读 `endAt - startAt`（唯一真值），不是 `startAt + 52 * 60`。
    /// 脏数据（`endAt <= startAt`，附录 B 的 `endAt == startAt` 用例）解出 0 或负数时
    /// **整段时长不写** —— 宁可少一句，也不编一个「0 分钟」糊弄人。
    static func daySheet(_ o: Occurrence) -> String {
        let start = Formatters.timeHHmm(o.startAt)
        let end = Formatters.timeHHmm(o.endAt)
        let minutes = Int(o.endAt.timeIntervalSince(o.startAt) / 60)
        guard minutes > 0 else {
            return "\(start) → \(end)"
        }
        return "\(start) → \(end)（\(minutes) 分钟）"
    }

    // MARK: - nil 安全重载（`RockPhase.occurrence` 是 `Occurrence?`）
    //
    // `RockPhase.notGenerated` / 数据还没生成时 `occurrence` 为 nil。
    // 调用方（T03 的 `NextEventBar` / `RedstoneFace` / 实时活动）直接把
    // `phase.occurrence` 传进来即可：nil 走这一组重载返回 nil，整块不渲染。
    // 两组同名形成重载：传 `Occurrence` 得 `String`，传 `Occurrence?` 得 `String?`，
    // 架构 §1.3 的签名与本批「不渲染占位」的要求同时满足。

    /// `nil` → `nil`（不渲染任何时间）
    static func compactRange(_ o: Occurrence?) -> String? {
        guard let o = o else { return nil }
        return compactRange(o)
    }

    /// `nil` → `nil`
    static func detail(_ o: Occurrence?) -> String? {
        guard let o = o else { return nil }
        return detail(o)
    }

    /// `nil` → `nil`
    static func endOnly(_ o: Occurrence?) -> String? {
        guard let o = o else { return nil }
        return endOnly(o)
    }


    /// `nil` → `nil`（小号 `entry.focus` 是 `Occurrence?`，notGenerated 时整行不渲染）
    static func endLine(_ o: Occurrence?) -> String? {
        guard let o = o else { return nil }
        return endLine(o)
    }

    /// `nil` → `nil`
    static func daySheet(_ o: Occurrence?) -> String? {
        guard let o = o else { return nil }
        return daySheet(o)
    }

    /// `nil` → `false`（没有场次就谈不上跨日）
    static func isCrossDay(_ o: Occurrence?) -> Bool {
        guard let o = o else { return false }
        return isCrossDay(o)
    }
}
