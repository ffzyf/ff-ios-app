import SwiftUI
import Foundation

/// 规律页的两块「表格类」内容：星期时刻表 + 已校准月份。
///
/// 为什么拆成独立文件：`RockRulesView` 本身要装"标题 + 兜底提示 + 四条规律卡 + 脚注"，
/// 再把两块表塞进去会破单文件 250 行的约定（设计文档 §7.4）。这两块都是纯展示，
/// 只吃 `rules`（可空），不持有任何状态 —— 拆出去对父视图零负担，也让"表格"与"文案"各自能改。

// MARK: - 星期 → 时刻

/// 本周星期对应时刻表（PRD P05 第二段）。
///
/// 七行**全部列出来**，没有场次的星期写「无场次」而不是隐藏：
/// 隐藏会让用户以为"漏了一天"，而"周一~周四没有红石"本身就是要传达的信息。
struct RuleWeekdayTable: View {
    let rules: RedstoneRules?

    /// 内置兜底时刻（与服务端 `rules.times` 同值，PRD P05 要求本地有文案）
    static let fallbackTimes: [String: String] = [
        "周五": "11:08 / 17:08 / 23:08",
        "周六": "10:08 / 14:08 / 22:08",
        "周日": "07:08 / 13:08 / 19:08"
    ]

    private let order = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    /// 显式 init：`order` 是 private 存储属性，memberwise init 会被降级成 private
    init(rules: RedstoneRules?) {
        self.rules = rules
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本周星期对应时刻")
                .font(Typography.titleS)
                .foregroundStyle(Theme.textPrimary)
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.weekday)
                        .font(Typography.footnoteMedium)
                        .foregroundStyle(row.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                        .frame(width: 34, alignment: .leading)
                    Text(row.times)
                        .font(Typography.footnote)
                        .foregroundStyle(row.isEmpty ? Theme.textTertiary : Theme.textBody)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
    }

    private var rows: [WeekdayRow] {
        let source: [String: String] = {
            if let times = rules?.times, !times.isEmpty { return times }
            return RuleWeekdayTable.fallbackTimes
        }()
        return order.map { weekday in
            let value = (source[weekday] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let empty = value.isEmpty
            return WeekdayRow(weekday: weekday, times: empty ? "无场次" : value, isEmpty: empty)
        }
    }
}

/// 星期 → 时刻（用结构体而不是元组：`ForEach` 的 `id` 不能写 `\.0`，KeyPath 不支持元组下标）
private struct WeekdayRow: Identifiable {
    let weekday: String
    let times: String
    let isEmpty: Bool

    var id: String { weekday }
}

// MARK: - 已校准月份

/// 已校准（播种）的月份列表（PRD P05 第三段）。
///
/// 数据来自 `rules.seeds`：键是 `"2027-02-07"`，值是当天被校准成的地图。
/// 按月份分组展示：一次列 20 个日期太长，而"哪几个月被校准过"才是用户想确认的事。
struct RuleSeedsSection: View {
    let rules: RedstoneRules?

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if !months.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("已校准的月份")
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)
                ForEach(months, id: \.self) { month in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Formatters.monthTitle(month) + "（\(rows(in: month).count) 天）")
                            .font(Typography.footnoteMedium)
                            .foregroundStyle(Theme.textSecondary)
                        ForEach(rows(in: month)) { row in
                            Text(row.day + " · " + row.map)
                                .font(Typography.captionXS)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.cardPadding)
            .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
        }
    }

    private var months: [String] {
        let seeds = rules?.seeds ?? [:]
        let months = seeds.keys.compactMap { key -> String? in
            let parts = key.split(separator: "-")
            guard parts.count >= 2 else { return nil }
            return String(parts[0]) + "-" + String(parts[1])
        }
        return Array(Set(months)).sorted()
    }

    private func rows(in month: String) -> [SeedRow] {
        let seeds = rules?.seeds ?? [:]
        let keys = seeds.keys.filter { $0.hasPrefix(month + "-") }.sorted()
        // 每月最多列 8 天：再多就变成一张清单，用户要的是"确认校准过"，不是逐条对表
        return keys.prefix(8).map { key in
            SeedRow(day: String(key.suffix(5)), map: seeds[key] ?? "")   // "02-07"
        }
    }
}

/// 某个月里被校准的一天
private struct SeedRow: Identifiable {
    let day: String
    let map: String

    var id: String { day }
}
