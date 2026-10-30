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
    /// 区块标题下间距
    static let sectionTitleGap: CGFloat = 12
    /// 正文块间距
    static let blockGap: CGFloat = 20
    /// 列表项最小点击高度
    static let listItemMinHeight: CGFloat = 48

    /// 浮动 Tab 栏高度
    static let tabBarHeight: CGFloat = 56
    /// 浮动 Tab 栏左右内缩
    static let tabBarInset: CGFloat = 24
    /// 浮动 Tab 栏距底
    static let tabBarBottomGap: CGFloat = 16
    /// 页面底部留白（PRD §3.1 第 9 条：至少 120pt，防浮层遮挡）
    static let pageBottomInset: CGFloat = 120

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
