import SwiftUI

/// 占位页（批次 1 专用）。
///
/// 为什么需要它：批次 1 要把 Tab 从 3 个扩到 5 个（PRD §2.2 方案 A），但「红石」与「更多」
/// 的真实页面要到批次 2 / 批次 3 才落地。如果不给占位，这一批就编译不过 —— 而批次 1 的意义
/// 正是"先让一个纯 iOS 18 API 的版本编译通过"，作为后续批次的基线。
///
/// 三条自我约束：
/// 1. **绝不画假数据**：占位页只说"这页还没做"，不放 `--:--`、不放空卡片、不放骨架屏
///    （骨架屏会让人以为在加载，几秒后还在转，观感比空态更差）；
/// 2. 保留 Tab 的身份：图标 + 页面名必须真实（用户点进来要知道自己没错）；
/// 3. 说明"什么时候有"，把不确定变成可预期。
struct PagePlaceholder: View {
    /// 页面名（Tab 标题，如「红石」）
    let title: String
    /// SF Symbol（与 Tab 图标一致，形成连续性）
    let icon: String
    /// 这一页将来装什么（一句话，给用户而不是给开发者看）
    var summary: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                iconBadge

                VStack(spacing: 8) {
                    Text(title)
                        .font(Typography.titleL)
                        .tracking(Typography.trackingLarge)
                        .foregroundStyle(Theme.textPrimary)
                    Text("建设中")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.limeInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill(Theme.lime.opacity(0.14))
                        }
                        .overlay {
                            Capsule().strokeBorder(Theme.limeInk.opacity(0.35), lineWidth: 1)
                        }
                }

                if !summary.isEmpty {
                    Text(summary)
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                        .padding(.horizontal, Spacing.page)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 96)
            .padding(.bottom, Spacing.pageBottomInset)
        }
        .scrollIndicators(.hidden)
        // 无障碍：占位是"状态"而不是"内容"，读屏只读一遍即可
        .accessibilityElement(children: .combine)
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(Theme.surfaceTint2)
            Circle()
                .strokeBorder(Theme.divider, lineWidth: 1)
            Image(systemName: icon)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.limeInk)
        }
        .frame(width: 84, height: 84)
    }
}
