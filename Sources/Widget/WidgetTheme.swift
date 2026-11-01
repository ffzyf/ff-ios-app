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
    //
    // 3.11.0 清理：这里原有 15 个「3.7–3.10 之间被替换掉的版式」留下的字号/间距常量
    // （小号 28pt 时刻、中号左右两栏的行字号、简报三档字号、顶部地名、地面注脚等），
    // 全工程已零引用（`BriefFace` 自带 `BriefMetrics`、红石小号自带 `RedstoneMetric`）。
    // 死常量留着比删掉危险：下次改版会有人以为"这个还在用"而不敢动它。
    // 同一批还删掉了 `label` / `meta` / `mapName` / `countdown` / `blockGap` 五个 ——
    // 它们原本服务的是已下线的红石中号版式，3.11.0 中/大号重建后字号全部收在
    // `WidgetTheme.Redstone`（按 338 宽重新配平），基础档只剩下面 `sunTime` 与 `padding` 在用。

    /// 11pt 等宽：地面区的日出 / 日落时刻（`06:44` / `17:33`）
    static let sunTime = Font.system(size: 11, weight: .medium, design: .monospaced)

    // MARK: - 间距

    /// 组件内容内边距
    static let padding: CGFloat = 12

    // MARK: - 天际线几何
    //
    // 3.11.0 清理：这里原有 `skyCrestY` / `skyEdgeY` 两个副本（0.62 / 0.74），靠注释
    // 说"必须和 SkyCard 一致"。现在两处都读 `Shared/UI/HorizonShape.swift` 的 `HorizonSky` ——
    // 同一个数只有一处定义，改一次三端（App 卡 / 组件 / 天光页）一起动。

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

        /// 阶段名字号（中号 / 小号）。`phaseLabel*` 与 `phaseLabelScaled(_:scale:)` 共用这两个数
        static let phaseLabelMediumSize: CGFloat = 10
        static let phaseLabelSmallSize: CGFloat = 9
        /// 倒计时字号（中号 / 小号）。同上，缩放版共用
        static let countdownMediumSize: CGFloat = 12
        static let countdownSmallSize: CGFloat = 10

        /// 10pt：中号左上「蓝调剩余」
        static let phaseLabelMedium = Font.system(size: phaseLabelMediumSize, weight: .semibold)
        /// 9pt：小号左上阶段名
        static let phaseLabelSmall = Font.system(size: phaseLabelSmallSize, weight: .semibold)
        /// 12pt 等宽：中号右上倒计时（数字对齐，读起来不跳）
        static let countdownMedium = Font.system(size: countdownMediumSize, weight: .semibold, design: .monospaced)
        /// 10pt 等宽：小号右上倒计时
        static let countdownSmall = Font.system(size: countdownSmallSize, weight: .semibold, design: .monospaced)
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

        /// 阶段名（按画布短边缩放，见 `WidgetCanvas`）。
        ///
        /// 为什么放在这里而不是 `SkyLightFace` 里：字号常量住在这个 enum，
        /// 缩放版必须和它读**同一个**尺寸数 —— 分居两个文件时，改字号的人只会看到一半。
        /// `textScale(158) == 1`，所以 iPhone 上与 `phaseLabel(_:)` 逐点相同。
        static func phaseLabelScaled(_ family: WidgetFamily, scale: CGFloat) -> Font {
            let size = family == .systemSmall ? phaseLabelSmallSize : phaseLabelMediumSize
            return Font.system(size: size * scale, weight: .semibold)
        }

        /// 倒计时（按画布短边缩放）。等宽必须保留：秒数每帧在走，非等宽会左右跳。
        static func countdownScaled(_ family: WidgetFamily, scale: CGFloat) -> Font {
            let size = family == .systemSmall ? countdownSmallSize : countdownMediumSize
            return Font.system(size: size * scale, weight: .semibold, design: .monospaced)
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

        // MARK: 着色 / 透明模式（iOS 26 桌面的「着色」「透明」外观）
        //
        // 用户原话："最重要的你这些小组件没有适配 ios 的桌面透明效果，开了透明之后就
        // 只能看见字，里面的效果看不见！" —— iOS 26 起用户选透明 / 着色外观时，系统用
        // **accented 渲染模式**重画小组件：拿掉 `containerBackground` 换成玻璃，
        // 不透明内容全部染白；**半透明内容保留不透明度**再整体染色。
        //
        // 所以适配的全部原理就一句话：着色模式下，把"实心"换成"低不透明度"。
        // 系统染白之后，这些层仍读得出深浅差（层次还在），而不是一坨死白。
        // 环境值 `\.widgetRenderingMode` 是 iOS 16+ API（deployment target 18，直接读）。

        /// 着色模式下天空渐变保留的不透明度。0.35：染白后仍读得出"上深下浅"的方向，
        /// 又不会把玻璃填成一整块白板
        static let tintedSkyAlpha: Double = 0.35
        /// 着色模式下地面弧保留的不透明度（比天空浅一档：地面必须仍在地平线以下压得住）
        static let tintedGroundAlpha: Double = 0.22
        /// 着色模式下云朵 α 的缩放系数（云本来就是 0.42–0.55 的半透明色块，再压一档防糊）
        static let tintedCloudAlphaScale: Double = 0.45
        /// 着色模式下太阳核保留的不透明度（实心圆染白后是一块死白，压到半透明才有"辉光点"层次）
        static let tintedSunAlpha: Double = 0.55
    }
}

// MARK: - 红石三档（3.11.0：中号恢复、大号新增）
//
// 小号那套字号仍留在 `RedstoneFace.swift` 的 `RedstoneMetric` 里（它按 158pt 见方配平，
// 一个数字都不改）。这里只放**中号 / 大号**的档位，理由与 `SkyLight` 那段相同：
// 三个尺寸是三种版式，字号必须一档一档给，**不许用一套字号硬缩放**（DESIGN-RULES §3）。
//
// 数字怎么来的：
//   · medium 338×158：左栏要放 30pt 的时刻（"23:08" 在 30pt 下约 78pt 宽，左栏留 140），
//     右栏三行 12pt；30pt 是"比小号的 34 略小、但仍是全卡最大字"的折中；
//   · large 338×354：卡片高度是小号的 2.24 倍，hero 时刻放到 52pt ——
//     它与下方 4 行排期（每行 16pt）加起来仍留出约 40pt 余量。
extension WidgetTheme {

    enum Redstone {

        // MARK: 字号

        /// 中号左栏主时刻（30pt rounded bold，与全工程"数字用 rounded"一致）
        static let mediumTime = Font.system(size: 30, weight: .bold, design: .rounded)
        /// 大号 hero 主时刻
        static let largeTime = Font.system(size: 52, weight: .bold, design: .rounded)
        /// 地图名（中/大号共用 13pt semibold）
        static let title = Font.system(size: 13, weight: .semibold)
        /// 右栏标签 / 分区标签（11pt semibold）
        static let label = Font.system(size: 11, weight: .semibold)
        /// 右栏数值 / 排期时刻（12pt 等宽：数字要对齐）
        static let value = Font.system(size: 12, weight: .semibold, design: .monospaced)
        /// 中/大号的倒计时（13pt 等宽）。
        ///
        /// 为什么不用小号那支 11pt：中号主时刻 30pt、大号 52pt，下面紧跟一行 11pt 会被读成
        /// "注脚"而不是"第二个读数"；13pt 是这套版式里"比标签大一档、又不抢主时刻"的位置。
        static let countdown = Font.system(size: 13, weight: .semibold, design: .monospaced)
        /// 排期的日期列（12pt，等宽是为了"今天/明天/周三"三个字宽不一也不抖）
        static let rowDay = Font.system(size: 12, weight: .semibold)
        /// 排期的时间串（12pt 等宽）
        static let rowTimes = Font.system(size: 12, weight: .medium, design: .monospaced)
        /// 排期的地点（11pt，压一档 —— 一行里最次要的那截）
        static let rowMap = Font.system(size: 11, weight: .regular)

        // MARK: 间距 / 尺寸

        /// 中号内边距（158pt 高，上下各 14 后内容 130pt）
        static let mediumPadding: CGFloat = 14
        /// 中号两栏之间的间距（栏间还有一条 1pt 竖线）
        static let mediumColumnGap: CGFloat = 12
        /// 大号内边距
        static let largePadding: CGFloat = 16
        /// 大号「本周排期」最多几行（第 5 行会顶到卡片底边）
        static let largeRowLimit = 4
        /// 排期里"今天/明天/周三"这一列的宽度（三个汉字 + 呼吸）
        static let rowDayWidth: CGFloat = 38
    }
}

// MARK: - 锁屏 accessory 档（3.10.0：天光与月相的紧凑形态）
//
// accessory（锁屏 / 灵动岛旁的环形与长条）没有 158pt 的画布，字号、行距都是另一套
// 尺度 —— 塞桌面档的 10~28pt 会直接溢出。三档集中在这里，与桌面档同一个取值纪律：
// **颜色一个都不放**（走 Theme token），只放尺寸与字号。
extension WidgetTheme {

    /// accessory 档的字号与行高
    enum Accessory {

        /// 环形（circular）里的主字： illumination 百分比、图标下的短数值
        static let circularValue = Font.system(size: 12, weight: .bold, design: .rounded)
        /// 长条（rectangular）的第一行：阶段名 / 月名
        static let linePrimary = Font.system(size: 13, weight: .semibold)
        /// 长条的第二行：时刻 / 百分比
        static let lineSecondary = Font.system(size: 11, weight: .medium, design: .monospaced)
        /// 一行（inline）形态：全部内容只有一行，字略小于长条主行
        static let inlineText = Font.system(size: 12, weight: .semibold)
        /// 长条行距
        static let lineSpacing: CGFloat = 2
    }
}

// MARK: - 天气三卡（日弧 / 月相 / 风，3.10.0）
//
// 三张新卡的常量集中处（与 `SkyLight` / `BriefMetrics` 同一个纪律：尺寸 / 字号住表里，
// View 里零字面量；颜色一个都不进这张表 —— 全部走 `Theme.sky(phase)` 等 token）。
extension WidgetTheme {

    /// 日弧卡（SunArc）
    enum SunArc {
        /// WidgetKit 的 kind（改名会让已上桌的实例失效）
        static let kind = "SunArcWidget"
        static let displayName = "日弧"
        static let description = "今天的日出日落与太阳在弧上的位置，倒数到日落。"

        /// 弧顶高度（占卡高）。比天光卡的 0.62 更高：这张卡的中段要给太阳点与倒计时留净空
        static let arcCrestY: CGFloat = 0.46
        /// 弧两端高度（占卡高）
        static let arcEdgeY: CGFloat = 0.64

        /// 太阳辉光点本体直径
        static let sunCoreDiameter: CGFloat = 10
        /// 辉光点外面那圈高光环的线宽
        static let sunRingWidth: CGFloat = 1.5
        /// 辉光点半径占比（画布宽 × 该值 = 光晕半径）
        static let glowFactor: CGFloat = 0.30
        /// 辉光中心不透明度
        static let glowAlpha: Double = 0.42

        /// 大字时刻字号（左下日出 / 右下日落）
        static let sunTimeSize: CGFloat = 15
        /// 中号底部倒计时的字号
        static let countdownSize: CGFloat = 12

        static let sunTime = Font.system(size: sunTimeSize, weight: .semibold, design: .monospaced)
        static let countdown = Font.system(size: countdownSize, weight: .semibold, design: .monospaced)
        /// 9pt 小标签（"日出"/"日落"）
        static let tagLabel = Font.system(size: 9, weight: .semibold)
    }

    /// 月相卡（MoonPhase）
    enum Moon {
        /// WidgetKit 的 kind
        static let kind = "MoonPhaseWidget"
        static let displayName = "月相"
        static let description = "今晚的月亮：月名与照明度，纯天文计算，不联网。"

        /// 月盘直径（占小号画布短边的比例）
        static let discRatio: CGFloat = 0.46
        /// 月名字号
        static let nameSize: CGFloat = 11
        /// 照明度百分比的字号
        static let percentSize: CGFloat = 10

        static let name = Font.system(size: nameSize, weight: .semibold)
        static let percent = Font.system(size: percentSize, weight: .medium, design: .monospaced)
        /// 月盘阴影的描边（亮面 / 暗面分界不画线，靠两圆交叠的自然边界）
        static let discStrokeWidth: CGFloat = 0.8
    }

    /// 风卡（Wind）
    enum Wind {
        /// WidgetKit 的 kind
        static let kind = "WindWidget"
        static let displayName = "风"
        static let description = "现在的风速与 16 方位风向，来自天气实况。"

        /// 风速大字字号
        static let speedSize: CGFloat = 26
        /// 单位 / 方位字号
        static let unitSize: CGFloat = 11
        /// 风向箭头字号（SF Symbol 尺寸）
        static let arrowSize: CGFloat = 20

        static let speed = Font.system(size: speedSize, weight: .bold, design: .rounded)
        static let unit = Font.system(size: unitSize, weight: .semibold)
        /// 底部注脚
        static let footnote = Font.system(size: 9, weight: .medium)
    }
}
