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
    /// 11pt 等宽：简报顶行的日期（`10月31日`），数字要对齐
    static let skyDate = Font.system(size: 11, weight: .medium, design: .monospaced)
    /// 11pt 等宽：地面区的日出 / 日落时刻（`06:44` / `17:33`）
    static let sunTime = Font.system(size: 11, weight: .medium, design: .monospaced)
    /// 10pt：地面区左槽的注脚（`宜 打猎、散步 · 忌 店铺开业`）—— 地平线以下只能放这么小
    static let skyNote = Font.system(size: 10, weight: .regular)

    // MARK: - 间距

    /// 组件内容内边距
    static let padding: CGFloat = 12
    /// 行间距
    static let rowGap: CGFloat = 3
    /// 区块之间
    static let blockGap: CGFloat = 8
    /// 简报卡左右内边距（比上下多 2pt：顶部胶囊离圆角要留出余量，否则会被裁角）
    static let skySidePadding: CGFloat = 14

    // MARK: - 天际线几何（与 App 内 `SkyCard` 同一组数）
    //
    // 这两个比例必须和 `Sources/DesignSystem/SkyCard.swift` 里的 `crestY` / `edgeY` 一致：
    // 桌面上那条地平线要和 App 内那张卡落在同一个高度，不然"同一套语言"就成了两套。

    /// 地平线弧顶（占卡片高度）
    static let skyCrestY: CGFloat = 0.62
    /// 地平线两端（占卡片高度）
    static let skyEdgeY: CGFloat = 0.74

    // MARK: - 实时太阳（V3.4：天空里那颗「现在在哪儿」的太阳）
    //
    // 尺寸取自参考图：太阳本体是一个"发光的小圆盘"—— 比一颗星大（≈4pt），
    // 比按钮小（≥16pt），所以定在 9pt。外面一圈 1.5pt 的高光环，再外面才是光晕。
    //
    // **颜色一个都没有新造**：太阳核 ⇒ `sky.edge`（每一档天色里最亮的那一支），
    // 光晕 ⇒ 按时段从 `sky.top` / `sky.horizon` / `sky.edge` 里挑。
    // 符合 PRD「View 层不出现裸颜色字面量」，也自动随天色（物理色）走。

    /// 太阳本体直径（pt）
    static let sunCoreDiameter: CGFloat = 9
    /// 本体外面那圈高光环的线宽
    static let sunRingWidth: CGFloat = 1.5
    /// 高光环比本体大多少（直径差）—— 1.5pt 的环要离开本体一点才看得见
    static let sunRingGap: CGFloat = 3.5
    /// 光晕半径占画布宽度的比例（参考图里那团扩散光：约 45% 屏宽）
    static let sunGlowFactor: CGFloat = 0.45
    /// 光晕最中心的不透明度（向外迅速衰减到 0）
    static let sunGlowAlpha: Double = 0.45
    /// 夜间余晖的半径占比（比白天的光晕小得多，只是一点"背光处"的痕迹）
    static let sunEmberFactor: CGFloat = 0.18
    /// 太阳正下方那段地平线额外加粗的线宽
    static let sunEdgeBoostWidth: CGFloat = 2.6

    /// 太阳本体：取当前时段天空里最亮的那支 `edge`（正午近白、晨昏暖白）
    static func sunCore(_ sky: Theme.SkyColors) -> Color {
        return sky.edge
    }

    /// 本体外面那圈高光环（同一支色，压一档不透明度 —— 环要"亮而薄"，不能抢本体）
    static func sunRing(_ sky: Theme.SkyColors) -> Color {
        return sky.edge.opacity(0.82)
    }

    /// 光晕主色：**随时刻变**。
    ///
    /// 日出、日落都取 `sky.top` —— 那两档是唯一"橙红 / 深橙"的天色；
    /// 黄金时刻取 `sky.horizon`（暖黄），白天取 `sky.edge`（近白）。
    /// 全部是 `Theme.sky(phase)` 里的既有 token，本文件一个颜色字面量都没有。
    static func sunGlow(_ sky: Theme.SkyColors, phase: SkyPhase) -> Color {
        switch phase {
        case .sunrise, .blueDawn:
            return sky.top
        case .golden:
            return sky.horizon
        case .sunset, .blueDusk:
            return sky.top
        case .day:
            return sky.edge
        case .night:
            // 夜里的 `horizon` 已经压到近黑，余晖会被自己的底色吃掉；
            // 改用 `edge`（那一档是冷蓝灰），才在深色地面上留得下一点痕迹
            return sky.edge
        }
    }
}

// MARK: - 天光（SkyLight）
//
// 「天光」是独立小组件（不是简报的皮肤），它只画"此刻的天光"，版式照参考图：
// 上排阶段名 + 倒计时，中间天空 / 地平线 / 太阳，下排日出日落。
//
// 为什么常量放在这里而不是散在三个新文件里：Widget 的画布只有 158 / 338 宽，
// 字号和线宽都是"差 1pt 就挤 / 就虚"的量，集中在一处才改得动、比得出来。
// **颜色一个都不在这里**：全部走 `Theme.sky(phase)`，本文件只放尺寸、字号与文案。
extension WidgetTheme {

    /// 天光组件的常量与文案
    enum SkyLight {

        // MARK: 注册信息

        /// WidgetKit 的 kind（改名会让已上桌的实例失效）
        static let kind = "SkyLightWidget"
        /// 组件库里的名字
        static let displayName = "天光"
        /// 组件库里的说明：一句话讲清"它会自己换"
        static let description = "只画此刻的天光：蓝调、日出、日落与夜色，太阳一落自己就换。"

        // MARK: 字号
        //
        // 小号（158pt）比中号（338pt）整体降一档：参考图的字号是按中号给的，
        // 原样搬进小号后"蓝调剩余 + 2分钟4秒"会顶到两边圆角。

        /// 10pt：中号左上「蓝调剩余」
        static let phaseLabelMedium = Font.system(size: 10, weight: .semibold)
        /// 9pt：小号左上阶段名
        static let phaseLabelSmall = Font.system(size: 9, weight: .semibold)
        /// 12pt 等宽：中号右上倒计时（数字对齐，读起来不跳）
        static let countdownMedium = Font.system(size: 12, weight: .semibold, design: .monospaced)
        /// 10pt 等宽：小号右上倒计时
        static let countdownSmall = Font.system(size: 10, weight: .semibold, design: .monospaced)
        /// 9pt 等宽：小号地面区的日出 / 日落（11pt 在两个时刻并排时会顶到边）
        static let sunTimeSmall = Font.system(size: 9, weight: .medium, design: .monospaced)

        /// 阶段名：按尺寸取档
        static func phaseLabel(_ family: WidgetFamily) -> Font {
            return family == .systemSmall ? phaseLabelSmall : phaseLabelMedium
        }

        /// 倒计时：按尺寸取档
        static func countdown(_ family: WidgetFamily) -> Font {
            return family == .systemSmall ? countdownSmall : countdownMedium
        }

        /// 地面区的日出 / 日落：中号复用 `WidgetTheme.sunTime`（11pt，与简报卡同一档）。
        ///
        /// 这里必须写全 `WidgetTheme.sunTime`：`SkyLight` 自己也有一个 `sunTime(_:)` 方法，
        /// 不加限定名会解析到方法本身（函数不是 `Font`，编译期直接报类型不匹配）。
        static func sunTime(_ family: WidgetFamily) -> Font {
            return family == .systemSmall ? sunTimeSmall : WidgetTheme.sunTime
        }

        // MARK: 尺寸

        /// 阶段色圆点直径（参考图里那颗小圆点，比标点略大一点才看得出颜色）
        static let dotDiameter: CGFloat = 5
        /// 圆点与阶段名 / 两段时间之间的最小间距
        static let dotGap: CGFloat = 5
        /// 中号内边距（158pt 高，上下各 14 后天空还剩 130pt，够放下拱形轨迹）
        static let mediumSidePadding: CGFloat = 14
        /// 小号内边距（方形画布更窄，收到 11pt 免得顶到圆角）
        static let smallSidePadding: CGFloat = 11

        // MARK: 地平线
        //
        // 参考图里的地平线是"有厚度的一道边"，不是 1px 线。这里用三层叠出厚度：
        // 雾化层（粗而淡）+ 实线层（本体）+ 太阳正下方的高光段（由 SkyLightFace 画）。
        // 零 `.blur()`：柔度靠"更粗 + 更低不透明度"伪造，Widget 每帧重绘，模糊太贵。

        /// 实线层线宽：白天的地平线
        static let edgeWidth: CGFloat = 1.6
        /// 雾化层线宽（替掉 blur 的那一层）
        static let edgeHazeWidth: CGFloat = 3.4
        /// 夜里实线层的线宽：参考图六那道"极细的冷光"
        static let nightEdgeWidth: CGFloat = 1.0
        /// 夜里实线层的峰值不透明度（比白天低得多，才像"远处一点冷光"）
        static let nightEdgePeak: Double = 0.55
    }
}
