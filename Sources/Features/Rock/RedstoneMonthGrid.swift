import SwiftUI
import Foundation

/// 红石 / 黑石的标记色。
///
/// PRD §3.2 的颜色表**没有**为「红石 / 黑石」单列 token，这里复用状态色里已有的两个值：
/// 红石用 `statusError` 的红档（深色 `#FF8F7A` / 浅色 `#C43B22`），黑石用 `statusOk` 的中性灰。
/// 包成 enum 而不是在每个视图里各写一遍，好处是将来 PRD 若补了专门的色，只改这一处；
/// 也顺手守住 lint 规则 1（View 层不出现 hex）。
enum RockMarkStyle {
    case redstone
    case blackstone

    var color: Color {
        switch self {
        case .redstone: return Theme.statusError
        case .blackstone: return Theme.statusOk
        }
    }

    var label: String {
        switch self {
        case .redstone: return "红石"
        case .blackstone: return "黑石"
        }
    }

    /// 服务端归一口径：含「黑」即黑石，其余一律红石
    static func of(_ day: RedstoneDay) -> RockMarkStyle {
        return day.isRedstone ? .redstone : .blackstone
    }
}

/// 月历网格（纯展示组件）：给定年月 + 该月条目，画 7 列格子。
///
/// 三条硬要求：
/// 1. **周一为首列**（PRD P04）。`Calendar.firstWeekday` 保持系统默认，偏移自己算，
///    这样同一个 `Calendar` 在工程里不会因为视图不同而语义不同；
/// 2. 每格只放"日期 + 标记 + 地图短名"，超过 2 场显示「+N」（PRD P04）——
///    一格宽约 46pt，塞满三个时刻必然截断，不如把"N 场"这件事说清楚；
/// 3. 纯组件：不读 Store、不发请求、不做时间判定。所有数据从外面传，方便以后给 Widget 复用。
struct RedstoneMonthGrid: View {
    /// `"2026-10"`
    let monthKey: String
    /// 该月的条目（顺序不重要，内部按 date 建索引）
    let days: [RedstoneDay]
    /// 今天的 `dayKey`（用于高亮，由调用方传，避免组件内部读 `Date()` 造成预览不稳定）
    let todayKey: String
    /// 点某天（当天空场次的日子不响应）
    let onSelect: (RedstoneDay) -> Void

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private let cellHeight: CGFloat = 56
    private let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    /// 显式 init：`columns` / `cellHeight` / `weekdayLabels` 是 private 存储属性，
    /// 自动合成的 memberwise init 会变成 private，跨文件就构造不了。
    init(monthKey: String, days: [RedstoneDay], todayKey: String, onSelect: @escaping (RedstoneDay) -> Void) {
        self.monthKey = monthKey
        self.days = days
        self.todayKey = todayKey
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            LazyVGrid(columns: columns, spacing: 5) {
                // 1 号之前补空格：周一是第一列，所以补 `mondayOffset` 个
                ForEach(0..<RedstoneClock.mondayOffset(ofMonth: monthKey), id: \.self) { _ in
                    Color.clear.frame(height: cellHeight)
                }
                ForEach(1...RedstoneClock.dayCount(in: monthKey), id: \.self) { dayNumber in
                    cell(dayNumber: dayNumber)
                }
            }
        }
    }

    // MARK: - 子视图

    private var header: some View {
        HStack(spacing: 5) {
            ForEach(weekdayLabels, id: \.self) { label in
                Text(label)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func cell(dayNumber: Int) -> some View {
        let key = dayKey(dayNumber: dayNumber)
        let day = daysByDate[key]
        return Group {
            if let day = day {
                Button(action: {
                    Haptics.light()
                    onSelect(day)
                }) {
                    cellContent(dayNumber: dayNumber, day: day)
                }
                .buttonStyle(PressableStyle(scale: 0.94))
                .accessibilityLabel(accessibilityText(dayNumber: dayNumber, day: day))
            } else {
                cellContent(dayNumber: dayNumber, day: nil)
            }
        }
    }

    /// 一格的内容：日期数字 + 标记（红/灰点，超 2 场给 +N）+ 地图短名
    private func cellContent(dayNumber: Int, day: RedstoneDay?) -> some View {
        let isToday = dayKey(dayNumber: dayNumber) == todayKey
        return VStack(spacing: 3) {
            Text(String(dayNumber))
                .font(.system(size: 13, weight: isToday ? .semibold : .regular))
                .foregroundStyle(day == nil ? Theme.textTertiary : Theme.textPrimary)
                .monospacedDigit()

            if let day = day {
                dots(day: day)
                Text(shortMap(day.map))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(day == nil ? Color.clear : Theme.surfaceTint1)
        }
        .overlay {
            // 今天用青柠描边而不是填色：填色会和"有场次"的底色语义打架
            if isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.limeInk.opacity(0.55), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// 场次标记：最多两个点 + 「+N」。
    /// `times` 为空（服务端 warning 里那种"缺时刻"的日子）只画一个灰点，表示"这天有排期但没时刻"。
    private func dots(day: RedstoneDay) -> some View {
        HStack(spacing: 3) {
            if day.times.isEmpty {
                Circle()
                    .fill(Theme.statusOk)
                    .frame(width: 5, height: 5)
            } else {
                ForEach(0..<min(day.times.count, 2), id: \.self) { _ in
                    Circle()
                        .fill(RockMarkStyle.of(day).color)
                        .frame(width: 5, height: 5)
                }
                if day.times.count > 2 {
                    Text("+\(day.times.count - 2)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(height: 8)
    }

    // MARK: - 数据

    private var daysByDate: [String: RedstoneDay] {
        var map: [String: RedstoneDay] = [:]
        for day in days {
            map[day.date] = day
        }
        return map
    }

    private func dayKey(dayNumber: Int) -> String {
        return monthKey + String(format: "-%02d", dayNumber)
    }

    /// `"霞谷·圆梦村"` → `"圆梦村"`（一格放不下全名，取「·」后面的点位名）
    private func shortMap(_ map: String) -> String {
        if let dotIndex = map.firstIndex(of: "·") {
            let tail = String(map[map.index(after: dotIndex)...])
            return tail.isEmpty ? map : tail
        }
        return String(map.prefix(3))
    }

    private func accessibilityText(dayNumber: Int, day: RedstoneDay) -> String {
        let title = Formatters.dayTitleWithWeekday(dayKey(dayNumber: dayNumber))
        let count = day.times.isEmpty ? "无场次时刻" : "\(day.times.count) 场"
        return title + "，" + RockMarkStyle.of(day).label + "，" + day.map + "，" + count
    }
}
