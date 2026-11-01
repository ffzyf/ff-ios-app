import SwiftUI

/// 卡片高度档（设计报告 §5 第 6 项）。
///
/// 为什么要有枚举而不是继续写字面量：改版前三张大卡的高度分别是 196 / 223 / 自适应，
/// 散在 `SkyCard` / `TrackCard` / `SkyStatusCard` 里，谁都说不出"这个数字是哪来的"。
/// 收进枚举之后，「这张卡是第几级」变成一个可读的参数，页面层不再出现无名高度，
/// 也就没法再"每个工程师自己拍一个高度"。
enum CardTier {
    /// 一屏唯一锚点（首页红石倒计时）
    case hero
    /// 次级主卡（首页简报摘要；同一份数据在简报页是 hero）
    case medium
    /// 并排小卡（今日一览 / 收益三格）
    case tile
    /// 横向 rail 里的卡（继续读）
    case rail

    /// 卡片高度（8pt 网格）
    ///
    /// 这是**窄档（iPhone / Slide Over）**的值，与 3.4.0 逐像素一致。
    /// 宽档不要直接读它 —— 走 `LayoutMetrics.cardHeight(_:)`。
    var height: CGFloat {
        switch self {
        case .hero: return 240
        case .medium: return 168
        case .tile: return 96
        case .rail: return 188
        }
    }

    /// 卡片高度（宽档 / iPad 画布 1080）。
    ///
    /// 为什么是"同比例放大"而不是等比缩放（设计文档 §5.1 / R6）：
    /// 宽度 ×1.21（560 → 680）时高度 ×1.22（216 → 264），高宽比几乎不变，
    /// 观感是"同一张卡变大了"；等比缩放（×1.56）会把 216 撑到 337，卡里只剩空气。
    ///
    /// `hero = 344` 不是随手取的：它是 40（分区标题）+ 120（tile）+ 12 + 172（简报卡被拉伸后的高），
    /// **同时**等于三列栅格的列宽（1080 = 344×3 + 24×2）—— 一个数字同时管住"列宽"和"大卡高度"，
    /// 概览页 Row A 的左右两块才能严格齐平（设计文档 §4.1）。
    var wideHeight: CGFloat {
        switch self {
        case .hero: return 344
        // 168 不动：它是 `minHeight`，宽档会被 `Spacer` 拉到 172 与 hero 齐平，本身不该变大
        case .medium: return 168
        case .tile: return 120
        // 宽档不再使用：iPad 上「继续读」改 3 列网格，横滑 rail 只服务窄档
        case .rail: return 188
        }
    }

    /// rail 卡的固定宽。
    ///
    /// 其余档位都吃满整行，所以宽度不作为档位属性给出 —— 只有一个值需要它时，
    /// 给一个常量比给一个"会给 nil 的计算属性"更好读。
    static let railWidth: CGFloat = 140
}

/// 非间距类几何常量（设计报告 §5 第 6 项）。
///
/// 为什么不塞进 `Spacing`：轨道高 4pt、构成条 10pt 是**元素自身的厚度**，不是"两块之间留多少"。
/// 混进 8pt 网格的间距表，后来的人会以为它们是随手可调的留白，而不是被设计定过的几何。
///
/// 关于名字：SwiftUI 有一个同名协议 `Layout`，但模块内声明优先于 import，
/// 且全工程没有任何类型实现该协议（只有一处注释提到它），所以不会撞。
enum Layout {
    /// 进度轨厚度（红石 hero 卡的「今日第 N/M 场」）
    static let trackHeight: CGFloat = 4
    /// 三态构成条厚度（收益页 hero 卡，下一轮用）
    static let compositionBar: CGFloat = 10
    /// rail 卡之间的间距
    static let railGap: CGFloat = 12

    // MARK: - 宽屏（iPad）常量（设计文档 §4.2，9 个）
    //
    // 只加不改：这些值只在 `LayoutMetrics.widthClass != .compact` 的分支里被读到，
    // 窄屏永远不进那些分支，所以新增它们对 iPhone 的观感是零影响的。
    //
    // 为什么不给 `Spacing` 加 `pageWide`：页面 20 在 393 与 1194 上都成立（列宽已经限住），
    // 多一个"宽屏页边距"等于给未来的自己留一个"什么时候该用哪个"的选择题。

    /// 单列页面列宽（含 page padding 20×2 → 文字 680）
    static let contentMaxWidth: CGFloat = 720
    /// 正文列宽（文字 600 ≈ 17pt 下 35 个汉字／70 个西文字符）
    static let readingMaxWidth: CGFloat = 640
    /// 表单（设置 / 监控 / 填答）
    static let formMaxWidth: CGFloat = 640
    // `twoColumnMaxWidth 960`（560 + 32 + 368）在 2026-10-31 的 iPad 版式重做里被删掉了：
    // 两列的实参改由 `LayoutMetrics.railPageWidth` 从**画布**算出来（1080 = 680 + 32 + 368），
    // 960 只表达"主列 560"，而 560 与 iPhone 的 353 只差 1.6 倍、屏幕宽了 3 倍 ——
    // 多出来的宽度全给了留白（设计文档 §0.1 ②）。删掉是为了不留两条并行的算法：
    // 留着它，下一个改版的人就会有一半页面读 960、一半读画布。
    /// 两列的副列（红石：下一场/今日场次/分布/规律；收益：平台 2×2）
    static let sideColumnWidth: CGFloat = 368
    /// 两列之间（= `Spacing.sectionGapLoose`，全页只有一种"组间呼吸"）
    static let columnGap: CGFloat = 32
    /// Tab 胶囊最大宽
    static let tabBarMaxWidth: CGFloat = 480
    /// 低于此宽一律按 compact 处理（iPhone 最宽竖屏 440 之上、iPad 最小全屏 744 之下）
    static let compactWidthThreshold: CGFloat = 500
    /// 达到此宽才开两列（从两列反推：900 时主列 500、月历格子 67）
    static let wideWidthThreshold: CGFloat = 900

    // MARK: - 画布 / 栅格 / 顶部导航条（2026-10-31 iPad 版式重做，设计文档 §3 / §4 / §6）
    //
    // 与上面那批"列宽"常量的关系：上面的是**列**（文字列 640 / 720）与**两列布局的实参**，
    // 下面这批是**画布**（一页最多能用多宽）与**栅格**（画布怎么切开）。
    // 一个页面只该读其中一套：正文类读列宽（行宽由字形决定，R9），卡片/列表类读画布。

    /// 画布上限 1080。1183/1194 等大屏一律封顶在这里。
    ///
    /// 为什么不是"满宽减 40"：20 / 1194 = 1.7%（iPhone 上是 5.1%），卡片边缘几乎贴屏幕边框，
    /// 读起来像"内容溢出到框外"。1080 的来历是 Apple News Format 的默认值
    /// （设计宽 1024 / 左右边距 60）按同比例放大到 1194 ≈ 1054，取整到能被三列整除：
    /// **1080 = 344×3 + 24×2**，内容占 90.5%、留白 57。
    static let canvasMaxWidth: CGFloat = 1080
    /// 栅格列宽（三列时；也是概览 hero 卡的宽档高度，见 `CardTier.wideHeight`）
    ///
    /// 两列宽 712 = 344×2 + 24 只是线框图上的一笔，**工程里不设常量**：1020…1039 那条窄带里
    /// 列宽不是 344，写死 712 会横向溢出；概览用的是 `frame(maxWidth: .infinity)`，
    /// 在 1080 的画布上它算出来正好是 712。（3.11.0 删掉了零引用的 `gridSpan2Width`。）
    static let gridColumnWidth: CGFloat = 344
    /// 栅格栏距
    static let gridGutter: CGFloat = 24
    /// 主列宽（rail 档：1080 − 32 − 368）
    static let mainColumnMaxWidth: CGFloat = 680
    /// 画布达到此宽才允许 2 列（760 = 368×2 + 24：两列时每列不小于副列宽 368）
    static let grid2MinCanvas: CGFloat = 760
    /// 画布达到此宽才允许 3 列（1020 = 324×3 + 24×2：每列不小于 324，否则标题掉成 1 行）
    static let grid3MinCanvas: CGFloat = 1020
    /// 画布达到此宽才允许"主列 + 副列"（1040 = 主列下限 640 + 32 + 368）
    static let railMinCanvas: CGFloat = 1040
    /// 宽档顶部导航条高度（44 同时是 iOS 最小点击目标）
    static let tabStripHeight: CGFloat = 44
    /// 宽档顶部导航条左右内边距
    static let tabStripHorizontalPadding: CGFloat = 10
}
