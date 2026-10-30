import SwiftUI

/// 红石卡的背景：光遇风格（云海 + 星点 + 一点暖光）。
///
/// 为什么不是天际线：红石卡是"提醒"，信息密度高（时刻 / 倒计时 / 场次表），
/// 一整块会变色的天空会把数字压得看不清。这里用**静态的夜 + 云**：
/// 星点极淡铺满（像颗粒，不干扰阅读），云海只压在底部三成，
/// 暖色光点放在右下角 —— 那是蜡烛/光的方向，也是红石的视觉暗示。
///
/// 所有元素都是 `Theme` token（`textPrimary` 的白 + `trackArc` 的蓝紫），
/// 换配色时会跟着变，不会出现"紫色主题里冒出一块绿云"。
struct SkyGameBackdrop: View {

    /// 星点位置（归一化坐标 + 尺寸 + 透明度）。写死而不是随机：
    /// 每次重绘都随机的话，滚动时星星会跳，看起来像画面在闪。
    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (0.08, 0.16, 1.6, 0.22), (0.19, 0.34, 1.2, 0.16), (0.31, 0.11, 1.0, 0.14),
        (0.44, 0.28, 1.8, 0.24), (0.57, 0.15, 1.1, 0.15), (0.68, 0.38, 1.4, 0.18),
        (0.79, 0.09, 1.0, 0.13), (0.88, 0.26, 1.5, 0.20), (0.94, 0.44, 1.1, 0.14),
        (0.14, 0.62, 1.0, 0.12), (0.86, 0.66, 1.2, 0.12)
    ]

    /// 云朵形状（归一化 x / 宽度占比）。三个错开的椭圆就够看，不必画真云轮廓
    private static let cloudBumps: [(x: CGFloat, width: CGFloat)] = [
        (0.12, 0.46), (0.38, 0.58), (0.66, 0.52), (0.90, 0.40)
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                    Circle()
                        .fill(Theme.trackArc.opacity(star.opacity))
                        .frame(width: star.size, height: star.size)
                        .position(x: w * star.x, y: h * star.y)
                }

                // 云海：三层，越靠下越实，只在底部三成 —— 上面留白给文字
                ForEach(0..<3, id: \.self) { layer in
                    cloudLayer(width: w, height: h, index: layer)
                }

                // 右下角的一团暖光（蜡烛 / 光的方向）
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.trackArc.opacity(0.22), Theme.trackArc.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 46
                        )
                    )
                    .frame(width: 92, height: 92)
                    .position(x: w * 0.86, y: h * 0.90)
            }
        }
        .allowsHitTesting(false)
    }

    /// 一层云。
    ///
    /// 关键在 `.blur`：纯色椭圆直接叠会在边界处留下硬边，浅色卡上看起来像"扫描线"。
    /// 模糊 12pt 之后边缘化开，才像雾。颜色用 `trackArc`（蓝紫）而不是 `textPrimary`：
    /// 后者在浅色模式是深灰，压在白卡上就是一道道脏印子。
    private func cloudLayer(width w: CGFloat, height h: CGFloat, index: Int) -> some View {
        let baseY = 0.86 + CGFloat(index) * 0.06
        let opacity = 0.07 + Double(index) * 0.04
        let thickness = h * (0.22 - CGFloat(index) * 0.02)

        return ZStack {
            ForEach(Array(Self.cloudBumps.enumerated()), id: \.offset) { _, bump in
                Ellipse()
                    .fill(Theme.trackArc.opacity(opacity))
                    .frame(width: w * bump.width, height: thickness)
                    .position(x: w * bump.x, y: h * baseY + CGFloat(index) * 4)
            }
        }
        .blur(radius: 12)
        .allowsHitTesting(false)
    }
}
