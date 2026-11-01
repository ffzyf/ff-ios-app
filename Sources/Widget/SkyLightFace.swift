import Foundation
import SwiftUI
import WidgetKit

/// 天光卡面 —— 参考图里那套"只有配色和文字在变"的版式。
///
/// ```
/// ● 蓝调剩余                    2分钟4秒   ← 左上：阶段色圆点 + 阶段名 / 右上：距下一阶段
///
///         （天空渐变 + 有厚度的地平线弧 + 太阳光点，太阳位置随时刻走）
///         （今天有云 / 有雨时，再往这套天空上叠一层天气）
///
/// 06:05                            18:13   ← 左下日出（偏亮/暖） / 右下日落（压暗/冷）
/// ```
///
/// 三条不能破的规矩：
/// 1. **颜色只有一个来源**：`Theme.sky(entry.phase)` 的六个 token（top / horizon /
///    ground / edge / ink / inkDim）。七档天色在 `Theme` 里逐档手调过，正好对应参考图的
///    六张（日出一档最接近纯白，夜里地平线只剩一道极细的冷光）。本文件没有一个颜色字面量。
/// 2. **几何复用 Shared 的 `HorizonGround` / `HorizonEdge`**：桌面这条弧必须和 App 内简报卡
///    落在同一个高度（`WidgetTheme.skyCrestY` = 0.62 / `skyEdgeY` = 0.74），重画一遍必然会漂。
/// 3. **一次模糊都不做**（`blur` 修饰器在本文件零出现）：Widget 每帧都重绘，模糊是这里最贵的一笔。柔光一律用
///    `RadialGradient` 与"低不透明度 + 更粗的线"伪造（见 `horizonLayers`）。
///
/// ## 天气是**叠加层**，不是替换
///
/// 用户原话："在它原有之上，再添加一种天气效果"。所以这一版最要紧的事是**别弄坏原来那套**：
/// 天空渐变、地平线、太阳随时刻走，一个像素都不动；天气只是一层贴在中间的半透明图形。
/// 逐层的先后顺序写死在 `SkyLightSky.body` 里（顺序错了会立刻变丑，注释里写明了为什么）：
/// 天空 → 光晕 → **云** → 地面 → 地平线亮边 → **降水/雾/闪电** → 太阳本体 → 文字。
struct SkyLightFace: View {

    @Environment(\.widgetFamily) private var family
    /// 渲染模式（iOS 16+ 环境值）：桌面透明 / 着色外观下系统用 accented 模式重画，
    /// 此刻必须把"实心层"换成"低不透明度层"、并把关键文字标进 accent 组 ——
    /// 否则用户的观感就是"开了透明之后只能看见字"（3.8.1 用户反馈）。
    @Environment(\.widgetRenderingMode) private var renderMode

    private let entry: SkyLightEntry

    /// 画布短边（pt）。0 = 还没量到 → 比例为 1 → 与 3.4.0 逐像素一致（降级方向安全）。
    /// **只影响字号**：padding / 弧高 / 圆点直径一个都不缩放（缩放会让地平线压字）。
    @State private var canvasMinSide: CGFloat = 0

    init(entry: SkyLightEntry) {
        self.entry = entry
    }

    /// 这一帧的字号比例（158 → 1.0；iPad 小号 ≈170 → 1.076，上限 1.15）
    private var s: CGFloat {
        return WidgetCanvas.textScale(minSide: canvasMinSide)
    }

    private var isSmall: Bool {
        return family == .systemSmall
    }

    /// 这一帧的天色（六个 token 的唯一入口）
    private var sky: Theme.SkyColors {
        return Theme.sky(entry.phase)
    }

    var body: some View {
        if isAccessory {
            accessoryContent
                // accessory 的背景由系统提供，透明底即"融入锁屏"
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(WidgetDeepLink.brief)
        } else {
            content
                // 画布测量（§5.2）：`.background` 不参与布局，`content` 的 proposal 与不挂时完全相同。
                // 只在 `onAppear` / 尺寸真变时写 `@State`，15 分钟换一帧的重绘不会触发 body 重算。
                .background {
                    canvasProbe
                }
                // 着色 / 透明模式（accented / vibrant）专用的一层：系统会拿掉 `containerBackground`
                // 换成玻璃 —— "开了透明就只能看见字"正是这么来的。但**内容层里的半透明内容**
                // 不会被拿掉：保留不透明度、整体染白。所以这里给 content 背后再垫一层
                // 低不透明度的天空（`SkyLightSky` 在着色模式下自会把实心层换成半透明版），
                // 玻璃上仍读得出"天幕渐变 + 地平线弧"的层次。fullColor 下不垫（有真背景）。
                .background {
                    if renderMode != .fullColor {
                        SkyLightSky(entry: entry, renderMode: renderMode)
                    }
                }
                // 整卡可点：落到简报页（复用 `WidgetProvider` 里已有的深链常量，不新造 URL）
                .widgetURL(WidgetDeepLink.brief)
                // 背景铺满四边（配合 `SkyLightWidget` 里的 `.contentMarginsDisabled()`）
                .containerBackground(for: .widget) {
                    SkyLightSky(entry: entry, renderMode: renderMode)
                }
        }
    }

    /// accessory 档（3.10.0）：rectangular = 阶段名 + 倒计时两行；
    /// inline = 一行紧凑文本。没有图形（锁屏长条容不下"天空 + 地平线 + 太阳"的
    /// 任何一种可读缩放，参考图的紧凑形态就是纯文字）。
    @ViewBuilder
    private var accessoryContent: some View {
        if family == .accessoryInline {
            Text(inlineText)
                .font(WidgetTheme.Accessory.inlineText)
                .widgetAccentable()
        } else {
            VStack(alignment: .leading, spacing: WidgetTheme.Accessory.lineSpacing) {
                Text(entry.phase.label)
                    .font(WidgetTheme.Accessory.linePrimary)
                    .widgetAccentable()
                Text(accessoryCountdownText)
                    .font(WidgetTheme.Accessory.lineSecondary)
            }
        }
    }

    /// accessory 里的倒计时文案：秒级走时交不了（accessory 不渲染走时文本的稳妥形态
    /// 见桌面档），这里用静态文案（与桌面档 ≥1 小时同一规则）；
    /// 算不出（deadline 缺失）整段不画。
    private var accessoryCountdownText: String {
        guard let deadline = entry.deadline, deadline > entry.date else {
            return entry.countdownText ?? ""
        }
        return SkyPhase.countdownText(to: deadline, now: entry.date)
    }

    private var inlineText: String {
        let countdown = accessoryCountdownText
        return countdown.isEmpty ? entry.phase.label : entry.phase.label + " " + countdown
    }

    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
    }

    /// 量画布**短边**。为什么不是宽度：medium 是 338×158（iPad 364×170），按宽度算会得到 2.14
    /// 再被 clamp 到 1.15 —— 所有 medium 档字号一次跳 15%，iPhone 上肉眼可见。
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

    /// 文字层：只有上下两行，中间全留给天空 —— 参考图里没有任何元素压在地平线上
    private var content: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, isSmall
                 ? WidgetTheme.SkyLight.smallSidePadding
                 : WidgetTheme.SkyLight.mediumSidePadding)
        .padding(.vertical, isSmall
                 ? WidgetTheme.SkyLight.smallSidePadding
                 : WidgetTheme.SkyLight.mediumSidePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - 上排：阶段名 + 倒计时

    private var header: some View {
        HStack(alignment: .center, spacing: WidgetTheme.SkyLight.dotGap) {
            // 阶段色圆点：取这一档天空里最亮的那支 `edge`（正午近白、晨昏暖白、夜里冷蓝）
            Circle()
                .fill(sky.edge)
                .frame(width: WidgetTheme.SkyLight.dotDiameter,
                       height: WidgetTheme.SkyLight.dotDiameter)
                // 关键元素进 accent 组：着色模式下 accent 组保持用户的强调色，
                // 与压成 primary 的其余内容拉开层次（iOS 16+ API，直接用）
                .widgetAccentable()

            Text(entry.phase.label)
                .font(WidgetTheme.SkyLight.phaseLabelScaled(family, scale: s))
                .foregroundStyle(sky.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .widgetAccentable()

            Spacer(minLength: WidgetTheme.SkyLight.dotGap)

            countdown
        }
    }

    /// 右上角倒计时。
    ///
    /// 两种画法，按"还剩多久"分派：
    /// - **< 1 小时**：`Text(timerInterval:countsDown:)` —— 系统自己每帧更新秒数，
    ///   零刷新成本，Widget 里也**不能**起 `Timer`（进程随时被挂起，计时器根本不会响）。
    ///   系统这个 API 只会渲染 `mm:ss`，输出不了中文的「x分钟x秒」，所以这一档以秒级
    ///   走时为准（参考图里"2分钟4秒"的含义由圆点位置与颜色承担）。
    /// - **≥ 1 小时**：静态文案 `12小时32分钟`（`SkyPhase.countdownText` 的既有规则），
    ///   分钟位随 15 分钟一帧的网格推进 —— 小时量级上肉眼无差，且不必挂计时器。
    ///
    /// 目标时刻 = **下一阶段的起点**；夜里是下一次日出，所以会出现参考图那样的
    /// 「12小时32分钟」。
    @ViewBuilder
    private var countdown: some View {
        if let deadline = entry.deadline, deadline > entry.date {
            if entry.needsSecondTicker {
                Text(timerInterval: entry.date...deadline, countsDown: true, showsHours: false)
                    .font(WidgetTheme.SkyLight.countdownScaled(family, scale: s))
                    .foregroundStyle(sky.inkDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // 倒计时是这张卡的关键数字：着色模式下进 accent 组，保住第一可读性
                    .widgetAccentable()
            } else {
                Text(entry.countdownText ?? "")
                    .font(WidgetTheme.SkyLight.countdownScaled(family, scale: s))
                    .foregroundStyle(sky.inkDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
            }
        }
    }

    // MARK: - 下排：日出 / 日落

    /// 左右两个时刻贴在弧线以下的地面区（参考图的位置）。
    ///
    /// 小号 158pt 宽也放得下：两个 `HH:mm` 在 9pt 等宽下各约 27pt，合计不到一半宽度。
    /// 万一将来字号变大，`minimumScaleFactor` 会先缩字，不会把两段时间挤成一团。
    ///
    /// 颜色职责：日出取 `sky.edge`（每档最亮、偏暖的那支），日落取 `sky.inkDim`
    /// （压暗退后，读作"要收起来的光"）。两者都是 Theme token，没有新造颜色。
    @ViewBuilder
    private var footer: some View {
        if entry.sunrise != nil || entry.sunset != nil {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if let sunrise = entry.sunrise {
                    Text(Formatters.timeHHmm(sunrise))
                        .font(WidgetTheme.SkyLight.sunTime(family))
                        .foregroundStyle(sky.edge)
                        .lineLimit(1)
                }
                Spacer(minLength: WidgetTheme.SkyLight.dotGap)
                if let sunset = entry.sunset {
                    Text(Formatters.timeHHmm(sunset))
                        .font(WidgetTheme.SkyLight.sunTime(family))
                        .foregroundStyle(sky.inkDim)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - 天空（背景层）

/// 天空本体：渐变 + 光晕 + 云 + 地面 + 地平线 + 降水 + 太阳。
///
/// 单独抽出来有两个原因：
/// 1. 它要做 `.containerBackground` 的内容，必须自己铺满整个画布（不受文字层内边距影响）；
/// 2. 太阳位置要按画布实际尺寸算（归一化坐标 × size），放在 `GeometryReader` 里最直接。
struct SkyLightSky: View {

    private let entry: SkyLightEntry
    /// 弧顶 / 两端高度（占画布）。默认与 App 内简报卡同一组数
    private let crestY: CGFloat
    private let edgeY: CGFloat
    /// 渲染模式。`.fullColor` 以外的两种（accented / vibrant）把实心层换成低不透明度版，
    /// 见 `WidgetTheme.SkyLight` 的"着色 / 透明模式"一节。实时活动（锁屏 / 灵动岛）复用
    /// 本视图时取默认值 `.fullColor` —— ActivityKit 没有 widget 渲染模式这回事。
    private let renderMode: WidgetRenderingMode

    init(entry: SkyLightEntry,
         crestY: CGFloat = WidgetTheme.skyCrestY,
         edgeY: CGFloat = WidgetTheme.skyEdgeY,
         renderMode: WidgetRenderingMode = .fullColor) {
        self.entry = entry
        self.crestY = crestY
        self.edgeY = edgeY
        self.renderMode = renderMode
    }

    /// 是否处于着色 / 透明外观（accented / vibrant）。
    /// 此刻系统拿掉了 `containerBackground`，本视图若作为**内容层**垫底
    /// （见 `SkyLightFace.body`），只有半透明部分能保住层次。
    private var tinted: Bool {
        return renderMode != .fullColor
    }

    /// 天空渐变两端的不透明度（fullColor = 1，着色 = `tintedSkyAlpha`）
    private var skyAlpha: Double {
        return tinted ? WidgetTheme.SkyLight.tintedSkyAlpha : 1
    }

    /// 地面渐变两端的不透明度
    private var groundAlpha: Double {
        return tinted ? WidgetTheme.SkyLight.tintedGroundAlpha : 1
    }

    /// 夜里不画太阳（连余晖也不画）：只在地平线上留一道极细的冷光
    private var isNight: Bool {
        return entry.phase == .night
    }

    /// 这一帧的太阳印记（位置 / 是否在地平线以上 / 余晖强度）。
    ///
    /// 用 `entry.date` 而不是现取 `Date()`：太阳必须和卡片上那句倒计时是同一刻的，
    /// 否则预渲染帧会让"太阳已经过午，文字还在正午"。
    private var sunMark: SunClock.SunMark? {
        return SunClock.sunMark(at: entry.date, on: entry.date, crestY: crestY)
    }

    /// 这一帧要叠加的天气类型。**nil 就什么都不叠**（缺数据不猜、不兜底成晴天）。
    private var weatherKind: WeatherKind? {
        return entry.weatherKind
    }

    /// 当天已经过去多少（0…1）。
    ///
    /// 云的"飘"全部由它驱动：Widget **没有持续动画**（不能起 Timer、不能 `withAnimation`），
    /// 系统只在 entry 到点的那一刻重绘一次。所以"动"只能靠**每一帧算出不同的静态位置** ——
    /// 天光一轮排 24 小时、15 分钟一帧，云的位置随日期推进而缓慢变化，
    /// 肉眼看就是"飘"，而不是"跳"。这里刻意用 `entry.date`，不用 `Date()`：
    /// 预渲染的一帧被系统延后展示时，云的位置必须和那一刻的画面对齐。
    private var dayFraction: CGFloat {
        let startOfDay = RedstoneClock.calendar.startOfDay(for: entry.date)
        let elapsed = entry.date.timeIntervalSince(startOfDay)
        return CGFloat(min(max(elapsed / 86_400, 0), 1))
    }

    var body: some View {
        let sky = Theme.sky(entry.phase)
        let mark = sunMark

        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // ① 天空：顶 → 地平线的一整段渐变（七档各自的 top / horizon）。
                //    着色模式下压到 `tintedSkyAlpha`：半透明渐变被系统染白后仍保留层次
                LinearGradient(colors: [sky.top.opacity(skyAlpha), sky.horizon.opacity(skyAlpha)],
                               startPoint: .top,
                               endPoint: .bottom)

                // ② 光晕：一层 RadialGradient，不用 blur。
                //    日落后半小时内还有余温（intensity 衰减到 0），之后什么都不留。
                //    它本来就是半透明渐变，着色模式下直接交给系统染，不另压档。
                if let mark, !isNight, mark.intensity > 0.01 {
                    glowLayer(sky: sky, mark: mark, size: size)
                }

                // ③ 云（新增）：**在光晕之上、地面之下**。
                //    为什么在光晕之上：光是穿过云才落到地上的，云压住光晕才有"云在前面飘"的层次；
                //    为什么在地面之下：地面和地平线亮边是这张卡最硬的一根线，云绝不许盖住它。
                //    着色模式下云的 α 再乘一档缩放系数（半透明色块染白后太实就是糊斑）。
                if let kind = weatherKind {
                    SkyLightCloudField(kind: kind,
                                       sky: sky,
                                       phase: entry.phase,
                                       dayFraction: dayFraction,
                                       crestY: crestY,
                                       edgeY: edgeY,
                                       alphaScale: tinted
                                           ? WidgetTheme.SkyLight.tintedCloudAlphaScale
                                           : 1,
                                       size: size)
                }

                // ④ 地面：弧线以下压深，让日出日落两个时刻自然退到次要层级。
                //    **着色模式下这里是重点**：实心 `fill` 会被系统整块染白，玻璃上就是
                //    一块死白 —— 压到 `tintedGroundAlpha` 后它退成"地平线以下略深一层"的暗示。
                HorizonGround(crestY: crestY, edgeY: edgeY)
                    .fill(
                        LinearGradient(colors: [sky.ground.opacity(groundAlpha),
                                                sky.ground.opacity(groundAlpha * 0.92)],
                                       startPoint: .top,
                                       endPoint: .bottom)
                    )

                // ⑤ 地平线亮边：夜里变成一道极细的冷光（线宽更细、更淡）。
                //    描边本来就是横向渐变的半透明线，着色模式下原样交给系统染。
                horizonLayers(sky: sky, mark: mark)

                // ⑥ 降水 / 雾 / 闪电（新增）：**落在天空区里，不落到地面区**。
                //    地平线以下画的是"地"，雨丝穿过去会像玻璃上的划痕。
                //    每一种的几何都按地平线高度硬夹（见 `SkyLightHorizon`）。
                if let kind = weatherKind {
                    SkyLightWeatherOverlay(kind: kind,
                                           code: entry.weather?.code,
                                           sky: sky,
                                           crestY: crestY,
                                           edgeY: edgeY,
                                           size: size)
                }

                // ⑦ 太阳本体：只有"露出地平线且不是夜里"才画。
                //    保持最上：它是整张卡最亮的那个点，压在任何东西下面都会被人读成"脏"。
                if let mark, !isNight, mark.isUp {
                    sunBody(sky: sky, mark: mark, size: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    // MARK: - ② 光晕

    /// 太阳外面那团扩散光。
    ///
    /// `.plusLighter` 是加成混合：底下的天色被往上提亮而不是被盖住 —— 参考图里
    /// "光散在空气里"的质感来自这一点。中心 0.45 的不透明度到 35% 半径已掉到 0.19，
    /// 边缘 0，所以不会把整片天空洗白。
    private func glowLayer(sky: Theme.SkyColors,
                           mark: SunClock.SunMark,
                           size: CGSize) -> some View {
        let color = WidgetTheme.sunGlow(sky, phase: entry.phase)
        let strength = Double(mark.intensity)
        let radius = size.width * (mark.isUp
                                   ? WidgetTheme.sunGlowFactor
                                   : WidgetTheme.sunEmberFactor)
        let alpha = WidgetTheme.sunGlowAlpha * (mark.isUp ? 1.0 : 0.7)

        return RadialGradient(
            gradient: Gradient(stops: [
                .init(color: color.opacity(alpha * strength), location: 0),
                .init(color: color.opacity(alpha * 0.42 * strength), location: 0.35),
                .init(color: color.opacity(0), location: 1)
            ]),
            center: UnitPoint(x: mark.point.x, y: mark.point.y),
            startRadius: 0,
            endRadius: radius
        )
        .blendMode(.plusLighter)
    }

    // MARK: - ⑤ 地平线

    /// 三层同一条弧（都是 Shared 的 `HorizonEdge`，一行几何都没重写）：
    /// 雾化层（粗而淡，替掉 `blur`）、实线层（地平线本体）、太阳正下方的高光段。
    ///
    /// 夜里只留实线层，线宽收到 1pt、亮度收到 0.55 —— 参考图六里那道"极细的冷光"。
    private func horizonLayers(sky: Theme.SkyColors, mark: SunClock.SunMark?) -> some View {
        let sunX: CGFloat? = {
            guard !isNight, let mark, mark.isUp else { return nil }
            return mark.point.x
        }()

        return ZStack {
            if !isNight {
                // 雾化层：Widget 里没有 blur，用"更粗 + 更淡"换柔度
                HorizonEdge(crestY: crestY, edgeY: edgeY)
                    .stroke(strokeStyle(sky.edge, sunX: sunX, peak: 0.32, base: 0.12, spread: 0.34),
                            lineWidth: WidgetTheme.SkyLight.edgeHazeWidth)
            }

            HorizonEdge(crestY: crestY, edgeY: edgeY)
                .stroke(strokeStyle(sky.edge,
                                    sunX: sunX,
                                    peak: isNight ? WidgetTheme.SkyLight.nightEdgePeak : 0.95,
                                    base: isNight ? 0.14 : 0.36,
                                    spread: 0.34),
                        lineWidth: isNight
                        ? WidgetTheme.SkyLight.nightEdgeWidth
                        : WidgetTheme.SkyLight.edgeWidth)

            // 太阳正下方那一段：更亮更粗，两头全透明（`base: 0`）
            if let sunX, let mark, mark.intensity > 0.01 {
                HorizonEdge(crestY: crestY, edgeY: edgeY)
                    .stroke(strokeStyle(sky.edge,
                                        sunX: sunX,
                                        peak: 0.9 * Double(mark.intensity),
                                        base: 0,
                                        spread: 0.16),
                            lineWidth: WidgetTheme.sunEdgeBoostWidth)
            }
        }
    }

    /// 亮边的横向渐变：最亮处对准太阳的 x，两侧渐隐。
    ///
    /// 用 `LinearGradient` 而不是 `AngularGradient`：这条弧几乎水平，
    /// 横向渐变的效果和"从太阳向外辐射"肉眼无差，但便宜得多。
    /// `location` 必须单调递增，所以落在 0 / 1 上的停靠点按情况省略。
    private func strokeStyle(_ edge: Color,
                             sunX: CGFloat?,
                             peak: Double,
                             base: Double,
                             spread: CGFloat) -> LinearGradient {
        let center = min(max(sunX ?? 0.5, 0), 1)
        let left = max(0, center - spread)
        let right = min(1, center + spread)

        var stops: [Gradient.Stop] = [.init(color: edge.opacity(base), location: 0)]
        if left > 0.001 {
            stops.append(.init(color: edge.opacity(base), location: left))
        }
        stops.append(.init(color: edge.opacity(peak), location: center))
        if right < 0.999 {
            stops.append(.init(color: edge.opacity(base), location: right))
        }
        stops.append(.init(color: edge.opacity(base * 0.85), location: 1))

        return LinearGradient(gradient: Gradient(stops: stops),
                              startPoint: .leading,
                              endPoint: .trailing)
    }

    // MARK: - ⑦ 太阳

    /// 参考图里的太阳是"一团亮核 + 向外扩散的光晕"，不是一个完整的太阳图标。
    ///
    /// 所以只有三样：9pt 实心圆（`sky.edge`）、外面一圈 1.5pt 高光环、
    /// 背后那层 `RadialGradient` 光晕（在 ② 里画）。**零 blur**。
    ///
    /// 圆心落在 `SunClock.sunMark` 给出的归一化位置上：日出贴左、正午到拱顶（y ≈ 0.10）、
    /// 日落贴右，两端正好压在弧顶高度上 —— 于是看起来"太阳压在那条亮边上"。
    private func sunBody(sky: Theme.SkyColors,
                         mark: SunClock.SunMark,
                         size: CGSize) -> some View {
        let core = WidgetTheme.sunCoreDiameter
        let ring = core + WidgetTheme.sunRingGap
        // 实心核在着色模式下会被整块染白（一块死白），压到半透明才有"辉光点"的层次；
        // 外环是描边（半透明），原样交给系统
        let coreColor = tinted
            ? WidgetTheme.sunCore(sky).opacity(WidgetTheme.SkyLight.tintedSunAlpha)
            : WidgetTheme.sunCore(sky)

        return ZStack {
            Circle()
                .fill(coreColor)
                .frame(width: core, height: core)

            Circle()
                .strokeBorder(WidgetTheme.sunRing(sky), lineWidth: WidgetTheme.sunRingWidth)
                .frame(width: ring, height: ring)
        }
        .frame(width: ring + WidgetTheme.sunRingWidth, height: ring + WidgetTheme.sunRingWidth)
        .position(x: mark.point.x * size.width, y: mark.point.y * size.height)
    }
}

// MARK: - 地平线的解析式

/// 地平线（`HorizonEdge` 那条二次贝塞尔）在任意 x 处的高度，单位 pt。
///
/// 这里能写成**闭式解**，是因为这条弧的 x(t) 恰好等于 t：
/// 三个控制点是 `(0, edgeY)`、`(0.5, 2·crestY − edgeY)`、`(1, edgeY)`，代入
/// `x(t) = (1−t)²·0 + 2(1−t)t·0.5 + t²·1 = t`。
///
/// 为什么这件小事值得单独一个类型：**降水绝不许越过地平线**（用户看得见的一根硬线）。
/// 有了这个式子，每一根雨丝 / 每一个雪点都能在绘制前算出自己脚下那道"地板"在哪，
/// 直接夹住即可 —— 既不用 mask（多一遍离屏合成，Widget 里很贵），
/// 也不是"看起来差不多"的目测值，而是几何上精确等于那条亮边。
enum SkyLightHorizon {

    /// 归一化 x（0…1）处地平线的高度（pt）
    static func y(atX x: CGFloat,
                  width: CGFloat,
                  height: CGFloat,
                  crestY: CGFloat,
                  edgeY: CGFloat) -> CGFloat {
        guard width > 0 else { return height * crestY }
        let t = min(max(x / width, 0), 1)
        let curve = (1 - t) * (1 - t) * edgeY
            + 2 * (1 - t) * t * (2 * crestY - edgeY)
            + t * t * edgeY
        return curve * height
    }
}

/// 确定性伪随机：同一组 `(index, salt)` 永远得到同一个 0…1。
///
/// 为什么不能用 `Double.random(in:)`：Widget 每次重绘都会重新执行 `body`
/// （15 分钟一帧，一天 100 多次），随机数会让**每一帧的雨滴整体换位置** ——
/// 看起来不是在下雨，是在抽搐。用坐标哈希之后，同一根雨丝的粗细长短整天不变，
/// 唯一在动的是云（由 `dayFraction` 驱动）。
private func skyScatter(_ index: Int, _ salt: UInt32) -> CGFloat {
    var value = UInt32(truncatingIfNeeded: index) &* 2_654_435_761
    value = value &+ salt &* 40_503
    value ^= value >> 13
    value = value &* 1_274_126_177
    value ^= value >> 16
    return CGFloat(value % 10_000) / 10_000
}

// MARK: - 天空区（地平线以上）

/// 地平线**以上**的那块天：上边贴画布顶，下边就是那条弧。
///
/// 与 Shared 的 `HorizonGround` 是同一组控制点、方向相反（地面在弧下，这块在弧上）。
/// 为什么不直接复用 `HorizonGround` 再旋转 / 取反：`.mask` 一个反向形状要额外一层，
/// 而这里只是"给暗纱一块准确的画布"，一条 path 就够。
private struct SkyLightSkyArea: Shape {

    var crestY: CGFloat
    var edgeY: CGFloat

    func path(in rect: CGRect) -> Path {
        let endsY = rect.minY + rect.height * edgeY
        let controlY = rect.minY + rect.height * (2 * crestY - edgeY)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: endsY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: endsY),
                          control: CGPoint(x: rect.midX, y: controlY))
        path.closeSubpath()
        return path
    }
}

// MARK: - ③ 云

/// 一朵云的形状：**3 个横向椭圆拼成的一块**。
///
/// 注意这里是"一条 path 里放 3 个椭圆，一次性 fill"，不是"三个半透明圆圈叠起来"——
/// 后者在椭圆重叠处会把 alpha 叠两次（0.55 → 0.80），云里会浮出几个更黑的圆斑，
/// 一眼就假。一次 fill 的覆盖率是按并集算的，所以整朵云的浓度完全一致。
///
/// 云**不做描边、不做内阴影**（用户："不要太假太难看"）：就是一块半透明色块。
private struct SkyLightCloudShape: Shape {

    /// 三团的比例（相对自身 rect）：左下矮、中间高、右边中 —— 横向拉长的云形
    private static let puffs: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = [
        (0.00, 0.42, 0.52, 0.58),
        (0.30, 0.00, 0.44, 1.00),
        (0.56, 0.34, 0.44, 0.66)
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for puff in SkyLightCloudShape.puffs {
            path.addEllipse(in: CGRect(x: rect.minX + puff.x * rect.width,
                                       y: rect.minY + puff.y * rect.height,
                                       width: puff.w * rect.width,
                                       height: puff.h * rect.height))
        }
        return path
    }
}

/// 一朵云的配方：基线位置、漂移速度、尺寸（全部相对画布，换尺寸不换比例）。
private struct SkyLightCloudSpec {

    /// 基线 x（占卡宽 0…1）
    let base: CGFloat
    /// 漂移速度：一整天走完「卡宽 × 这个系数」
    let speed: CGFloat
    /// 中心 y（占卡高 0…1）
    let y: CGFloat
    /// 宽度（占卡宽）
    let width: CGFloat
    /// 高度（占卡高）
    let height: CGFloat

    // 数量是硬上限（用户："云最多 4 朵"），所以这里只有两张写死的表，
    // 不做"按 cloudiness 算出 3.7 朵再取整"那种聪明事 —— 变化只该发生在大小与透明上。

    /// 多云：2 朵，一高一低，别并排放
    static let partly: [SkyLightCloudSpec] = [
        SkyLightCloudSpec(base: 0.15, speed: 0.28, y: 0.200, width: 0.46, height: 0.135),
        SkyLightCloudSpec(base: 0.55, speed: 0.33, y: 0.345, width: 0.40, height: 0.115)
    ]

    /// 阴 / 雷雨：4 朵铺满上半部。宽度给到 0.55 以上是为了横向互相压住，
    /// 靠"同色 alpha 叠两次"叠出"压顶"的连续感（用户要的正是这个，不是四朵孤立的云）。
    static let overcast: [SkyLightCloudSpec] = [
        SkyLightCloudSpec(base: 0.15, speed: 0.28, y: 0.155, width: 0.58, height: 0.150),
        SkyLightCloudSpec(base: 0.42, speed: 0.33, y: 0.275, width: 0.62, height: 0.160),
        SkyLightCloudSpec(base: 0.68, speed: 0.30, y: 0.145, width: 0.56, height: 0.145),
        SkyLightCloudSpec(base: 0.86, speed: 0.31, y: 0.305, width: 0.60, height: 0.155)
    ]

    /// 这一档天要画几朵（0 = 这一档不该出现云层）
    static func specs(for kind: WeatherKind) -> [SkyLightCloudSpec] {
        switch kind {
        case .partly:
            return partly
        case .overcast, .thunder:
            // 雷雨用阴天那套云，另加一层暗纱压下去（见 `SkyLightCloudField`）
            return overcast
        case .clear:
            return []          // 晴天：现有那张卡已经最好看，别画蛇添足
        case .fog:
            return []          // 雾只画雾带：云被雾吃掉了，画云反而分散注意力
        case .drizzle, .rain, .snow:
            return []          // 雨 / 雪只画自己的粒子（按需求表，不额外加云）
        }
    }

    /// 单朵云的 alpha。多云给足 0.55（天空是亮的，太淡就看不见）；
    /// 阴天压到 0.42，因为 4 朵会互相叠，单片给高会糊成一整块不透明的板。
    static func alpha(for kind: WeatherKind) -> Double {
        switch kind {
        case .partly:
            return 0.55
        case .overcast:
            return 0.42
        case .thunder:
            return 0.48
        case .clear, .fog, .drizzle, .rain, .snow:
            return 0
        }
    }
}

/// 云层：按 weather 摆 2 朵或 4 朵，位置随当天进度缓慢横移。
private struct SkyLightCloudField: View {

    let kind: WeatherKind
    let sky: Theme.SkyColors
    let phase: SkyPhase
    let dayFraction: CGFloat
    let crestY: CGFloat
    let edgeY: CGFloat
    /// 云朵 α 的缩放系数（着色模式 < 1，fullColor = 1，见 `WidgetTheme.SkyLight`）
    let alphaScale: Double
    let size: CGSize

    /// 云的颜色。
    ///
    /// 只有两种取法，都是 `Theme.sky(phase)` 里已有的 token：
    /// - 亮天（日出 / 黄金 / 白天 / 日落）用 `edge`：那是每档最亮的一支，云才"看得见"；
    /// - 暗天（夜 / 晨蓝 / 暮蓝）用 `ink`：这三档的 `edge` 偏冷偏紫，画上去像脏，
    ///   而 `ink` 是中性白，夜里读作"被月光照到的云"。
    ///
    /// **日出日落不给云加暖色边**：那需要一层描边或模糊，Widget 里做不好就是一圈脏边
    /// （用户明确说过"不要太假太难看"），所以云保持中性。
    private var tint: Color {
        switch phase {
        case .night, .blueDawn, .blueDusk:
            return sky.ink
        case .sunrise, .golden, .day, .sunset:
            return sky.edge
        }
    }

    /// 一朵云的中心 x（pt）。
    ///
    /// ```
    /// x = (基线 + 当天进度 × 速度系数) mod 1 × 卡宽
    /// ```
    /// - 一天走完「卡宽 × 速度系数」（0.28 ~ 0.33），一小时约 1.2% 卡宽；
    /// - 15 分钟一帧 → 每帧约 0.3% 卡宽，肉眼几乎察觉不到，但一整天确实横飘了 30%；
    /// - 取模是为了防出界：`0.86 + 0.31` 会越过右边，越过就从左边回来。
    ///   跳变只可能发生在子夜（`dayFraction` 归零），而那一刻整张卡本来就在换天色。
    ///
    /// **不要写 `withAnimation`**：Widget 里视图树是一次性快照，动画是死代码。
    /// "飘"只能靠"每帧给不同的静态位置"，没有第二条路。
    private func centerX(_ spec: SkyLightCloudSpec) -> CGFloat {
        let raw = spec.base + dayFraction * spec.speed
        let unit = raw - floor(raw)
        return unit * size.width
    }

    var body: some View {
        let specs = SkyLightCloudSpec.specs(for: kind)
        let alpha = SkyLightCloudSpec.alpha(for: kind)

        return ZStack {
            ForEach(specs.indices, id: \.self) { index in
                cloud(spec: specs[index], alpha: alpha)
            }

            // 雷雨：再压一层暗纱（**画在云之后** = 云也被压暗一点）。
            // 用 `sky.ground` 而不是新造一支深色：它是六元组里**每一档都最暗**的那支
            // （白天地面近黑、夜里更黑），压在天空区上读作"云更低、更重"，
            // 而且是既有 token，不需要在 Theme 里加东西。
            // 形状跟着地平线走（`SkyLightSkyArea`），所以暗纱不会在地平线上留下一条硬边。
            if kind == .thunder {
                SkyLightSkyArea(crestY: crestY, edgeY: edgeY)
                    .fill(sky.ground.opacity(0.18))
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func cloud(spec: SkyLightCloudSpec, alpha raw: Double) -> some View {
        let alpha = min(raw * alphaScale, 1)
        return SkyLightCloudShape()
            .fill(tint.opacity(alpha))
            .frame(width: spec.width * size.width, height: spec.height * size.height)
            .position(x: centerX(spec), y: spec.y * size.height)
    }
}

// MARK: - ⑥ 降水 / 雾 / 闪电

/// 天气的"落下来"那一层：雾带、雨丝、雪点、闪电。
///
/// 三条贯穿整层的硬约束：
/// 1. **不越过地平线**：每一笔都先问 `SkyLightHorizon.y(atX:)` 要自己脚下那道地板，
///    再往上收 3pt —— 地平线以下是"地"，雨丝穿过去会像玻璃上的划痕；
/// 2. **数量有上限**（雨丝 ≤ 22 / 雪点 ≤ 16），宁少不多；
/// 3. **不做模糊**：闪电不发光、不做光晕扩散 —— Widget 里模糊太贵，而且会糊成一团。
private struct SkyLightWeatherOverlay: View {

    let kind: WeatherKind
    /// WMO 代码只用来取降水强度（`WeatherKind.intensity(code:)`），不参与任何判断
    let code: Int?
    let sky: Theme.SkyColors
    let crestY: CGFloat
    let edgeY: CGFloat
    let size: CGSize

    /// 降水强度 0…1。它**只调长度与浓度，不调条数** ——
    /// 条数是需求里写死的上限，强度该表达"雨多大"，不该表达"雨有几根"。
    private var intensity: CGFloat {
        return CGFloat(WeatherKind.intensity(code: code))
    }

    /// 地平线在某个 x 处的高度，再往上收 3pt（别压到那条亮边）
    private func skyLine(atX x: CGFloat) -> CGFloat {
        let line = SkyLightHorizon.y(atX: x,
                                     width: size.width,
                                     height: size.height,
                                     crestY: crestY,
                                     edgeY: edgeY)
        return line - 3
    }

    var body: some View {
        switch kind {
        case .clear, .partly, .overcast:
            // 这三种天没有东西落下来（多云 / 阴只在上层加云）
            EmptyView()

        case .fog:
            fogBand

        case .drizzle:
            // 12 条极短竖划：读作"空气里的湿气"，不是雨
            rainLines(count: 12,
                      lengthFactor: 0.035,
                      slantRatio: 0,
                      lowOnly: true,
                      alpha: 0.42,
                      lineWidth: 0.7)

        case .rain:
            // 22 条斜划（约 10°），铺满天顶到地平线
            rainLines(count: 22,
                      lengthFactor: 0.15,
                      slantRatio: 0.176,
                      lowOnly: false,
                      alpha: 0.55,
                      lineWidth: 0.9)

        case .snow:
            snowDots

        case .thunder:
            ZStack {
                // 雷雨的雨：20 条，比普通雨略长略密（视觉上"雨幕"）
                rainLines(count: 20,
                          lengthFactor: 0.17,
                          slantRatio: 0.176,
                          lowOnly: false,
                          alpha: 0.55,
                          lineWidth: 0.9)
                bolt
            }
        }
    }

    // MARK: 雾

    /// 地平线之上一条横向雾带：高约天空区的 30%，`LinearGradient` 上下淡出。
    ///
    /// 下沿没有完全归零（收到 0.10）：雾在物理上最浓的地方就是贴地那一层，
    /// 归零会让这条带子悬在半空像一张贴纸。上沿必须归零，否则会出现一条硬边。
    private var fogBand: some View {
        let skyHeight = size.height * crestY
        let bandHeight = max(skyHeight * 0.30, 1)

        return LinearGradient(
            stops: [
                .init(color: sky.horizon.opacity(0), location: 0),
                .init(color: sky.horizon.opacity(0.40), location: 0.45),
                .init(color: sky.horizon.opacity(0.26), location: 0.80),
                .init(color: sky.horizon.opacity(0.10), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: size.width, height: bandHeight)
        .position(x: size.width / 2, y: skyHeight - bandHeight / 2)
    }

    // MARK: 雨

    /// 所有雨丝合成**一条 path、一次描边**：22 个子路径各画一次是最贵的那种写法，
    /// Widget 每次重绘都要付一遍。
    private func rainLines(count: Int,
                           lengthFactor: CGFloat,
                           slantRatio: CGFloat,
                           lowOnly: Bool,
                           alpha: Double,
                           lineWidth: CGFloat) -> some View {
        return rainPath(count: count,
                        lengthFactor: lengthFactor,
                        slantRatio: slantRatio,
                        lowOnly: lowOnly)
            .stroke(sky.inkDim.opacity(alpha),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size.width, height: size.height)
    }

    private func rainPath(count: Int,
                          lengthFactor: CGFloat,
                          slantRatio: CGFloat,
                          lowOnly: Bool) -> Path {
        var path = Path()
        guard size.width > 4, size.height > 4 else { return path }

        // 长度随强度小幅变化：小雨的雨丝短、大雨的雨丝长（条数不变）
        let length = max(size.height * lengthFactor * (0.75 + 0.4 * intensity), 2)
        let slant = length * slantRatio

        for index in 0..<count {
            // 两根互不相关的哈希：横向位置与纵向位置不能同步，否则雨会排成斜队
            let across = skyScatter(index, 11)
            let along = skyScatter(index, 29)

            // 横向留出斜出去的余量，右端的雨丝也不会掉到卡外
            let x = 1 + across * max(size.width - slant - 2, 1)
            // 这一根的地板 = 地平线在"最右那一点"的高度，再收 3pt
            let ceiling = skyLine(atX: x + slant)
            guard ceiling > 3 else { continue }

            let top: CGFloat
            if lowOnly {
                // 毛毛雨只落在天空区最下面 40pt 里（用户：地平线以上 40pt 内）
                let band = min(40, ceiling)
                top = ceiling - band * (0.2 + 0.8 * along)
            } else {
                // 普通雨：铺满天空区（从靠近天顶到地平线）
                top = 2 + along * max(ceiling - length - 2, 1)
            }
            // 硬约束：下端最多到地板，绝不穿过地平线
            let bottom = min(top + length, ceiling)

            path.move(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x + slant, y: bottom))
        }
        return path
    }

    // MARK: 雪

    /// 16 个 1.5–2pt 的圆点，**下密上疏**（真实的雪在靠近地面那一段看起来更密）。
    ///
    /// "下密上疏"用 `y = 1 − v²` 实现：v 均匀采样后，靠近 v = 0 的样本会挤进很小的 y 区间，
    /// 于是点自然堆在地平线那一侧 —— 不需要写任何"几行几列"的网格。
    private var snowDots: some View {
        var path = Path()
        let count = 16

        if size.width > 4, size.height > 4 {
            for index in 0..<count {
                let across = skyScatter(index, 7)
                let along = skyScatter(index, 13)
                // 1.5 … 2.0pt：再大就是雨夹雪，再小就看不见
                let diameter = 1.5 + 0.5 * skyScatter(index, 23)

                let x = 2 + across * max(size.width - 4, 1)
                let ceiling = skyLine(atX: x)
                guard ceiling > 3 else { continue }

                let y = 2 + (ceiling - 2) * (1 - along * along)
                path.addEllipse(in: CGRect(x: x - diameter / 2,
                                          y: y - diameter / 2,
                                          width: diameter,
                                          height: diameter))
            }
        }

        return path
            .fill(sky.ink.opacity(0.85))
            .frame(width: size.width, height: size.height)
    }

    // MARK: 闪电

    /// **一道** 3 段折线，线宽 1.5，不发光。
    ///
    /// 为什么不加"外发光"：那需要一次模糊、或者几层逐级放大的描边，
    /// Widget 里既贵又会把 1.5pt 的细线糊成一团光斑 —— 那时候它就不是闪电，是污渍。
    /// 一道就够：闪电是"看一眼就知道"的东西，画两道反而像电路图。
    private var bolt: some View {
        let topY = size.height * 0.06
        let bottomY = size.height * (crestY - 0.10)   // 停在地平线上方，不压亮边
        let span = max(bottomY - topY, 1)
        let centerX = size.width * 0.62
        let dx = size.width * 0.05

        var path = Path()
        path.move(to: CGPoint(x: centerX, y: topY))
        path.addLine(to: CGPoint(x: centerX - dx, y: topY + span * 0.30))
        path.addLine(to: CGPoint(x: centerX + dx * 1.1, y: topY + span * 0.42))
        path.addLine(to: CGPoint(x: centerX + dx * 0.4, y: bottomY))

        return path
            .stroke(sky.edge.opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .miter))
            .frame(width: size.width, height: size.height)
    }
}
