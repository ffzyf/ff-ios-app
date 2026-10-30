import ActivityKit
import Foundation
import WidgetKit

/// 红石实时活动的生命周期（PRD §5.4，**只在主 App**）。
///
/// 六条硬规则，逐条对应代码里的守卫，改之前先看一眼：
/// 1. **仅前台**：ActivityKit 不允许后台自行拉起活动，`evaluate` 在 `isForeground == false` 时直接返回；
/// 2. **落地前 20 分钟**才启动，且只在窗口内启动（落地之后不回补 —— 不假装有）；
/// 3. **落地时刻必须落在 06:30–22:30**（与推送昼夜规则一致），否则这场不启动；
/// 4. **同一时刻只允许 1 个**：已有活动就只更新，不再开第二个；
/// 5. `endAt = startAt + 52 分钟` **硬编码**，不读服务端/模型里的 `endAt`
///    （模型里的值同样按 52 分钟算，但这条兜底必须写死：万一上游改了口径，
///    活动也不会变成 24 小时常驻 —— PRD 验收第 9 条）；
/// 6. 提供 `endAll()`：关开关、切场、退后台都走它。
///
/// 退到后台时额外做一件事：把仍在跑的活动 `end(content, dismissalPolicy: .after(endAt))`。
/// 这一步是 R19 的真正保险 —— 即使用户把 App 划掉、进程被系统回收，
/// 锁屏上的活动也会在 `endAt` 由系统移除，不需要 App 活着。
@MainActor
final class LiveActivityCoordinator {

    /// 全 App 唯一实例（`FFWangApp` 注入 `@StateObject`、设置页直接读同一个）
    static let shared = LiveActivityCoordinator()

    /// 开关的存储键（定义在 Shared 的 `SunEventSettings` 里，见那里的注释：
    /// `@MainActor` 类的 `static let` 不能直接喂给 `@AppStorage`）
    static let storageKey: String = SunEventSettings.storageKey

    /// 提前量（秒）：落地前 20 分钟启动
    static let leadSeconds: TimeInterval = SunEventActivityAttributes.ContentState.leadSeconds

    /// 单场存活（秒）：落地后 52 分钟结束（= 场次结束时刻）
    static let durationSeconds: TimeInterval = SunEventActivityAttributes.ContentState.durationSeconds

    // MARK: - 昼夜窗口（北京时区，分钟数）

    /// 06:30
    static let dayStartMinute: Int = 6 * 60 + 30
    /// 22:30
    static let dayEndMinute: Int = 22 * 60 + 30

    // MARK: - 状态

    /// 是否在前台。由 `FFWangApp` 的 `scenePhase` 维护
    private(set) var isForeground: Bool = false
    /// 最近一次启动失败的原因（只用于内部诊断，不上屏）
    private(set) var lastErrorDescription: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 设置里的「红石实时活动」开关。**没设置过默认开启**（新用户应该直接有锁屏体验）
    var isEnabled: Bool {
        if defaults.object(forKey: Self.storageKey) == nil { return true }
        return defaults.bool(forKey: Self.storageKey)
    }

    // MARK: - 前台循环

    /// 前台期间每 60 秒评估一次：进窗口就启动、落地就切文案、到点就结束。
    ///
    /// 为什么把循环放在这里而不是用 `Timer`：`Timer` 在 App 退后台之后仍然"存在"，
    /// 而 ActivityKit 的活动只允许前台请求 —— 留着它只会造成"看起来在跑但其实什么都做不了"。
    /// 由视图的 `.task(id: scenePhase)` 驱动，视图消失 → 任务取消 → 循环结束，干净。
    ///
    /// - Parameter daysProvider: 每次 tick 现取一次排期（`RockStore.allLoadedDays`），
    ///   刻意标 `@MainActor`：它读的是主线程上的 Store，闭包体必须与调用点同一个 actor。
    func monitorForeground(daysProvider: @escaping @MainActor () -> [RedstoneDay]) async {
        isForeground = true
        defer {
            isForeground = false
            // 退前台：把还在跑的活动交给系统按 endAt 收尾（R19 的真正保险）
            scheduleDismissalForRunningActivities()
        }

        while !Task.isCancelled {
            if isEnabled {
                evaluate(days: daysProvider(), now: Date())
            }
            do {
                // 60 秒一个 tick：活动窗口是 20 分钟，1 分钟的粒度足够，也不耗电
                try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            } catch {
                break   // 任务被取消（切场景 / 视图销毁）→ 立刻退出，绝不空转
            }
        }
    }

    // MARK: - 评估

    /// 评估一次「现在该不该有活动」。纯前台同步动作，可被循环、场景切换反复调用。
    func evaluate(days: [RedstoneDay], now: Date = Date()) {
        // 规则 1：仅前台
        guard isForeground else { return }

        // 用户关了开关 / 系统关了实时活动：先把已有活动收掉，再什么都不做
        guard isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            endAll()
            return
        }

        let running = Activity<SunEventActivityAttributes>.activities

        // 先把已经过了 endAt 的收掉（可能因为 App 被杀而残留）
        for activity in running where now >= activity.content.state.endAt {
            finish(activity, state: activity.content.state, dismissAfter: now)
        }

        // 规则 4：同一时刻只允许 1 个。已有活动就只更新文案，不再开第二个
        if let existing = Activity<SunEventActivityAttributes>.activities.first {
            var state = existing.content.state
            let phase = state.isOngoing(now: now) ? "ongoing" : "upcoming"
            if state.phase != phase {
                state.phase = phase
                update(existing, state: state)
            }
            return
        }

        // 规则 2 + 3：只有「落地前 20 分钟」且「落地时刻在 06:30–22:30」的场次才启动
        guard let target = startCandidate(in: days, now: now) else { return }
        start(target)
    }

    /// 关掉全部活动（关开关 / 切场 / 退后台前手动收尾都走这里）
    func endAll() {
        let running = Activity<SunEventActivityAttributes>.activities
        guard !running.isEmpty else { return }
        for activity in running {
            let state = activity.content.state
            let content = ActivityContent(state: state, staleDate: state.endAt)
            Task { await activity.end(content, dismissalPolicy: .immediate) }
        }
        reloadWidgets()
    }

    // MARK: - 候选场次

    /// 满足启动条件的第一场（按落地时刻升序，取最早的那一场）
    ///
    /// 条件三连（缺一不可）：
    ///   · `now` 落在 `[startAt - 20min, startAt)` 里 —— 已经落地的场次不回补；
    ///   · 落地时刻的北京时间为 06:30–22:30；
    ///   · 数据没有待确认标记也无所谓（`needsCheck` 只降可信度，不阻止提醒）。
    private func startCandidate(in days: [RedstoneDay], now: Date) -> Occurrence? {
        let occurrences = RedstoneTimeline.occurrences(in: days)
        for occurrence in occurrences {
            let windowOpen = occurrence.startAt.addingTimeInterval(-Self.leadSeconds)
            guard now >= windowOpen, now < occurrence.startAt else { continue }
            guard Self.isWithinDayWindow(occurrence.startAt) else { continue }
            return occurrence
        }
        return nil
    }

    /// 落地时刻是否落在 06:30–22:30（北京时区）。
    ///
    /// 端点边界按"含头不含尾"处理：恰好 22:30 落地算窗口外（与「22:30 后合并到次日」一致），
    /// 恰好 06:30 落地算窗口内。
    static func isWithinDayWindow(_ date: Date) -> Bool {
        let parts = RedstoneClock.calendar.dateComponents([.hour, .minute], from: date)
        let minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minuteOfDay >= dayStartMinute && minuteOfDay < dayEndMinute
    }

    // MARK: - 启动 / 更新 / 结束

    /// 启动一场活动。
    ///
    /// `endAt` 在这里**重新算一遍**（`startAt + 52 分钟`），刻意不用 `occurrence.endAt`：
    /// 这条硬编码是 PRD 验收第 9 条（"活动在场次结束后自动消失，不会变成 24 小时常驻"）的兜底。
    private func start(_ occurrence: Occurrence) {
        let startAt = occurrence.startAt
        let endAt = startAt.addingTimeInterval(Self.durationSeconds)

        let state = SunEventActivityAttributes.ContentState(
            phase: "upcoming",
            map: occurrence.map,
            rate: occurrence.rate,
            startAt: startAt,
            endAt: endAt,
            needsCheck: occurrence.needsCheck
        )
        let attributes = SunEventActivityAttributes(
            eventDate: occurrence.date,
            startTime: occurrence.time
        )
        // `staleDate` 显式给 endAt：系统在这之后会把状态标记为过期（视觉上提示"数据不再更新"）
        let content = ActivityContent(state: state, staleDate: endAt)

        do {
            // `pushType: nil` 写全：本版没有服务端 push-to-start，走本地 request
            _ = try Activity<SunEventActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            lastErrorDescription = nil
            reloadWidgets()
        } catch {
            // 启动失败（系统限制 / 用户在设置里关了实时活动）不该影响 App 的任何功能
            lastErrorDescription = error.localizedDescription
        }
    }

    /// 更新已有活动的状态（阶段从 upcoming → ongoing 时调用）
    private func update(_ activity: Activity<SunEventActivityAttributes>, state: SunEventActivityAttributes.ContentState) {
        let content = ActivityContent(state: state, staleDate: state.endAt)
        Task { await activity.update(content) }
    }

    /// 结束一场活动，并指定"什么时候从锁屏消失"。
    private func finish(
        _ activity: Activity<SunEventActivityAttributes>,
        state: SunEventActivityAttributes.ContentState,
        dismissAfter date: Date
    ) {
        let content = ActivityContent(state: state, staleDate: state.endAt)
        Task { await activity.end(content, dismissalPolicy: .after(date)) }
        reloadWidgets()
    }

    /// 退后台时把仍在跑的活动交给系统按 `endAt` 收尾。
    ///
    /// 这是"App 被划掉也不会留下 24 小时通知"的关键一步：
    /// `dismissalPolicy: .after(endAt)` 由系统计时，不依赖本进程存活。
    private func scheduleDismissalForRunningActivities() {
        let now = Date()
        for activity in Activity<SunEventActivityAttributes>.activities {
            let state = activity.content.state
            guard state.endAt > now else {
                finish(activity, state: state, dismissAfter: now)
                continue
            }
            finish(activity, state: state, dismissAfter: state.endAt)
        }
    }

    // MARK: - 小组件

    /// 排期 / 活动变化后主动推一次 Timeline（PRD §5.3：手动刷新成功后 `reloadTimelines`）
    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
