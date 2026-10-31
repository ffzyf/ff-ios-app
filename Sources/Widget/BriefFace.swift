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
    static let titleSize: CGFloat = 20
    /// 正文字号（同上）
    static let bodySize: CGFloat = 13

    /// 20pt bold：卡名「每日简报」。一句话的卡不需要 28pt，但必须明显高于正文
    static let title = Font.system(size: titleSize, weight: .bold)
    /// 13pt：正文首句（中号 2 行 / 小号 1 行）
    static let body = Font.system(size: bodySize, weight: .regular)

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
    /// 粒子层底部留白。
    ///
    /// 只有 6pt —— 不为"轨迹 + 注脚"整块让位，理由见 `BriefWeatherLayer.precipitationBand`：
    /// 那一块是**画在粒子之上**的（轨迹与注脚在 `content` 里，天气层是 `content` 的背景），
    /// 所以雨丝从它们背后落过不会盖住任何读数，反而正是"雨落满整卡"的观感。
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

    /// 正文行数：小号只放得下 1 行（2 行会把轨迹顶出画布）
    static func bodyLineLimit(_ family: WidgetFamily) -> Int {
        return family == .systemSmall ? 1 : 2
    }

    /// 正文块的**顶边**到卡顶的距离（行高逐项相加，见「行高」一节的理由）
    static func bodyTop(_ family: WidgetFamily) -> CGFloat {
        return verticalPadding(family)
            + eyebrowLineHeight
            + titleGap
            + titleLineHeight
            + bodyGap
    }

    /// 正文块的**底边**到卡顶的距离
    static func bodyBottom(_ family: WidgetFamily) -> CGFloat {
        let lines = CGFloat(bodyLineLimit(family))
        let bodyHeight = bodyLineHeight * lines + bodyLineSpacing * max(lines - 1, 0)
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
/// │                                          │
/// │ 每日简报                                 │ ← 20pt bold
/// │ 今天的第一句正文，最多 2 行，超出截断……    │ ← 13pt，行距 2
/// │                                          │
/// │  · · · · · · · · ● · · · · · · · · ·     │ ← 24 颗 2pt 刻度 + 1 颗 5pt 光点
/// │ 宜 打猎          忌 店铺开业   06:44 17:33│ ← 11pt，两端对齐
/// └─────────────────────────────────────────┘
/// ```
///
/// V3.7 起，**底色与粒子跟着当天的真实天气走**（用户原话："把拉到的天气对应放到对应的效果上"）。
/// 五层，从下到上（顺序不能调，调了就挡字）：
///
/// 1. **底色**：`Theme.Weather.of(kind).top` → `sky(.night).ground` 的两档线性渐变；
/// 2. **中心柔光**：`glow` 的径向渐变，alpha 随云量**反向**（晴 0.30 / 阴 0.12）；
/// 3. **天气粒子**：云 / 雾带 / 毛毛雨 / 雨丝 / 雪点 / 闪电（本文件下半部分）；
/// 4. **轨迹刻度 + 光点**：它是"现在几点"的读数，永远压在粒子之上；
/// 5. **文字**：最高层。
///
/// 四条不能破的规矩：
/// 1. **没有的字段整行不画**：宜忌为空就不画左下、日出算不出就不画右下、
///    正文为空就明说"今天还没有简报"，绝不编内容；
/// 2. **没有天气就回到现在的样子**（`entry.weather == nil`）：不画任何粒子、中心柔光退回
///    那层青柠光，一个像素都不变 —— 天气是装饰，简报才是主体，装饰缺失不该改变版式；
/// 3. **零模糊滤镜、零颜色字面量**：柔光用 `RadialGradient`，颜色全部走 `Theme` token；
/// 4. **文字色只看 `sky(.night).ink`**：天气改的是"面"（底色 / 光 / 粒子），不改字色 ——
///    否则换一天天气就可能出现一处读不清的灰字。
struct BriefFace: View {

    @Environment(\.widgetFamily) private var family

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

    /// 纸面基色（**只用来取字色**）。固定 `.night` 这一档，不随天气 / 时间换档：
    /// 天气改的是底色与粒子，字色必须是一套稳定的近白，否则八档天气要配八套字色。
    private var paper: Theme.SkyColors {
        return Theme.sky(.night)
    }

    var body: some View {
        content
            // 天气粒子层 = 正文的 `.background`：它因此天然待在"底色之上、文字之下"，
            // 不必在 `content` 里插一层 ZStack（那会把版式骨架和天气耦合在一起）
            .background {
                if let today = kind {
                    BriefWeatherLayer(kind: today, date: entry.date, family: family)
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
                BriefCanvas(kind: kind)
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

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            titleRow
                .padding(.top, BriefMetrics.titleGap)

            bodyRow
                .padding(.top, BriefMetrics.bodyGap)

            // 唯一的弹性留白：把小号也"钉"成上文字下轨迹的两段式，
            // 其余间距全是固定 PT —— 正文多少都不会把轨迹挤出画布。
            Spacer(minLength: 0)

            BriefTrack(progress: dayProgress,
                       dotCount: BriefMetrics.dotCount(family),
                       ink: paper)

            if hasFooter {
                footer
                    .padding(.top, BriefMetrics.footerGap)
            }
        }
        .padding(.horizontal, BriefMetrics.sidePadding(family))
        .padding(.vertical, BriefMetrics.verticalPadding(family))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - 顶行：日期 · 星期 · 胶囊

    private var header: some View {
        HStack(spacing: 6) {
            Text(entry.dateText)
                .font(BriefMetrics.eyebrow)
                .foregroundStyle(paper.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if !entry.weekdayText.isEmpty {
                Text(entry.weekdayText)
                    .font(BriefMetrics.eyebrow)
                    .foregroundStyle(paper.inkDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // 小号不放胶囊：158pt 宽，胶囊会和"10月31日 周六"抢位置
            if !isSmall {
                Text("简报")
                    .font(BriefMetrics.tag)
                    .foregroundStyle(paper.ink)
                    .padding(.horizontal, BriefMetrics.tagHorizontalPadding)
                    .padding(.vertical, BriefMetrics.tagVerticalPadding)
                    .background {
                        // 面用天色 token 的半透白（`ink` 压一档），不是新造颜色
                        Capsule().fill(paper.ink.opacity(0.10))
                    }
                    .overlay {
                        Capsule().strokeBorder(paper.ink.opacity(0.28),
                                               lineWidth: BriefMetrics.tagStrokeWidth)
                    }
            }
        }
    }

    // MARK: - 标题

    private var titleRow: some View {
        Text("每日简报")
            .font(BriefMetrics.titleScaled(s))
            .foregroundStyle(paper.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 正文首句

    @ViewBuilder
    private var bodyRow: some View {
        if let text = bodyText {
            Text(text)
                .font(BriefMetrics.bodyScaled(s))
                .foregroundStyle(paper.inkDim)
                .lineLimit(BriefMetrics.bodyLineLimit(family))
                .lineSpacing(BriefMetrics.bodyLineSpacing)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // 早上简报还没生成是**正常业务状态**，不是错误：说清楚"还没有"，不吓人、不编内容
            Text("今天还没有简报")
                .font(BriefMetrics.bodyScaled(s))
                .foregroundStyle(paper.inkDim)
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
                    .foregroundStyle(paper.inkDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
            }

            Spacer(minLength: 4)

            // 右端 = 日出 + 日落，用主字色（`ink`）压在深纸上：它们是"时刻"，
            // 比左边的历书注脚更重要，所以不压暗。
            if let rise = sunTexts.rise {
                Text(rise)
                    .font(BriefMetrics.footnoteTime)
                    .foregroundStyle(paper.ink)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            if let set = sunTexts.set {
                Text(set)
                    .font(BriefMetrics.footnoteTime)
                    .foregroundStyle(paper.ink)
                    .monospacedDigit()
                    .lineLimit(1)
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
    /// 纸面色组（只取 `ink`，本组件自己不再造色）
    let ink: Theme.SkyColors

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
    /// 两支都是 `Theme.sky(.night).ink` 压不透明度，没有新颜色。
    private func dotFill(at index: Int) -> Color {
        return fraction(of: index) <= progress
            ? ink.ink.opacity(0.55)
            : ink.ink.opacity(0.20)
    }
}

// MARK: - 纸面底色

/// 卡片的底色层（第 1、2 层）。
///
/// · **底色**：`Theme.Weather.of(kind).top` → `Theme.sky(.night).ground` 的两档线性渐变
///   （角度不变，还是自上而下）。下沿固定是那块近黑的"夜"，所以八档天气的卡片
///   都压在同一个暗度上，只有上半张在变天 —— 这正是"深浅一致、只换色相"的实现方式。
/// · **中心柔光**：`glow` 的径向渐变，alpha 由云量反向决定（见 `BriefMetrics.glowAlpha`）。
///   晴天 0.30（纸被晒过）、阴天 0.12（云把光挡了）—— 阴天本来就没光，给它打一团亮光就是假的。
///
/// `kind == nil` 时**逐像素沿用旧版**：夜纸渐变 + 青柠光 α0.10，一颗粒子都不画。
private struct BriefCanvas: View {

    /// 今天的天气；nil = 没拉到（退回旧版外观）
    let kind: WeatherKind?

    var body: some View {
        ZStack {
            LinearGradient(colors: [mood.top, night.ground],
                           startPoint: .top,
                           endPoint: .bottom)

            glow
        }
    }

    /// 固定取 `.night` 这一档：这张卡讲的是"今天"，底色该是稳定的一张纸，
    /// 而"今天什么天"由天气那八档负责，不再由时段负责。
    private var night: Theme.SkyColors {
        return Theme.sky(.night)
    }

    /// 天气氛围的两色（nil 时是夜纸的 top / ground，本身不会被用到渐变终点上）
    private var mood: (top: Color, glow: Color) {
        return Theme.Weather.of(kind)
    }

    @ViewBuilder
    private var glow: some View {
        if let kind = kind {
            RadialGradient(
                colors: [mood.glow.opacity(BriefMetrics.glowAlpha(cloudiness: kind.cloudiness)),
                         mood.glow.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.22),
                startRadius: 0,
                endRadius: BriefMetrics.canvasGlowRadius
            )
        } else {
            // 无天气：旧版那层青柠光，α 0.10（PRD 的"纸面被中心打亮"）
            RadialGradient(
                colors: [Theme.lime.opacity(BriefMetrics.canvasGlowAlpha),
                         Theme.lime.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.22),
                startRadius: 0,
                endRadius: BriefMetrics.canvasGlowRadius
            )
        }
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
/// 1. **颜色只有两个来源**：`Theme.Weather.of(kind).glow` 与 `Theme.sky(.night).ink` 的
///    `opacity` 变体。粒子一旦自己造一个"雨丝蓝"，它就不属于主题了 ——
///    换肤、换明暗、将来调色板，这个颜色都会是唯一一处对不上的地方；
/// 2. **数量封顶**：云 ≤ 3、雨丝 ≤ 20、雪点 ≤ 14。再多就不是天气，是噪点
///    （顺带也是 Widget 的绘制成本：系统每小时都会重画一次）；
/// 3. **正文保护**：正文块上下各留 `particleClearBand`（20pt）的净空带，里面一颗粒子都不放。
///    斜雨穿两行中文会把字切碎；云落在标题行上是可以的（α ≤ 0.16，白字照样读得清），
///    但绝不越过这条带；
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
    /// 云只活在这一条里，于是"云压字"这件事在几何上就不可能发生 ——
    /// 比"我算一个够小的透明度和刚好不压字的坐标"可靠得多。
    private func cloudBand(in size: CGSize) -> CGRect {
        let top = BriefMetrics.verticalPadding(family) * 0.2
        let bottom = BriefMetrics.bodyTop(family) - BriefMetrics.particleClearBand
        let height = max(bottom - top, 1)
        return CGRect(x: 0, y: top, width: size.width, height: height)
    }

    /// 降水带：正文块底边往下整个净空带 → 卡底上方 6pt。
    ///
    /// 这条带的上下沿用两件事定：
    /// · 上沿 = 正文底边 + 净空带。正文是**唯一**必须保护的东西（两行中文被斜雨穿过去就废了）；
    /// · 下沿 = 卡底。中号卡只有 158pt 高，"正文 → 轨迹 → 注脚"之间只剩 ~23pt 的弹性留白，
    ///   如果为了避让轨迹再切一刀，降水带会只剩十几 pt —— 那就画不出"下雨"，只能画一条线。
    ///   所以雨是**落满整卡下半部**的：轨迹与注脚画在粒子之上（`content` 在天气层前面），
    ///   读数一个都没被盖住，而视觉上正是"雨落满整张卡"的样子。
    private func precipitationBand(in size: CGSize) -> CGRect {
        let top = BriefMetrics.bodyBottom(family) + BriefMetrics.particleClearBand
        let bottom = size.height - BriefMetrics.particleBottomInset
        let height = max(bottom - top, 1)
        return CGRect(x: 0, y: top, width: size.width, height: height)
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
    private var cloudFill: Color {
        let alpha = kind == .overcast ? 0.16 : 0.12
        return Theme.Weather.of(kind).glow.opacity(alpha)
    }

    // MARK: 阴天薄纱

    /// 阴天那层"整卡蒙一层灰"的薄纱（`ground` 色 α0.10）
    ///
    /// 为什么薄纱能压在文字之上色的位置却仍然不挡字：它是**文字之下**的一层，
    /// α 只有 0.10，作用是把整张卡的对比度压低一档 —— 那正是阴天的观感。
    @ViewBuilder
    private func overcastVeil(in size: CGSize) -> some View {
        if kind == .overcast {
            Rectangle()
                .fill(Theme.sky(.night).ground.opacity(BriefMetrics.overcastVeilAlpha))
                .frame(width: size.width, height: size.height)
                .position(x: size.width / 2, y: size.height / 2)
        }
    }

    // MARK: 降水（fog / drizzle / rain / snow / thunder）

    @ViewBuilder
    private func precipitation(in size: CGSize) -> some View {
        let band = precipitationBand(in: size)
        switch kind {
        case .clear, .partly, .overcast:
            // 这三档天上不掉东西。晴更是一颗粒子都没有
            EmptyView()
        case .fog:
            fogBand(in: size, band: band)
        case .drizzle:
            streaks(in: band,
                    count: BriefMetrics.drizzleCount,
                    lengthMin: BriefMetrics.drizzleLengthMin,
                    lengthMax: BriefMetrics.drizzleLengthMax,
                    alpha: 0.18,
                    tilt: 0)
        case .rain:
            streaks(in: band,
                    count: BriefMetrics.rainCount,
                    lengthMin: BriefMetrics.rainLengthMin,
                    lengthMax: BriefMetrics.rainLengthMax,
                    alpha: 0.22,
                    tilt: BriefMetrics.rainTilt)
        case .snow:
            snowDots(in: size)
        case .thunder:
            ZStack(alignment: .topLeading) {
                streaks(in: band,
                        count: BriefMetrics.thunderRainCount,
                        lengthMin: BriefMetrics.rainLengthMin,
                        lengthMax: BriefMetrics.rainLengthMax,
                        alpha: 0.22,
                        tilt: BriefMetrics.rainTilt)
                lightning(in: band)
            }
        }
    }

    /// 雨丝 / 毛毛雨：一排极细的 `Capsule`，按 `tilt` 倾斜
    ///
    /// 位置用"一半网格 + 一点抖动"：纯等距能看出排队，纯随机会结块，
    /// 混合之后才像真的雨。抖动值来自 `scattered`，**同一个 index 永远同一个值** ——
    /// Widget 每帧都重画，用 `random()` 会让整片雨每小时重排一次，看起来像闪。
    private func streaks(in band: CGRect,
                         count: Int,
                         lengthMin: CGFloat,
                         lengthMax: CGFloat,
                         alpha: Double,
                         tilt: Double) -> some View {
        ForEach(0..<count, id: \.self) { index in
            let seed = scattered(index, 1.7)
            let length = lengthMin + (lengthMax - lengthMin) * CGFloat(scattered(index, 3.1))
            let column = (Double(index) + 0.5) / Double(count)
            let x = band.minX + band.width * CGFloat(column + 0.22 * (seed - 0.5))
            // 纵向只落在降水带内部：先抬半个长度，再在剩余空间里取一段
            let slack = max(band.height - length, 0)
            let y = band.minY + length / 2 + slack * CGFloat(scattered(index, 5.3))

            Capsule()
                .fill(particle(alpha))
                .frame(width: 1, height: length)
                .rotationEffect(.degrees(tilt))
                .position(x: x, y: y)
        }
    }

    /// 雾带：一条上下淡出的横向带子（**不用 blur**，柔边靠渐变两端透明）
    ///
    /// 位置在正文下方的降水带里，高约卡高 18% —— 雾是"能见度"，不是"粒子"，
    /// 所以它是唯一一个成品形状（一条带），而不是一堆点。
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

    /// 雪点：1.5pt 的小白点，约 1/3 散在上半张（"散布全卡"），其余落在降水带
    ///
    /// 上下两块区域都用净空带隔开正文 —— 雪点虽小，落在字上同样是脏点。
    private func snowDots(in size: CGSize) -> some View {
        let lower = precipitationBand(in: size)
        let upper = cloudBand(in: size)

        return ForEach(0..<BriefMetrics.snowCount, id: \.self) { index in
            let inUpper = index % 3 == 0
            let area = inUpper ? upper : lower
            let x = area.minX + area.width * CGFloat(0.04 + 0.92 * scattered(index, 7.9))
            let y = area.minY + area.height * CGFloat(0.10 + 0.80 * scattered(index, 9.4))

            Circle()
                .fill(Theme.sky(.night).ink.opacity(0.35))
                .frame(width: BriefMetrics.snowDotDiameter,
                       height: BriefMetrics.snowDotDiameter)
                .position(x: x, y: y)
        }
    }

    /// 闪电：**一道**折线，2pt，从降水带顶端斜向下 3 段，色 `glow` α0.5
    ///
    /// 只画一道是有意的：真雷暴的照片里闪电也是一条，画成三道就变成漫画符号了。
    /// 起点取降水带上沿（而不是卡顶）是为了不划过正文 —— 见硬约束 3。
    private func lightning(in band: CGRect) -> some View {
        let segment = band.height / CGFloat(BriefMetrics.lightningSegments)
        let middleX = band.midX

        let bolt = Path { path in
            path.move(to: CGPoint(x: middleX + band.width * 0.03, y: band.minY))
            path.addLine(to: CGPoint(x: middleX - band.width * 0.02, y: band.minY + segment))
            path.addLine(to: CGPoint(x: middleX + band.width * 0.025, y: band.minY + segment * 2))
            path.addLine(to: CGPoint(x: middleX - band.width * 0.015, y: band.minY + segment * 3))
        }
        return bolt.stroke(Theme.Weather.of(kind).glow.opacity(0.5),
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

    /// 粒子色：一律是 `glow` 压不透明度（唯一例外是雪点，用 `ink`，见 `snowDots`）
    private func particle(_ alpha: Double) -> Color {
        return Theme.Weather.of(kind).glow.opacity(alpha)
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
