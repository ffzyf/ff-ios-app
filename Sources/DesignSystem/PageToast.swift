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
    /// 外部直接给文案时使用（Monitor / Survey 等独立 store 的 toast）。
    /// 传 nil（或不传）时回退到全局 `ToastStore.shared`（AppModel 的 toast，B 批次后唯一来源）。
    var message: String? = nil
    /// 观察全局 toast：这样 `PageToast()` 不传文案时也能随着 `ToastStore` 变化重绘，
    /// 而不必在调用方手动传 `ToastStore.shared.message`（那样读取值不会触发订阅）。
    @ObservedObject private var globalToast = ToastStore.shared

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
        let raw = message ?? globalToast.message
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var animation: Animation {
        return displayText == nil ? Motion.glassOut : Motion.glassIn
    }
}
