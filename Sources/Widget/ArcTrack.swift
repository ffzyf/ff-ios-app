import SwiftUI

/// 桌面小组件专用的一层薄包装：把共享的 `TrackArcBackdrop` 铺满整卡。
///
/// 几何、进度、节点全部来自 `Sources/Shared/UI/TrackArc.swift`（App 与 Widget 同源），
/// 这里只负责"widget 卡片的弧线带应该开在哪个高度"，不重复实现任何曲线算法。
///
/// 保留 `geometry:` 参数是为了不动锁屏实时活动（`SunEventLiveActivity`）的调用点：
/// 它传进来的 ratio / bottomPad 会被换算成同样的高度带参数。
struct TrackCardBackdrop: View {

    let geometry: ArcGeometry
    let progress: CGFloat
    let tint: Color
    var lineWidth: CGFloat = 2.5
    var nodeRadius: CGFloat = 4

    var body: some View {
        // 旧的整卡几何（bottomPad=0.20 / ratio=0.55）等价于：弧底在 80% 处、弧顶在 25% 处。
        // 现在收窄成 45%…86% 的窄带：文字区永远在弧线之上，曲线不会再从标题中间穿过。
        TrackArcBackdrop(
            progress: progress,
            tint: tint,
            lineWidth: lineWidth,
            nodeRadius: nodeRadius,
            bandTop: max(0.30, 1 - geometry.bottomPad - geometry.ratio + 0.12),
            bandBottom: min(0.95, 1 - geometry.bottomPad + 0.06),
            peak: geometry.peakX
        )
    }
}
