import SwiftUI

/// 轨迹卡容器（V3.1 返工新增）—— 首页卡片与桌面小组件的**同一套视觉底盘**。
///
/// 为什么不再用 `GlassCard`：`GlassCard` 是"页面上的玻璃块"，靠采样背景立住；
/// 参考设计里的卡是**一块独立的夜** —— 自己的深靛渐变 + 一条光轨 + 细描边，
/// 压在玻璃层上时不需要采样，滚动时也不会跟着背景一起抖动（顺带省掉一层真玻璃的开销）。
///
/// 三条硬规则：
/// 1. **文字永远在弧线之上**：弧线只画在 `bandTop…bandBottom` 这一条窄带里（默认卡片下部），
///    绝不从标题或数字中间穿过；
/// 2. 圆角与页面其它卡片一致（`Radius.card`），描边用上亮下暗的渐变，模仿玻璃接光；
/// 3. 内容内边距由调用方给，容器只管底盘与裁剪（同心圆角规则）。
struct TrackCard<Content: View>: View {

    /// 当天已过比例（0 = 00:00，1 = 24:00），决定光轨画到哪儿、节点落在哪儿
    var progress: CGFloat
    /// 光轨颜色，默认淡蓝紫
    var tint: Color = Theme.trackArc
    var cornerRadius: CGFloat = Radius.card
    /// 弧线带的上沿（占卡片高度比例）
    var bandTop: CGFloat = 0.40
    /// 弧线带的下沿
    var bandBottom: CGFloat = 0.95
    /// 弧顶横向位置
    var peak: CGFloat = 0.66
    private let content: Content

    init(progress: CGFloat,
         tint: Color = Theme.trackArc,
         cornerRadius: CGFloat = Radius.card,
         bandTop: CGFloat = 0.40,
         bandBottom: CGFloat = 0.95,
         peak: CGFloat = 0.66,
         @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.bandTop = bandTop
        self.bandBottom = bandBottom
        self.peak = peak
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [Theme.trackTop, Theme.trackBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    // 左上角一层极淡的青柠余晖：让深靛不死板，同时和 App 的青柠主色呼应
                    RadialGradient(
                        colors: [Theme.lime.opacity(0.10), Theme.lime.opacity(0)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 220
                    )
                    TrackArcBackdrop(
                        progress: progress,
                        tint: tint,
                        lineWidth: 2,
                        nodeRadius: 4.5,
                        bandTop: bandTop,
                        bandBottom: bandBottom,
                        peak: peak,
                        scrimOpacity: 0
                    )
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Theme.glassStrokeTop, Theme.glassStrokeBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: Theme.glassShadowSoft, radius: 16, y: 8)
    }
}
