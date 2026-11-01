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

/// 风卡（3.10.0 新组件）。
///
/// **家族表（#8 审计）**：systemSmall / accessoryRectangular / accessoryInline。
/// 不加 systemMedium / systemLarge：参考图里风卡就是一张竖向的方章
/// （风速大字 + 一枚箭头），拉长没有第二排内容可填 —— medium/large 版式
/// 需要逐小时预报列（上游未提供），在数据到位前不摆假适配。
struct WindWidget: Widget {

    /// WidgetKit 用 kind 匹配已上桌的实例，改名等于让所有用户的小组件失效
    static let kind = WidgetTheme.Wind.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WindWidget.kind, provider: WindProvider()) { entry in
            WindFace(entry: entry)
        }
        .configurationDisplayName(WidgetTheme.Wind.displayName)
        .description(WidgetTheme.Wind.description)
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}
