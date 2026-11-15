import SwiftUI
import WidgetKit

// MARK: - 弧的几何
//
// 5.1.2 · T03：从 `SunArcWidget.swift` **纯平移**到本文件（视觉 / 几何零改动）。
// 原文件保留 Provider / Widget 注册；本文件由 `project.yml` 独立 `path:` 条目引入
// 主 App target，供 R5 调试面板复用同一份渲染层。

/// 日弧（二次贝塞尔，与 Shared 的 `HorizonEdge` 同一族控制点）在参数 t 处的点。
///
/// 为什么单独写闭式解：太阳辉光点必须**精确压在弧线上**（差 2pt 就像画错了）。
/// 这条弧与 `HorizonEdge` 一样满足 x(t) = t，代入贝塞尔公式即得 y ——
/// 与 `SkyLightHorizon.y(atX:)` 是同一个技巧的兄弟版本（那边算高度、这边算整点）。
enum SunArcGeometry {

    /// 参数 t（0…1）处的归一化坐标（x、y 各占画布宽 / 高的比例）
    static func point(at t: Double, crestY: CGFloat, edgeY: CGFloat) -> CGPoint {
        let clamped = CGFloat(min(max(t, 0), 1))
        let x = clamped
        let y = (1 - clamped) * (1 - clamped) * edgeY
            + 2 * (1 - clamped) * clamped * (2 * crestY - edgeY)
            + clamped * clamped * edgeY
        return CGPoint(x: x, y: y)
    }
}

// MARK: - 卡面

/// 日弧卡面 —— 参考图 IMG_9273 右2 + IMG_9277 SUNSET 卡的单色系语言：
/// 强渐变天空底 + 一条辉光弧线 + 弧上一个按当日进度移动的太阳辉光点，
/// 左下实际日出、右下实际日落；中号加"距日落 / 日出"倒计时。
///
/// 三条不能破的规矩（与天光卡同一套）：
/// 1. **颜色只有一个来源**：`Theme.sky(entry.phase)` 六 token，本文件零颜色字面量；
/// 2. **零 blur**：辉光用 `RadialGradient` 伪造（Widget 每帧重绘，模糊最贵）；
/// 3. **没有的数据整段不画**：日出日落算不出就不写时刻，绝不显示 "00:00"。
struct SunArcFace: View {

    @Environment(\.widgetFamily) private var family

    private let entry: SunArcEntry

    init(entry: SunArcEntry) {
        self.entry = entry
    }

    private var sky: Theme.SkyColors {
        return Theme.sky(entry.phase)
    }

    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
    }

    var body: some View {
        if isAccessory {
            accessoryContent
                // accessory 的背景由系统提供，这里给透明底（iOS 17 accessory 同样要求
                // containerBackground，给 clear 即"融入锁屏"）
                .containerBackground(for: .widget) { Color.clear }
                // 日弧画的是"此刻的太阳"，点开就进沉浸式天光页（`skyapp://sky`）
                .widgetURL(WidgetDeepLink.sky)
        } else {
            systemContent
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [sky.top, sky.horizon],
                                   startPoint: .top,
                                   endPoint: .bottom)
                }
                .widgetURL(WidgetDeepLink.sky)
        }
    }

    // MARK: 桌面档（小 / 中 / 大）

    /// 大号（338×354，3.12.0 新增）。
    ///
    /// 与中号的差别**不是"放大"**，而是多了三样东西（任务书逐条）：
    /// 1. 弧更长更粗（弧顶 0.46 → 0.40，线宽 1.6 → 2.4）；
    /// 2. 太阳点更大（10 → 16pt），两端时刻 15 → 22pt；
    /// 3. 底部**新增**一句今日天气（`weatherSummary`），中间那行倒计时放大到 17pt。
    private var isLarge: Bool {
        return family == .systemLarge
    }

    /// 弧顶高度（大号拉得更长）
    private var crestY: CGFloat {
        return isLarge ? WidgetTheme.SunArc.largeArcCrestY : WidgetTheme.SunArc.arcCrestY
    }

    /// 弧两端高度
    private var edgeY: CGFloat {
        return isLarge ? WidgetTheme.SunArc.largeArcEdgeY : WidgetTheme.SunArc.arcEdgeY
    }

    private var systemContent: some View {
        ZStack {
            arcLayers
            sunGlow
            textLayers
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 弧线两层（无 blur 的"辉光"配方，与天光卡地平线同款）：
    /// 雾化层（粗而淡）+ 实线层。
    private var arcLayers: some View {
        ZStack {
            HorizonEdge(crestY: crestY, edgeY: edgeY)
                .stroke(sky.edge.opacity(0.22),
                        lineWidth: isLarge
                            ? WidgetTheme.SkyLight.edgeHazeWidth * 1.6
                            : WidgetTheme.SkyLight.edgeHazeWidth)
            HorizonEdge(crestY: crestY, edgeY: edgeY)
                .stroke(sky.edge.opacity(0.85),
                        lineWidth: isLarge
                            ? WidgetTheme.SunArc.largeArcWidth
                            : WidgetTheme.SkyLight.edgeWidth)
        }
    }

    /// 弧上的太阳辉光点：位置按"当日进度"沿弧移动（夜里整组不画）。
    ///
    /// 进度用 `entry.date`（预渲染帧纪律），不用 `Date()`。
    @ViewBuilder
    private var sunGlow: some View {
        if let progress = entry.dayProgress {
            let point = SunArcGeometry.point(at: progress, crestY: crestY, edgeY: edgeY)
            let core = isLarge
                ? WidgetTheme.SunArc.largeSunCoreDiameter
                : WidgetTheme.SunArc.sunCoreDiameter
            GeometryReader { proxy in
                let center = CGPoint(x: point.x * proxy.size.width,
                                     y: point.y * proxy.size.height)
                ZStack {
                    // 光晕：RadialGradient 伪造（零 blur），plusLighter 提亮不盖底
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: sky.edge.opacity(WidgetTheme.SunArc.glowAlpha), location: 0),
                            .init(color: sky.edge.opacity(0), location: 1)
                        ]),
                        center: UnitPoint(x: point.x, y: point.y),
                        startRadius: 0,
                        endRadius: proxy.size.width * WidgetTheme.SunArc.glowFactor
                    )
                    .blendMode(.plusLighter)

                    Circle()
                        .fill(sky.edge)
                        .frame(width: core, height: core)
                        .position(center)

                    Circle()
                        .strokeBorder(sky.edge.opacity(0.82), lineWidth: WidgetTheme.SunArc.sunRingWidth)
                        .frame(width: core + 2 * WidgetTheme.SunArc.sunRingWidth,
                               height: core + 2 * WidgetTheme.SunArc.sunRingWidth)
                        .position(center)
                }
            }
        }
    }

    /// 文字层：左下日出（暖亮）、右下日落（压暗）；中号加一行倒计时；
    /// 大号再加一行今日天气（最底）。
    private var textLayers: some View {
        VStack(spacing: isLarge ? 8 : 4) {
            Spacer(minLength: 0)
            countdownRow
            timesRow
            if isLarge {
                largeWeatherRow
            }
        }
        .padding(.horizontal, isLarge ? WidgetTheme.SunArc.largePadding : WidgetTheme.padding)
        .padding(.bottom, isLarge ? WidgetTheme.SunArc.largePadding : WidgetTheme.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// 大号底部：今日天气一句（温度 / 现象 / 高低温）。没有数据整段不画。
    @ViewBuilder
    private var largeWeatherRow: some View {
        if let summary = entry.weatherSummary {
            Text(summary)
                .font(WidgetTheme.SunArc.largeWeather)
                .foregroundStyle(sky.inkDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// 中/大号专属的倒计时（小号空间不够，整段不画）。
    ///
    /// `Text(timerInterval:)` 必须有区间合法性守卫：`entry.date < deadline` 不成立时
    /// （帧迟到、系统时钟回拨）这个 API 会渲染出负数或乱码 —— 守卫是硬要求，
    /// 不成立就整段不画（下一帧 30 分钟内会来）。
    @ViewBuilder
    private var countdownRow: some View {
        if family != .systemSmall, let event = entry.nextEvent, event > entry.date {
            HStack(spacing: 5) {
                Text(entry.date < (entry.sunset ?? event) ? "距日落" : "距日出")
                    .font(WidgetTheme.SunArc.tagLabel)
                    .foregroundStyle(sky.inkDim)
                Text(timerInterval: entry.date...event, countsDown: true, showsHours: true)
                    .font(isLarge ? WidgetTheme.SunArc.largeCountdown : WidgetTheme.SunArc.countdown)
                    .foregroundStyle(sky.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
            }
        }
    }

    @ViewBuilder
    private var timesRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let sunrise = entry.sunrise {
                VStack(alignment: .leading, spacing: 1) {
                    Text("日出")
                        .font(WidgetTheme.SunArc.tagLabel)
                        .foregroundStyle(sky.inkDim)
                    Text(Formatters.timeHHmm(sunrise))
                        .font(isLarge ? WidgetTheme.SunArc.largeSunTime : WidgetTheme.SunArc.sunTime)
                        .foregroundStyle(sky.edge)
                        .monospacedDigit()
                        .lineLimit(1)
                        .widgetAccentable()
                }
            }
            Spacer(minLength: 8)
            if let sunset = entry.sunset {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("日落")
                        .font(WidgetTheme.SunArc.tagLabel)
                        .foregroundStyle(sky.inkDim)
                    Text(Formatters.timeHHmm(sunset))
                        .font(isLarge ? WidgetTheme.SunArc.largeSunTime : WidgetTheme.SunArc.sunTime)
                        .foregroundStyle(sky.inkDim)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: accessory 档（rectangular / inline）

    /// 极简版：一行文字 + 两个时刻。没有图形（锁屏的环形 / 长条容不下弧线，
    /// 硬缩放出来的图形是不可读的噪点 —— 参考图的"紧凑一行"正是纯文字形态）。
    @ViewBuilder
    private var accessoryContent: some View {
        switch family {
        case .accessoryInline:
            // 一行：↑06:05 ↓18:13（参考图那种"紧凑一行"）
            Text(accessoryTimesText(separator: "  "))
                .font(WidgetTheme.Accessory.inlineText)
                .widgetAccentable()
        default:
            VStack(alignment: .leading, spacing: WidgetTheme.Accessory.lineSpacing) {
                Text("日弧")
                    .font(WidgetTheme.Accessory.linePrimary)
                    .widgetAccentable()
                Text(accessoryTimesText(separator: " · "))
                    .font(WidgetTheme.Accessory.lineSecondary)
            }
        }
    }

    private func accessoryTimesText(separator: String) -> String {
        let rise = entry.sunrise.map { Formatters.timeHHmm($0) } ?? "--:--"
        let set = entry.sunset.map { Formatters.timeHHmm($0) } ?? "--:--"
        return "↑" + rise + separator + "↓" + set
    }
}
