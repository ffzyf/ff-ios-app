import SwiftUI

/// 字号阶（PRD §4.2 逐条落成）。全部走系统字体 SF Pro，中文自动 fallback 苹方。
///
/// 刻意不引入自定义字体：中文下自定义字体字重不全，会破坏层级。
/// 也刻意用固定 pt 而不是 `.largeTitle` 这类语义字号：本项目视觉规范精确到 pt，
/// 交给系统字号会导致不同设备上排版漂移。
enum Typography {
    /// 34pt Bold / 1.15 —— 页面大标题、首页日期
    static let display = Font.system(size: 34, weight: .bold)
    /// 28pt Bold / 1.25 —— 文章详情标题
    static let titleXL = Font.system(size: 28, weight: .bold)
    /// 22pt Semibold / 1.3 —— 分区标题
    static let titleL = Font.system(size: 22, weight: .semibold)
    /// 20pt Semibold / 1.3 —— 卡片主字（状态卡）
    static let titleM = Font.system(size: 20, weight: .semibold)
    /// 17pt Semibold / 1.4 —— 文章卡标题、块内 h3
    static let titleS = Font.system(size: 17, weight: .semibold)
    /// 17pt Regular / 1.75 —— 正文
    static let body = Font.system(size: 17, weight: .regular)
    /// 16pt Regular / 1.8 —— 引用块
    static let bodySmall = Font.system(size: 16, weight: .regular)
    /// 15pt Regular / 1.5 —— 摘要、次级正文
    static let callout = Font.system(size: 15, weight: .regular)
    /// 13pt Regular / 1.45 —— 元信息、图注
    static let footnote = Font.system(size: 13, weight: .regular)
    /// 13pt Medium —— 按钮文字
    static let footnoteMedium = Font.system(size: 13, weight: .medium)
    /// 12pt Medium —— 徽标文字
    static let caption = Font.system(size: 12, weight: .medium)
    /// 11pt Medium —— Caps 分区标签、时间戳
    static let captionXS = Font.system(size: 11, weight: .medium)

    // MARK: - 数字锚点 / 眉题（设计报告 §5 第 2–4 项）

    /// 40pt Bold Rounded —— **大卡里的那一个数字**（首页倒计时、收益总额）。
    ///
    /// 之前这两个位置分别 inline 硬写 36 与 40：同一个语义两个值，还没法统一调。
    /// 走 `.rounded` 是因为数字在圆角卡片上是"读数"不是"正文"，圆体让 0/8/9 更易分辨。
    static let metricL = Font.system(size: 40, weight: .bold, design: .rounded)
    /// 56pt Bold Rounded —— **宽档**大卡里的那一个数字（iPad 画布上的首页倒计时）。
    ///
    /// 为什么宽档要单独一档、而不是把 `metricL` 整个放大：40pt 在 712 宽的卡里只占 16.5%，
    /// 卡变大了锚点却没变大，读起来就是"放大的空卡"（设计文档 §5.2）。
    /// 而窄档 353 宽的卡里 40pt 占 35%，正好 —— 所以只增一档、只在宽档取。
    static let metricXL = Font.system(size: 56, weight: .bold, design: .rounded)
    /// 28pt Bold Rounded —— tile（96pt）里的数字：比 `titleL` 大、比 `metricL` 小，
    /// 补的正是现有字阶 22 → 34 之间的空档
    static let metricM = Font.system(size: 28, weight: .bold, design: .rounded)
    /// 11pt Semibold —— 眉题（"红石 · 今日"这类"这是什么栏目"）。
    ///
    /// 不复用 `captionXS`：那个是 11 medium 无字距，用于时间戳；眉题要"更小更宽"才不会被
    /// 当成元信息读走（中文不做大写变形，只能靠字距和字重差异）。
    static let eyebrow = Font.system(size: 11, weight: .semibold)
    /// 眉题字距（配合 `eyebrow` 使用）
    static let trackingEyebrow: CGFloat = 0.5

    /// 13pt 等宽 —— 代码块（SF Mono）
    static let code = Font.system(size: 13, weight: .regular, design: .monospaced)
    /// 15pt 等宽 —— 版本号
    static let versionValue = Font.system(size: 15, weight: .semibold, design: .monospaced)
    /// 20pt 等宽 —— 版本双列卡主字
    static let versionLarge = Font.system(size: 20, weight: .semibold, design: .monospaced)

    /// 48pt 白 12% —— 封面首字水印
    static let coverWatermark = Font.system(size: 48, weight: .bold)

    /// 大字号标题的字距（PRD §4.2：≥22pt 加 -0.4pt，正文不动）
    static let trackingLarge: CGFloat = -0.4

    /// 行高换算：SwiftUI 的 `lineSpacing` 是「行间额外空白」，
    /// 系统单行自然高度约等于 `fontSize * 1.2`，所以额外量 = 目标行高 − 自然行高。
    static func lineSpacing(fontSize: CGFloat, multiple: CGFloat) -> CGFloat {
        let natural = fontSize * 1.2
        let target = fontSize * multiple
        return max(0, target - natural)
    }
}

/// 阅读字号三档（PRD §3.3 + §3.6：15 / 17 / 19，全局生效并持久化）
enum ReaderScale: String, CaseIterable, Identifiable {
    case small
    case standard
    case large

    var id: String { rawValue }

    var pointSize: CGFloat {
        switch self {
        case .small: return 15
        case .standard: return 17
        case .large: return 19
        }
    }

    var title: String {
        switch self {
        case .small: return "小"
        case .standard: return "标准"
        case .large: return "大"
        }
    }

    /// 正文行高倍数（PRD §4.2：正文 1.75）
    var lineHeightMultiple: CGFloat { 1.75 }
}
