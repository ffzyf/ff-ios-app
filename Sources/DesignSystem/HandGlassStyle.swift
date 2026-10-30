import SwiftUI

// MARK: - iOS 18–25 手工玻璃（保底配方，也是全平台的兜底路径）

/// 手工玻璃。
///
/// 配方 = 材质 + 白 6/8/10% 叠层 + 顶缘渐变描边(0.18→0.04) + 内侧 1pt 高光(0.14) + 黑 45% 投影。
///
/// 为什么这四条缺一不可（PRD §4.4「深色背景下避免糊成一片的三个具体手段」）：
/// 1. 描边高光是分界线 —— 深色玻璃与深色背景亮度差极小；
/// 2. 内侧高光模拟折射 —— 18–25 的系统材质不带这个；
/// 3. 卡片绝不与背景同色填充 —— 明度差至少 4%。
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

    /// 底色：材质 → 白色叠层（提亮）→ 业务染色 → 顶部向内渐亮
    private var fill: some View {
        shape
            .fill(level.material)
            .overlay {
                shape.fill(Color.white.opacity(level.whiteFill))
            }
            .overlay {
                if let tint = tint {
                    shape.fill(tint)
                }
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.035), Color.white.opacity(0.0)],
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
                colors: [
                    Color.white.opacity(level.topStroke),
                    Color.white.opacity(level.bottomStroke)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 1
        )
    }

    /// 内侧顶部 1pt 高光：模拟折射
    private var innerHighlight: some View {
        shape
            .inset(by: 0.5)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(level.innerHighlight), Color.white.opacity(0.0)],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.38)
                ),
                lineWidth: 1
            )
    }
}
