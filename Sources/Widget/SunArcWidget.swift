import SwiftUI
import WidgetKit

// MARK: - 日弧卡（SunArc，3.10.0 新组件）

/// 日弧卡的一条 Timeline entry。
///
/// 为什么日出 / 日落 / 阶段在 entry 里备好、而不是 View 里现算：与 `SkyLightEntry`
/// 同一条纪律 —— entry 是预渲染帧，View 里现取 `Date()` 会让"卡片显示的时刻"与
/// "太阳在弧上的位置"错位。

// MARK: - SunArcEntry 工厂方法

/// 5.1.2 · T03：`SunArcEntry` 的字段 + 纯计算属性已抽到
/// `Sources/Shared/WidgetDebug/WidgetEntries.swift`（App / Widget 双 target 共用，
/// 供主 App 的 `SunArcFace` 与本文件的 Provider 引用同一份类型）。
/// 下面这个工厂依赖 Widget-only 的 `WeatherCardPayload`，继续只在
/// 本文件（Widget target）编译；主 App 侧调试面板用预设注入自造 entry，不需要它。
extension SunArcEntry {

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
        // 天气数值只在**同一天**采信（理由同上：`dayKey` 挡住跨天的旧值）
        let weather = payload?.dayKey == dayKey ? payload : nil
        return SunArcEntry(
            date: date,
            phase: SunClock.phase(at: date),
            sunrise: actual?.0 ?? computed?.sunrise,
            sunset: actual?.1 ?? computed?.sunset,
            temp: weather?.temp,
            weatherText: weather?.text,
            tMax: weather?.tMax,
            tMin: weather?.tMin
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


// MARK: - 组件注册

/// 日弧卡（3.10.0 新组件，3.12.0 补大号）。
///
/// **家族表**：systemSmall / systemMedium / systemLarge / accessoryRectangular / accessoryInline。
/// - 中号 = 小号 + 一行倒计时（弧 + 两个时刻 + 倒计时，已是完整闭环）；
/// - 大号（3.12.0，任务书要求）= 更长的弧 + 更大的太阳点 + 22pt 两端时刻 +
///   17pt「距日落 x 小时」+ 底部「今日天气一句」。这三样**中号没有**，
///   所以它不是"把小卡放大"，而是"多了一层内容"（DESIGN-RULES §3）。
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
        .supportedFamilies([.systemSmall,
                            .systemMedium,
                            .systemLarge,
                            .accessoryRectangular,
                            .accessoryInline])
        // 底色铺到四边（与天光 / 简报卡同一纪律，否则外围一圈系统色像"卡中卡"）
        .contentMarginsDisabled()
    }
}
