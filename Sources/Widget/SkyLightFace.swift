import SwiftUI
import WidgetKit

/// 天光卡面 —— 参考图里那套"只有配色和文字在变"的版式。
///
/// ```
/// ● 蓝调剩余                    2分钟4秒   ← 左上：阶段色圆点 + 阶段名 / 右上：距下一阶段
///
///         （天空渐变 + 有厚度的地平线弧 + 太阳光点，太阳位置随时刻走）
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
/// 3. **零 `.blur()`**：Widget 每帧都重绘，模糊是这里最贵的一笔。柔光一律用
///    `RadialGradient` 与"低不透明度 + 更粗的线"伪造（见 `horizonLayers`）。
struct SkyLightFace: View {

    @Environment(\.widgetFamily) private var family

    private let entry: SkyLightEntry

    init(entry: SkyLightEntry) {
        self.entry = entry
    }

    private var isSmall: Bool {
        return family == .systemSmall
    }

    /// 这一帧的天色（六个 token 的唯一入口）
    private var sky: Theme.SkyColors {
        return Theme.sky(entry.phase)
    }

    var body: some View {
        content
            // 整卡可点：落到简报页（复用 `WidgetProvider` 里已有的深链常量，不新造 URL）
            .widgetURL(WidgetDeepLink.brief)
            // 背景铺满四边（配合 `SkyLightWidget` 里的 `.contentMarginsDisabled()`）
            .containerBackground(for: .widget) {
                SkyLightSky(entry: entry)
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

            Text(entry.phase.label)
                .font(WidgetTheme.SkyLight.phaseLabel(family))
                .foregroundStyle(sky.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

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
                    .font(WidgetTheme.SkyLight.countdown(family))
                    .foregroundStyle(sky.inkDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(entry.countdownText ?? "")
                    .font(WidgetTheme.SkyLight.countdown(family))
                    .foregroundStyle(sky.inkDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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

/// 天空本体：渐变 + 光晕 + 地面 + 地平线 + 太阳。
///
/// 单独抽出来有两个原因：
/// 1. 它要做 `.containerBackground` 的内容，必须自己铺满整个画布（不受文字层内边距影响）；
/// 2. 太阳位置要按画布实际尺寸算（归一化坐标 × size），放在 `GeometryReader` 里最直接。
struct SkyLightSky: View {

    private let entry: SkyLightEntry
    /// 弧顶 / 两端高度（占画布）。默认与 App 内简报卡同一组数
    private let crestY: CGFloat
    private let edgeY: CGFloat

    init(entry: SkyLightEntry,
         crestY: CGFloat = WidgetTheme.skyCrestY,
         edgeY: CGFloat = WidgetTheme.skyEdgeY) {
        self.entry = entry
        self.crestY = crestY
        self.edgeY = edgeY
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

    var body: some View {
        let sky = Theme.sky(entry.phase)
        let mark = sunMark

        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // ① 天空：顶 → 地平线的一整段渐变（七档各自的 top / horizon）
                LinearGradient(colors: [sky.top, sky.horizon],
                               startPoint: .top,
                               endPoint: .bottom)

                // ② 光晕：一层 RadialGradient，不用 blur。
                //    日落后半小时内还有余温（intensity 衰减到 0），之后什么都不留。
                if let mark, !isNight, mark.intensity > 0.01 {
                    glowLayer(sky: sky, mark: mark, size: size)
                }

                // ③ 地面：弧线以下压深，让日出日落两个时刻自然退到次要层级
                HorizonGround(crestY: crestY, edgeY: edgeY)
                    .fill(
                        LinearGradient(colors: [sky.ground, sky.ground.opacity(0.92)],
                                       startPoint: .top,
                                       endPoint: .bottom)
                    )

                // ④ 地平线亮边：夜里变成一道极细的冷光（线宽更细、更淡）
                horizonLayers(sky: sky, mark: mark)

                // ⑤ 太阳本体：只有"露出地平线且不是夜里"才画
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

    // MARK: - ④ 地平线

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

    // MARK: - ⑤ 太阳

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

        return ZStack {
            Circle()
                .fill(WidgetTheme.sunCore(sky))
                .frame(width: core, height: core)

            Circle()
                .strokeBorder(WidgetTheme.sunRing(sky), lineWidth: WidgetTheme.sunRingWidth)
                .frame(width: ring, height: ring)
        }
        .frame(width: ring + WidgetTheme.sunRingWidth, height: ring + WidgetTheme.sunRingWidth)
        .position(x: mark.point.x * size.width, y: mark.point.y * size.height)
    }
}
