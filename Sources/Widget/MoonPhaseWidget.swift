import SwiftUI
import WidgetKit


// MARK: - MoonPhaseEntry 工厂方法

/// 5.1.2 · T03：`MoonPhaseEntry` 的值类型定义、`MoonPhaseMath` 纯天文计算
/// 已抽到 `Sources/Shared/WidgetDebug/WidgetEntries.swift`（App / Widget 双 target
/// 共用）；`MoonDisc` / `MoonPhaseFace` 纯平移到 `MoonPhaseFace.swift`。
/// 下面这个工厂继续只在本文件（Widget target）编译。
extension MoonPhaseEntry {

    static func make(date: Date) -> MoonPhaseEntry {
        let age = MoonPhaseMath.age(on: date)
        return MoonPhaseEntry(date: date,
                              age: age,
                              illumination: MoonPhaseMath.illumination(age),
                              name: MoonPhaseMath.name(age))
    }
}


/// 月相卡的 Timeline：**6 小时一帧、铺 24 小时、`.atEnd` 重取，零网络请求**。
///
/// 为什么敢比别的卡更省：月相一天变约 2% 照明度 —— 6 小时一帧（4 帧）的变化量
/// 连 1% 都不到，肉眼完全无差。这是"刷新预算"意义上的极端奢侈：
/// 它一天 0 次网络、`getTimeline` 一天 1 次，全部预算留给联网的卡。
struct MoonPhaseProvider: TimelineProvider {

    /// 帧距（6 小时）
    static let gridStep: TimeInterval = 6 * 3600
    /// 视野（24 小时）
    static let horizon: TimeInterval = 24 * 3600

    func placeholder(in context: Context) -> MoonPhaseEntry {
        return MoonPhaseEntry.make(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (MoonPhaseEntry) -> Void) {
        completion(MoonPhaseEntry.make(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoonPhaseEntry>) -> Void) {
        let now = Date()
        let stamps = WidgetTimeline.stamps(now: now, horizon: Self.horizon, step: Self.gridStep)
        let entries = stamps.filter { $0 >= now }.sorted().map { MoonPhaseEntry.make(date: $0) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}


// MARK: - 组件注册

/// 月相卡（3.10.0 新组件，3.12.0 补大号）。纯本地计算（见 `MoonPhaseMath`），永不因网络失败而空白。
struct MoonPhaseWidget: Widget {

    /// WidgetKit 用 kind 匹配已上桌的实例，改名等于让所有用户的小组件失效
    static let kind = WidgetTheme.Moon.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MoonPhaseWidget.kind, provider: MoonPhaseProvider()) { entry in
            MoonPhaseFace(entry: entry)
        }
        .configurationDisplayName(WidgetTheme.Moon.displayName)
        .description(WidgetTheme.Moon.description)
        .supportedFamilies([.systemSmall,
                            .systemLarge,
                            .accessoryCircular,
                            .accessoryRectangular,
                            .accessoryInline])
        .contentMarginsDisabled()
    }
}
