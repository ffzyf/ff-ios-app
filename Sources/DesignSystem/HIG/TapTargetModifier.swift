import SwiftUI

/// 44pt 触控命中区（HIG 迭代 · L3 组件内部叠加）。
///
/// 关键约束：**只能扩大命中区，不能改变布局尺寸**。
/// 因此透明矩形放在 `overlay` 里（overlay 不参与父级布局），而**不是**直接给 content
/// 加 `frame(minWidth:minHeight:)` —— 后者会把 36pt 的 `IconGlassButton` 真正撑成 44pt，
/// 视觉就回归了。
///
/// **调用位置红线**：本 modifier 必须挂在 Button 的 **label（content 闭包）内部**，
/// 使透明 overlay 成为 Button 子视图，点击沿响应链冒泡到 Button 的 action。
/// 切勿挂在 Button **外层**（如 `Button(...).tapTarget()`）—— 此时 overlay 是 Button 的
/// 兄弟视图且在 Z 轴更上方，`Color.clear` 默认可交互 + `contentShape(Rectangle())`
/// 会截获全部 hit-test，Button 收不到点击（5.6.7 底部 Tab 栏失灵即此因）。
/// 最稳妥的扩大命中区方式是 label 内 overlay + 外层 `.contentShape(...)` 组合。
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
