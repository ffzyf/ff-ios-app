import SwiftUI

/// 轨迹卡容器（V3.1 返工新增）—— 首页卡片与桌面小组件的**同一套视觉底盘**。
///
/// 为什么不再用 `GlassCard`：`GlassCard` 是"页面上的玻璃块"，靠采样背景立住；
/// 参考设计里的卡是**一块独立的夜** —— 自己的深靛渐变 + 一条光轨 + 细描边，
/// 压在玻璃层上时不需要采样，滚动时也不会跟着背景一起抖动（顺带省掉一层真玻璃的开销）。
///
/// 三条硬规则：
/// 1. **文字永远在弧线之上**——靠布局保证，不靠高度运气：容器在内容底部固定让出 `arcBand` 高，
///    弧线带贴底画在这块留白里。上一版用"占卡片高度的比例"给弧线带定位，
///    结果红石卡降级成两行字时卡片变矮，带子上浮，弧线直接穿过「光遇简报」——
///    **内容多少不该影响弧线压不压文字**，所以改成绝对高度；
/// 2. 圆角与页面其它卡片一致（`Radius.card`），描边用上亮下暗的渐变，模仿玻璃接光；
/// 3. 内容内边距由调用方给，容器只管底盘、留白与裁剪（同心圆角规则）。
struct TrackCard<Content: View>: View {

    /// 当天已过比例（0 = 00:00，1 = 24:00），决定光轨画到哪儿、节点落在哪儿
    var progress: CGFloat
    /// 光轨颜色，默认淡蓝紫
    var tint: Color = Theme.trackArc
    var cornerRadius: CGFloat = Radius.card
    /// 底部光轨带高度（**绝对值**，贴卡片底边）。桌面小组件不走这个容器。
    ///
    /// 留白怎么算：容器给内容加的是 `arcBand + arcGap`，而弧线带只占底部 `arcBand`。
    /// 于是「末行文字 → 带顶（弧线最高点）」恒为 `arcGap`，与卡片多高、内容多少都无关 ——
    /// 这就是"文字永远在弧线之上"从布局上被钉死的原因。
    var arcBand: CGFloat = 52
    /// 文字与弧线带之间额外留的呼吸。
    ///
    /// 不能省：发光节点的光晕半径就有 16pt（`nodeRadius 4.5 × 3.6`），
    /// 节点走到弧顶时光晕会向上溢出 16pt。留 22pt 才能保证光晕不蹭到末行文字。
    var arcGap: CGFloat = 22
    /// 弧顶横向位置
    var peak: CGFloat = 0.66
    /// 背景样式：轨迹弧（通用）/ 光遇云海（红石提醒卡用）。
    ///
    /// 为什么做成二选一而不是叠在一起：红线是"文字永远不被装饰压住"，
    /// 弧线和云海都要占底部空间，同时画会互相打架，也让底部留白翻倍。
    var backdrop: TrackBackdrop = .arc
    private let content: Content

    init(progress: CGFloat,
         tint: Color = Theme.trackArc,
         cornerRadius: CGFloat = Radius.card,
         arcBand: CGFloat = 52,
         arcGap: CGFloat = 22,
         peak: CGFloat = 0.66,
         backdrop: TrackBackdrop = .arc,
         @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.arcBand = arcBand
        self.arcGap = arcGap
        self.peak = peak
        self.backdrop = backdrop
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            // 先让出「光轨带 + 呼吸」，再铺背景 —— 顺序反了背景就盖不到留白处，弧线会被裁掉。
            // 云海背景是铺满整卡的，不需要额外留白（云本来就画在底部，不压字）。
            .padding(.bottom, backdrop == .arc ? arcBand + arcGap : arcGap * 0.6)
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
                    if backdrop == .arc {
                        TrackArcBackdrop(
                            progress: progress,
                            tint: tint,
                            lineWidth: 2,
                            nodeRadius: 4.5,
                            bandHeight: arcBand,
                            peak: peak,
                            scrimOpacity: 0
                        )
                    } else {
                        SkyGameBackdrop()
                    }
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

/// 轨迹卡的两种背景
enum TrackBackdrop {
    /// 一条光轨 + 发光节点（简报到日 / 通用卡片）
    case arc
    /// 光遇风格的云海 + 星点（红石提醒卡）
    case skyGame
}
