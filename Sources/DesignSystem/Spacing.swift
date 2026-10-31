import SwiftUI

/// 间距（8pt 网格，PRD §4.3）
enum Spacing {
    /// 页面左右边距
    static let page: CGFloat = 20
    /// 卡片内间距
    static let cardPadding: CGFloat = 16
    /// 小卡内间距
    static let smallCardPadding: CGFloat = 12
    /// 卡片之间
    static let cardGap: CGFloat = 12
    /// 区块之间
    static let sectionGap: CGFloat = 24
    /// 分组之间（设计报告 §5 第 1 项）。
    ///
    /// 为什么 24 不够：`sectionGap 24 : cardGap 12` 只有 2.0×，卷起来两组读成"一行行"；
    /// 32 : 12 = 2.67× 才有肉眼可辨的两级 —— 间距差本身就是层级，不是装饰。
    static let sectionGapLoose: CGFloat = 32
    /// 区块标题下间距
    static let sectionTitleGap: CGFloat = 12
    /// 正文块间距
    static let blockGap: CGFloat = 20
    /// 列表项最小点击高度
    static let listItemMinHeight: CGFloat = 48

    /// 浮动 Tab 栏高度（3.8.1：74 → 66，压缩栏内上下死空间 —— 推导见 `FloatingTabBar.barHeight`）
    static let tabBarHeight: CGFloat = 66
    /// 浮动 Tab 栏左右内缩（V3.1：24 → 8，改成整幅宽，落点更大也更贴近系统栏观感）
    static let tabBarInset: CGFloat = 8
    /// 浮动 Tab 栏距底（3.8.1：10 → 4，栏更贴近底部安全区，少一截悬空 —— 用户原话
    /// "底部选择栏太往下了……点击图标不顺手"）
    static let tabBarBottomGap: CGFloat = 4
    /// 页面底部留白（3.8.1：120 → 96。Tab 栏压矮 8pt + 底距收 6pt 后，内容底部留白跟着收；
    /// 96 仍高于栏的实际占位 66 + 4，滚动到底不会露出"内容被栏压住"的缝隙）
    static let pageBottomInset: CGFloat = 96

    /// 网格单位
    static let gridUnit: CGFloat = 8
}

/// 圆角（PRD §4.3，含同心圆角规则：子元素圆角 = 父圆角 − 内间距）
enum Radius {
    /// 卡片
    static let card: CGFloat = 24
    /// 小卡 / 缩略图
    static let smallCard: CGFloat = 14
    /// 徽标
    static let badge: CGFloat = 6
    /// 弹层
    static let sheet: CGFloat = 32
    /// 正文内图片
    static let inlineImage: CGFloat = 16
    /// 卡片内图片（24 − 16 = 8）
    static let insideCard: CGFloat = 8
}

/// 动效（PRD §4.6 逐条落成常量）
enum Motion {
    /// Tab 切换：内容 opacity + scale，高亮胶囊 morph 滑移
    static let tab = Animation.spring(response: 0.35, dampingFraction: 0.82)
    /// 页面推入
    static let push = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// 页面返回
    static let pop = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// 卡片按压
    static let press = Animation.spring(response: 0.28, dampingFraction: 0.7)
    /// 简报卡展开
    static let expand = Animation.spring(response: 0.4, dampingFraction: 0.85)
    /// 图片比例过渡
    static let imageResize = Animation.spring(response: 0.35, dampingFraction: 0.9)
    /// 玻璃出现（比消失慢，消失要利落）
    static let glassIn = Animation.easeOut(duration: 0.3)
    static let glassOut = Animation.easeIn(duration: 0.22)
    /// 状态卡左缘光晕呼吸（2.4s 循环，只在 A 态存在）
    static let glow = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)
    /// 骨架 shimmer（1.4s 循环）
    static let shimmer = Animation.linear(duration: 1.4).repeatForever(autoreverses: false)
    /// 刷新圆弧旋转
    static let spinner = Animation.linear(duration: 0.9).repeatForever(autoreverses: false)
    /// 骨架呼吸（比 shimmer 更含蓄，用于 reduceMotion 之外的静默态）
    static let skeletonBreath = Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
}
