import SwiftUI

/// 红石小组件的底盘：**光遇风格**（星点 + 云海 + 一团暖光）。
///
/// 为什么红石**不用天际线**（这是本轮唯一一条"故意不对称"的设计决定）：
/// 红石卡的信息密度是简报卡的三倍（大字时刻 / 倒计时 / 今日场次表 / 倍率），
/// 一整块会随时段变色的天空会把数字压得看不清 —— 白天那段渐变（`#BFE4FF`）上
/// 压白色场次表，对比度直接不合格。所以这里的底是**静态的夜**：天色不参与信息表达，
/// 只有星点、云海和右下角那团暖光在让画面"活着"。
///
/// 与 App 内 `SkyGameBackdrop`（DesignSystem）是同一套配方，但**必须重写一份**：
/// Widget target 只编译 `Sources/Widget` + `Sources/Shared`，DesignSystem 下的符号在小组件里不存在。
///
/// 颜色全部走 `Theme` token（`trackTop` / `trackBottom` / `trackArc` / `lime`）：
/// 换配色时跟着变，也不会踩主题闸门（Widget 里出现十六进制会直接报红）。
/// 全程不判 `colorScheme` —— token 自己是动态色，深浅由系统解析，Widget 只需要跟随桌面外观。
struct WidgetGameBackdrop: View {

    /// 星点位置（归一化坐标 + 尺寸 + 透明度）。
    ///
    /// 写死而不是随机：每次重绘都随机的话，刷新时星星会跳，看起来像画面在闪。
    /// 位置故意避开中上部（大字时刻与场次表都在那里），只做极淡的颗粒。
    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (0.06, 0.12, 1.5, 0.20), (0.17, 0.30, 1.1, 0.14), (0.29, 0.09, 1.0, 0.13),
        (0.42, 0.24, 1.6, 0.20), (0.55, 0.13, 1.0, 0.13), (0.67, 0.33, 1.3, 0.16),
        (0.78, 0.07, 1.0, 0.12), (0.88, 0.22, 1.4, 0.18), (0.95, 0.40, 1.0, 0.12),
        (0.12, 0.58, 1.0, 0.10), (0.90, 0.62, 1.1, 0.10)
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
                // ① 底色：与 App 内轨迹卡同一组 token 的深靛渐变
                LinearGradient(
                    colors: [Theme.trackTop, Theme.trackBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // ② 左上角一层极淡的品牌色余晖：让深底不死板，也和 App 的青柠主色呼应
                RadialGradient(
                    colors: [Theme.lime.opacity(0.10), Theme.lime.opacity(0)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 180
                )

                // ③ 星点
                ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                    Circle()
                        .fill(Theme.trackArc.opacity(star.opacity))
                        .frame(width: star.size, height: star.size)
                        .position(x: w * star.x, y: h * star.y)
                }

                // ④ 云海：三层，越靠下越实，只压在底部三成 —— 上面留白给文字
                ForEach(0..<3, id: \.self) { layer in
                    cloudLayer(width: w, height: h, index: layer)
                }

                // ⑤ 右下角的一团暖光（蜡烛 / 光的方向，也是红石的视觉暗示）
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.lime.opacity(0.18), Theme.lime.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 46
                        )
                    )
                    .frame(width: 92, height: 92)
                    .position(x: w * 0.86, y: h * 0.88)
            }
            .frame(width: w, height: h)
        }
        .allowsHitTesting(false)
    }

    /// 一层云。
    ///
    /// 关键在 `.blur`：纯色椭圆直接叠会在边界留下硬边，浅色下看起来像"扫描线"。
    /// 模糊 12pt 之后边缘化开才像雾。颜色用 `trackArc`（淡蓝紫）而不是 `textPrimary`：
    /// 后者在浅色主题是深灰，压在白卡上就是一道道脏印子。
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
