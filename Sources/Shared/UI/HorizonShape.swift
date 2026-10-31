import SwiftUI

/// 天际线的两个几何 Shape —— **App 与桌面小组件共用这一份**。
///
/// 为什么从 `DesignSystem/SkyCard.swift` 搬到这里：V3.3 起桌面简报小组件要和 App 内那张
/// 简报卡是**同一条地平线**（同一个弧顶比例、同一条亮边的模糊半径），而 Widget target
/// 只编译 `Sources/Widget` + `Sources/Shared`（见 project.yml）—— 留在 DesignSystem 里，
/// 小组件就引用不到。搬到 Shared 后两个 target 编译同一份几何，像素级一致是编译期保证。
///
/// 这两个类型是**纯几何、零依赖**：不碰颜色、不碰主题、不读 `colorScheme`。
/// 天色由调用方通过 `fill` / `stroke` 传进来（`Theme.sky(phase)`），所以它们天然通过主题闸门。
///
/// 逻辑一字未改，只换了文件位置 —— App 内那张卡的视觉在本次重构前后必须逐像素相同。

/// 地平线以下的地面（弧顶在正中，两端下沉）。
///
/// 用二次贝塞尔而不是圆弧：参考图里的地平线是"缓坡"不是"圆边"，
/// 圆弧在宽卡片上两端会翘得过于明显。控制点取 `2·crestY − edgeY`，
/// 使曲线在 t=0.5 处正好落在 `crestY`（数学上精确穿过弧顶，不是目测）。
struct HorizonGround: Shape {
    /// 弧顶位置（正中），占高度比例
    var crestY: CGFloat
    /// 两端位置，占高度比例（应大于 crestY）
    var edgeY: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let controlY = h * (2 * crestY - edgeY)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: h * edgeY))
        path.addQuadCurve(to: CGPoint(x: w, y: h * edgeY),
                          control: CGPoint(x: w / 2, y: controlY))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

/// 地平线亮边（只画那条弧，不闭合）
struct HorizonEdge: Shape {
    var crestY: CGFloat
    var edgeY: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h * edgeY))
        path.addQuadCurve(to: CGPoint(x: w, y: h * edgeY),
                          control: CGPoint(x: w / 2, y: h * (2 * crestY - edgeY)))
        return path
    }
}
