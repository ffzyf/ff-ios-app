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
    var height: CGFloat {
        switch self {
        case .hero: return 240
        case .medium: return 168
        case .tile: return 96
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
    /// rail「露边」的参考值：393 屏上 353 − 140×2 − 12×2 = 49，第三张能露出 1/3
    static let railPeek: CGFloat = 20

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
    /// 两列页面总宽（560 + 32 + 368）
    static let twoColumnMaxWidth: CGFloat = 960
    /// 两列的副列（红石：下一场/分布/规律；收益：平台 2×2）
    static let sideColumnWidth: CGFloat = 368
    /// 两列之间（= `Spacing.sectionGapLoose`，全页只有一种"组间呼吸"）
    static let columnGap: CGFloat = 32
    /// Tab 胶囊最大宽
    static let tabBarMaxWidth: CGFloat = 480
    /// 低于此宽一律按 compact 处理（iPhone 最宽竖屏 440 之上、iPad 最小全屏 744 之下）
    static let compactWidthThreshold: CGFloat = 500
    /// 达到此宽才开两列（从两列反推：900 时主列 500、月历格子 67）
    static let wideWidthThreshold: CGFloat = 900
}
