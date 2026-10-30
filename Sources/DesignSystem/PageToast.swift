import SwiftUI

/// 全站共享的底部轻提示（刷新失败 / 局部报错 / 复制成功）。
///
/// 为什么放在 DesignSystem 而不是每页各画一个：toast 是**跨页面一致的失败语言**
/// （PRD §5.2：「下拉刷新失败 → 顶部 toast，1.8s 自动消失，不清空已显示内容」），
/// 各页各写一份就会出现三种不同的圆角与间距。
///
/// 三条约定：
/// 1. 玻璃只走 `.glassSurface(.floating, in: Capsule())`（层 2），不自己写材质；
/// 2. 出现用 `Motion.glassIn`、消失用 `Motion.glassOut`（消失比出现快，感觉更利落，PRD §4.6）；
/// 3. 不吃点击（`allowsHitTesting(false)`）—— toast 盖在内容上，用户点它不该没反应。
struct PageToast: View {
    /// nil 或空串时不显示任何东西（连占位都不留）
    let message: String?

    var body: some View {
        Group {
            if let text = displayText {
                Text(text)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassSurface(.floating, in: Capsule())
                    .padding(.horizontal, Spacing.page)
                    .padding(.bottom, Spacing.gridUnit + 4)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity)
        .animation(animation, value: displayText)
    }

    /// 空白文案当作「没有 toast」：`Text("")` 会渲染出一枚空胶囊，比不弹更糟
    private var displayText: String? {
        guard let message = message else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var animation: Animation {
        return displayText == nil ? Motion.glassOut : Motion.glassIn
    }
}
