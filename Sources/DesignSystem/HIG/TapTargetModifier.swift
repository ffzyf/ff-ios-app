import SwiftUI

/// 44pt 触控命中区（HIG 迭代 · L3 组件内部叠加）。
///
/// 关键约束：**只能扩大命中区，不能改变布局尺寸**。
/// 因此透明矩形放在 `overlay` 里（overlay 不参与父级布局），而**不是**直接给 content
/// 加 `frame(minWidth:minHeight:)` —— 后者会把 36pt 的 `IconGlassButton` 真正撑成 44pt，
/// 视觉就回归了。透明矩形仍接收命中测试，点击作为按钮 label 的子视图冒泡到同一个 action。
struct TapTargetModifier: ViewModifier {
    let minSide: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(minWidth: minSide, minHeight: minSide)
                    .contentShape(Rectangle())
            }
    }
}

extension View {
    /// 叠加至少 `side × side` 的透明命中区，视觉尺寸完全不变。
    ///
    /// 默认 `Spacing.tapMinSide`（44）。业务页的自定义按钮本轮不覆盖（红线：不动业务 body）。
    func tapTarget(_ side: CGFloat = Spacing.tapMinSide) -> some View {
        modifier(TapTargetModifier(minSide: side))
    }
}
