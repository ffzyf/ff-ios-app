import SwiftUI

/// 记账模块的排版常量。
///
/// 为什么单独一组而不是往 `Typography` 里加：`Typography` 是全工程共用的字号阶，
/// 为了一个模块加「rounded 金额字」会把共用 token 变成垃圾桶。而金额用 rounded 设计是
/// 记账区的专属观感（数字更圆、更像账本），所以固定在模块内部，改也只改这一处。
enum LedgerType {
    /// 34pt Bold Rounded —— 表单里的金额输入
    static let amountInput = Font.system(size: 34, weight: .bold, design: .rounded)
    /// 22pt Bold Rounded —— 「收入 / 支出 / 结余」三连大数字
    static let summaryValue = Font.system(size: 22, weight: .bold, design: .rounded)
    /// 16pt Semibold Rounded —— 流水行的金额
    static let rowValue = Font.system(size: 16, weight: .semibold, design: .rounded)
    /// 12pt Medium Rounded —— 当天合计
    static let groupTotal = Font.system(size: 12, weight: .medium, design: .rounded)
}

/// 金额的语义色：**中国口径，红涨绿跌** —— 收入红、支出绿，和股票一样。
///
/// 两个颜色都是从已有 token 里挑的，不新造纯红纯绿：
/// - 收入用 `Theme.badgeRed`（深色 `#FF6B5A` / 浅色 `#E03A22`，本身就是"提亮过一档的红"）；
/// - 支出用 `Theme.limeInk`（青柠主题下就是深绿字色，浅色 `#1F6B22` 有 6.2:1）。
///   这里**只能**用 `limeInk`，不能 `Theme.lime`：`lime` 是面，做文字色在浅色下只有 1.76:1。
enum LedgerInk {
    /// 收入色（也用于所有「正数」金额）
    static var income: Color { Theme.badgeRed }
    /// 支出色（也用于所有「负数」金额）
    static var expense: Color { Theme.limeInk }

    /// 按符号取色：≥ 0 走收入色，< 0 走支出色
    static func signed(_ cents: Int) -> Color {
        return cents < 0 ? expense : income
    }
}

/// 分组标题的文案（今天 / 昨天 / 8月3日 周日 · 8月 / 2025年8月）。
///
/// 时间口径跟 `Formatters` 保持一致（北京时间），"今天/昨天"用与 `LedgerStore` 同一个日历判断，
/// 避免"分组按北京时间、标签按设备时区"这种跨时区用户的错位。
enum LedgerLabel {

    static func day(_ day: Date, now: Date = Date()) -> String {
        let calendar = LedgerStore.calendar
        if calendar.isDate(day, inSameDayAs: now) {
            return "今天"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "昨天"
        }
        return Formatters.absoluteCN(day, now: now) + " " + Formatters.weekdayCN(day)
    }

    static func month(_ month: Date) -> String {
        let calendar = LedgerStore.calendar
        let year = calendar.component(.year, from: month)
        let monthValue = calendar.component(.month, from: month)
        let currentYear = calendar.component(.year, from: Date())
        return year == currentYear ? "\(monthValue)月" : "\(year)年\(monthValue)月"
    }

    static func isCurrentMonth(_ month: Date, now: Date = Date()) -> Bool {
        return LedgerStore.calendar.isDate(month, equalTo: now, toGranularity: .month)
    }
}
