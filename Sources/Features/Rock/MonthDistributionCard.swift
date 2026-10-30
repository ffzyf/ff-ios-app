import SwiftUI

/// 底部折叠区「本月分布」（P04 折叠区）。
///
/// 折叠状态放在自己身上（`@State private var expanded`）：这是**纯展示偏好**，
/// 换个月份收起/展开都无所谓，不值得让父视图持有 —— 父视图 `RockCalendarView` 只负责把
/// 当前月的条目传进来。默认收起：月历本身已经占满一屏，图是"想深究时再看"的第二层信息。
struct MonthDistributionCard: View {
    /// 当前显示月的条目
    let days: [RedstoneDay]

    @State private var expanded: Bool = false

    /// 显式 init：`@State` 是 private 存储属性，memberwise init 会被降级成 private
    init(days: [RedstoneDay]) {
        self.days = days
    }

    var body: some View {
        GlassCard(level: .card) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Haptics.light()
                    withAnimation(Motion.expand) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.limeInk)
                        Text("本月分布")
                            .font(Typography.titleS)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint(expanded ? "收起图表" : "展开各星期的场次分布")

                if expanded {
                    MonthDistributionChart(days: days)
                }
            }
            .padding(Spacing.cardPadding)
        }
    }
}
