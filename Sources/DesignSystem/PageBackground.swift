import SwiftUI

/// 深空双层背景（PRD §4.1）：
/// 1. 线性渐变（顶）`bgRaise` → `bgBase`（底部 60% 处）
/// 2. 径向青柠光斑：圆心 `(0.2, -0.1)`，半径随屏宽，青柠 → 透明
///
/// **这是整个 App 唯一的大面积彩色**，只出现在概览与简报两页顶部。
/// 文章列表与详情页必须传 `glow: false`：阅读页要保持中性，否则正文对比度被干扰。
///
/// 双主题（批次 1）：光斑的**半径与强度**是全工程仅有的两个"必须随外观变、又不能写成 Color"的数值，
/// 它们走 `ThemeMetrics`（`ThemeScope` 注入）。这里不判深浅 —— 只乘两个由环境给的数。
///
/// 为什么保留 `0.2` 这个换算系数：`ThemeMetrics.glowOpacity` 是 PRD §3.3 的**强度基准**
/// （深 0.35 / 浅 0.16），而 V2 渐变里实测的青柠不透明度是 0.07。两者之比恰好是 0.2，
/// 于是深色 `0.35 × 0.2 = 0.07`（**与 V2 逐像素一致**）、浅色 `0.16 × 0.2 = 0.032`（正好是 V2 的一半，
/// 符合 PRD「浅色光晕必须减半，否则整屏发绿」）。
struct PageBackground: View {
    var glow: Bool = true

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.bgRaise, Theme.bgBase, Theme.bgBase],
                startPoint: .top,
                endPoint: .bottom
            )
            if glow {
                LimeGlow()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// 青柠径向光斑
private struct LimeGlow: View {
    /// 数值 token（唯一允许随外观变的一组，见 ThemeMetrics）
    @Environment(\.themeMetrics) private var metrics

    /// V2 渐变里的青柠不透明度 / PRD 的强度基准 → 0.2（推导见 `PageBackground` 注释）
    private static let alphaRatio: Double = 0.2
    /// V2 的半径基准：屏宽 × 1.1（`metrics.glowRadius` 深色正好等于 220，所以深色除出来是 1.0）
    private static let radiusRatio: CGFloat = 1.1
    private static let radiusBaseline: CGFloat = 220

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            RadialGradient(
                colors: [
                    Theme.lime.opacity(metrics.glowOpacity * Self.alphaRatio),
                    Theme.lime.opacity(0)
                ],
                center: UnitPoint(x: 0.2, y: -0.1),
                startRadius: 0,
                endRadius: width * Self.radiusRatio * (metrics.glowRadius / Self.radiusBaseline)
            )
        }
    }
}
