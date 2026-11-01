import SwiftUI
import WidgetKit

// MARK: - 日弧卡（SunArc，3.10.0 新组件）

/// 日弧卡的一条 Timeline entry。
///
/// 为什么日出 / 日落 / 阶段在 entry 里备好、而不是 View 里现算：与 `SkyLightEntry`
/// 同一条纪律 —— entry 是预渲染帧，View 里现取 `Date()` 会让"卡片显示的时刻"与
/// "太阳在弧上的位置"错位。
struct SunArcEntry: TimelineEntry {
    let date: Date
    /// 这一帧属于哪一档天色（七档，决定整卡渐变的配色）
    let phase: SkyPhase
    /// 当天实际日出（来自天气接口；接口没给就回退 `SunClock` 计算值，见 `make`）
    let sunrise: Date?
    /// 当天实际日落（同上）
    let sunset: Date?

    /// 太阳在弧上的进度（0 = 日出、1 = 日落）；夜里 / 算不出时为 nil（不画太阳点）
    var dayProgress: Double? {
        guard let sunrise = sunrise, let sunset = sunset else { return nil }
        let span = sunset.timeIntervalSince(sunrise)
        guard span > 0 else { return nil }
        let raw = date.timeIntervalSince(sunrise) / span
        guard raw >= 0, raw <= 1 else { return nil }   // 夜里：太阳在弧线以下，不画
        return raw
    }

    /// 下一站（倒计时目标）：白天数到日落，日落后数到下一次日出。
    ///
    /// 为什么不复用 `SkyLightEntry.deadline`：那张卡数的是"下一阶段起点"（换色用），
    /// 这张卡数的是"距离日落 / 日出"——参考图 SUNSET 卡的口径就是整个事件，
    /// 两个口径在 `sunset` 附近会差出 70 分钟，不能混用。
    var nextEvent: Date? {
        if let sunset = sunset, date < sunset { return sunset }
        guard let tomorrow = SunClock.times(on: date.addingTimeInterval(86_400)) else { return nil }
        return tomorrow.sunrise
    }

    /// 用一份载荷 + 指定时刻造一帧（纯函数）。
    ///
    /// 实际日出日落只在**同一天**生效（载荷带 `dayKey`）；跨天的帧回退 `SunClock`
    /// —— 上游只预报今天，拿昨天的日落顶替明天，比 ±3 分钟的计算值糟得多
    ///（与 `SunTimesOverride` 同一条纪律）。
    static func make(date: Date, payload: WeatherCardPayload?) -> SunArcEntry {
        let dayKey = RedstoneClock.dayKey(date)
        let actual = payload.flatMap { payload -> (Date, Date)? in
            guard payload.dayKey == dayKey,
                  let sunrise = payload.sunriseDate, let sunset = payload.sunsetDate else { return nil }
            return (sunrise, sunset)
        }
        let computed = SunClock.times(on: date)
        return SunArcEntry(
            date: date,
            phase: SunClock.phase(at: date),
            sunrise: actual?.0 ?? computed?.sunrise,
            sunset: actual?.1 ?? computed?.sunset
        )
    }
}

// MARK: - Provider

/// 日弧卡的 Timeline 刷新策略（对齐工程预算纪律，注释讲清理由）：
///
/// - **帧距 30 分钟**：弧上的太阳点靠"每帧一个静态位置"移动（Widget 无持续动画），
///   30 分钟一帧与红石 / 简报卡同频 —— 两张并排的卡不该有两个脾气；
/// - **视野 24 小时 + `.atEnd`**：与 `BriefProvider` 同款，一天只发 1 次网络请求
///   （`/api/app/weather`，与简报 / 天光共用同一份 10 分钟服务端缓存），
///   离 iOS 每天 40–70 次的刷新预算差两个数量级。帧全是预渲染，不消耗预算；
/// - 倒计时交给 `Text(timerInterval:)` 系统自绘，秒级走时零刷新成本。
struct SunArcProvider: TimelineProvider {

    /// 帧距（30 分钟）
    static let gridStep: TimeInterval = 30 * 60
    /// 视野（24 小时）
    static let horizon: TimeInterval = 24 * 3600

    func placeholder(in context: Context) -> SunArcEntry {
        return SunArcEntry.make(date: Date(), payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SunArcEntry) -> Void) {
        completion(SunArcEntry.make(date: Date(), payload: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SunArcEntry>) -> Void) {
        Task {
            let now = Date()
            let payload = await WeatherCardFeed.fetch()
            let stamps = WidgetTimeline.stamps(now: now, horizon: Self.horizon, step: Self.gridStep)
            let entries = Array(Set(stamps.filter { $0 >= now })).sorted()
                .map { SunArcEntry.make(date: $0, payload: payload) }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }
}

// MARK: - 弧的几何

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

    // MARK: 桌面档（小 / 中）

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
            HorizonEdge(crestY: WidgetTheme.SunArc.arcCrestY,
                        edgeY: WidgetTheme.SunArc.arcEdgeY)
                .stroke(sky.edge.opacity(0.22),
                        lineWidth: WidgetTheme.SkyLight.edgeHazeWidth)
            HorizonEdge(crestY: WidgetTheme.SunArc.arcCrestY,
                        edgeY: WidgetTheme.SunArc.arcEdgeY)
                .stroke(sky.edge.opacity(0.85),
                        lineWidth: WidgetTheme.SkyLight.edgeWidth)
        }
    }

    /// 弧上的太阳辉光点：位置按"当日进度"沿弧移动（夜里整组不画）。
    ///
    /// 进度用 `entry.date`（预渲染帧纪律），不用 `Date()`。
    @ViewBuilder
    private var sunGlow: some View {
        if let progress = entry.dayProgress {
            let point = SunArcGeometry.point(at: progress,
                                             crestY: WidgetTheme.SunArc.arcCrestY,
                                             edgeY: WidgetTheme.SunArc.arcEdgeY)
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
                        .frame(width: WidgetTheme.SunArc.sunCoreDiameter,
                               height: WidgetTheme.SunArc.sunCoreDiameter)
                        .position(center)

                    Circle()
                        .strokeBorder(sky.edge.opacity(0.82), lineWidth: WidgetTheme.SunArc.sunRingWidth)
                        .frame(width: WidgetTheme.SunArc.sunCoreDiameter + 2 * WidgetTheme.SunArc.sunRingWidth,
                               height: WidgetTheme.SunArc.sunCoreDiameter + 2 * WidgetTheme.SunArc.sunRingWidth)
                        .position(center)
                }
            }
        }
    }

    /// 文字层：左下日出（暖亮）、右下日落（压暗）；中号加一行倒计时。
    private var textLayers: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            countdownRow
            timesRow
        }
        .padding(.horizontal, WidgetTheme.padding)
        .padding(.bottom, WidgetTheme.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// 中号专属的倒计时（小号空间不够，整段不画）。
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
                    .font(WidgetTheme.SunArc.countdown)
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
                        .font(WidgetTheme.SunArc.sunTime)
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
                        .font(WidgetTheme.SunArc.sunTime)
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

// MARK: - 组件注册

/// 日弧卡（3.10.0 新组件）。
///
/// **家族表（#8 审计）**：systemSmall / systemMedium / accessoryRectangular / accessoryInline。
/// 不加 `.systemLarge`：这张卡的全部内容（弧 + 两个时刻 + 倒计时）在小 / 中号已构成
/// 完整的视觉闭环，放大到大号只会得到"更空的天"—— 天光卡那种"整屏天空"才是
/// Large 该有的样子，硬套这张卡是负收益（注释即文档，改动前先想清楚加什么内容）。
/// 不加 accessoryCircular：环形里放不下"两个时刻 + 弧"中任何一项的可读形态。
struct SunArcWidget: Widget {

    /// WidgetKit 用 kind 匹配已上桌的实例，改名等于让所有用户的小组件失效
    static let kind = WidgetTheme.SunArc.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SunArcWidget.kind, provider: SunArcProvider()) { entry in
            SunArcFace(entry: entry)
        }
        .configurationDisplayName(WidgetTheme.SunArc.displayName)
        .description(WidgetTheme.SunArc.description)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        // 底色铺到四边（与天光 / 简报卡同一纪律，否则外围一圈系统色像"卡中卡"）
        .contentMarginsDisabled()
    }
}
