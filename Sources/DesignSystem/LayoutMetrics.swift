import SwiftUI

/// 版式档（设计文档 §3.2）：**这一页怎么排**，不是"内容的列数"。
///
/// 为什么不合并成一个自适应栅格（§3.4）：红石月历必须恰好 7 列、收益 hero 必须跨列 ——
/// 用 `LazyVGrid(.adaptive)` 表达不了这些。版式档是"排法"，栅格列数是"排法的一个结果"。
///
/// 四个档只由**画布宽度**推出（门槛 760 / 1020 / 1040），与设备类型无关：
/// iPad 1⁄3 分屏（320）落在 `single`，13" 竖屏（canvas 984）落在 `grid2` 但 rail 页退回单列。
enum PageTier: Equatable {
    /// 单列（iPhone / Slide Over / 竖屏 / 分屏）：与 3.7.0 完全一致
    case single
    /// 2 列列表（834 竖屏 canvas 794）
    case grid2
    /// 3 列（canvas 1020…1039，只在 Stage Manager 的窄窗口里出现）
    case grid3
    /// 主列 + 副列（canvas ≥ 1040：1194 横屏 / 1210 / 1366）
    case rail
}

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

    /// 单列页面列宽（§3.1：概览 / 简报 / 更多 / 问卷列表与结果）
    var contentWidth: CGFloat { min(effectiveWidth, Layout.contentMaxWidth) }

    /// 正文列宽（§3.8 阅读行宽 60–75 字符原则）
    var readingWidth: CGFloat { min(effectiveWidth, Layout.readingMaxWidth) }

    /// 表单列宽（§3.7 设置行"标题 …… 值"不折行的上限）
    var formWidth: CGFloat { min(effectiveWidth, Layout.formMaxWidth) }

    // MARK: - 画布与版式档（2026-10-31 iPad 版式重做，设计文档 §3）

    /// 画布宽度 = **内容区**最多多宽（不含页边距 20×2）。
    ///
    /// 1194 → `min(1194 − 40, 1080)` = **1080**；834 → **794**；393 → **353**（= 今天）。
    ///
    /// 为什么减 `Spacing.page * 2`：`pageColumn(_:)` 套在 `.padding(.horizontal, 20)` **外面**，
    /// 所以它收到的是"内容 + 页边距"的总宽。画布量的是内容 —— 两列栅格 344 / 385 都是内容宽，
    /// 只有把 40 扣掉，三列 344×3 + 24×2 才恰好等于 1080（设计文档 R1 的"留白 57"也是这么算的：
    /// 37 列区外留白 + 20 页边距）。
    var canvasWidth: CGFloat {
        let usable = effectiveWidth - Spacing.page * 2
        return max(0, min(usable, Layout.canvasMaxWidth))
    }

    /// 版式档。门槛顺序必须从大到小 —— 1040 也满足 1020，反过来判定会把 rail 判成 grid3。
    var pageTier: PageTier {
        if canvasWidth >= Layout.railMinCanvas { return .rail }
        if canvasWidth >= Layout.grid3MinCanvas { return .grid3 }
        if canvasWidth >= Layout.grid2MinCanvas { return .grid2 }
        return .single
    }

    /// 这一页要不要"主列 + 副列"。**页面里唯一的宽档判断入口之一**（另一个是 `gridColumns`）。
    var usesRail: Bool { pageTier == .rail }

    /// 宽档是否把 Tab 栏搬到屏幕顶部（设计文档 §6.2 选 C）。
    ///
    /// 判据是"不是 compact"而不是"画布够宽"：iPad 竖屏 834 也该是顶部的系统形态（HIG：
    /// iPadOS 的 tab bar 在屏幕顶部）。`compact`（iPhone / Slide Over / 1⁄3 分屏）继续用底部胶囊，
    /// 几何一个像素都不变。
    ///
    /// **只读 `horizontalSizeClass`，不读 `widthClass`（3.7.0 修首帧闪）**：`widthClass` 混了
    /// `containerSize.width`，而那是 `LayoutMetricsScope` 用 GeometryReader 量出来的 ——
    /// iPad 冷启动首帧 `containerSize == .zero`，于是首帧判成 `.compact` 先用底部胶囊条、
    /// 第二帧量到宽度再跳成顶部条：chrome 从屏幕底部跳到顶部，是全页最显眼的一种闪。
    /// `horizontalSizeClass` 由系统直接给，不依赖任何测量，首帧就是正确的。
    /// 三种情况都不会漏：
    /// - Stage Manager 把窗口拖窄 → 尺寸类自己变成 `.compact` → 仍然退回底部条；
    /// - iPad 竖屏 834 / 横屏 1194 → 一直是 `.regular` → 从第一帧就是顶部条；
    /// - iPhone 恒为 `.compact` → 恒 false，零回归。
    var usesTopTabStrip: Bool { horizontalSizeClass == .regular }

    /// 画布 + 页边距 = **传给 `pageColumn` 的值**。
    ///
    /// 页面里的所有 `pageColumn(...)` 实参都该从这三个派生值里取，而不是自己算：
    /// - 正文列（640 / 720）→ `readingWidth` / `contentWidth`
    /// - 画布那一层（导航条 / 顶部条）→ `canvasPageWidth`
    /// - 版式档那一层 → `railPageWidth` / `gridPageWidth`
    ///
    /// 为什么必须加 `Spacing.page * 2`：`pageColumn` 套在 `.padding(.horizontal, 20)` 外面，
    /// 它收到的是"内容 + 页边距"。少加这 40，iPad 上每一列都会瘦 40/n（三列时每列瘦 13.3），
    /// 而 iPhone 上看不出来（宽于 393 的限宽本来就不生效）。
    var canvasPageWidth: CGFloat {
        return canvasWidth + Spacing.page * 2
    }

    /// rail 页（红石 / 收益 / 简报 / 更多）传给 `pageColumn` 的值。
    ///
    /// rail 不成立时等于今天的 720（834 竖屏、1024 竖屏、所有 compact 尺寸都是这条路）。
    /// 成立时是画布 + 页边距：渲染出来的内容宽才等于画布 1080（主列 680 / 栏距 32 / 副列 368）。
    var railPageWidth: CGFloat {
        usesRail ? canvasPageWidth : min(effectiveWidth, Layout.contentMaxWidth)
    }

    /// grid 页（概览 / 文章 / 攻略 / 监控 / 问卷结果）传给 `pageColumn` 的值。
    ///
    /// 单列时与今天完全一致（720）；多列时是画布 + 页边距（理由同上）。
    var gridPageWidth: CGFloat {
        gridColumns > 1 ? canvasPageWidth : min(effectiveWidth, Layout.contentMaxWidth)
    }

    /// 栅格列数：1 / 2 / 3。门槛与 `pageTier` 用同一组常量，两处不会漂。
    var gridColumns: Int {
        if canvasWidth >= Layout.grid3MinCanvas { return 3 }
        if canvasWidth >= Layout.grid2MinCanvas { return 2 }
        return 1
    }

    /// rail 页主列宽 = 画布 − 栏距 − 副列（1194 → 680）。
    ///
    /// 从画布算而不是写死 680：Stage Manager 拖到 1100 时主列会自动变窄，
    /// 写死会让副列被挤出画布（横向裁掉右半边卡）。
    /// `min(..., Layout.mainColumnMaxWidth)` 是把"主列不超过 680"这条写进代码 ——
    /// 画布已经封顶 1080，所以它今天恒不生效，但换个封顶值也不会悄悄把主列撑宽。
    var railMainWidth: CGFloat {
        let derived = canvasWidth - Layout.columnGap - Layout.sideColumnWidth
        return max(0, min(derived, Layout.mainColumnMaxWidth))
    }

    /// 单列宽度 = 画布按列数切开后的一格（1080 三列 → 344；794 两列 → 385）。
    var gridColumnWidth: CGFloat {
        let count = CGFloat(gridColumns)
        let gutters = Layout.gridGutter * (count - 1)
        return max(0, (canvasWidth - gutters) / count)
    }

    /// 卡片是否走宽档档位。`cardHeight(_:)` 与"hero 数字要不要换 56pt"共用这一个判据。
    ///
    /// 为什么要暴露出来而不是让页面各自判 `widthClass`：卡高与卡内字号是**同一件事的两面** ——
    /// 卡长到 344、数字却还是 40pt，就是设计文档 §5.2 说的"放大的空卡"。
    /// 两处共用一个布尔，才不会出现"高度换了字号没换"这种一半一半的状态。
    var usesWideCards: Bool { widthClass != .compact }

    /// 卡片立体倾斜（`CardTilt`）的最大角度（3.10.0 起窄档也启用）。
    ///
    /// 为什么窄档要收一档（5.5° → 4°）：窄档是**单列全宽卡片**（393pt 屏上卡片约 353pt 宽），
    /// 同样的旋转角在更宽的卡上，远端边缘的透视位移（弧长 ∝ 半宽 × sin θ）按比例放大，
    /// 视觉幅度明显大于 iPad 分栏里 ~340pt 的卡 —— 标题字形更容易被拉斜，
    /// 观感从"卡在转"滑向"字变形"。收 1.5° 把远端位移拉回与宽档同级，
    /// 手感（拖动行程 `Tilt.travel` 不变）与层次（视差 / 高光 / 阴影）都不动。
    ///
    /// 常量集中在这里而不是 `CardTilt.swift`：角度是"版式档位的属性"（跟卡宽走），
    /// 不是"手势的属性"；`CardTiltModifier` 已经读 `@Environment(\.layoutMetrics)`，
    /// 顺路取值，不再维护第二份与 `widthClass` 平行的判断。
    var cardTiltMaxAngle: Double {
        return widthClass == .compact ? Self.tiltAngleCompact : Self.tiltAngleWide
    }

    /// 宽档（iPad 分栏）最大倾角：3.9.0 及之前的既有值，一字未动
    static let tiltAngleWide: Double = 5.5
    /// 窄档（iPhone 单列全宽）最大倾角：理由见 `cardTiltMaxAngle` 的注释
    static let tiltAngleCompact: Double = 4.0

    /// 卡片高度：窄档给今天的值，宽档给同比例放大后的值（设计文档 §5.1）。
    ///
    /// 页面**不许**再直接写 `CardTier.xxx.height` —— 那个值只服务窄档，
    /// 在 1080 的画布上摆 240 高的卡就是"放大的手机"（设计文档 §5.4 的验收线 1.4…3.1:1）。
    func cardHeight(_ tier: CardTier) -> CGFloat {
        usesWideCards ? tier.wideHeight : tier.height
    }

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
