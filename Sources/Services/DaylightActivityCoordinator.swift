import ActivityKit
import Foundation
import WidgetKit

/// 天光实时活动的生命周期（方案 §1.2 / §1.3，**只在主 App**）。
///
/// 与红石实时活动**互斥**（红石优先）。启动条件：
///   · 开关开
///   · `areActivitiesEnabled`
///   · 红石不占用（`Activity<SunEventActivityAttributes>.activities` 中
///     `activityState == .active` 或 `.stale` 的计数为 0）
///   · `now < sunset`
///   · 剩余 ≥ 10 分钟
///   · 自己的活动列表为空
///
/// `windowEnd = min(sunset, now + 8h)`，`staleDate` 用它。
/// 前台 60 秒 tick 循环；update 只在三个条件任一满足时发：
///   ① `now − lastUpdateAt ≥ 600s`
///   ② 天气值变了
///   ③ `now ≥ windowEnd − 300s`（准备收尾）
///
/// 退后台：不动它（既不 end 也不 update），系统驱动的倒计时/进度条照常走。
/// 回前台：重新 `evaluate`，如果 `now < sunset` 且剩余 ≥10 分钟且列表为空，
/// 重新 `request` 一个新活动（新的 8 小时预算）。
@MainActor
final class DaylightActivityCoordinator {

    /// 全 App 唯一实例。
    static let shared = DaylightActivityCoordinator()

    /// 开关的存储键（定义在 Shared 的 `DaylightSettings` 里，见那里的注释：
    /// `@MainActor` 类的 `static let` 不能直接喂给 `@AppStorage`）
    static let storageKey: String = DaylightSettings.storageKey

    /// 活动最长存活（秒）：8 小时上限（方案 §1.3）。
    static let maxLifetimeSeconds: TimeInterval = 8 * 60 * 60

    /// 启动的最小剩余时间（秒）：日落前少于 10 分钟不开。
    static let minRemainingSeconds: TimeInterval = 10 * 60

    /// update 最短间隔（秒）：10 分钟一次心跳。
    static let updateIntervalSeconds: TimeInterval = 600

    /// 收尾前 5 分钟强制发一次 update，让最后 5 分钟内容是新鲜的。
    static let finalUpdateLeadSeconds: TimeInterval = 300

    // MARK: - 状态

    /// 是否在前台。由 `FFWangApp` 的 `scenePhase` 维护
    private(set) var isForeground: Bool = false
    /// 最近一次启动/更新失败的原因（只用于内部诊断，不上屏）
    private(set) var lastErrorDescription: String?

    /// 上一次成功 update 的时间；用于「距上次 ≥ 600s 才发」的闸门。
    /// nil = 还没发过 update（活动刚 request 出来）。
    private var lastUpdateAt: Date?

    /// 上一次写进 state 的 weatherCode，用于「天气变了才发 update」的闸门。
    private var lastWeatherCode: Int?

    private let defaults: UserDefaults
    private let weatherStore: WeatherStore

    init(defaults: UserDefaults = .standard, weatherStore: WeatherStore = .shared) {
        self.defaults = defaults
        self.weatherStore = weatherStore
    }

    /// 设置里的「天光实时活动」开关。
    /// **默认关闭**（新增的常驻型活动，不替用户做主；`defaults.bool(forKey:)`
    /// 天然返回 false，不需要写 `object(forKey:) == nil` 分支）。
    var isEnabled: Bool {
        defaults.bool(forKey: Self.storageKey)
    }

    // MARK: - 前台循环

    /// 前台期间每 60 秒评估一次：满足启动条件就开、天气变了或到点就更新、日落或 8 小时就结束。
    ///
    /// 写法照抄 `LiveActivityCoordinator.monitorForeground`：
    /// `while !Task.isCancelled` + `try? await Task.sleep`，**不用 `Timer`**；
    /// 由视图的 `.task(id: scenePhase)` 驱动，视图消失 → 任务取消 → 循环结束。
    func monitorForeground() async {
        isForeground = true
        defer {
            isForeground = false
            // 退前台：什么都不做。活动留在锁屏上，系统驱动的倒计时/进度条照常走；
            // 回前台后重新评估，能续就续。
        }

        while !Task.isCancelled {
            if isEnabled {
                evaluate(now: Date())
            } else {
                // 关了开关：立刻收掉
                endAll()
            }
            do {
                // 60 秒一个 tick
                try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            } catch {
                break   // 任务被取消 → 立刻退出，绝不空转
            }
        }
    }

    // MARK: - 评估

    /// 评估一次「现在该不该有天光活动」。纯前台同步动作，可被循环、场景切换反复调用。
    ///
    /// 守卫链（缺一不可，按顺序）：
    /// 1. 仅前台
    /// 2. 开关开
    /// 3. `areActivitiesEnabled`
    /// 4. 红石不占用（`activityState == .active || .stale` 的个数为 0）
    /// 5. `now < sunset`
    /// 6. 剩余 ≥ 10 分钟
    /// 7. 自己的活动列表为空
    func evaluate(now: Date = Date()) {
        guard isForeground else { return }

        guard isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            endAll()
            return
        }

        // 规则 4：红石占用中就收掉自己的，不留重叠窗口
        if isRockOccupied() {
            endAll()
            return
        }

        guard let today = SunClock.times(on: now), now < today.sunset else {
            endAll()
            return
        }
        guard today.sunset.timeIntervalSince(now) >= Self.minRemainingSeconds else {
            endAll()
            return
        }

        let myRunning = Activity<DaylightActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }

        if let existing = myRunning.first {
            // 已有活动：按条件决定要不要 update
            considerUpdate(existing, now: now, today: today)
            return
        }

        // 列表为空 → 启动
        start(now: now, today: today)
    }

    /// 红石是否占用：`Activity<SunEventActivityAttributes>.activities` 中存在
    /// `activityState == .active` 或 `.stale` 的那一个。
    ///
    /// **为什么不用 `isEmpty`**：`end(_:dismissalPolicy:)` 传 `.after(date)` 时
    /// 活动仍然留在 `Activity.activities` 里，直到系统真的把它从锁屏撤下。
    /// 只判 `isEmpty` 会让天光的恢复被一个"已经 ended 但还没被撤下"的活动永久阻塞。
    private func isRockOccupied() -> Bool {
        return Activity<SunEventActivityAttributes>.activities.contains {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    // MARK: - 启动 / 更新 / 结束

    /// 启动一场天光实时活动。
    private func start(now: Date, today: (sunrise: Date, sunset: Date)) {
        let windowEnd = min(today.sunset, now.addingTimeInterval(Self.maxLifetimeSeconds))

        let weather = weatherStore.current
        let state = DaylightActivityAttributes.ContentState(
            sunrise: today.sunrise,
            sunset: today.sunset,
            windowEnd: windowEnd,
            weatherCode: weather?.code,
            weatherText: weather?.text,
            tempC: weather?.temp
        )
        let attributes = DaylightActivityAttributes(
            dayText: Self.dayText(for: now)
        )
        // `staleDate` = windowEnd：到了 8 小时或日落，系统把状态标记为过期
        let content = ActivityContent(state: state, staleDate: windowEnd)

        do {
            _ = try Activity<DaylightActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            lastErrorDescription = nil
            lastUpdateAt = now
            lastWeatherCode = weather?.code
            reloadWidgets()
        } catch {
            lastErrorDescription = error.localizedDescription
        }
    }

    /// 决定是否给现有活动发一次 update。
    ///
    /// 三个条件任一满足就发：
    /// ① 距上次 ≥ 600s
    /// ② 天气值变了
    /// ③ `now ≥ windowEnd − 300s`（准备收尾）
    private func considerUpdate(
        _ activity: Activity<DaylightActivityAttributes>,
        now: Date,
        today: (sunrise: Date, sunset: Date)
    ) {
        let state = activity.content.state
        let weather = weatherStore.current

        let timeGate = lastUpdateAt == nil
            || now.timeIntervalSince(lastUpdateAt!) >= Self.updateIntervalSeconds
        let weatherChanged = (weather?.code ?? nil) != lastWeatherCode
        let finalGate = now >= state.windowEnd.addingTimeInterval(-Self.finalUpdateLeadSeconds)

        guard timeGate || weatherChanged || finalGate else { return }

        // 到 windowEnd 了 → 结束
        guard now < state.windowEnd else {
            finish(activity, state: state, dismissAfter: now)
            return
        }

        var newState = state
        newState.weatherCode = weather?.code
        newState.weatherText = weather?.text
        newState.tempC = weather?.temp

        let content = ActivityContent(state: newState, staleDate: state.windowEnd)
        Task { await activity.update(content) }
        lastUpdateAt = now
        lastWeatherCode = weather?.code
    }

    /// 结束一场活动，并指定"什么时候从锁屏消失"。
    private func finish(
        _ activity: Activity<DaylightActivityAttributes>,
        state: DaylightActivityAttributes.ContentState,
        dismissAfter date: Date
    ) {
        let content = ActivityContent(state: state, staleDate: state.windowEnd)
        Task { await activity.end(content, dismissalPolicy: .after(date)) }
        reloadWidgets()
    }

    /// 关掉全部天光活动（关开关 / 切场 / 被红石让位都走这里）。
    func endAll() {
        let running = Activity<DaylightActivityAttributes>.activities
        guard !running.isEmpty else { return }
        for activity in running {
            let state = activity.content.state
            let content = ActivityContent(state: state, staleDate: state.windowEnd)
            Task { await activity.end(content, dismissalPolicy: .immediate) }
        }
        lastUpdateAt = nil
        lastWeatherCode = nil
        reloadWidgets()
    }

    /// 红石要开始了：天光立刻让道。
    ///
    /// `LiveActivityCoordinator.start(_:)` 成功后调用，让收尾是**立即**的，
    /// 而不是等下一个 tick。`end(.immediate)` + `reloadAllTimelines()`。
    func suspendForRock() {
        endAll()
    }

    // MARK: - 小组件

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - 日期文案

    /// 当天日期文案（"10月31日 周六"），北京时区。
    static func dayText(for date: Date) -> String {
        let cal = RedstoneClock.calendar
        let comps = cal.dateComponents([.month, .day, .weekday], from: date)
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekdayIdx = ((comps.weekday ?? 1) - 1 + 7) % 7
        return "\(month)月\(day)日 \(weekdayNames[weekdayIdx])"
    }
}
