import Charts
import SwiftUI

/// 「周一 ~ 周日 × 场次数」的柱状图（PRD §4 #4：让"周日全勤、周五六出现"一眼可视）。
///
/// 写法刻意保持**最朴素**：`BarMark(x: .value("星期", label), y: .value("场次", count))`，
/// `label` 是 `String`、`count` 是 `Int`。不用泛型组合、不用 `Plottable` 自定义类型、
/// 不加坐标轴样式闭包 —— 那些写法在 CI 无签名编译下最容易报"无法推断泛型参数"（设计文档 R11），
/// 而这张图的信息量只需要 7 根柱子。
///
/// 统计口径：某天有 N 场，就把 N 计入该天的星期。空 `times` 的日子记 0 场（它在日历里是"缺时刻"，
/// 不是"有场次"，画进图里会误导）。
struct MonthDistributionChart: View {
    let days: [RedstoneDay]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if totalSessions == 0 {
                Text("本月还没有可统计的场次。")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 16)
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("星期", bucket.label),
                        y: .value("场次", bucket.count)
                    )
                    .foregroundStyle(Theme.chartBar)
                    .cornerRadius(4)
                }
                .frame(height: 150)
                .accessibilityLabel("本月各星期场次分布")
            }
            Text("按落地日统计；周日每周都有场次，所以柱子最高。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - 数据

    /// 7 个桶（周一在前），顺序固定 —— 即使某天 0 场也要保留，否则横轴会缺列
    private var buckets: [WeekdayBucket] {
        var counts = Array(repeating: 0, count: 7)
        for day in days {
            guard let date = RedstoneClock.startOfDay(dayKey: day.date) else { continue }
            let index = RedstoneClock.mondayIndex(of: date)
            guard (0..<7).contains(index) else { continue }
            counts[index] += day.times.count
        }
        let labels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        return (0..<7).map { index in
            WeekdayBucket(id: index, label: labels[index], count: counts[index])
        }
    }

    private var totalSessions: Int {
        return days.reduce(0) { $0 + $1.times.count }
    }
}

/// 图表的横轴类目（`Charts` 需要一个 `Identifiable` 数据源）
struct WeekdayBucket: Identifiable {
    let id: Int
    let label: String
    let count: Int
}
