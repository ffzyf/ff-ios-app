import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// 天光实时活动的 attributes + 状态。
///
/// **这个文件被两个 target 各编译一次**（主 App 与 Widget 扩展），与
/// `SunEventActivityAttributes.swift` 同一套路：ActivityKit 以 `activity id`
/// 为键跨进程匹配，attributes 只是解码载体，两边类型同名同构即可。
///
/// 两条硬约束（违反会编译不过或运行期崩）：
/// 1. `ContentState` 必须 `Codable & Hashable`（ActivityKit 的协议要求）；
/// 2. 只放**纯数据**：不引 UIKit、不引 SwiftUI、不碰 App 的 Store（Widget 进程里都没有）。
struct DaylightActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// 日出（当天，北京时间）。端点必须稳定：`ProgressView(timerInterval:)` 的区间从这里来
        var sunrise: Date
        /// 日落（当天）。同时是"这次活动最晚该结束的时刻"的上界
        var sunset: Date
        /// 本次活动窗口的上界 = min(sunset, 创建时刻 + 8h)。`staleDate` 用它
        var windowEnd: Date
        /// WMO 4677 天气代码原语。nil = 没拿到天气（不渲染任何天气元素）
        ///
        /// **为什么是 `Int?` 而不是 `WeatherKind`**：
        /// 1. `WeatherKind` 是 `String` 原始值的 `enum`，`JSONDecoder` 解到未知 case
        ///    会走 `RawRepresentable` 合成实现直接抛错；`ContentState` 解码失败 =
        ///    这次 `update` 整个失败 = 卡片停在旧内容上不动，且 ActivityKit 不抛给调用方。
        ///    将来服务端多给一个 WMO 代码、或 App 与 Widget 安装版本错位一天，就会"卡片冻住"。
        /// 2. `Int` 是原语，任何版本都能解；`WeatherKind.from(code:)` 本来就把未知码返回 `nil`
        ///    （那个函数的设计意图就是"认不出就不画天气"）。所以中转用 `Int?`，视图里再翻译 ——
        ///    数据层用原语，画法层用枚举，这条分界在工程里已经用过一次（`Monitor.swift` 的
        ///    原始字符串时间戳）。
        var weatherCode: Int?
        /// 服务端给的中文描述（"小雨"）。有就上屏，没有就不渲染这一格
        var weatherText: String?
        /// 气温（℃）。nil = 不渲染
        var tempC: Double?
    }

    /// 当天日期文案（"10月31日 周六"）。创建后不变
    var dayText: String
}

// MARK: - 偏好键

/// 天光实时活动相关的本地偏好键。
///
/// 为什么单独一个 `enum` 而不是挂在 `DaylightActivityCoordinator` 上：
/// `UserDefaults` 的键会被 `@AppStorage` 用到，而 `@AppStorage(...)` 的参数在
/// View 的属性初始化器里求值（非隔离上下文）；`DaylightActivityCoordinator` 是 `@MainActor`
/// 的类，它的 `static let` 也带主 actor 隔离 —— 直接引用会编译不过（Swift 6）
/// 或至少告警（Swift 5）。把这个纯字符串常量放在**非隔离的** Shared 里，
/// 主 App 与设置页都能安全取用。
enum DaylightSettings {
    /// 设置里「天光实时活动」的开关键。
    /// **默认关闭**（新增的常驻型活动，不替用户做主）
    static let storageKey = "skyLightLiveActivity"
}
