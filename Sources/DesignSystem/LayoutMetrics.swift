import SwiftUI

/// 全工程唯一的"设备有多大"判定（设计文档 §1.3 / §1.4）。
///
/// 为什么不是 `UIDevice.current.userInterfaceIdiom`：iPad 的 Split View / Slide Over /
/// Stage Manager 会让**同一台设备**在 320pt 与 1194pt 之间自由切换，而 idiom 全程返回 `.pad`。
/// 按 idiom 分支的布局，要么在 320pt 的 Slide Over 里排成"缩小的 iPad 版"（字挤、图裁），
/// 要么在切分屏的瞬间不重排。宽度是唯一能表达"还有多少地方可以并排"的量。
///
/// 为什么不是只用 `horizontalSizeClass`：它只有两档，无法区分 iPad 竖屏（834，该单列 720）
/// 与横屏（1194，该两列 960）。所以判定输入 = `horizontalSizeClass` + 容器实际宽度，两者都要。
struct LayoutMetrics: Equatable {
    /// 三档（判定见设计文档 §1.2）
    enum WidthClass: Int, Equatable {
        /// 与 3.4.0 逐像素一致 —— 所有宽屏分支都不进
        case compact
        /// 单列居中限宽（iPad 竖屏 834 / 1⁄2 分屏 590 / Stage Manager 700）
        case regularNarrow
        /// 两列（仅红石 / 收益 / 文章三页）
        case regularWide
    }

    /// 容器实际尺寸（不含安全区）。由 `LayoutMetricsScope` 的 GeometryReader 量一次
    var containerSize: CGSize
    var horizontalSizeClass: UserInterfaceSizeClass?

    /// 兜底值：任何拿不到环境的场合（预览、单测、忘记注入的子树）自动退回今天的版式。
    ///
    /// 393×852 是 iPhone 15/16 的逻辑尺寸，取它是为了让"兜底"与"真机 iPhone"完全同构，
    /// 而不是随便挑一个"看起来像手机"的数字。
    static let compact = LayoutMetrics(
        containerSize: CGSize(width: 393, height: 852),
        horizontalSizeClass: .compact
    )

    /// 档位判定。顺序不能反：`.compact` 的尺寸类优先于宽度阈值 ——
    /// iPad 1⁄3 分屏约 400pt（宽度已 < 500，两条都成立），但 Stage Manager 里
    /// 一个 520pt 的窗口也可能是 `.compact`，那种情况必须跟着系统给的尺寸类走。
    var widthClass: WidthClass {
        if horizontalSizeClass == .compact { return .compact }
        if containerSize.width < Layout.compactWidthThreshold { return .compact }
        if containerSize.width < Layout.wideWidthThreshold { return .regularNarrow }
        return .regularWide
    }

    /// 只有 `regularWide` 才并排。8pt 级的差异不改结构，避免边界抖动时反复重排。
    var isTwoColumn: Bool { widthClass == .regularWide }

    /// 单列页面列宽（§3.1：概览 / 简报 / 更多 / 问卷列表与结果）
    var contentWidth: CGFloat { min(effectiveWidth, Layout.contentMaxWidth) }

    /// 正文列宽（§3.8 阅读行宽 60–75 字符原则）
    var readingWidth: CGFloat { min(effectiveWidth, Layout.readingMaxWidth) }

    /// 表单列宽（§3.7 设置行"标题 …… 值"不折行的上限）
    var formWidth: CGFloat { min(effectiveWidth, Layout.formMaxWidth) }

    /// 两列页面总宽（560 + 32 + 368）
    var twoColumnWidth: CGFloat { min(effectiveWidth, Layout.twoColumnMaxWidth) }

    /// Tab 胶囊宽度。
    ///
    /// 窄屏 393 − 8×2 = 377，与 3.4.0 完全一致；宽屏封顶 480。
    /// 减 `tabBarInset * 2` 是因为 `RootView` 在限宽之后还会加 `.padding(.horizontal, 8)` ——
    /// 这里先扣掉，最终成品宽度才等于本值。
    var tabBarWidth: CGFloat {
        min(effectiveWidth - Spacing.tabBarInset * 2, Layout.tabBarMaxWidth)
    }

    /// 参与计算的宽度：**没量到（首帧 `containerSize == .zero`）时一律用 `.compact` 的 393**。
    ///
    /// 这是对 §1.3 字面公式的一处必要修正：`@State` 初值 `.zero` 确实会让 `widthClass`
    /// 落到 `.compact`（因为 `0 < 500`），但所有**由宽度算出来的**值都会跟着变成 0 ——
    /// `tabBarWidth` 变 0 意味着 App 启动首帧的 Tab 栏宽度是 0（一次肉眼可见的闪缩），
    /// 而 T4 要给正文列调用 `.pageColumn(metrics.readingWidth)`，`readingWidth == 0`
    /// 会让整页首帧宽度为 0（比闪缩严重得多）。
    ///
    /// 用 `.compact` 的值兜底，才能让文档里那句"首帧按 iPhone 版式"对**宽度**也成立，
    /// 而不只是对 `widthClass` 成立。真机宽度最小 320（Slide Over），永远不会是 0，
    /// 所以这个兜底只在"还没量到"的那一帧生效。
    private var effectiveWidth: CGFloat {
        containerSize.width > 0 ? containerSize.width : LayoutMetrics.compact.containerSize.width
    }

    /// 列宽被限住（= 屏幕比列宽宽）时，横向 rail 不允许出血（§4.3）。
    ///
    /// 出血的前提是"列宽 = 屏宽"：卡片滑到屏幕边才有意义。
    /// 宽屏下列宽 720 < 1194，出血会让卡片滑到列外、压在空白上。
    /// 未测量时 `0 <= 720` 成立 → 出血 = `.compact` 的行为（今天的样子），方向正确。
    var allowsRailBleed: Bool { containerSize.width <= Layout.contentMaxWidth }
}

private struct LayoutMetricsKey: EnvironmentKey {
    /// 默认 `.compact`：漏注入只会退回 iPhone 尺寸，**不会编译失败**（设计文档 §0 的硬要求）
    static let defaultValue: LayoutMetrics = .compact
}

extension EnvironmentValues {
    /// 由 `LayoutMetricsScope` 在 App 根注入一次，之后所有页面只读不算。
    var layoutMetrics: LayoutMetrics {
        get { self[LayoutMetricsKey.self] }
        set { self[LayoutMetricsKey.self] = newValue }
    }
}

/// 尺寸测量与注入。**全工程只有这里一个 GeometryReader 参与尺寸判定。**
///
/// 三条决定"零回归"的实现要点（§1.4）：
///
/// 1. 测量用 `.background { GeometryReader … }`，**不是**包一层 `GeometryReader`。
///    `background` 不参与父级布局，`RootView` 拿到的 proposal 与今天完全一样 ——
///    这是不碰 `safeAreaInset` 语义的唯一办法。包一层会让 Tab 栏重新计算后可能上移/下移 1–2pt。
///
/// 2. 只在 `onAppear` / `onChange(of: proxy.size)` 时写 `@State`，**不做每帧读**。
///    滚动、Tab 切换、`matchedGeometryEffect` 滑动期间 `proxy.size` 不变，写值不触发，
///    因此不会引起 body 重算 —— 这正是 B7 那个"每帧重建渐变"问题的解法，同一个手法。
///
/// 3. `@State` 初值是 `CGSize.zero` → `widthClass == .compact`。
///    **首帧按 iPhone 版式、第二帧切宽屏**。这个代价换来的是"任何环境丢失都退回今天的样子"，
///    比"猜一个 iPad 宽度"（等于把设备假设重新写回来）安全得多。
///
/// 为什么不是"每个页面自己写 GeometryReader"：6 个一级页 + 5 个二级页 + 3 个弹层，
/// 各写一份就有 14 个"设备判定"入口，其中任意一个漏改就是一处只在 iPad 上错位的 bug。
/// **一份环境值，一个判定函数。**
struct LayoutMetricsScope<Content: View>: View {
    /// 尺寸类从系统读（它已经跟随窗口变化，不需要我们量）
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var containerSize: CGSize = .zero
    private let content: Content

    /// 手写 init 而不是依赖 `@ViewBuilder` 修饰存储属性：
    /// 与 `ThemeScope` 保持同一写法，避免跨文件构造时隐式 memberwise init 可见性被降级。
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background {
                GeometryReader { proxy in
                    // Color.clear 只为占据测量区域：它不绘制、不参与布局、不吃触摸
                    Color.clear
                        .onAppear { containerSize = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in
                            // 尺寸真变才写。旋转 / 分屏 / Stage Manager 拉窗口才到这里，
                            // 滚动与 Tab 动画期间 proxy.size 恒定 → 不写 → 不重算 body。
                            if containerSize != newSize { containerSize = newSize }
                        }
                }
            }
            .environment(
                \.layoutMetrics,
                LayoutMetrics(
                    containerSize: containerSize,
                    horizontalSizeClass: horizontalSizeClass
                )
            )
    }
}
