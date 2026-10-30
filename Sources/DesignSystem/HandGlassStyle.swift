import SwiftUI

// MARK: - iOS 18–25 手工玻璃（保底配方，也是全平台的兜底路径）

/// 手工玻璃。
///
/// 配方 = 材质 + 白叠层 + 顶缘渐变描边 + 内侧 1pt 高光 + 双层投影。
///
/// 为什么这四条缺一不可（PRD §4.4「深色背景下避免糊成一片的三个具体手段」）：
/// 1. 描边高光是分界线 —— 深色玻璃与深色背景亮度差极小；
/// 2. 内侧高光模拟折射 —— 18–25 的系统材质不带这个；
/// 3. 卡片绝不与背景同色填充 —— 明度差至少 4%。
///
/// 双主题改造（批次 1）：V2 这里是"给白色就地加透明度"（`level.whiteFill` 那几个 Double），
/// 现在全部换成 `GlassLevel` 返回的 token。本文件因此**不读任何环境**，深浅色由 token 自己解析。
/// 浅色下的补偿只有两条（PRD §3.2 脚注）：上缘 90% 白描边保住玻璃边、双层灰蓝阴影保住层次 ——
/// 都由 token 提供，这里不需要额外分支。
struct HandGlass<S: InsettableShape>: ViewModifier {
    let level: GlassLevel
    let shape: S
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background { fill }
            .overlay { edgeStroke }
            .overlay { innerHighlight }
            .compositingGroup()
    }

    /// 底色：材质 → 白叠层（提亮）→ 业务染色 → 顶部向内渐亮
    private var fill: some View {
        shape
            .fill(level.material)
            .overlay {
                shape.fill(level.fillColor)
            }
            .overlay {
                if let tint = tint {
                    shape.fill(tint)
                }
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [Theme.glassSheen, Theme.glassHighlightFade],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
    }

    /// 顶缘渐变描边：深色玻璃与深色背景唯一的分界线
    private var edgeStroke: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [level.strokeTopColor, level.strokeBottomColor],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 1
        )
    }

    /// 内侧顶部 1pt 高光：模拟折射。
    /// 渐变的"透明端"也是 token（`glassHighlightFade`），不写 `.opacity(0)` ——
    /// 否则浅色模式下会冒出一个没人审过的硬编码值。
    private var innerHighlight: some View {
        shape
            .inset(by: 0.5)
            .strokeBorder(
                LinearGradient(
                    colors: [level.highlightColor, Theme.glassHighlightFade],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.38)
                ),
                lineWidth: 1
            )
    }
}
