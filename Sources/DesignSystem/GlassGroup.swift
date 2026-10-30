import SwiftUI

/// 相邻玻璃的分组容器。
///
/// iOS 26：交给系统统一渲染（相邻玻璃会融合、性能更好）；
/// iOS 18–25：原样透传，**不做任何布局包裹**（避免改变父容器的语义）。
///
/// 设计上**不依赖**它的 morph 效果（设计文档 §5.3-①）：Tab 高亮胶囊的滑移统一用
/// `matchedGeometryEffect`，保证 iOS 18 与 26 观感一致。
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    private let content: () -> Content

    init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}
