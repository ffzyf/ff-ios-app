import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// 红石实时活动的 attributes + 状态。
///
/// **这个文件被两个 target 各编译一次**（主 App 与 Widget 扩展），这是 Apple 官方
/// Live Activity 模板的做法：ActivityKit 以 `activity id` 为键跨进程匹配，
/// attributes 只是解码载体，两边类型同名同构即可。
///
/// 两条硬约束（违反会编译不过或运行期崩）：
/// 1. `ContentState` 必须 `Codable & Hashable`（ActivityKit 的协议要求）；
/// 2. 只放**纯数据**：不引 UIKit、不引 SwiftUI、不碰 App 的 Store（Widget 进程里都没有）。
///
/// 时间戳全部用 `Date`（不是字符串）：这份状态只在内存里活 72 分钟，
/// 不落盘、不跨版本迁移，不需要 `Monitor.swift` 那套「原始字符串」的防御。
struct SunEventActivityAttributes: ActivityAttributes {

    /// 活动期间会变的部分（阶段 / 剩余时间由 UI 按 `startAt`/`endAt` 现算）
    struct ContentState: Codable, Hashable {
        /// `"upcoming"`（尚未落地） | `"ongoing"`（落地后 52 分钟内）
        var phase: String
        /// 地图名。`"待确认"` 表示服务端无点位数据（此时不渲染倍率徽标）
        var map: String
        /// 倍率。`nil` = 待确认，绝不显示「0×」
        var rate: Double?
        /// 落地时刻
        var startAt: Date
        /// 结束时刻。**永远等于 `startAt + 52 分钟`**（PRD §5.4 硬规则，兜底不靠服务端）
        var endAt: Date
        /// 待玩家核对（只降可信度，不参与时间计算）
        var needsCheck: Bool

        /// 活动全程（秒）：落地前 20 分钟 + 落地后 52 分钟 = 72 分钟。
        /// 进度条按这个窗口铺满（PRD §5.4「一条极细进度条（覆盖 72 分钟全程）」）。
        static let leadSeconds: TimeInterval = 20 * 60
        static let durationSeconds: TimeInterval = 52 * 60
        static let totalSeconds: TimeInterval = leadSeconds + durationSeconds

        /// 活动窗口起点 = 落地前 20 分钟
        var windowStart: Date { startAt.addingTimeInterval(-Self.leadSeconds) }
        /// 活动窗口终点（= 场次结束，也就是活动必须消失的时刻）
        var windowEnd: Date { endAt }

        /// 是否已落地（据此决定文案是「还有 N 分钟」还是「进行中 · 剩 N 分钟」）
        func isOngoing(now: Date) -> Bool {
            return now >= startAt
        }

        /// 剩余分钟（向上取整，至少 1 —— 永不显示「剩 0 分钟」）
        func minutesLeft(now: Date) -> Int {
            let remain = (isOngoing(now: now) ? endAt : startAt).timeIntervalSince(now)
            return max(1, Int((remain / 60).rounded(.up)))
        }
    }

    /// 所属自然日（`"2026-10-30"`，北京时区）。创建后不变
    var eventDate: String
    /// 落地时刻原文（`"19:08"`）。创建后不变
    var startTime: String
}

// MARK: - 偏好键

/// 实时活动相关的本地偏好键。
///
/// 为什么单独一个 `enum` 而不是挂在 `LiveActivityCoordinator` 上：
/// `UserDefaults` 的键会被 `@AppStorage` 用到，而 `@AppStorage(...)` 的参数在
/// View 的属性初始化器里求值（非隔离上下文）；`LiveActivityCoordinator` 是 `@MainActor` 的类，
/// 它的 `static let` 也带主 actor 隔离 —— 直接引用会编译不过（Swift 6）或至少告警（Swift 5）。
/// 把这个纯字符串常量放在**非隔离的** Shared 里，主 App 与设置页都能安全取用。
enum SunEventSettings {
    /// 设置里「红石实时活动」的开关键。改它等于让所有用户回到默认（开启）
    static let storageKey = "rockLiveActivity"
}
