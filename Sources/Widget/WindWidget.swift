import SwiftUI
import WidgetKit

// MARK: - 风卡（Wind，3.10.0 新组件）


// MARK: - WindEntry 工厂方法

/// 5.1.2 · T03：`WindEntry` 的值类型定义已抽到
/// `Sources/Shared/WidgetDebug/WidgetEntries.swift`（App / Widget 双 target 共用，
/// 供主 App 的 `WindFace` 与本文件的 Provider 引用同一份类型）。
/// 下面这个工厂依赖 Widget-only 的 `WeatherCardPayload`，继续只在
/// 本文件（Widget target）编译；主 App 侧调试面板用预设注入自造 entry，不需要它。
extension WindEntry {

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
