import SwiftUI
import WidgetKit

// MARK: - 风卡（Wind，3.10.0 新组件）

/// 风卡的 Timeline entry：当前风速 / 风向（来自 `/api/app/weather`，失败回退缓存）。
struct WindEntry: TimelineEntry {
    let date: Date
    /// 风速（km/h，Open-Meteo 默认单位）；nil = 没拿到（卡面走缺省形态）
    let wind: Double?
    /// 风向 16 方位中文（"东北"…）；nil = 同上
    let windDirText: String?
    /// 风向来向角度（0 = 正北、顺时针，meteorological：风**从**这个方向来）
    let windDirectionDegrees: Double?
    /// 上游观测时刻（底行"数据时间"；nil = 整段不画）
    let updatedAt: Date?

    static func make(date: Date, payload: WeatherCardPayload?) -> WindEntry {
        guard let payload = payload else {
            return WindEntry(date: date, wind: nil, windDirText: nil,
                             windDirectionDegrees: nil, updatedAt: nil)
        }
        // 度数从中文方位反查（后端只给中文；±11.25° 的取整损失对"画个箭头"无意义）
        let degrees = payload.windDirText.flatMap { text -> Double? in
            guard let index = WeatherNow.compassNames.firstIndex(of: text) else { return nil }
            return Double(index) * 22.5
        }
        return WindEntry(date: date,
                         wind: payload.wind,
                         windDirText: payload.windDirText,
                         windDirectionDegrees: degrees,
                         updatedAt: payload.updatedAt)
    }
}

/// 风卡的 Timeline：**30 分钟一帧、24 小时视野、`.atEnd` 重取**（与日弧卡同一预算：
/// 一天 1 次网络，帧全预渲染）。风在 30 分钟内的变化对"今天风多大"没有展示意义。
struct WindProvider: TimelineProvider {

    /// 帧距（30 分钟）
    static let gridStep: TimeInterval = 30 * 60
    /// 视野（24 小时）
    static let horizon: TimeInterval = 24 * 3600

    func placeholder(in context: Context) -> WindEntry {
        return WindEntry.make(date: Date(), payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WindEntry) -> Void) {
        completion(WindEntry.make(date: Date(), payload: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WindEntry>) -> Void) {
        Task {
            let now = Date()
            let payload = await WeatherCardFeed.fetch()
            let stamps = WidgetTimeline.stamps(now: now, horizon: Self.horizon, step: Self.gridStep)
            let entries = stamps.filter { $0 >= now }.sorted()
                .map { WindEntry.make(date: $0, payload: payload) }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }
}

// MARK: - 卡面

/// 风卡面 —— 参考图 IMG_9275 左3 的语言：风速大字 + 中文方位 + 一排风向箭头，
/// 底部 NOW / 上下文行。
///
/// ## 风向箭头的角度语义（重要，别"修回去"）
/// `windDirectionDegrees` 是 **meteorological 风向：风从哪个方向来**（0° = 北风 = 从北往南吹）。
/// 箭头要表示"风吹向哪"，所以旋转角 = 来向 + 180° —— 直接用来向旋转会画出
/// "北风往北吹"的反物理箭头。
///
/// 布局（小号）：上行「12 KM/H + 东北」，中间一枚随风向旋转的箭头，
/// 下行「现在 + 观测时刻」。没有数据（nil）时整卡退化为"暂无数据"的静默形态，
/// 绝不显示 0 KM/H —— 0 是"无风"，不是"没拿到"。
struct WindFace: View {

    @Environment(\.widgetFamily) private var family

    private let entry: WindEntry

    init(entry: WindEntry) {
        self.entry = entry
    }

    /// 风卡底色：跟随当前天色的单色系渐变（与日弧 / 天光同一套语言）。
    /// 风本身没有"颜色语义"，硬造一支"风青色"会脱离主题 —— 跟天色走最稳。
    private var sky: Theme.SkyColors {
        return Theme.sky(SunClock.phase(at: entry.date))
    }

    var body: some View {
        Group {
            if family == .accessoryRectangular || family == .accessoryInline {
                accessoryContent
                    .containerBackground(for: .widget) { Color.clear }
            } else if family == .systemLarge {
                largeContent
                    .containerBackground(for: .widget) {
                        LinearGradient(colors: [sky.top, sky.horizon],
                                       startPoint: .top,
                                       endPoint: .bottom)
                    }
            } else {
                systemContent
                    .containerBackground(for: .widget) {
                        LinearGradient(colors: [sky.top, sky.horizon],
                                       startPoint: .top,
                                       endPoint: .bottom)
                    }
            }
        }
        // 风画的是"此刻这片天的一部分"，点开就进沉浸式天光页（`skyapp://sky`）
        .widgetURL(WidgetDeepLink.sky)
    }

    // MARK: 桌面小号

    private var systemContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            Spacer(minLength: 0)
            arrowRow
            Spacer(minLength: 0)
            footRow
        }
        .padding(WidgetTheme.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: 桌面大号（338×354，3.12.0 新增）
    //
    // 与中/小号的差别（任务书要求"承载更多内容"）：
    // 1. 风速大字 26 → **56pt**，方位 16pt，箭头 44pt；
    // 2. **新增**「风力刻度」：一条 0…60 KM/H 的轨道 + 指针 + 三档标签 ——
    //    同一份当前风速，用"它在刻度的哪个位置"表达，这是**真实数据的第二种读法**；
    // 3. 底部观测行（现在 + 观测时刻）。
    //
    // 为什么不是"未来 3 小时趋势"：上游 `/api/app/weather` 只给当前实况，
    // `WeatherNow` 里没有 hourly、也没有 gust。按工程纪律"没有的数据整段不画"，
    // 画一条编出来的趋势线是这个项目最不能做的事（`WeatherKind.from(code:)` 的注释里
    // 已经踩过一次"把缺数据画成晴天"的坑）。所以用刻度表达当前值，不伪造时间序列。
    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let wind = entry.wind {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(wind.rounded()))")
                        .font(WidgetTheme.Wind.largeSpeed)
                        .foregroundStyle(sky.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                    Text("KM/H")
                        .font(WidgetTheme.Wind.largeUnit)
                        .foregroundStyle(sky.inkDim)
                    Spacer(minLength: 6)
                    if let dir = entry.windDirText {
                        Text(dir)
                            .font(WidgetTheme.Wind.largeUnit)
                            .foregroundStyle(sky.ink)
                            .lineLimit(1)
                            .widgetAccentable()
                    }
                }
                .padding(.top, WidgetTheme.Wind.largePadding)

                Spacer(minLength: 0)

                if let degrees = entry.windDirectionDegrees {
                    HStack {
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up")
                            .font(.system(size: WidgetTheme.Wind.largeArrowSize, weight: .bold))
                            .foregroundStyle(sky.edge)
                            // meteorological 来向 + 180 = 风吹去的方向（与 `WindFace` 头注释同一套语义）
                            .rotationEffect(.degrees(degrees + 180))
                        Spacer(minLength: 0)
                    }
                }

                Spacer(minLength: 0)

                windScale(wind: wind)
                    .padding(.bottom, 10)

                footRow
            } else {
                // 没拿到数据：整卡静默（不显示 0 KM/H —— 0 是"无风"，不是"没拿到"）
                Spacer(minLength: 0)
                Text("暂无数据")
                    .font(WidgetTheme.Wind.largeUnit)
                    .foregroundStyle(sky.inkDim)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, WidgetTheme.Wind.largePadding)
        .padding(.bottom, WidgetTheme.Wind.largePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// 风力刻度：0…60 KM/H 的轨道 + 一个指针 + 三档标签。
    ///
    /// 指针位置是**纯几何**（`wind / scaleMax`），不参与动画、不重新计算颜色。
    private func windScale(wind: Double) -> some View {
        let fraction = min(max(CGFloat(wind / Double(WidgetTheme.Wind.scaleMax)), 0), 1)
        let knob = WidgetTheme.Wind.scaleKnobDiameter

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(sky.inkDim.opacity(0.20))
                        .frame(height: WidgetTheme.Wind.scaleHeight)
                    Capsule()
                        .fill(sky.edge)
                        .frame(width: max(0, width * fraction),
                               height: WidgetTheme.Wind.scaleHeight)
                    Circle()
                        .fill(sky.ink)
                        .frame(width: knob, height: knob)
                        .offset(x: min(max(width * fraction - knob / 2, 0), max(0, width - knob)))
                }
                .frame(height: knob, alignment: .leading)
            }
            .frame(height: knob)

            HStack(spacing: 0) {
                Text("无风")
                    .font(WidgetTheme.Wind.scaleLabel)
                    .foregroundStyle(sky.inkDim)
                Spacer(minLength: 0)
                Text("微风")
                    .font(WidgetTheme.Wind.scaleLabel)
                    .foregroundStyle(sky.inkDim)
                Spacer(minLength: 0)
                Text("强风")
                    .font(WidgetTheme.Wind.scaleLabel)
                    .foregroundStyle(sky.inkDim)
            }
        }
    }

    /// 上行：风速大字 + 单位 / 方位。风速缺省时整行显示「暂无数据」——
    /// 不显示 0（0 是合法的"无风"，缺数据给 0 是这个项目踩过两次的坑）
    @ViewBuilder
    private var headerRow: some View {
        if let wind = entry.wind {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(wind.rounded()))")
                    .font(WidgetTheme.Wind.speed)
                    .foregroundStyle(sky.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                Text("KM/H")
                    .font(WidgetTheme.Wind.unit)
                    .foregroundStyle(sky.inkDim)
                Spacer(minLength: 4)
                Text(entry.windDirText ?? "")
                    .font(WidgetTheme.Wind.unit)
                    .foregroundStyle(sky.ink)
                    .lineLimit(1)
                    .widgetAccentable()
            }
        } else {
            Text("暂无数据")
                .font(WidgetTheme.Wind.unit)
                .foregroundStyle(sky.inkDim)
        }
    }

    /// 中间：一枚随风向旋转的箭头（旋转角 = 来向 + 180°，理由见类型注释）。
    /// 来向拿不到就不画（方位与箭头必须成对出现，半对半错最误导）。
    @ViewBuilder
    private var arrowRow: some View {
        if entry.wind != nil, let degrees = entry.windDirectionDegrees {
            HStack {
                Spacer(minLength: 0)
                Image(systemName: "arrow.up")
                    .font(.system(size: WidgetTheme.Wind.arrowSize, weight: .bold))
                    .foregroundStyle(sky.edge)
                    // meteorological 来向 + 180 = 风吹去的方向
                    .rotationEffect(.degrees(degrees + 180))
                Spacer(minLength: 0)
            }
        }
    }

    /// 底行：左「现在」+ 右观测时刻（数据时间用载荷的 `updatedAt`，
    /// 不是"我们何时拉取"—— 那是两个时刻，参考图 NOW 行的口径是数据时间）
    @ViewBuilder
    private var footRow: some View {
        if entry.wind != nil {
            HStack {
                Text("现在")
                    .font(WidgetTheme.Wind.footnote)
                    .foregroundStyle(sky.inkDim)
                Spacer(minLength: 4)
                if let updated = observedText {
                    Text(updated)
                        .font(WidgetTheme.Wind.footnote)
                        .foregroundStyle(sky.inkDim)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }

    /// 观测时刻文案（`HH:mm`）。缺省 nil = 整段不画，不显示 "--:--"
    private var observedText: String? {
        return entry.updatedAt.map { Formatters.timeHHmm($0) }
    }

    // MARK: accessory 档

    @ViewBuilder
    private var accessoryContent: some View {
        if family == .accessoryInline {
            Text(inlineText)
                .font(WidgetTheme.Accessory.inlineText)
                .widgetAccentable()
        } else {
            VStack(alignment: .leading, spacing: WidgetTheme.Accessory.lineSpacing) {
                Text(headerText)
                    .font(WidgetTheme.Accessory.linePrimary)
                    .widgetAccentable()
                Text(subtitleText)
                    .font(WidgetTheme.Accessory.lineSecondary)
            }
        }
    }

    private var headerText: String {
        guard let wind = entry.wind else { return "风 · 暂无数据" }
        return "\(Int(wind.rounded())) KM/H" + (entry.windDirText.map { " " + $0 } ?? "")
    }

    private var subtitleText: String {
        guard entry.wind != nil else { return "等待天气数据" }
        // 面向用户的语义句：风"从"某方位来（meteorological 口径的文字表达）
        return "现在" + (entry.windDirText.map { " · 风从\($0)来" } ?? "")
    }

    private var inlineText: String {
        guard let wind = entry.wind else { return "风 暂无数据" }
        return "\(Int(wind.rounded())) KM/H" + (entry.windDirText.map { " " + $0 } ?? "")
    }
}

// MARK: - 组件注册

/// 风卡（3.10.0 新组件，3.12.0 补大号）。
///
/// **家族表**：systemSmall / systemLarge / accessoryRectangular / accessoryInline。
/// - 大号（3.12.0）= 56pt 风速大字 + 方位 + 44pt 箭头 + **风力刻度**（0…60 KM/H 轨道 + 指针）
///   + 观测行 —— 刻度是这一档独有的内容，小号没有；
/// - 仍然不加 systemMedium：中号 338×158 的横向空间放不下"刻度 + 箭头"两样，
///   硬摆只会得到一个被压扁的大号（DESIGN-RULES §3 禁止一套布局硬缩放）。
struct WindWidget: Widget {

    /// WidgetKit 用 kind 匹配已上桌的实例，改名等于让所有用户的小组件失效
    static let kind = WidgetTheme.Wind.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WindWidget.kind, provider: WindProvider()) { entry in
            WindFace(entry: entry)
        }
        .configurationDisplayName(WidgetTheme.Wind.displayName)
        .description(WidgetTheme.Wind.description)
        .supportedFamilies([.systemSmall,
                            .systemLarge,
                            .accessoryRectangular,
                            .accessoryInline])
        .contentMarginsDisabled()
    }
}
