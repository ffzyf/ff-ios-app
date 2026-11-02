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

    /// 简报正文最多切出几段（3.12.0）。
    ///
    /// 3.11.0 是硬编码的 2 段 —— 中号只显示首句，2 段够用；但**大号要 4–5 行正文**，
    /// 2 段拼起来往往只有 2 行，大号的下半张卡就会空掉（用户原话：
    /// "每日简报大的小组件因为它大也可以显示更多内容啊，把内容显出来啊"）。
    /// 所以切段上限提到 4，由渲染层各取所需：小/中号取首句，大号取前 4 段。
    static let largeParagraphLimit: Int = 4

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
    ///
    /// 蓝调两档取 `sky.horizon`（3.23.0）。原来跟着 `.sunrise` / `.sunset` 取 `sky.top`，
    /// 是因为那时的 `blueDusk.top` 是绯红 `#C9486F` —— 一团"晚霞残余"的红光。
    /// 3.23.0 把蓝调改成真蓝之后，两档的 `top` 一律是**天顶最深的那支**
    /// （`#16305C` / `#0E1E42`），而光晕是 `.plusLighter` 加成混合：
    /// 加一层 0.45α 的 `#0E1E42` 只给底色提亮约 (6,13,30)，在深色天上等于没画 ——
    /// 用户会丢掉"太阳就差一点/刚落下去"这个唯一的亮处。
    /// 物理上也该取 `horizon`：蓝调时刻太阳压在地平线上、下，天空最亮的地方就是地平线那条带
    /// （民用暮光里天顶最暗、地平线最亮），`#6E9AC4` / `#44679B` 正是那支较亮的钢蓝-青蓝。
    static func sunGlow(_ sky: Theme.SkyColors, phase: SkyPhase) -> Color {
        switch phase {
        case .sunrise:
            return sky.top
        case .blueDawn, .blueDusk:
            return sky.horizon
        case .golden:
            return sky.horizon
        case .sunset:
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
        /// 阶段名字号（大号 338×354，3.12.0）：天空比中号高出一倍，
        /// 10pt 在 354pt 的画布上会被读成"注脚" —— 大号的标题必须一眼可读，取 13pt
        static let phaseLabelLargeSize: CGFloat = 13
        /// 倒计时字号（中号 / 小号）。同上，缩放版共用
        static let countdownMediumSize: CGFloat = 12
        static let countdownSmallSize: CGFloat = 10
        /// 倒计时字号（大号）：15pt 等宽，与 hero 化的阶段名同一档
        static let countdownLargeSize: CGFloat = 15

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

        /// 阶段名：按尺寸取档（小 / 中复用预置 Font，大号现造一支 —— 三档里只有它是新增的）
        static func phaseLabel(_ family: WidgetFamily) -> Font {
            switch family {
            case .systemSmall:
                return phaseLabelSmall
            case .systemLarge:
                return Font.system(size: phaseLabelLargeSize, weight: .semibold)
            default:
                return phaseLabelMedium
            }
        }

        /// 阶段名的字号（三档：9 / 10 / 13）
        static func phaseLabelSize(_ family: WidgetFamily) -> CGFloat {
            switch family {
            case .systemSmall:
                return phaseLabelSmallSize
            case .systemLarge:
                return phaseLabelLargeSize
            default:
                return phaseLabelMediumSize
            }
        }

        /// 倒计时：按尺寸取档
        static func countdown(_ family: WidgetFamily) -> Font {
            switch family {
            case .systemSmall:
                return countdownSmall
            case .systemLarge:
                return Font.system(size: countdownLargeSize, weight: .semibold, design: .monospaced)
            default:
                return countdownMedium
            }
        }

        /// 倒计时的字号（三档：10 / 12 / 15）
        static func countdownSize(_ family: WidgetFamily) -> CGFloat {
            switch family {
            case .systemSmall:
                return countdownSmallSize
            case .systemLarge:
                return countdownLargeSize
            default:
                return countdownMediumSize
            }
        }

        /// 阶段名（按画布短边缩放，见 `WidgetCanvas`）。
        ///
        /// 为什么放在这里而不是 `SkyLightFace` 里：字号常量住在这个 enum，
        /// 缩放版必须和它读**同一个**尺寸数 —— 分居两个文件时，改字号的人只会看到一半。
        /// `textScale(158) == 1`，所以 iPhone 上与 `phaseLabel(_:)` 逐点相同。
        static func phaseLabelScaled(_ family: WidgetFamily, scale: CGFloat) -> Font {
            return Font.system(size: phaseLabelSize(family) * scale, weight: .semibold)
        }

        /// 倒计时（按画布短边缩放）。等宽必须保留：秒数每帧在走，非等宽会左右跳。
        static func countdownScaled(_ family: WidgetFamily, scale: CGFloat) -> Font {
            return Font.system(size: countdownSize(family) * scale,
                               weight: .semibold,
                               design: .monospaced)
        }

        /// 地面区的日出 / 日落：中号复用 `WidgetTheme.sunTime`（11pt，与简报卡同一档）；
        /// 大号升到 13pt（354pt 高的卡上 11pt 会被天空"吃掉"）。
        ///
        /// 这里必须写全 `WidgetTheme.sunTime`：`SkyLight` 自己也有一个 `sunTime(_:)` 方法，
        /// 不加限定名会解析到方法本身（函数不是 `Font`，编译期直接报类型不匹配）。
        static func sunTime(_ family: WidgetFamily) -> Font {
            switch family {
            case .systemSmall:
                return sunTimeSmall
            case .systemLarge:
                return Font.system(size: sunTimeLargeSize, weight: .medium, design: .monospaced)
            default:
                return WidgetTheme.sunTime
            }
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
        /// 大号内边距（338×354：四周各 18pt，天空仍占九成面积）
        static let largeSidePadding: CGFloat = 18
        /// 大号的地平线弧顶 / 两端高度（3.12.0）：0.62 → 0.52 是把天压低的唯一手段，
        /// 「天空区域更大」这件事必须落在**几何**上，不能靠缩放文字假装
        static let largeCrestY: CGFloat = 0.52
        static let largeEdgeY: CGFloat = 0.66
        /// 大号底部"今日天气摘要"的字号（3.12.0，13pt —— 与阶段名同档，低于倒计时一档）
        static let largeSummarySize: CGFloat = 13
        /// 大号日出 / 日落字号（3.12.0）
        static let sunTimeLargeSize: CGFloat = 13

        /// 大号底部那一行：`晴 21° 12°/24°`（温度 + 现象 + 高低温），
        /// 没有天气数据时整行不画（绝不用"—°"占位）
        static func summary(_ family: WidgetFamily) -> Font {
            return Font.system(size: family == .systemLarge ? largeSummarySize : countdownSize(family),
                               weight: .medium)
        }

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
//   · medium 338×158：左栏要放主时刻（"23:08" 在 23pt 下约 60pt 宽，左栏留 140），
//     右栏三行 12pt；
//   · large 338×354：卡片高度是小号的 2.24 倍，hero 时刻放到 52pt ——
//     它与下方 4 行排期（每行 16pt）加起来仍留出约 40pt 余量。
//
// 3.16.0：用户反馈"APP 里面的小组件有点太大了，跟下面的差不多大小就行" ——
// **只动中号那一套**（30 → 23pt，间距同步收紧），大号 hero 52pt 一个字都没改
// （它本来就在 354pt 的大画布上，缩了反而空）。
extension WidgetTheme {

    enum Redstone {

        // MARK: 字号

        /// 中号左栏主时刻（23pt rounded bold，与全工程"数字用 rounded"一致）。
        ///
        /// 3.16.0：用户反馈中号号码过大（30 → 23pt，×0.77），与天光组件同量级 ——
        /// 上半张卡只有它一个是 30pt 的大字，右栏三行 11/12pt 被压成了注脚，
        /// 视觉重心全跑到左边那个时刻上，而这一档真正要读的是"几点 + 还有多久"两行。
        static let mediumTime = Font.system(size: 23, weight: .bold, design: .rounded)
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
        /// 为什么不用小号那支 11pt：中号主时刻 23pt、大号 52pt，下面紧跟一行 11pt 会被读成
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
        /// 中号顶行（地图 + 倍率）→ 正文的间距。
        ///
        /// 3.16.0：10 → 8。主时刻从 30pt 收到 23pt 后，原来那 10pt 的顶行留白
        /// 在视觉上会把"地图名"和"时刻"读成两块不相干的内容。
        static let mediumHeadGap: CGFloat = 8
        /// 中号左栏内部行距（主时刻 → 倒计时 → 第三行）。
        ///
        /// 3.16.0：6 → 4。时刻小了 7pt，行距若不动，三行之间会显得松散、整块不再像一个读数组。
        static let mediumMainSpacing: CGFloat = 4
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

        // MARK: 大号（3.12.0）
        //
        // 大号 338×354：弧拉长、太阳点更大、两端时刻放大到 22pt，中间那行"距日落 3 小时"
        // 是这一档**新增**的信息（中号放不下第三行）—— 这就是"比中号多出的内容"。

        /// 大号的弧顶 / 两端高度：比中号更高（0.46 → 0.40），把弧拉长、把中间让给倒计时
        static let largeArcCrestY: CGFloat = 0.40
        static let largeArcEdgeY: CGFloat = 0.56
        /// 大号太阳辉光点直径（中号 10 → 大号 16：画布高了一倍，10pt 会变成一个像素点）
        static let largeSunCoreDiameter: CGFloat = 16
        /// 大号两端时刻字号
        static let largeSunTimeSize: CGFloat = 22
        /// 大号中间倒计时字号
        static let largeCountdownSize: CGFloat = 17
        /// 大号底部"今日天气一句话"字号
        static let largeWeatherSize: CGFloat = 13
        /// 大号内边距
        static let largePadding: CGFloat = 18
        /// 大号弧线线宽（比中号粗一档：画布放大后 1.6pt 会显得"细得像划痕"）
        static let largeArcWidth: CGFloat = 2.4

        static let largeSunTime = Font.system(size: largeSunTimeSize,
                                             weight: .semibold,
                                             design: .monospaced)
        static let largeCountdown = Font.system(size: largeCountdownSize,
                                               weight: .semibold,
                                               design: .monospaced)
        static let largeWeather = Font.system(size: largeWeatherSize, weight: .medium)
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

        // MARK: 大号（3.12.0）
        //
        // 大号 338×354：月盘放大到 148pt，月名 18pt、照明度 15pt，
        // **新增**一行「下次满月还有 N 天」（中号没有这个位置）。
        // 纯天文计算就能得到这个数（见 `MoonPhaseMath.daysToFullMoon`），不需要任何网络。

        /// 大号月盘直径（pt）。354pt 高的卡放 148pt 的月盘，上下各留 ~100pt 给文字
        static let largeDiscDiameter: CGFloat = 148
        /// 大号月名字号
        static let largeNameSize: CGFloat = 18
        /// 大号照明度字号
        static let largePercentSize: CGFloat = 15
        /// 大号"下次满月"提示字号
        static let largeHintSize: CGFloat = 12
        /// 大号内边距
        static let largePadding: CGFloat = 18

        static let largeName = Font.system(size: largeNameSize, weight: .semibold)
        static let largePercent = Font.system(size: largePercentSize,
                                             weight: .medium,
                                             design: .monospaced)
        static let largeHint = Font.system(size: largeHintSize, weight: .medium)
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

        // MARK: 大号（3.12.0）
        //
        // 大号 338×354：风速大字 56pt + 方位 + 箭头（放大到 44pt）+
        // **新增**「风力刻度」（0…60 KM/H 的分段轨道 + 一个指针）+ 底部观测行。
        //
        // 为什么用"风力刻度"代替"未来 3 小时趋势"：上游 `/api/app/weather` 只给**当前**实况，
        // 没有逐小时预报也没有阵风（`WeatherNow` 里没有 hourly / gust 字段）。
        // 按工程纪律"没有的数据整段不画"，趋势线就是不能画的东西 —— 那就把**已有的数**
        // （当前风速）放进一个能读出"这是小风还是大风"的刻度里，这是真实数据的另一种表达，
        // 不是编一条曲线出来。

        /// 大号风速字号
        static let largeSpeedSize: CGFloat = 56
        /// 大号方位字号
        static let largeUnitSize: CGFloat = 16
        /// 大号箭头字号
        static let largeArrowSize: CGFloat = 44
        /// 大号内边距
        static let largePadding: CGFloat = 18
        /// 刻度轨道的总长对应的风速上限（km/h）。60 覆盖"清风～强风"，
        /// 再往上（飓风）在光遇玩家的日常里没有意义
        static let scaleMax: CGFloat = 60
        /// 刻度轨道的高度
        static let scaleHeight: CGFloat = 6
        /// 刻度分档的标签字号
        static let scaleLabelSize: CGFloat = 10
        /// 指针直径
        static let scaleKnobDiameter: CGFloat = 10

        static let largeSpeed = Font.system(size: largeSpeedSize, weight: .bold, design: .rounded)
        static let largeUnit = Font.system(size: largeUnitSize, weight: .semibold)
        static let scaleLabel = Font.system(size: scaleLabelSize, weight: .medium)
    }
}
