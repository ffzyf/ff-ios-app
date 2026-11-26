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

    // MARK: - HIG 迭代（T01）新增

    /// 触控目标最小边长（HIG ≥44×44）。供 `tapTarget()` 的透明命中区使用，
    /// 视觉尺寸完全不变（例如 IconGlassButton 仍是 36pt）。
    static let tapMinSide: CGFloat = 44
    /// 沉浸页底部给 Home Indicator 的留白（沉浸页忽略安全区时的兜底）
    static let homeIndicatorReserve: CGFloat = 8
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
    /// 公告 / 更新弹层的图标入场（5.3.0）。
    ///
    /// 为什么不是 `glassIn` 的 easeOut：那一条是"整块玻璃淡入"，而这里是**一个小元素
    /// 从 0.86 长到 1**，需要回弹一点点才像材料落位，线性缓出会显得"贴上去的"。
    /// 参数照 Apple 的 sheet 档（damping 0.86 / response 0.34）——
    /// 阻尼略低于 1.0 留一丝过冲，但不弹跳，因为这不是手势带出来的动能。
    static let notice = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// 状态卡左缘光晕呼吸（2.4s 循环，只在 A 态存在）
    static let glow = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)
    /// 骨架 shimmer（1.4s 循环）
    static let shimmer = Animation.linear(duration: 1.4).repeatForever(autoreverses: false)
    /// 沉浸页 chrome 显隐偏好（HIG 迭代 T01，供后续浮层动画复用）
    static let immersiveChrome = Animation.easeInOut(duration: 0.25)

    // MARK: - 5.7.0 redesign 新增（MASTER.md §7）

    /// 太阳下沉 —— The one motion。界面做产品做的事：天光页让天空真的在走。
    /// 1.2s easeInOut，太阳 y −14 → 0、亮度渐显；环境动作要慢，不能是微交互的节奏。
    static let sunSink = Animation.easeInOut(duration: 1.2)

    /// 微交互 120ms：开关、图标点按这类即时反馈。
    static let micro = Animation.spring(response: 0.12, dampingFraction: 0.78)

    /// 卡片依次入场每张卡的间隔（不是 Animation，是延迟量）。
    static let staggerStep: Double = 0.06

    /// 减弱动态时的统一降级：只留 180ms 的透明度淡入，位移/stagger 全部归零。
    static let reduced = Animation.easeOut(duration: 0.18)

    /// 按 reduceMotion 选动画：真 → 纯淡入降级；假 → 传入的完整动画。
    /// 让每个挂载点不必各写一遍 if reduceMotion 分支。
    static func choose(_ full: Animation, reduced: Bool) -> Animation {
        reduced ? Self.reduced : full
    }
}
