import SwiftUI

/// 概览页头部（PRD §3.1 第 1–3 条 + 右上角设置齿轮）。
///
/// 三个约定：
/// · 称呼固定「你」——本版无账号体系，昵称不传服务端（PRD §3.1 第 1 条）；
/// · 日期数字走 `.monospacedDigit()`，午夜跳数字时排版不抖（PRD §4.2）；
/// · 齿轮只管「发一个动作」，sheet 的开关状态留在 `OverviewView`，组件不持有业务状态。
struct OverviewHeader: View {
    /// 农历 / 节气副行；nil 时整行不占位
    let lunar: String?
    /// 点齿轮：打开设置 sheet
    let onSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Formatters.greeting())
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Text(Formatters.todayHeader())
                    .font(Typography.display)
                    .tracking(Typography.trackingLarge)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if let lunar = lunar, !lunar.isEmpty {
                    Text(lunar)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            // 设计系统里的圆形玻璃按钮（层 2），不是自己画的圆
            IconGlassButton(icon: "gearshape") {
                onSettings()
            }
            .accessibilityLabel("设置")
        }
    }
}
