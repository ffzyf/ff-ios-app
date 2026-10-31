import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// 天光实时活动的 attributes + 状态（设计文档 §1.1）。
///
/// **这个文件被两个 target 各编译一次**（主 App 与 Widget 扩展），与
/// `SunEventActivityAttributes.swift` 是同一套路：ActivityKit 以 `activity id` 为键跨进程
/// 匹配，attributes / ContentState 只是解码载体，两边同名同构即可。
///
/// 三条硬约束：
/// 1. `ContentState` 必须 `Codable & Hashable`（`ActivityAttributes` 的协议要求）；
/// 2. 只放**纯数据**：不引 UIKit、不引 SwiftUI、不碰 App 的 Store —— Widget/实时活动进程里
///    没有 `WeatherStore`，天气只能由主 App 写进 state；
/// 3. `weatherCode` 用 `Int?` 而**不是** `WeatherKind`：`WeatherKind` 是 `String` 原始值的
///    枚举，`JSONDecoder` 遇到未知 case 会直接抛错，而 `ContentState` 解码失败 = 这次
///    `update` 静默失败 = 卡片冻在旧内容上（ActivityKit 不把错误抛给调用方）。
///    `Int` 是原语，任何版本都解得开；视图里再用 `WeatherKind.from(code:)` 翻译 ——
///    数据层用原语、画法层用枚举，与 `Monitor.swift` 的「原始字符串时间戳」同一条分界。
///
/// **不放** `sunX` / `sunY` / `phase`：太阳位置由视图每次 `body` 求值时用
/// `SunClock.sunMark(at:on:)` 现算（理由见设计文档 §1.4 —— 纯烘焙要每 6 分钟一次 update
/// 才能不跳，那是滥用配额，且 App 被杀后烘焙值会永久冻结）。
struct DaylightActivityAttributes: ActivityAttributes {

    /// 活动期间会变的四样：两个时间区间 + 天气三件套
    struct ContentState: Codable, Hashable {
        /// 日出（当天，北京时间）。
        ///
        /// 必须进 state：`ProgressView(timerInterval:)` 与 `Text(timerInterval:)` 要一个
        /// **稳定的**区间。每次重绘重算虽然值相同，但区间对象变了会让系统进度条重置到起点
        /// （视觉上是"进度突然回零又追上"）。
        var sunrise: Date

        /// 日落（当天）。同时是"这次活动最晚该结束的时刻"的上界
        var sunset: Date

        /// 本次窗口的上界 = `min(sunset, 创建时刻 + 8h)`。`staleDate` 用它。
        ///
        /// 必须在**创建时**定死，不能每次重绘按 `now + 8h` 算（那永远不会到点，成了常驻）。
        var windowEnd: Date

        /// WMO 4677 天气代码原语。nil = 这次没拿到天气（不渲染任何天气元素）
        var weatherCode: Int?

        /// 服务端给的中文描述（"小雨"）。有就上屏，没有就不渲染这一格
        var weatherText: String?

        /// 气温（℃）。nil = 不渲染
        var tempC: Double?
    }

    /// 当天日期文案（"10月31日 周六"）。创建后不变，不参与 update 的 diff
    var dayText: String
}

// MARK: - 偏好键

/// 天光实时活动的本地偏好键。
///
/// 为什么单独一个 `enum` 而不是挂在 `DaylightActivityCoordinator` 上：与
/// `SunEventSettings` 完全同一个理由 —— `@AppStorage(...)` 的参数在 View 的属性初始化器里
/// 求值（非隔离上下文），而 `DaylightActivityCoordinator` 是 `@MainActor` 类，它的
/// `static let` 带主 actor 隔离，直接在 `@AppStorage` 里引用会编译不过（或至少告警）。
/// 把这个纯字符串常量放在**非隔离的** Shared 里，主 App 与设置页都能安全取用。
enum DaylightSettings {

    /// 设置里「天光实时活动」的开关键。
    ///
    /// **默认关闭是刻意的**：天光是新增的**常驻型**活动（白天一直在灵动岛/锁屏上占位），
    /// 而红石那种"20 分钟后有场次"是事件型的、默认开启才合理。不替用户做主。
    /// `UserDefaults.bool(forKey:)` 对没写过的键天然返回 `false`，所以不需要
    /// `object(forKey:) == nil` 那种分支（红石那边需要，因为它的默认是开启）。
    static let storageKey = "skyLightLiveActivity"
}
