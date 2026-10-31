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
    /// 光斑半径改用「**实际被涂的那块区域**最大边的相对比例」（B7 + 设计文档 §1.6）：
    /// 不再用 `GeometryReader` 包住渐变读 `width`（那会让布局参与每帧动画、重建渐变），
    /// 也不用 `UIScreen.main.bounds`（分屏下那是**屏幕**尺寸而不是**窗口**尺寸）。
    private static let radiusRatio: CGFloat = 0.9

    /// 绘制区域的最大边。只在 `onAppear` 与尺寸真变时写入，滚动 / Tab 动画期间不变 → 不重算渐变。
    ///
    /// 初值 852 = 393×852 的长边，于是首帧半径 = 852 × 0.9 = **766.8**，
    /// 与今天 iPhone 上逐像素相同 —— 即使 `onAppear` 因为任何原因没有跑到，也不会闪一个错的半径。
    @State private var maxDimension: CGFloat = 852

    var body: some View {
        // 半径与几何布局无关（只取决于被绘制的区域有多大），不进 GeometryReader 的每帧布局路径
        RadialGradient(
            gradient: Self.gradient(opacity: metrics.glowOpacity),
            center: UnitPoint(x: 0.2, y: -0.1),
            startRadius: 0,
            endRadius: maxDimension * Self.radiusRatio
        )
        // 为什么不复用 `layoutMetrics.containerSize`：根部量到的那个尺寸是"窗口的安全区内容尺寸"
        // 还是"全窗口尺寸"，取决于 SwiftUI 在该层的 proposal 语义（RootView 自己也有 safeAreaInset）。
        // 若它不含状态栏 / Home Indicator 区域，iPhone 上半径会从 766.8 掉到 ~683（小 11%，肉眼可见）。
        // **半径应当相对"实际被涂的那块区域"算** —— 那就到涂它的这一层去量，语义自洽，
        // 且与安全区怎么分配无关。`PageBackground` 带 `.ignoresSafeArea()`，所以这里量到的就是全屏。
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { maxDimension = max(proxy.size.width, proxy.size.height) }
                    .onChange(of: proxy.size) { _, newSize in
                        let next = max(newSize.width, newSize.height)
                        // 只在尺寸真变时写：旋转 / 分屏才触发，滚动与 Tab 滑动期间恒定
                        if next > 0, next != maxDimension { maxDimension = next }
                    }
            }
        }
    }

    /// 颜色停靠点固定（只随外观变、不随布局变）：抽成函数，避免每次 body 重建 `Gradient` 对象。
    /// `metrics.glowOpacity` 在外观切换外是稳定的，所以渐变不会随 tab 动画每帧重算。
    private static func gradient(opacity: Double) -> Gradient {
        Gradient(colors: [
            Theme.lime.opacity(opacity * alphaRatio),
            Theme.lime.opacity(0)
        ])
    }
}
