import SwiftUI
import WidgetKit

// MARK: - 简报卡自己的度量
//
// 为什么单独一个 `BriefMetrics`：Widget target 只编译 `Sources/Widget` + `Sources/Shared`，
// **看不到** `DesignSystem/Typography` / `Radius` / `Spacing`。所以这张卡的每一档字号、
// 每一个间距都必须写在 Widget 自己家里；散在 View 里的话，下次想整体调一档就得满文件找数字。
//
// 尺寸只有两种：中号 338×158、小号 158×158。小号整体收一档（字号不动、行数与内边距收），
// 因为小号是正方形，横向只有 158pt —— 内边距留着中号的 14pt 会让正文只剩 130pt 宽。
enum BriefMetrics {

    // MARK: 字号

    /// 11pt semibold：顶行日期 / 星期（eyebrow 层）
    static let eyebrow = Font.system(size: 11, weight: .semibold)
    /// 9pt semibold：右上角「简报」胶囊 —— 它只是标记，不能和标题抢字重
    static let tag = Font.system(size: 9, weight: .semibold)
    /// 标题字号。`title` 与 `titleScaled(_:)` **共用这一个数**：两处各写一个字面量，
    /// 将来调字号时必然有一处被忘掉，而"忘掉"的表现是"iPad 上只有一半的字变大"。
    /// 3.10.0 起标题只在**无天气兜底态**出现（有天气时主视觉换成温度大字），字号不动。
    static let titleSize: CGFloat = 20
    /// 正文字号（同上）。3.10.0 起降格为"弱化正文"，仍是这段字的唯一字号出处
    static let bodySize: CGFloat = 13
    /// 弱化正文字号（3.10.0）：天气升为主视觉后，简报首句降一档、再压一档透明度 ——
    /// "今天天气怎么样"是第一眼要答的，"今天有什么事"退到第二眼。
    static let weakBodySize: CGFloat = 11
    /// 温度大字字号（3.10.0 主视觉）。参考图 IMG_9275 的"21°C"与"22° 19°"层级：
    /// 温度是卡上最大的数字，但 158pt 高的画布放不下 44pt 那种 hero，
    /// 30pt 是"一眼读出今天多少度"与"不挤压上下文行"的平衡点
    static let tempSize: CGFloat = 30
    /// 天气现象文字字号（"小雨"、"晴间多云"…）
    static let weatherTextSize: CGFloat = 15
    /// 高低温字号（"22° 19°"）。等宽：两个数字要对齐，分钟位之间不跳
    static let hiLoSize: CGFloat = 11

    /// 20pt bold：卡名「每日简报」。一句话的卡不需要 28pt，但必须明显高于正文
    static let title = Font.system(size: titleSize, weight: .bold)
    /// 13pt：正文首句（中号 2 行 / 小号 1 行）。**只在无天气兜底态使用**
    static let body = Font.system(size: bodySize, weight: .regular)
    /// 30pt rounded bold：温度大字（3.10.0 主视觉）
    static let temp = Font.system(size: tempSize, weight: .bold, design: .rounded)
    /// 15pt semibold：天气现象文字
    static let weatherText = Font.system(size: weatherTextSize, weight: .semibold)
    /// 11pt 等宽：高低温
    static let hiLo = Font.system(size: hiLoSize, weight: .medium, design: .monospaced)

    /// 标题（按画布短边缩放，见 `WidgetCanvas`）。
    ///
    /// 为什么新增一个函数而不是把 `title` 改成 `title(scale:)`：本机没有 Swift 工具链，
    /// 改签名会把"漏改一处 → 只错在 iPad"升级成"漏改一处 → 编译失败 → 一轮 CI 报废"。
    /// `textScale(158) == 1`，所以 iPhone 上与 `title` 逐点相同。
    static func titleScaled(_ scale: CGFloat) -> Font {
        return Font.system(size: titleSize * scale, weight: .bold)
    }

    /// 正文（按画布短边缩放）
    static func bodyScaled(_ scale: CGFloat) -> Font {
        return Font.system(size: bodySize * scale, weight: .regular)
    }

    /// 弱化正文（按画布短边缩放）
    static func weakBodyScaled(_ scale: CGFloat) -> Font {
        return Font.system(size: weakBodySize * scale, weight: .regular)
    }

    /// 温度大字（按画布短边缩放）。数字必须等宽走时稳定，rounded 保持与红石大字同一气质
    static func tempScaled(_ scale: CGFloat) -> Font {
        return Font.system(size: tempSize * scale, weight: .bold, design: .rounded)
    }

    /// 天气现象（按画布短边缩放）
    static func weatherTextScaled(_ scale: CGFloat) -> Font {
        return Font.system(size: weatherTextSize * scale, weight: .semibold)
    }
    /// 正文行距：中文字面高、行距为 0 会糊成一团
    static let bodyLineSpacing: CGFloat = 2
    /// 11pt：底部注脚（宜忌）
    static let footnote = Font.system(size: 11, weight: .medium)
    /// 11pt 等宽：底部右端的日出 / 日落（数字必须对齐，否则两帧之间会左右跳）
    static let footnoteTime = Font.system(size: 11, weight: .medium, design: .monospaced)

    // MARK: 内边距

    /// 中号左右内边距
    static let mediumSidePadding: CGFloat = 14
    /// 中号上下内边距（158pt 高，去掉 24pt 还剩 134pt 给四行）
    static let mediumVerticalPadding: CGFloat = 12
    /// 小号左右内边距（方形画布，收到 11pt 免得正文被圆角切）
    static let smallSidePadding: CGFloat = 11
    /// 小号上下内边距
    static let smallVerticalPadding: CGFloat = 12

    // MARK: 行距

    /// 顶行 → 标题
    static let titleGap: CGFloat = 6
    /// 标题 → 正文
    static let bodyGap: CGFloat = 4
    /// 轨迹 → 底部注脚
    static let footerGap: CGFloat = 6

    // MARK: 行高（不是字号，是"这一行占多高"）
    //
    // 为什么要把行高写成常量：天气粒子层必须知道「正文块的上下边界在哪」，
    // 才能在正文周围让出净空带。Widget 里量真实文字高度需要 `PreferenceKey` 一轮布局回传，
    // 而这一层是纯装饰 —— 晚一帧拿到高度只会让粒子闪一下。按行高逐项加出来误差 ≤ 2pt，
    // 比回传测量更稳，也让"净空带"这件事在代码里是**可读的算式**而不是魔法数字。

    /// 11pt semibold 的行高
    static let eyebrowLineHeight: CGFloat = 14
    /// 20pt bold 的行高
    static let titleLineHeight: CGFloat = 24
    /// 13pt regular 的行高
    static let bodyLineHeight: CGFloat = 16
    /// 温度大字块的行高（3.10.0）：30pt rounded bold 的实测行高 ≈ 36，
    /// 再加 2pt 给同排"天气现象 + 高低温"两行的溢出余量
    static let heroLineHeight: CGFloat = 38
    /// 弱化正文（11pt）的行高。3.10.0 起正文恒 1 行（中号 / 小号同此）
    static let weakBodyLineHeight: CGFloat = 14

    // MARK: 轨迹

    /// 普通刻度点直径（2pt —— 比 1pt 的线"有质感"，又不至于变成一串珠子）
    static let dotDiameter: CGFloat = 2
    /// 「今天过了多少」那颗光点直径（5pt：明显大于刻度点，但小于任何字号）
    static let markerDiameter: CGFloat = 5
    /// 光点外面那圈柔光的直径。**不用模糊滤镜** —— 模糊在 Widget 里每帧重绘太贵，
    /// 柔度由 `RadialGradient` 的两档不透明度伪造（见 `BriefTrack`）。
    static let markerHaloDiameter: CGFloat = 26
    /// 轨迹占的高度（含光点溢出，不写死会被上层 VStack 压扁）
    static let trackHeight: CGFloat = 12
    /// 中号刻度点数量
    static let mediumDotCount: Int = 24
    /// 小号刻度点数量（画布只有 136pt 可用宽，24 颗会挤成一条实线）
    static let smallDotCount: Int = 20

    // MARK: 胶囊

    /// 胶囊左右内边距
    static let tagHorizontalPadding: CGFloat = 7
    /// 胶囊上下内边距
    static let tagVerticalPadding: CGFloat = 2
    /// 胶囊描边线宽
    static let tagStrokeWidth: CGFloat = 0.7

    // MARK: 纸面光晕

    /// 中心那层主题色径向光的半径（pt）。只做面，不承载文字
    static let canvasGlowRadius: CGFloat = 132
    /// 中心径向光的峰值不透明度 —— 只有 0.10：纸面上一点"被打亮"的感觉，不是一块绿斑。
    /// **只在没有天气数据时用**（保住"回到现在的样子"这一条）。
    static let canvasGlowAlpha: Double = 0.10
    /// 有天气时中心柔光的峰值：晴天最亮
    static let weatherGlowAlphaMax: Double = 0.30
    /// 有天气时中心柔光的谷值：阴天几乎没光（云把光挡住了，这是物理事实）
    static let weatherGlowAlphaMin: Double = 0.12

    // MARK: 天气粒子（V3.7）

    /// 正文块上下各留的「净空带」高度。
    ///
    /// 雨丝斜穿两行中文会把字切碎，而这 20pt 正好是行距 + 一点余量的量级，
    /// 视觉上又不会被读成"卡片中间有一条空带"。八档天气共用同一条，不各调各的。
    static let particleClearBand: CGFloat = 20

    /// 正文块**下方**给降水让出的高度（只有 6pt，远小于 `particleClearBand`）。
    ///
    /// 为什么上下不对称：`particleClearBand` 那条 20pt 是给**云**留的 —— 云是 α ≤ 0.16 的
    /// 软团，落在标题行上只是"标题后面有一点亮"，不影响读数（3.7 上线后没人报过问题）。
    /// 但雨是 1pt 的锐利斜线，穿进 20pt 粗的标题就会把字切碎。
    ///
    /// 而这张卡的上半部**全是字**（顶行日期 [12,26]、标题 [32,56]、正文 [60,92]），
    /// 正文块顶边以上就是 `verticalPadding` 那 12pt —— 上方根本没有能落雨的空白。
    /// 所以"雨滴太往下了"这个诉求，唯一能动的方向是**把下面那条净空带收窄**：
    /// 20 → 6，中号卡的雨区从 38pt 变成 54pt、上沿从 y=114 提到 y=98，
    /// 雨就从正文正下方开始落，不再贴着卡底那一条。
    static let particleClearBelowBody: CGFloat = 6
    /// 粒子层底部留白。
    ///
    /// 只有 6pt —— 不为"轨迹 + 注脚"整块让位，理由见 `BriefWeatherLayer.precipitationBands`：
    /// 那一块是**画在粒子之上**的（轨迹与注脚在 `content` 里，天气层是 `content` 的背景），
    /// 所以雨丝从它们背后落过不会盖住任何读数，反而正是"雨落满整卡（正文净空带除外）"的观感。
    static let particleBottomInset: CGFloat = 6
    /// 云的位置每过一天推进多少个卡宽（**预排帧实现"飘"**，理由见 `BriefWeatherLayer.drift`）
    static let cloudDriftPerDay: CGFloat = 0.35
    /// 云的最多条数（2~3 朵；再多就是噪点，不是天气）
    static let partlyCloudCount: Int = 2
    /// 阴天的云朵数
    static let overcastCloudCount: Int = 3
    /// 阴天那层薄纱的不透明度
    static let overcastVeilAlpha: Double = 0.10
    /// 雾带高度占卡高的比例
    static let fogBandRatio: CGFloat = 0.18
    /// 雾带中段的不透明度（上下两端渐变到 0）
    static let fogBandAlpha: Double = 0.20
    /// 毛毛雨的竖划条数
    static let drizzleCount: Int = 10
    /// 毛毛雨竖划长度下限 / 上限（pt）
    static let drizzleLengthMin: CGFloat = 4
    static let drizzleLengthMax: CGFloat = 5
    /// 雨丝条数（上限 20：再多就看不清哪条是哪条了）
    static let rainCount: Int = 20
    /// 雨丝长度下限 / 上限
    static let rainLengthMin: CGFloat = 8
    static let rainLengthMax: CGFloat = 12
    /// 雨丝倾角（度）。12° 是"斜"的下限：再小看着像没画直，再大像暴风雨
    static let rainTilt: Double = 12
    /// 雷暴里的雨丝条数（比纯雨略少，给闪电留出画面）
    static let thunderRainCount: Int = 18
    /// 雪点数量（14 个封顶：1.5pt 的白点在 158pt 高的卡上已经很密）
    static let snowCount: Int = 14
    /// 雪点直径
    static let snowDotDiameter: CGFloat = 1.5
    /// 闪电折线段数（3 段 = 4 个点；就一道，别做成漫画闪电）
    static let lightningSegments: Int = 3
    /// 闪电线宽
    static let lightningWidth: CGFloat = 2

    /// 雨丝倾斜后的包围盒相对"未倾斜半长"的最大外溢（pt）。
    ///
    /// 12° / 长度 8…12 的实测上界是 0.016pt（旋转后包围盒半高 `= 0.489L + 0.104`，
    /// 与未旋转的 `L/2` 相比在 `L = 8` 时多出 0.016、在 `L = 12` 时反而少 0.028）。
    /// 取 1 是为了留 **60 倍余量**：净空带是硬约束，不能靠"算出来刚好不超"。
    static let particleTiltGuard: CGFloat = 1

    /// 一段太矮就整段放弃（把粒子全给另一段）：低于 16pt 画不出雨丝，只能画一条线。
    static let minFilledBand: CGFloat = 16

    /// 把 `count` 条粒子按**两段的高度比例**分配，两段各保底 1 条。
    ///
    /// 为什么按比例而不是"固定对半分"：小号卡的地面段 56pt、天空段 37.6pt，
    /// 五五分会把一半的雨丝塞进更矮的天空段，一段的条间距从 19.8pt 掉到 15.8pt ——
    /// 12° 倾斜后一条雨丝的横向包围盒约 3.5pt、抖动最大 ±1.45pt，余量就被吃掉了。
    /// 按比例分出来是：中号 10/10、小号 8/12、iPad 中号 9/11，两段的条间距都 ≥ 13pt。
    ///
    /// `minFilledBand` 那条分支是"宁可一段空着"：一段矮到 16pt 以下时，
    /// 12pt 长的雨丝在里面只能停在一个位置上，画出来是一条横线，比不画更假。
    static func split(count: Int,
                      skyHeight: CGFloat,
                      groundHeight: CGFloat) -> (sky: Int, ground: Int) {
        guard count > 0 else { return (sky: 0, ground: 0) }
        // 任一段太矮 → 该段 0 条，另一段全收
        if skyHeight < minFilledBand { return (sky: 0, ground: count) }
        if groundHeight < minFilledBand { return (sky: count, ground: 0) }

        let total = skyHeight + groundHeight
        guard total > 0 else { return (sky: count, ground: 0) }

        let raw = CGFloat(count) * skyHeight / total
        // clamp 到 [1, count − 1]：两段都保底 1 条，谁也不会被算成 0 条
        let sky = min(max(Int(raw.rounded()), 1), max(count - 1, 1))
        return (sky: sky, ground: count - sky)
    }

    // MARK: 按尺寸取档

    /// 左右内边距
    static func sidePadding(_ family: WidgetFamily) -> CGFloat {
        return family == .systemSmall ? smallSidePadding : mediumSidePadding
    }

    /// 上下内边距
    static func verticalPadding(_ family: WidgetFamily) -> CGFloat {
        return family == .systemSmall ? smallVerticalPadding : mediumVerticalPadding
    }

    /// 刻度点数量
    static func dotCount(_ family: WidgetFamily) -> Int {
        return family == .systemSmall ? smallDotCount : mediumDotCount
    }

    /// 正文行数：弱化正文恒 1 行（3.10.0 起正文降格，中号也只给 1 行 ——
    /// 多出来的高度全部让给天气主视觉；小号整行不画）
    static func bodyLineLimit(_ family: WidgetFamily) -> Int {
        return 1
    }

    /// 正文块的**顶边**到卡顶的距离（行高逐项相加，见「行高」一节的理由）。
    ///
    /// 3.10.0 起按新版式推导：眉题 → 天气主视觉（heroLineHeight）→ 弱化正文。
    /// 无天气兜底态里这一行数与实际文字块略有出入（那边是标题 + 正文），
    /// 但它的消费方只有降水/云的粒子带 —— 装饰层的 ±6pt 误差换算过来是
    /// "雨从正文底下多一点或少一点开始落"，方向安全，不值得为兜底态再算一套。
    static func bodyTop(_ family: WidgetFamily) -> CGFloat {
        return verticalPadding(family)
            + eyebrowLineHeight
            + titleGap
            + heroLineHeight
            + bodyGap
    }

    /// 正文块的**底边**到卡顶的距离
    static func bodyBottom(_ family: WidgetFamily) -> CGFloat {
        let lines = CGFloat(bodyLineLimit(family))
        let bodyHeight = weakBodyLineHeight * lines
        return bodyTop(family) + bodyHeight
    }

    /// 中心柔光的不透明度：**随云量反向线性**（晴 0.30 → 阴 0.12）。
    ///
    /// 为什么不是"每档写一个数"：8 档 × 5 套主题就是 40 个数，改一档要看 40 行；
    /// 而这件事本身是单调的物理关系 —— 云越多，到达纸面的光越少。
    static func glowAlpha(cloudiness: Double) -> Double {
        let clamped = min(max(cloudiness, 0), 1)
        return weatherGlowAlphaMin + (weatherGlowAlphaMax - weatherGlowAlphaMin) * (1 - clamped)
    }

    // MARK: 纸面 α 补偿（3.7.1）

    /// 浅色纸上的粒子 / 云 α 补偿系数。
    ///
    /// **同一个 α 在两张纸上不等强**：深色纸是"亮了就看得见"，浅色纸是"压下去才看得见"。
    /// 实测（雨丝 α0.22 压在 `#E3DDCE` 上）：浅色纸对比度只有 1.21:1、深色纸是 1.5:1 ——
    /// 1pt 细线在米纸上会被自己的明度吃掉，看起来像"没画天气"。所以浅色纸乘这一档。
    /// **深色纸乘 1**（见 `paperAlpha`）：这一档 α 补偿在深色纸上一动没动。
    /// 深色**纸基与墨色**与 3.6.0 相同；八档天气的 `top` 是**有意**提亮了一到两档
    /// （阴天 `#15181C → #262C33`、雷 `#100E18 → #1A1526`），为的是让粒子和柔光在深色纸上也看得见。
    static let lightPaperAlphaBoost: Double = 1.7

    /// 粒子 / 云的不透明度上限：再往上就从"天气"变成"色斑"（雪点与闪电不走这条，
    /// 它们本来就是实心形状，浅色纸上看得很清楚）。
    static let lightPaperAlphaCap: Double = 0.36

    /// 按纸补偿后的 α。深色纸原样返回（3.6.0 的 α 不变 —— 深色纸上变的是八档 `top`，不是这里）。
    static func paperAlpha(_ alpha: Double, paper: Theme.Weather.Paper) -> Double {
        switch paper {
        case .dark:
            return alpha
        case .light:
            return min(alpha * lightPaperAlphaBoost, lightPaperAlphaCap)
        }
    }
}

// MARK: - 卡面

/// 每日简报的卡面 —— 「一张纸 + 一条轨道 + 当天天气的氛围」。
///
/// 用户原话："现在我这里有两个天际线的效果小组件……要不然两个一模一样的小组件看着有点烦"。
/// 上一版这张卡是"天空渐变 + 地平线弧 + 太阳"，和天光组件（`SkyLightFace`）摆在同一屏上
/// 就是两块几乎一样的图。天光那套是用户自己挑的参考，保持不动；**这张卡换语言**：
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │ 10月31日 周六                     简报   │ ← 11pt semibold + 9pt 胶囊
/// │ 21°  小雨                  22° 19°      │ ← 3.10.0 主视觉：温度 + 现象 + 高低温
/// │ 今天的第一句正文（弱化，1 行）……          │ ← 11pt 弱化辅行
/// │  · · · · · · · · ● · · · · · · · · ·     │ ← 24 颗 2pt 刻度 + 1 颗 5pt 光点
/// │ 宜 打猎          忌 店铺开业   06:44 17:33│ ← 11pt，两端对齐
/// └─────────────────────────────────────────┘
/// ```
///
/// 3.10.0 用户原话："我不是想看太阳等级，我是想看今天的天气怎么样" —— 所以主视觉
/// 从"每日简报标题"换成**今日天气**（温度大字 + 现象 + 高低温，数据同源
/// `entry.weather` = `GET /api/app/weather`，简报 Provider 本来就在并发拉）；
/// 简报首句保留但弱化（11pt + 再压一档透明度）。天气没拉到时不编内容：
/// 整卡退回 3.9.0 的"每日简报 + 首句"形态，温度行整个不画。
/// 雨滴 / 云 / 雾 / 闪电粒子带原样保留，只跟随真实天气（下雨才出）。
///
/// V3.7 起，**底色与粒子跟着当天的真实天气走**（用户原话："把拉到的天气对应放到对应的效果上"）；
/// 3.7.1 起，**纸面跟着系统的浅色 / 深色走**（用户第二次反馈"背景还是黑的"）。
/// 五层，从下到上（顺序不能调，调了就挡字）：
///
/// 1. **纸面**：`Theme.Weather.of(kind, paper:).top` → `Theme.Weather.paperBase(paper).bottom`
///    的两档线性渐变（浅色 = 米纸、深色 = 夜纸）；
/// 2. **中心柔光**：`glow` 的径向渐变，alpha 随云量**反向**（晴 0.30 / 阴 0.12）；
/// 3. **天气粒子**：云 / 雾带 / 毛毛雨 / 雨丝 / 雪点 / 闪电（本文件下半部分）；
/// 4. **轨迹刻度 + 光点**：它是"现在几点"的读数，永远压在粒子之上；
/// 5. **文字**：最高层。
///
/// 四条不能破的规矩：
/// 1. **没有的字段整行不画**：宜忌为空就不画左下、日出算不出就不画右下、
///    正文为空就明说"今天还没有简报"，绝不编内容；
/// 2. **没有天气就回到"这张纸本来的样子"**（`entry.weather == nil`）：不画任何粒子、
///    深色纸下中心柔光退回那层青柠光（浅色纸不画光）—— 天气是装饰，简报才是主体；
/// 3. **零模糊滤镜、零颜色字面量**：柔光用 `RadialGradient`，颜色全部走 `Theme` token；
/// 4. **字色只看 `Theme.Weather.ink(paper)`**：天气改的是"面"（底色 / 光 / 粒子），不改字色 ——
///    否则换一天天气就可能出现一处读不清的灰字。纸换档时字色跟着换，那不是天气的事。
struct BriefFace: View {

    @Environment(\.widgetFamily) private var family

    /// 为什么这里必须读、而且**只在这里读**：`ThemeScope`（App 侧唯一那处）属于 App target，
    /// Widget 进程里没有它；而 `Widget` 本身不是 `View`、拿不到环境 —— 所以"系统是浅色还是
    /// 深色"只能在 `BriefFace`（真正的卡片视图）落到一个枚举上，往下全部走
    /// `Theme.Weather.Paper`。其它 Widget 视图（`BriefCanvas` / `BriefTrack` /
    /// `BriefWeatherLayer`）只收这个枚举，一处都不许再读。
    /// lint:allow —— 简报卡（Widget face）里唯一允许读 colorScheme 的位置
    ///（`SunEventLiveActivity` 那处属独立的灵动岛视图，本次一行未动）
    @Environment(\.colorScheme) private var scheme

    private let entry: BriefEntry

    /// 画布短边（pt）。0 = 还没量到 → `s == 1` → 字号与 3.4.0 完全一致（降级方向安全）。
    /// 只影响字号，不参与任何几何计算（padding / 行高 / 轨迹点数全部不动）。
    @State private var canvasMinSide: CGFloat = 0

    init(entry: BriefEntry) {
        self.entry = entry
    }

    /// 这一帧的字号比例（158 → 1.0，iPad 小号 ≈170 → 1.076，上限 1.15）
    private var s: CGFloat {
        return WidgetCanvas.textScale(minSide: canvasMinSide)
    }

    private var isSmall: Bool {
        return family == .systemSmall
    }

    /// 今天的天气类型。`nil` = 没拉到天气 / 代码未知 —— 整张卡退回无天气形态。
    ///
    /// 注意这里**不做任何兜底**：`WeatherKind.from(code:)` 认不出的代码也是 nil，
    /// 因为"画一个晴天"比"不画天气"错得多（后者只是朴素，前者是在骗人）。
    private var kind: WeatherKind? {
        return entry.weather?.kind
    }

    /// 纸面档位 —— 跟着**系统**浅色 / 深色走（不跟 App 的三态设置：桌面上不合群的方块最刺眼）。
    ///
    /// 为什么不是"再判一次天气"：纸是纸，天气是天气。纸只回答"现在是什么外观"，
    /// 天气只回答"今天什么天"，两者在 `Theme.Weather.of(_:paper:)` 里合成一种颜色。
    private var paperMode: Theme.Weather.Paper {
        return scheme == .dark ? .dark : .light
    }

    /// 墨色（字 / 轨迹刻度 / 光点 / 粒子）。**整张卡唯一的字色来源**。
    ///
    /// 3.7 之前这里固定取「夜纸的墨色」那一档，于是浅色纸上一片白字看不见；
    /// 现在它跟着纸走：浅色纸 → 深灰 `#24262A`，深色纸 → 近白（3.6.0 的墨色）。
    private var ink: Color {
        return Theme.Weather.of(kind, paper: paperMode).ink
    }

    /// 次要字色：主墨压 0.72（与 3.6.0 的 `sky.inkDim` 同一个比例；深色墨色未变，比例因此也不变）
    private var inkDim: Color {
        return ink.opacity(0.72)
    }

    var body: some View {
        content
            // 天气粒子层 = 正文的 `.background`：它因此天然待在"底色之上、文字之下"，
            // 不必在 `content` 里插一层 ZStack（那会把版式骨架和天气耦合在一起）
            .background {
                if let today = kind {
                    BriefWeatherLayer(kind: today,
                                      date: entry.date,
                                      family: family,
                                      paper: paperMode)
                }
            }
            // 画布测量：`.background` 不参与布局，`content` 的 proposal 与不挂时完全相同。
            // 只在 `onAppear` / 尺寸真变时写 `@State`（滚动、重绘都不会触发），
            // 与 `LayoutMetricsScope` / `PageBackground` 用的是同一个手法。
            .background {
                canvasProbe
            }
            // 整卡可点：落到 `skyapp://brief`（深链契约见 `WidgetDeepLink`）
            .widgetURL(WidgetDeepLink.brief)
            .containerBackground(for: .widget) {
                BriefCanvas(kind: kind, paper: paperMode)
            }
    }

    /// 量画布**短边**。为什么不是宽度：medium 是 338×158（iPad 364×170），
    /// 按宽度算会得到 2.14 再被 clamp 到 1.15 —— iPhone 上所有 medium 档字号一次跳 15%，
    /// 肉眼立刻可见。短边在两档里都是 158，才是真正的"画布尺度"。
    private var canvasProbe: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { canvasMinSide = min(proxy.size.width, proxy.size.height) }
                .onChange(of: proxy.size) { _, newSize in
                    let short = min(newSize.width, newSize.height)
                    if short != canvasMinSide { canvasMinSide = short }
                }
        }
    }

    // MARK: - 版式骨架
    //
    // 3.10.0 重排（用户原话："我不是想看太阳等级，我是想看今天的天气怎么样"）：
    // **主视觉 = 今日天气**（大号温度 + 天气现象 + 高低温），简报首句降格为弱化的辅行，
    // 轨迹与宜忌 / 日出日落注脚原样保留 —— 天气是第一眼要答的，"今天有什么事"是第二眼。
    // 天气没拉到（nil）时**不编内容**：整卡退回原来的"每日简报 + 首句"形态，
    // 温度行整个不画，绝不显示 "—°" 或 "0°"。
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if hasWeather {
                weatherHero
                    .padding(.top, BriefMetrics.titleGap)

                weakenedBody
                    .padding(.top, BriefMetrics.bodyGap)
            } else {
                // 无天气兜底态：沿用 3.9.0 的版式（标题 + 正文首句），
                // 这是"不知道天气"的诚实形态，不是错误态
                titleRow
                    .padding(.top, BriefMetrics.titleGap)

                bodyRow
                    .padding(.top, BriefMetrics.bodyGap)
            }

            // 唯一的弹性留白：把小号也"钉"成上文字下轨迹的两段式，
            // 其余间距全是固定 PT —— 正文多少都不会把轨迹挤出画布。
            Spacer(minLength: 0)

            BriefTrack(progress: dayProgress,
                       dotCount: BriefMetrics.dotCount(family),
                       ink: ink)

            if hasFooter {
                footer
                    .padding(.top, BriefMetrics.footerGap)
            }
        }
        .padding(.horizontal, BriefMetrics.sidePadding(family))
        .padding(.vertical, BriefMetrics.verticalPadding(family))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 有没有天气可当主视觉：`ok` 且温度或现象至少有一头（两头全缺就不摆 hero）。
    private var hasWeather: Bool {
        guard let weather = entry.weather, weather.ok else { return false }
        return weather.temp != nil || weather.text != nil
    }

    // MARK: - 天气主视觉（3.10.0）

    /// 大号温度 + 天气现象 + 高低温（参考 IMG_9275 右上的"22° 19°"层级）。
    ///
    /// 温度取整显示（`Int` 截断而非四舍五入）：天气数字约定俗成不带小数，
    /// 而截断保证 21.9° 显示 21° —— 读起来永远"不低于实际"，不会反向夸大暖度。
    private var weatherHero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let temp = entry.weather?.temp {
                Text("\(Int(temp))°")
                    .font(BriefMetrics.tempScaled(s))
                    .foregroundStyle(ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // 温度是这张卡的关键数字：着色模式下进 accent 组（与 3.9.0 标题同一理由）
                    .widgetAccentable()
            }

            if let text = entry.weather?.text, text.isEmpty == false {
                Text(text)
                    .font(BriefMetrics.weatherTextScaled(s))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            if let hiLo = hiLoText {
                Text(hiLo)
                    .font(BriefMetrics.hiLo)
                    .foregroundStyle(inkDim)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// 高低温文案："22° 19°"（照参考图样式）。两头都拿不到就 nil（整段不画），
    /// 只有一头也 nil —— 半对半错的高低温比不显示更让人怀疑数据。
    private var hiLoText: String? {
        guard let tMax = entry.weather?.tMax, let tMin = entry.weather?.tMin else { return nil }
        return "\(Int(tMax))° \(Int(tMin))°"
    }

    // MARK: - 弱化正文（3.10.0）

    /// 简报首句：字号降一档（13 → 11）、颜色再压一档（inkDim），
    /// 内容与 3.9.0 的 `bodyText` 完全同源（同一套"滤栏目头"规则）。
    @ViewBuilder
    private var weakenedBody: some View {
        if let text = bodyText {
            Text(text)
                .font(BriefMetrics.weakBodyScaled(s))
                .foregroundStyle(inkDim.opacity(0.85))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // 早上简报还没生成是**正常业务状态**，不是错误：说清楚"还没有"，不吓人、不编内容
            Text("今天还没有简报")
                .font(BriefMetrics.weakBodyScaled(s))
                .foregroundStyle(inkDim)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 顶行：日期 · 星期 · 胶囊

    private var header: some View {
        HStack(spacing: 6) {
            Text(entry.dateText)
                .font(BriefMetrics.eyebrow)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if !entry.weekdayText.isEmpty {
                Text(entry.weekdayText)
                    .font(BriefMetrics.eyebrow)
                    .foregroundStyle(inkDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // 小号不放胶囊：158pt 宽，胶囊会和"10月31日 周六"抢位置
            if !isSmall {
                Text("简报")
                    .font(BriefMetrics.tag)
                    .foregroundStyle(ink)
                    .padding(.horizontal, BriefMetrics.tagHorizontalPadding)
                    .padding(.vertical, BriefMetrics.tagVerticalPadding)
                    .background {
                        // 面用墨色压一档（浅色纸 → 深灰底、深色纸 → 半透白底），不是新造颜色
                        Capsule().fill(ink.opacity(0.10))
                    }
                    .overlay {
                        Capsule().strokeBorder(ink.opacity(0.28),
                                               lineWidth: BriefMetrics.tagStrokeWidth)
                    }
            }
        }
    }

    // MARK: - 标题（无天气兜底态）

    private var titleRow: some View {
        Text("每日简报")
            .font(BriefMetrics.titleScaled(s))
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 关键文字进 accent 组：iOS 26 桌面透明 / 着色（accented 渲染模式）下，
            // 系统拿掉 containerBackground、把未标记内容压成 primary —— 标题是这张卡
            // 的身份，必须在压完之后仍是第一眼读到的（iOS 16+ API，直接用）
            .widgetAccentable()
    }

    // MARK: - 正文首句

    @ViewBuilder
    private var bodyRow: some View {
        if let text = bodyText {
            Text(text)
                .font(BriefMetrics.bodyScaled(s))
                .foregroundStyle(inkDim)
                .lineLimit(BriefMetrics.bodyLineLimit(family))
                .lineSpacing(BriefMetrics.bodyLineSpacing)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // 早上简报还没生成是**正常业务状态**，不是错误：说清楚"还没有"，不吓人、不编内容
            Text("今天还没有简报")
                .font(BriefMetrics.bodyScaled(s))
                .foregroundStyle(inkDim)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 今天的第一句。
    ///
    /// 服务端 `body` 不是纯正文，而是带 emoji 小标题的分段文本（`🗓 每日简报` /
    /// `🎁 距离生日还有 253 天` / 正文若干段）。直接取第一行会把"栏目头"当正文显示，
    /// 所以先按行拆开、滤掉栏目头，剩下的第一行才是"今天的第一句"。
    /// 判据与 App 内 `TodayBriefTrackCard.bodyParts` 同一套（emoji 开头 / 过短无句读）。
    private var bodyText: String? {
        let rows = entry.paragraphs
            .joined(separator: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !BriefFace.isHeading($0) }
        return rows.first
    }

    /// 判断某一行是不是"栏目头"：emoji 开头，或短到不可能是一句话
    private static func isHeading(_ line: String) -> Bool {
        if let scalar = line.unicodeScalars.first, scalar.properties.isEmojiPresentation {
            return true
        }
        let hasPunctuation = line.contains("，") || line.contains("。")
            || line.contains("！") || line.contains("？") || line.contains("、")
        return line.count <= 6 && !hasPunctuation
    }

    // MARK: - 底部：宜忌 + 日出日落

    /// 底部这一行有没有内容。两头都空时整行不画（比留一行空白诚实）。
    private var hasFooter: Bool {
        // 小号不放这一行：正方形画布上它会和轨迹挤成一团
        guard !isSmall else { return false }
        if entry.ritualText != nil { return true }
        let sun = entry.sunTexts()
        return sun.rise != nil || sun.set != nil
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let ritual = entry.ritualText {
                Text(ritual)
                    .font(BriefMetrics.footnote)
                    .foregroundStyle(inkDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
            }

            Spacer(minLength: 4)

            // 右端 = 日出 + 日落，用主字色（`ink`，跟着纸走）压上去：它们是"时刻"，
            // 比左边的历书注脚更重要，所以不压暗。着色模式下也进 accent 组（与标题同一理由）
            if let rise = sunTexts.rise {
                Text(rise)
                    .font(BriefMetrics.footnoteTime)
                    .foregroundStyle(ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .widgetAccentable()
            }

            if let set = sunTexts.set {
                Text(set)
                    .font(BriefMetrics.footnoteTime)
                    .foregroundStyle(ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .widgetAccentable()
            }
        }
    }

    /// 日出 / 日落文案（服务端值优先，缺了回落 `SunClock`，两头都没有就是 nil）
    private var sunTexts: (rise: String?, set: String?) {
        return entry.sunTexts()
    }

    // MARK: - 轨迹进度

    /// 今天已经过去的比例（00:00 → 0，24:00 → 1）。
    ///
    /// 用 `entry.date` 而不是 `Date()`：entry 的 `date` 就是"这一帧被渲染的时刻"，
    /// 它是 Timeline 预渲染的；渲染时现取 `Date()` 会让光点位置和卡片的时间错位
    /// （典型症状：光点比桌面上其它小组件慢一拍）。
    ///
    /// 分母取 `startOfDay(明天) - startOfDay(今天)` 而不是写死 86400：
    /// 夏令时切换那天一天不是 24 小时，写死会让光点在凌晨 3 点就跑到 25%。
    private var dayProgress: Double {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: entry.date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let passed = entry.date.timeIntervalSince(start)
        return min(max(passed / total, 0), 1)
    }
}

// MARK: - 轨迹

/// 一条横贯卡宽的点线 + 一颗"今天过了多少"的光点。
///
/// 参考图里那条虚线轨迹是整张卡唯一的图形元素 —— 它承担"进度"，不承担装饰。
/// 所以这里没有任何曲线、没有任何插画：一排 **2pt 圆点** 等距铺满可用宽度，
/// 其中一颗 **5pt 光点** 按 `progress` 落在两点之间（不是"落在第 N 颗点上"，
/// 那样一天只跳 24 次，看不出时间在走）。
///
/// 圆点间距由 `GeometryReader` 量出来的真实宽度决定（`span / (count - 1)`），
/// 中号 310pt 宽 ≈ 13pt 一颗、小号 136pt 宽 ≈ 7pt 一颗 —— 同一份代码两种密度都不会挤。
private struct BriefTrack: View {

    /// 0…1：今天已过的比例
    let progress: Double
    /// 刻度点数量（中号 24 / 小号 20）
    let dotCount: Int
    /// 刻度点与光点的墨色（`Theme.Weather` 给的那一支，本组件自己不再造色）
    let ink: Color

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = BriefMetrics.trackHeight
            // 两端各留一个点的半径：第一颗和最后一颗都不会被画布边缘切掉一半
            let inset = BriefMetrics.dotDiameter / 2
            let span = max(width - BriefMetrics.dotDiameter, 0)
            let clamped = min(max(progress, 0), 1)

            ZStack(alignment: .topLeading) {
                ForEach(0..<dotCount, id: \.self) { index in
                    Circle()
                        .fill(dotFill(at: index))
                        .frame(width: BriefMetrics.dotDiameter,
                               height: BriefMetrics.dotDiameter)
                        .position(x: inset + span * fraction(of: index),
                                  y: height / 2)
                }

                // 柔光：一团径向渐变，中心 α 高、外圈 α 归零。
                // **零模糊滤镜** —— Widget 每帧重绘，模糊是这里最贵的一笔。
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.lime.opacity(0.42), Theme.lime.opacity(0.0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: BriefMetrics.markerHaloDiameter / 2
                        )
                    )
                    .frame(width: BriefMetrics.markerHaloDiameter,
                           height: BriefMetrics.markerHaloDiameter)
                    .position(x: inset + span * clamped, y: height / 2)

                // 光点本体：品牌青柠**当面**（lime 只做面，不做字色）
                Circle()
                    .fill(Theme.lime)
                    .frame(width: BriefMetrics.markerDiameter,
                           height: BriefMetrics.markerDiameter)
                    .position(x: inset + span * clamped, y: height / 2)
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .frame(height: BriefMetrics.trackHeight)
    }

    /// 第 `index` 颗点在 0…1 上的位置
    private func fraction(of index: Int) -> Double {
        guard dotCount > 1 else { return 0 }
        return Double(index) / Double(dotCount - 1)
    }

    /// 已过的点亮一些、未到的点暗一些 —— 光点两侧因此读得出"前后"。
    /// 两支都是同一支 `ink`（浅色纸是深灰、深色纸是近白）压不透明度，没有新颜色。
    private func dotFill(at index: Int) -> Color {
        return fraction(of: index) <= progress
            ? ink.opacity(0.55)
            : ink.opacity(0.20)
    }
}

// MARK: - 纸面底色

/// 卡片的底色层（第 1、2 层）。
///
/// · **底色**：`Theme.Weather.of(kind, paper:).top` → `Theme.Weather.paperBase(paper).bottom`
///   的两档线性渐变（角度不变，还是自上而下）。
///   3.7.1 起**终点不再是那块近黑的夜**：浅色系统走 `#F1EDE3 → #E3DDCE` 的米纸、
///   深色系统仍走 3.6.0 的夜纸 —— 这就是"桌面这张卡是一块黑砖"的修法。
/// · **中心柔光**：`glow` 的径向渐变，alpha 由云量反向决定（见 `BriefMetrics.glowAlpha`）。
///   晴天 0.30（纸被晒过）、阴天 0.12（云把光挡了）—— 阴天本来就没光，给它打一团亮光就是假的。
///
/// `kind == nil` 时：深色纸**逐像素沿用 3.6.0**（夜纸渐变 + 青柠光 α0.10）；
/// 浅色纸就只是那张米纸，**不画任何光**（α0.10 的青柠压在米纸上是一块脏绿，不是"被打亮"）。
private struct BriefCanvas: View {

    /// 今天的天气；nil = 没拉到（退回"这张纸本来的样子"）
    let kind: WeatherKind?
    /// 纸面档位（深色 / 浅色），**只由 `BriefFace` 那唯一一处 colorScheme 决定**
    let paper: Theme.Weather.Paper

    var body: some View {
        ZStack {
            LinearGradient(colors: [mood.top, base.bottom],
                           startPoint: .top,
                           endPoint: .bottom)

            glow
        }
    }

    /// 纸基两端（深色 = 3.6.0 的那张夜纸，浅色 = 米纸）
    private var base: (top: Color, bottom: Color) {
        return Theme.Weather.paperBase(paper)
    }

    /// 天气氛围三色（`kind == nil` 时 `top` 就是纸基顶端、`glow` 也回到底色，不会被用到）
    private var mood: (top: Color, glow: Color, ink: Color) {
        return Theme.Weather.of(kind, paper: paper)
    }

    @ViewBuilder
    private var glow: some View {
        if let kind = kind {
            radial(mood.glow,
                   alpha: BriefMetrics.glowAlpha(cloudiness: kind.cloudiness))
        } else {
            // 按纸判，而不是按 `==` 判：这里只需要"是哪张纸"，枚举 switch 更直白
            switch paper {
            case .dark:
                // 无天气 + 深色：3.6.0 那层青柠光 α0.10（PRD 的"纸面被中心打亮"），逐像素不变
                radial(Theme.lime, alpha: BriefMetrics.canvasGlowAlpha)
            case .light:
                // 无天气 + 浅色：不画光。米纸本身已经是亮的，再打一层只会脏
                EmptyView()
            }
        }
    }

    /// 一团中心亮、外圈归零的径向光（**零模糊滤镜**：Widget 每帧重绘，模糊太贵）
    private func radial(_ color: Color, alpha: Double) -> some View {
        return RadialGradient(
            colors: [color.opacity(alpha), color.opacity(0)],
            center: UnitPoint(x: 0.5, y: 0.22),
            startRadius: 0,
            endRadius: BriefMetrics.canvasGlowRadius
        )
    }
}

// MARK: - 天气粒子层

/// 「今天什么天」的画法 —— 八档天气各自的粒子。
///
/// **位置**：底色之上、文字与轨迹之下（由 `BriefFace` 用 `.background` 挂在正文背后）。
///
/// 用户原话："做一个效果……把拉到的天气对应放到对应的效果上"，同时又要求"不能太假"。
/// 所以四条硬约束写死在这里，任何一档天气都不许破：
///
/// 1. **颜色只有两个来源**：`Theme.Weather.of(kind, paper:).glow` 与同一处返回的 `ink` 的
///    `opacity` 变体。粒子一旦自己造一个"雨丝蓝"，它就不属于主题了 ——
///    换肤、换明暗、将来调色板，这个颜色都会是唯一一处对不上的地方；
/// 2. **数量封顶**：云 ≤ 3、雨丝 ≤ 20、雪点 ≤ 14。再多就不是天气，是噪点
///    （顺带也是 Widget 的绘制成本：系统每小时都会重画一次）；
/// 3. **正文保护**：正文块 `[verticalPadding, bodyBottom]` 之内一颗粒子都不放。
///    斜雨穿两行中文会把字切碎；云落在标题行上是可以的（α ≤ 0.16、软团，白字照样读得清），
///    但雨 / 雪 / 闪电是锐利图形，一律不越过正文块顶边（见 `particleClearBelowBody`）；
/// 4. **零模糊滤镜**（连 `.blur` 这个 modifier 都不出现）：Widget 每帧重绘，模糊是这里最贵的一笔。
///    雾带的柔边完全由 `LinearGradient` 的上下两端透明伪造。
///
/// **"飘"是怎么来的（重要，别当成 bug 去修）**：Widget 组件不能跑 `Timer`、不能有持续动画 ——
/// 系统只在 entry 到点时重绘**一次**，进程随时会被挂起。所以云的位移只能靠**预排帧**：
/// 每帧的云位置由这一帧的 `date` 算出来（见 `drift`），一天走完 0.35 个卡宽。
/// 到点系统自己换下一帧，看起来就是"每小时挪一点点"。**不要**改成 `withAnimation`：
/// Widget 里没有任何动画时钟，写了也是一段死代码（还要多一份 review 成本）。
private struct BriefWeatherLayer: View {

    /// 天气类型（非可选：由 `BriefFace` 判空后才创建本层）
    let kind: WeatherKind
    /// 这一帧对应的时刻 —— 云的位置由它推算，**不能**用 `Date()`（那会让预渲染帧错位）
    let date: Date
    /// 尺寸档：决定正文块的位置，进而决定净空带的位置
    let family: WidgetFamily
    /// 纸面档位：粒子的颜色要压在**这张纸**上才立得住（浅色纸上近白的雨丝是看不见的）
    let paper: Theme.Weather.Paper

    /// 这一档天气压在**这张纸**上的三色（`glow` 与 `ink` 是粒子的全部颜色来源）
    private var mood: (top: Color, glow: Color, ink: Color) {
        return Theme.Weather.of(kind, paper: paper)
    }

    /// 粒子的墨色（雪点、阴天薄纱用它；其余粒子用 `glow`）
    private var ink: Color {
        return mood.ink
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                clouds(in: size)
                overcastVeil(in: size)
                precipitation(in: size)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    // MARK: 区域划分

    /// 云带：卡顶 → 正文块顶边往上一整个净空带。
    ///
    /// 云只活在这一条里。它**会压到标题行**（中号下沿 40，而标题占 [32,56]）——
    /// 这是刻意的：云是 α ≤ 0.16 的软团，落在标题后面只是"字后面有一点亮"，
    /// 读得清（3.7 上线后没有反馈过问题）。换成锐利图形（雨 / 雪 / 闪电）就必须
    /// 让开正文块，见 `particleClearBelowBody` 与 `precipitationBands`。
    /// 不要把这条带子"顺手"往下推：它决定了云在卡上的高度，一改就是整张卡的天变了。
    private func cloudBand(in size: CGSize) -> CGRect {
        let top = BriefMetrics.verticalPadding(family) * 0.2
        let bottom = BriefMetrics.bodyTop(family) - BriefMetrics.particleClearBand
        let height = max(bottom - top, 1)
        return CGRect(x: 0, y: top, width: size.width, height: height)
    }

    /// 降水区：**天空段 + 地面段**两条带。
    ///
    /// 用户原话是「雨滴太往下了」。旧版只有一条带 = `[正文底边 + 净空带, 卡底 − 6]`，
    /// 中号卡上就是 y∈[114,152] —— 卡高 72%–96% 那一窄条，所以"往下"说的就是这个。
    ///
    /// **3.8.1 修正（第一版错了，记在这里）**：第一版把天空段下沿写成 `bodyTop − 20`
    /// （中号 = 40），可那条线其实落在**标题内部**（标题占 y∈[32,56]、顶行日期占 [12,26]）——
    /// 雨丝会斜穿 20pt 粗的标题，正是净空带想避免的事。正文块是
    /// `[verticalPadding, bodyBottom]`（中号 [12,92]），卡顶到正文块顶边只剩 `verticalPadding`
    /// 那 12pt，**上方没有任何能落雨的空白**。所以现在的口径是：
    ///
    /// · 天空段 = 卡顶内边距那一条（`[padding × 0.2, padding]`，中号 9.6pt）。
    ///   它低于 `minFilledBand`（16pt），`split` 会把粒子全给地面段 —— 这是**预期**结果，
    ///   不是 bug：158pt 高的卡上半部全是字，雨放上去就是切字。
    ///   保留这条带是为了将来正文块变矮、或出现更高的 family 时，雨自己回到上面，
    ///   不用再改第二处几何；
    /// · 地面段 = `[bodyBottom + particleClearBelowBody, 卡底 − particleBottomInset]`
    ///   （中号 [98,152] 共 54pt；小号 [82,152] 共 70pt）。**"太往下"是在这里解决的**：
    ///   下方净空带从 20 收到 6，雨区高度 +42%（中号 38→54、小号 56→70），上沿从
    ///   y=114 提到 y=98。雨从正文正下方就开始落，而不是贴着卡底那一条。
    ///
    /// 下沿仍然不避让轨迹与注脚（理由同旧注释）：那一块画在粒子之上，雨从它们背后落过
    /// 不盖任何读数，而视觉上正是"雨落满整卡"。
    private func precipitationBands(in size: CGSize) -> (sky: CGRect, ground: CGRect) {
        let skyTop = BriefMetrics.verticalPadding(family) * 0.2
        let skyBottom = BriefMetrics.verticalPadding(family)
        let groundTop = BriefMetrics.bodyBottom(family) + BriefMetrics.particleClearBelowBody
        let groundBottom = size.height - BriefMetrics.particleBottomInset

        let sky = CGRect(x: 0,
                         y: skyTop,
                         width: size.width,
                         height: max(skyBottom - skyTop, 1))
        let ground = CGRect(x: 0,
                            y: groundTop,
                            width: size.width,
                            height: max(groundBottom - groundTop, 1))
        return (sky: sky, ground: ground)
    }

    // MARK: 云（partly / overcast）

    @ViewBuilder
    private func clouds(in size: CGSize) -> some View {
        let count = cloudCount
        if count > 0 {
            let band = cloudBand(in: size)
            ForEach(0..<count, id: \.self) { index in
                cloud(in: size, band: band, index: index, count: count)
            }
        }
    }

    private var cloudCount: Int {
        switch kind {
        case .partly:
            return BriefMetrics.partlyCloudCount
        case .overcast:
            return BriefMetrics.overcastCloudCount
        default:
            // 晴：一朵都不画（"只靠底色暖 + 柔光亮"）；雾 / 雨 / 雪 / 雷：云被降水层接管，
            // 再叠云会把上半张挤满 —— 数量封顶是硬要求
            return 0
        }
    }

    /// 一朵云：`height` 由云带高度决定，因此永远不会溢出到正文里
    private func cloud(in size: CGSize, band: CGRect, index: Int, count: Int) -> some View {
        let density: CGFloat = kind == .overcast ? 0.70 : 0.55
        let tallest = band.height * density
        // 第二朵给满高，其余略小：三朵一样大看着像库存素材
        let height = index == 1 ? tallest : tallest * 0.86
        let width = height * 2.3
        let baseX = size.width * baseFraction(index: index, count: count)
        let centerX = wrappedX(base: baseX, cloudWidth: width, cardWidth: size.width)
        let centerY = band.minY + band.height * (index == 1 ? 0.56 : 0.40)

        return BriefCloud(size: CGSize(width: width, height: height), fill: cloudFill)
            .position(x: centerX, y: centerY)
    }

    /// 云在卡宽上的基线位置（0…1）。两朵一左一右，三朵散开
    private func baseFraction(index: Int, count: Int) -> CGFloat {
        if count <= 1 { return 0.5 }
        if count == 2 { return index == 0 ? 0.24 : 0.68 }
        return 0.16 + 0.30 * CGFloat(index)
    }

    /// 云的填充色：多云 0.12 / 阴 0.16（阴天的云更"实"）
    ///
    /// 3.7.1 起浅色纸上按 `paperAlpha` 提一档：同样的 0.16 压在米纸上几乎看不见
    /// （深色纸是"亮云压暗纸"，浅色纸是"灰云压灰纸"，本来就更难读）。
    private var cloudFill: Color {
        let alpha = kind == .overcast ? 0.16 : 0.12
        return mood.glow.opacity(BriefMetrics.paperAlpha(alpha, paper: paper))
    }

    // MARK: 阴天薄纱

    /// 阴天那层"整卡蒙一层灰"的薄纱（**墨色** α0.10）
    ///
    /// 为什么薄纱压在文字之下的位置仍然不挡字：它是文字**之下**的一层，α 只有 0.10，
    /// 作用是把整张卡的对比度压低一档 —— 那正是阴天的观感。
    ///
    /// 3.7.1 起这支色从「夜纸的地面色」换成 `ink`：两张纸的"压暗方向"是相反的
    /// （浅色纸要往墨里压、深色纸要往亮里提），只有 ink 在两边都等于"把对比度压低一档"，
    /// 也才不会在浅色纸上糊出一块脏黑。
    @ViewBuilder
    private func overcastVeil(in size: CGSize) -> some View {
        if kind == .overcast {
            Rectangle()
                .fill(ink.opacity(BriefMetrics.overcastVeilAlpha))
                .frame(width: size.width, height: size.height)
                .position(x: size.width / 2, y: size.height / 2)
        }
    }

    // MARK: 降水（fog / drizzle / rain / snow / thunder）

    @ViewBuilder
    private func precipitation(in size: CGSize) -> some View {
        let bands = precipitationBands(in: size)
        switch kind {
        case .clear, .partly, .overcast:
            // 这三档天上不掉东西。晴更是一颗粒子都没有
            EmptyView()
        case .fog:
            // 雾是"能见度"，贴着地面才有意义 → 只用地面段
            fogBand(in: size, band: bands.ground)
        case .drizzle:
            streaks(in: bands,
                    count: BriefMetrics.drizzleCount,
                    lengthMin: BriefMetrics.drizzleLengthMin,
                    lengthMax: BriefMetrics.drizzleLengthMax,
                    alpha: 0.18,
                    tilt: 0)
        case .rain:
            streaks(in: bands,
                    count: BriefMetrics.rainCount,
                    lengthMin: BriefMetrics.rainLengthMin,
                    lengthMax: BriefMetrics.rainLengthMax,
                    alpha: 0.22,
                    tilt: BriefMetrics.rainTilt)
        case .snow:
            snowDots(in: size)
        case .thunder:
            ZStack(alignment: .topLeading) {
                streaks(in: bands,
                        count: BriefMetrics.thunderRainCount,
                        lengthMin: BriefMetrics.rainLengthMin,
                        lengthMax: BriefMetrics.rainLengthMax,
                        alpha: 0.22,
                        tilt: BriefMetrics.rainTilt)
                // 闪电起点仍在地面段上沿（正文下方）→ 不划过字
                lightning(in: bands.ground)
            }
        }
    }

    /// 雨丝 / 毛毛雨：一排极细的 `Capsule`，按 `tilt` 倾斜。
    ///
    /// 条数按两段的高度比例分（`BriefMetrics.split`），然后**两段各画一遍**：
    /// 每段各自等距排布，段与段之间由正文块隔开（正文块内一颗粒子都没有，
    /// 见 `precipitationBands`）。今天天空段只有 9.6pt，低于 `minFilledBand`，
    /// 所以实际雨丝全在地面段 —— `split` 的 0 条分支会自然处理，不需要外面再判一次。
    ///
    /// 为什么两段共用同一个 `ForEach` 之外不共用一个 `ForEach`：段不同、坐标就不同，
    /// 分两个 `ForEach` 之后每段的 `column` 都以**本段的条数**为分母（`(i + 0.5) / n`），
    /// 每段自己就是等距排布；塞进一个 `ForEach` 就只能按总条数算列，天空段的雨会挤在左半边。
    private func streaks(in bands: (sky: CGRect, ground: CGRect),
                         count: Int,
                         lengthMin: CGFloat,
                         lengthMax: CGFloat,
                         alpha: Double,
                         tilt: Double) -> some View {
        let parts = BriefMetrics.split(count: count,
                                       skyHeight: bands.sky.height,
                                       groundHeight: bands.ground.height)
        return Group {
            // `base` 是全局 index 的起点：散列种子用全局 index，两段才不会出现
            // "上下镜像的同一组抖动"（同一个 index 永远同一个值，见 `scattered`）
            streakSection(in: bands.sky,
                          base: 0,
                          count: parts.sky,
                          lengthMin: lengthMin,
                          lengthMax: lengthMax,
                          alpha: alpha,
                          tilt: tilt)
            streakSection(in: bands.ground,
                          base: parts.sky,
                          count: parts.ground,
                          lengthMin: lengthMin,
                          lengthMax: lengthMax,
                          alpha: alpha,
                          tilt: tilt)
        }
    }

    /// 一段雨丝。位置用"一半网格 + 一点抖动"：纯等距能看出排队，纯随机会结块，
    /// 混合之后才像真的雨。抖动值来自 `scattered`，**同一个 index 永远同一个值** ——
    /// Widget 每帧都重画，用 `random()` 会让整片雨每小时重排一次，看起来像闪。
    private func streakSection(in band: CGRect,
                               base: Int,
                               count: Int,
                               lengthMin: CGFloat,
                               lengthMax: CGFloat,
                               alpha: Double,
                               tilt: Double) -> some View {
        ForEach(0..<count, id: \.self) { slot in
            let index = base + slot
            let seed = scattered(index, 1.7)
            let length = lengthMin + (lengthMax - lengthMin) * CGFloat(scattered(index, 3.1))
            let column = (Double(slot) + 0.5) / Double(max(count, 1))
            let x = band.minX + band.width * CGFloat(column + 0.22 * (seed - 0.5))
            // 纵向：先上下各让出 particleTiltGuard，再在剩余空间里取一段。
            // 那 1pt 是给"倾斜后的包围盒"的（12° 时最多外溢 0.016pt，余量 60 倍）——
            // 没有它，"净空带里一颗粒子都没有"就只是"算出来差不多"。
            let slack = max(band.height - length - BriefMetrics.particleTiltGuard * 2, 0)
            let y = band.minY + BriefMetrics.particleTiltGuard + length / 2
                + slack * CGFloat(scattered(index, 5.3))

            Capsule()
                .fill(particle(alpha))
                .frame(width: 1, height: length)
                .rotationEffect(.degrees(tilt))
                .position(x: x, y: y)
        }
    }

    /// 雾带：一条上下淡出的横向带子（**不用 blur**，柔边靠渐变两端透明）
    ///
    /// 位置在**地面段**里，高约卡高 18% —— 雾是"能见度"，不是"粒子"，
    /// 所以它是唯一一个成品形状（一条带），而不是一堆点；也正因为是"贴地"的，
    /// 它只认地面段，天空段再空也不往那儿放。
    private func fogBand(in size: CGSize, band: CGRect) -> some View {
        let height = min(size.height * BriefMetrics.fogBandRatio, band.height)
        let centerY = band.maxY - height / 2

        return LinearGradient(
            colors: [particle(0), particle(BriefMetrics.fogBandAlpha), particle(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: size.width, height: height)
        .position(x: size.width / 2, y: centerY)
    }

    /// 雪点：1.5pt 的小点，全部散在**地面段**。
    ///
    /// 原本有 1/3 落在天空段（"散布全卡"），但天空段现在只有 9.6pt 高 ——
    /// 5 个 1.5pt 的点挤在一条 9.6pt 的横条里，画出来像一条虚线，比不画更假。
    /// 所以先问一句"这一段够不够高"，不够就全给地面段（判据与 `split` 的 `minFilledBand` 同源）。
    /// 雪点虽小，落在字上同样是脏点，正文块内依然一颗都不放。
    private func snowDots(in size: CGSize) -> some View {
        let bands = precipitationBands(in: size)

        return ForEach(0..<BriefMetrics.snowCount, id: \.self) { index in
            let inSky = bands.sky.height >= BriefMetrics.minFilledBand && index % 3 == 0
            let area = inSky ? bands.sky : bands.ground
            let x = area.minX + area.width * CGFloat(0.04 + 0.92 * scattered(index, 7.9))
            let y = area.minY + area.height * CGFloat(0.10 + 0.80 * scattered(index, 9.4))

            Circle()
                .fill(ink.opacity(0.35))
                .frame(width: BriefMetrics.snowDotDiameter,
                       height: BriefMetrics.snowDotDiameter)
                .position(x: x, y: y)
        }
    }

    /// 闪电：**一道**折线，2pt，从地面段顶端斜向下 3 段，色 `glow` α0.5
    ///
    /// 只画一道是有意的：真雷暴的照片里闪电也是一条，画成三道就变成漫画符号了。
    /// 起点取**地面段**上沿（正文下方，而不是卡顶）是为了不划过正文 —— 见硬约束 3。
    private func lightning(in band: CGRect) -> some View {
        let segment = band.height / CGFloat(BriefMetrics.lightningSegments)
        let middleX = band.midX

        let bolt = Path { path in
            path.move(to: CGPoint(x: middleX + band.width * 0.03, y: band.minY))
            path.addLine(to: CGPoint(x: middleX - band.width * 0.02, y: band.minY + segment))
            path.addLine(to: CGPoint(x: middleX + band.width * 0.025, y: band.minY + segment * 2))
            path.addLine(to: CGPoint(x: middleX - band.width * 0.015, y: band.minY + segment * 3))
        }
        return bolt.stroke(mood.glow.opacity(0.5),
                           style: StrokeStyle(lineWidth: BriefMetrics.lightningWidth,
                                              lineCap: .round,
                                              lineJoin: .round))
    }

    // MARK: 位置与颜色

    /// 云在这一帧的横向位移（pt）。
    ///
    /// `entry.date` 当天的"第几分钟 / 1440" × 卡宽 × 0.35 —— 线性、单调、可复现：
    /// 同一帧无论被系统重绘多少次，云都在同一个位置（这是"预渲染帧"的前提）。
    /// 一天走完 0.35 个卡宽 = 每小时约 1.4% 卡宽，慢到不刺眼，又快到"过一会儿看一眼确实动了"。
    private func drift(cardWidth: CGFloat) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let minutes = Double(hour * 60 + minute)
        return cardWidth * BriefMetrics.cloudDriftPerDay * CGFloat(minutes / 1440)
    }

    /// 云心横坐标：基线 + 位移，再对「卡宽 + 云宽」取模。
    ///
    /// 取模是为了一天的位移累计之后**永不飘出卡外**（飘出去就永远回不来，
    /// 那张卡第二天会缺一朵云）。取模区间从"整朵出左"到"整朵出右"，
    /// 于是到边界时它是平滑地绕回，而不是"卡住"。
    private func wrappedX(base: CGFloat, cloudWidth: CGFloat, cardWidth: CGFloat) -> CGFloat {
        let span = cardWidth + cloudWidth
        guard span > 0 else { return cardWidth / 2 }
        let raw = base + drift(cardWidth: cardWidth)
        let wrapped = raw - (raw / span).rounded(.down) * span
        return wrapped - cloudWidth / 2
    }

    /// 粒子色：一律是 `glow` 压不透明度（唯一例外是雪点，用 `ink`，见 `snowDots`）。
    ///
    /// 浅色纸按 `BriefMetrics.paperAlpha` 提一档，深色纸原样 —— 深色纸上**这一层 α** 零变化
    /// （深色纸基与墨色未变；变了的是八档天气的 `top`，有意提亮一到两档）。
    private func particle(_ alpha: Double) -> Color {
        return mood.glow.opacity(BriefMetrics.paperAlpha(alpha, paper: paper))
    }

    /// 稳定伪随机（0…1）：同一 `index` + `salt` 永远得到同一个值。
    ///
    /// 这不是"随机"，是**确定性散列** —— Widget 的每一帧都是重新绘制，
    /// 真正的随机数会让雨丝的排布每小时整体重排一次，看起来像画面在闪。
    /// 用 `sin` 取小数部分是最省事的散列：无依赖、无状态、可复现。
    private func scattered(_ index: Int, _ salt: Double) -> Double {
        let raw = sin(Double(index) * 12.9898 + salt) * 43758.5453
        return raw - raw.rounded(.down)
    }
}

// MARK: - 云

/// 一朵云 = 一个 `Path` 里三个椭圆（一条横底 + 两团鼓包），**一次填充**。
///
/// 为什么不是"叠三个 `Circle()`"：三个半透明圆叠在一起，重叠处 α 会翻倍，
/// 云上会出现三个更亮的圆斑 —— 看着像三个圈而不是一朵云。
/// 一个 Path 一次填充，α 均匀，边缘还是连成一片的。
///
/// 形状本身用椭圆而不是贝塞尔手绘：云在 158pt 高的卡里只有 ~20pt 高，
/// 手绘曲线在这个尺度上看不出差别，反而多一份没人敢改的坐标。
private struct BriefCloudShape: Shape {

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // 底座：横向椭圆（云的"腰"）
        path.addEllipse(in: CGRect(x: rect.minX,
                                   y: rect.minY + rect.height * 0.50,
                                   width: rect.width,
                                   height: rect.height * 0.50))
        // 左鼓包
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.13,
                                   y: rect.minY + rect.height * 0.16,
                                   width: rect.width * 0.44,
                                   height: rect.height * 0.66))
        // 右鼓包（略高：云不是左右对称的）
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.48,
                                   y: rect.minY,
                                   width: rect.width * 0.38,
                                   height: rect.height * 0.58))
        return path
    }
}

/// 一朵云（形状 + 填充色由调用方给，本组件不造色）
private struct BriefCloud: View {

    let size: CGSize
    let fill: Color

    var body: some View {
        BriefCloudShape()
            .fill(fill)
            .frame(width: size.width, height: size.height)
    }
}
