import SwiftUI
import WidgetKit

/// Widget 专用排版常量。
///
/// 为什么单独一个文件而不复用 `Typography`：
/// 小组件画布只有 158pt / 338pt 宽，`Typography.display`（34pt）在桌面上一行都放不下；
/// 如果把 Widget 的字号塞进 `Typography`，主 App 那边就会多出一批"只有小组件在用"的字号，
/// 下次改版没人敢删。这里只放**小组件自己的**几档，主 App 零影响。
///
/// 颜色一律走 `Theme` / `TrackGradient`（Shared 里的动态色在 Widget 进程同样生效）：
/// 但 Widget **跟随系统外观，不跟随 App 的三态设置** —— 这是有意的：
/// 苹果的小组件就应该跟桌面走，用户在 App 里选"始终深色"不该让桌面出现一块不合群的黑方块。
enum WidgetTheme {

    // MARK: - 字号

    /// 10pt：小号里最上面的「红石」标签、徽标
    static let label = Font.system(size: 10, weight: .semibold)
    /// 11pt：中号里「今日 3 场」这类计数、右半列表
    static let meta = Font.system(size: 11, weight: .medium)
    /// 13pt：地图名（小号最多 2 行）
    static let mapName = Font.system(size: 13, weight: .semibold)
    /// 12pt：中号右半的场次行
    static let rowText = Font.system(size: 12, weight: .regular)
    /// 12pt Medium：场次时刻
    static let rowTime = Font.system(size: 12, weight: .semibold, design: .monospaced)
    /// 28pt：小号大字时刻 `19:08`（rounded，任务 1 特征5「rounded」）
    static let bigTime = Font.system(size: 28, weight: .bold, design: .rounded)
    /// 22pt：中号左半大字时刻（比小号略小，给右半让位）
    static let mediumTime = Font.system(size: 24, weight: .bold, design: .rounded)
    /// 11pt 等宽：倒计时
    static let countdown = Font.system(size: 11, weight: .semibold, design: .monospaced)
    /// 13pt：简报正文（前 2 段）
    static let briefBody = Font.system(size: 12, weight: .regular)
    /// 11pt：简报页脚（推送状态）
    static let briefFooter = Font.system(size: 10, weight: .medium)
    /// 20pt bold：简报首句（句子不是数字，不要 44pt，约 20pt 截断 2 行）
    static let briefBig = Font.system(size: 20, weight: .bold)
    /// 11pt semibold：底部两行的地点图标
    static let placeIcon = Font.system(size: 11, weight: .semibold)
    /// 11pt：顶部一行次要状态色（如「简报」「周四」）
    static let statusSecondary = Font.system(size: 11, weight: .medium)
    /// 12pt semibold：顶部一行地名/地图名
    static let headerTitle = Font.system(size: 12, weight: .semibold)

    // MARK: - 间距

    /// 组件内容内边距
    static let padding: CGFloat = 12
    /// 行间距
    static let rowGap: CGFloat = 3
    /// 区块之间
    static let blockGap: CGFloat = 8

    // MARK: - 外观辅助

    /// Widget 的容器背景：**每个 widget 传自己的渐变**。
    ///
    /// 为什么改成接收渐变参数（而不是旧的纯色 `Theme.bgBase`）：
    /// 任务 1「太阳轨迹」设计要求整卡渐变背景、颜色即信息（晨/日间/黄昏/夜/进行中/即将各有配方），
    /// 旧的纯色背景直接违背"颜色即信息"。`containerBackground(for: .widget)` 这个 API 必须存在
    /// （iOS 17 起不加会被 WidgetKit 打红警），所以保留它，但改成交渐变；逐 widget 接线后，
    /// 全工程已无 widget 再走纯色实现。
    ///
    /// - Parameters:
    ///   - gradient: 由 `TrackGradient.gradient(for:)` 算好的 [Color]（已随系统外观自适应）
    ///   - start: 渐变起点，默认 `.topLeading`（与设计文档方向一致）
    ///   - end: 渐变终点，默认 `.bottomTrailing`
    @ViewBuilder
    static func containerBackground(gradient: [Color],
                                   start: UnitPoint = TrackGradient.startPoint,
                                   end: UnitPoint = TrackGradient.endPoint) -> some View {
        LinearGradient(colors: gradient, startPoint: start, end: end)
    }
}
