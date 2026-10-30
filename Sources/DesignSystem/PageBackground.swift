import SwiftUI

/// 深空双层背景（PRD §4.1）：
/// 1. 线性渐变 `#121826`（顶）→ `#0A0D14`（底部 60% 处）
/// 2. 径向青柠光斑：圆心 `(0.2, -0.1)`，半径 = 屏宽 × 1.1，`#6BDB5C` 透明度 0.07 → 透明
///
/// **这是整个 App 唯一的大面积彩色**，只出现在概览与简报两页顶部。
/// 文章列表与详情页必须传 `glow: false`：阅读页要保持中性，否则正文对比度被干扰。
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
    var body: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [Theme.lime.opacity(0.07), Theme.lime.opacity(0.0)],
                center: UnitPoint(x: 0.2, y: -0.1),
                startRadius: 0,
                endRadius: max(proxy.size.width * 1.1, 1)
            )
        }
    }
}
