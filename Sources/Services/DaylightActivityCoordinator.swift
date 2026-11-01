import ActivityKit
import Foundation
import WidgetKit

/// 天光实时活动的生命周期（设计文档 §1.2 / §1.3，**只在主 App**）。
///
/// 它是全工程第二个实时活动。与红石的关系是**互斥、红石优先**：
/// 红石是"20 分钟后有个限时场次"，天光是"现在天色如何"——前者等不起，后者等得起。
///
/// 五条硬规则，逐条对应 `evaluate(now:)` 里的守卫：
/// 1. **仅前台**：ActivityKit 不允许后台自行拉起活动，循环由 `.task(id: scenePhase)` 驱动；
/// 2. **默认关闭 + 系统能力**：任一不满足就收掉已有的活动并原地返回；
/// 3. **红石占用 → 立刻收**（`.immediate`）：两个活动同屏会被系统折叠成一组，
///    用户点开看到的是一团乱；也正因为如此，红石那里（见 `LiveActivityCoordinator.start`）
///    成功后会回调 `suspendForRock()`，不等下一个 tick；
/// 4. **窗口上界 = min(deadline, 创建 + 8h)**，在**创建那一刻**定死
///    （deadline 由调用方给：白天 = 日落，夜间手动启动 = 下一阶段边界，见 `startNow()`）。
///    不能每次按 `now + 8h` 算 —— 那永远到不了点，卡片就变常驻了；
/// 5. **同一时刻只允许 1 个**：已有自己的活动就只做心跳 update，不再开第二个。
///
/// 为什么查红石活动用 `activityState` 过滤而不是"列表非空"：红石退后台时用的是
/// `.after(endAt)` 的收尾策略，那之后活动**仍留在 `Activity.activities` 里**直到系统真的
/// 把它从锁屏撤下。只判 `isEmpty` 会让天光被一个"已经结束但还没被撤下"的活动**永久阻塞**。
/// （同理适用于自己：只处理 `.active` / `.stale`。）
///
/// 3.10.0 追加：`isIslandActive` / `refreshActivityState()` —— 设置页的「天光灵动岛」
/// 从纯 Toggle 改成**状态跟随型按钮**后的状态源（见 `DaylightActivitySection`）：
/// 按钮文案读的是"活动此刻是否真的在屏幕上"（红石占用 / 系统收掉 / 窗口过期都会让
/// 实际状态偏离存储里的开关意图），不是"用户上次把开关拨到了哪边"。
/// 因此它必须可观察（`ObservableObject`），且在每个改活动生命的出口顺手刷新。
@MainActor
final class DaylightActivityCoordinator: ObservableObject {

    /// 全 App 唯一实例（`FFWangApp` 的 `.task` 与设置页直接读同一个）
    static let shared = DaylightActivityCoordinator()

    /// 开关的存储键（定义在 Shared 的 `DaylightSettings` 里，见那里的注释：
    /// `@MainActor` 类的 `static let` 不能直接喂给 `@AppStorage`）
    static let storageKey: String = DaylightSettings.storageKey

    /// 前台循环的 tick（秒）：活动窗口是数小时量级，1 分钟粒度足够，也不费电
    static let tickSeconds: TimeInterval = 60
    /// 单次窗口上限（秒）：8 小时 —— 系统允许的最长活跃时长。
    /// 北京夏天日出到日落 15 小时，任何一种"日出到日落"的活动都必然超时，
    ///    写死 8h 是为了让"卡片消失的时刻"永远可预测（创建时刻 + 8h），
    ///    而不是"有时候 8 小时、有时候 15 小时"
    static let maxWindowSeconds: TimeInterval = 8 * 3600
    /// 距日落不足这么多秒就不启动（§1.3）：日落前 8 分钟开一张锁屏卡，
    /// 用户扣下手机它就消失了 —— 开了等于没开，还多耗一次 request
    static let minimumRemainSeconds: TimeInterval = 10 * 60
    /// 心跳间隔（秒）：间隔到了、或天气值变了才 `update`，其余 tick 一个字节都不多推
    static let heartbeatSeconds: TimeInterval = 600

    // MARK: - 状态

    /// 是否在前台。由 `monitorForeground` 自己维护
    private(set) var isForeground: Bool = false

    /// 天光活动此刻是否真的显示在灵动岛 / 锁屏上（3.10.0，设置页按钮的状态源）。
    ///
    /// 判据与 `runningActivities()` 同源：列表里有 `.active` / `.stale` 的活动才算"显示中"
    /// —— `.ended` / `.dismissed` 的残影不算（理由见文件头"为什么不用 isEmpty"）。
    /// 它跟随**实际状态**而不是存储里的开关：红石占用、窗口过期、系统收掉，
    /// 都会让"开关是开的"与"屏幕上没有"同时成立 —— 按钮必须说真话的那一边。
    @Published private(set) var isIslandActive: Bool = false

    /// 最近一次启动 / 更新失败的原因（只用于内部诊断，不上屏）
    private(set) var lastErrorDescription: String?

    /// 最近一次成功启动活动的时刻（诊断用：它决定下一次 start 的 8 小时预算起点）
    private var lastStartAt: Date?
    /// 最近一次 `update` 的时刻。App 被杀重启后会是 nil —— 那时第一次 tick 一定补一次 update
    private var lastUpdateAt: Date?
    /// 上一次写进活动的天气指纹（值变了才值得推一次 update）
    private var lastWeatherSignature: String = ""
    /// 上一次写进活动时的天光阶段（`SunClock.phase` 七档）。
    ///
    /// 3.8.1 新增：tick 的心跳路径用它做**阶段变更检测** —— 蓝调→日出→黄金→白天→
    /// 日落→蓝调→夜的每一次换档，卡片颜色 / 阶段名 / 倒计时目标都要跟着变，
    /// 不能等 10 分钟心跳。视图层虽然按 `Date()` 现算，但系统不重绘就什么都看不到；
    /// 换档立刻 `activity.update` 是唯一可靠的"定点切换"。App 被杀重启后为 nil，
    /// 第一次 tick 会当作"变了"补一次 update（与 `lastUpdateAt == nil` 时 `due == true` 同理）。
    private var lastPhase: SkyPhase?

    /// `init` 必须 `nonisolated`：整类被 `@MainActor` 隔离后，合成的 init 也是默认的
    /// 隔离成员，而 `static let shared` 的惰性初始化发生在**非隔离上下文**里
    /// （`Swift` 的全局 / 静态属性惰性求值带 `@MainActor` 时会在调用点 hop，
    /// 显式标 `nonisolated` 才能避免 Xcode 报 "cannot be constructed because ..."）。
    nonisolated init() {
        // 冷启动也刷一次状态（3.10.0）：设置页按钮第一次出现之前，
        // `isIslandActive` 就该是对的（App 被杀重启后残留的活动仍可能显示着）。
        // init 是 nonisolated，所以借 Task 跳回主线程；Task 在 init 返回之后才跑，
        // 那时 `shared` 已初始化完成，不会递归。
        Task { @MainActor in
            DaylightActivityCoordinator.shared.refreshActivityState()
        }
    }

    // MARK: - 活动状态（3.10.0）

    /// 按 `Activity<DaylightActivityAttributes>.activities` 重算 `isIslandActive`。
    ///
    /// 为什么用**查询**而不是在 start / end 处手工置位：ActivityKit 的状态由系统管理
    /// （系统可以自己收掉活动、红石可以让位），任何"只在我们的代码里改标志"的写法
    /// 都会出现标志与真实状态分叉的那一刻 —— 查询是唯一不会说谎的来源。
    /// 成本可忽略（一次进程内列表读）。
    ///
    /// 调用点：init（冷启动）、`evaluate`（60 秒 tick 尾部）、`startNow`、`endAll`，
    /// 以及设置页 `.task` / scenePhase 回前台（前台回来状态要跟上）。
    func refreshActivityState() {
        isIslandActive = !Self.runningActivities().isEmpty
    }

    /// 设置里的「天光实时活动」开关。
    ///
    /// **没设置过默认关闭**：天光是新增的**常驻型**活动（白天一直占着灵动岛 / 锁屏），
    /// 不替用户做主。`bool(forKey:)` 对没写过的键天然返回 `false`，
    /// 所以这里不需要 `object(forKey:) == nil` 那种分支（红石那边需要，因为它的默认相反）。
    var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: Self.storageKey)
    }

    // MARK: - 前台循环

    /// 前台期间每 60 秒评估一次：该启动就启动、该收就收、该心跳就心跳。
    ///
    /// 循环放在这里而**不用 `Timer`**（与 `LiveActivityCoordinator` 同一条理由）：
    /// `Timer` 在 App 退后台之后仍然"存在"，而 ActivityKit 的活动只允许前台请求 ——
    /// 留着它只会造成"看起来在跑但其实什么都做不了"。
    /// 由视图的 `.task(id: scenePhase)` 驱动：scenePhase 变化 → 旧任务取消 → 循环退出。
    ///
    /// 天光**不需要任何外部数据**（不像红石要排期），所以这里刻意没有 `daysProvider`
    /// 那类闭包参数：日出日落在 `SunClock` 里现算，太阳算法是纯函数。
    func monitorForeground() async {
        isForeground = true
        defer {
            // 退后台：**什么都不做**（§1.3）。既不 end 也不 update —— 不像红石那样排
            // `dismissalPolicy`，因为天光的收尾已经由 `windowEnd` 的 staleDate +
            // 系统 12 小时上限兜住了，而用户下次回前台它自己会接回来。
            isForeground = false
        }

        while !Task.isCancelled {
            // 每个 tick 重读开关：用户在设置页关掉开关要能在 ≤60 秒内生效
            // （关那一瞬间由设置页直接 `endAll()`，这里只是兜住"别处改了值"的情况）
            if isEnabled {
                evaluate(now: Date())
            }
            // `try?` 而不是 `do/catch`：睡眠被取消是**正常退出路径**，下一次循环条件
            // `Task.isCancelled` 会拦住它，不值得为它写一个 catch 分支
            try? await Task.sleep(nanoseconds: Self.tickNanoseconds)
        }
    }

    /// 一个 tick 的纳秒数。**由 `tickSeconds` 派生**，不另写一份 `60 * 1_000_000_000` ——
    /// 两份就一定会漂成"改了秒忘了纳秒"。
    /// 显式写全类型名：static 存储属性初始化器里不能引用协变 `Self`
    /// （3.8.0 CI 编译错误 `covariant 'Self' type cannot be referenced from a stored
    /// property initializer` 的修法 —— 存储属性初始化发生在类型尚未完全成形的时候，
    /// `Self` 在那里是协变的、不可引用，只有具体类型名是安全的）。
    private static let tickNanoseconds: UInt64 = UInt64(DaylightActivityCoordinator.tickSeconds) * 1_000_000_000

    // MARK: - 评估

    /// 评估一次「现在该不该有天光活动」。纯前台同步动作，可被循环反复调用。
    ///
    /// 3.10.0：`defer` 顺手刷新 `isIslandActive` —— evaluate 的每条分支
    /// （收掉已有 / 启动新活动 / 什么都不做）都可能改变活动集合，包装层统一刷新，
    /// 就不必在每个 return 前各补一句（漏一处就是一次状态失真）。
    func evaluate(now: Date = Date()) {
        defer { refreshActivityState() }
        evaluateRules(now: now)
    }

    /// evaluate 的规则本体（3.10.0 从 `evaluate` 拆出，逻辑一字未改 ——
    /// 拆是为了让外层统一挂"结束后刷新状态"这一件事）。
    private func evaluateRules(now: Date) {
        // 规则 1：仅前台
        guard isForeground else { return }

        // 规则 2：开关 / 系统能力。任一不满足 → 收掉已有的，然后什么都不做
        guard isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            endAll()
            return
        }

        // 规则 3：红石在跑 → 立刻收（红石优先，见文件头）
        guard !Self.isRockOccupying() else {
            endAll()
            return
        }

        // 先把过了窗口上界的收掉（可能是 App 被杀之后残留的活动）
        endExpired(now: now)

        // 规则 5：已经有自己在跑的活动 → 只做心跳 update，绝不开第二个
        if let existing = Self.runningActivities().first {
            heartbeat(existing, now: now)
            return
        }

        // 规则 4 的第一个前提：算不出日出日落（极昼 / 极夜）就不启动 —— 不假装有太阳
        guard let today = SunClock.times(on: now) else { return }

        // 夜里不启动（§6 待明确事项 ① 的推荐项）：夜里没有太阳可画，
        // 卡片只剩一片近黑 + 一个"距日出 7 小时"的倒计时，而灵动岛是稀缺资源
        guard SunClock.phase(at: now) != .night else { return }

        // 已日落、或距日落不足 10 分钟 → 这次不启动
        guard today.sunset > now,
              today.sunset.timeIntervalSince(now) >= Self.minimumRemainSeconds else { return }

        start(sunrise: today.sunrise, sunset: today.sunset, deadline: today.sunset, now: now)
    }

    // MARK: - 红石占用

    /// 红石是否正在占用灵动岛 / 锁屏。
    ///
    /// 天光自己查红石的活动列表，而不是与 `LiveActivityCoordinator` 共享一个 busy 标志：
    /// 跨类型查活动是 ActivityKit 的公开能力，一个静态查询就够；引入共享标志就有了两份
    /// 真相（"App 被杀之后那个标志会不会残留？"是一个不需要问的问题）。
    static func isRockOccupying() -> Bool {
        // `.active` / `.stale` 算占用：它们都还显示在屏幕上。
        // `.ended` / `.dismissed` 不算 —— 见文件头"为什么不用 isEmpty"
        return Activity<SunEventActivityAttributes>.activities.contains {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    /// 自己仍在屏幕上的活动（同样按 `.active` / `.stale` 过滤）
    private static func runningActivities() -> [Activity<DaylightActivityAttributes>] {
        return Activity<DaylightActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    // MARK: - 对外动作

    /// 红石开跑 → 天光立刻收（`LiveActivityCoordinator.start(_:)` 成功后调用）。
    ///
    /// 行为上与 `endAll()` 完全一致，单独命名是为了让调用点读得出"为什么"
    /// （调用方那里写的是红石的代码，不写这句语义不明）。
    func suspendForRock() {
        endAll()
    }

    /// 用户在设置页打开开关那一刻的**显式立即启动**（3.8.2）。
    ///
    /// 与 `evaluate(now:)` 的自动启动是两回事：evaluate 是"App 替用户决定要不要常驻"，
    /// 这里是"用户点了开关就是要『立马出现在灵动岛上』"——等下一次 60 秒 tick，
    /// 开关就成了假开关。因此：
    /// - **保留硬规则**：开关、系统能力、红石优先（红石占用时写 `lastErrorDescription`
    ///   说明原因并返回——红石是"20 分钟后有个限时场次"，等不起，铁律不破）；
    /// - **刻意跳过两条自动启动守卫**（它们只对"自动"成立，不是被"绕过"）：
    ///   1. "夜里不启动"：夜里没有太阳可画，是针对**自动常驻**的成本考量；
    ///      夜里手动开，用户就是要看那张夜间卡（近黑天色 + 距日出倒计时）；
    ///   2. "距日落不足 10 分钟不启动"：那条是为了**自动启动**省一次 request——
    ///      即将过期的窗口不值得常驻；而用户手点的每一次 request 都是明确要花的。
    ///
    /// 同步方法（无 await）：设置页的按钮动作直接调，不需要包 `Task { }`。
    ///
    /// 3.10.0：`defer` 顺手刷新 `isIslandActive`（与 `evaluate` 同一包装手法）——
    /// startNow 的每条出口（心跳已有 / 红石占用返回 / 真启动）之后按钮状态都要跟上。
    func startNow() {
        defer { refreshActivityState() }
        startNowRules()
    }

    /// `startNow` 的规则本体（3.10.0 从 `startNow` 拆出，逻辑一字未改）。
    private func startNowRules() {
        // 硬规则 2：开关 / 系统能力。任一不满足就什么都不做
        //（与 evaluate 不同：evaluate 会顺手收掉已有活动，这里是"打开"方向的意图，
        // 能力不存在时活动也不存在，无事可收）
        guard isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // 硬规则 3：红石优先。不收自己的活动也不报错给 UI——
        // 红石结束后下一次 tick / 下次回前台，evaluate 会自动把天光接回来
        guard !Self.isRockOccupying() else {
            lastErrorDescription = "红石占用中，结束后天光自动回来"
            return
        }

        let now = Date()

        // 先收掉过了窗口上界的残留（App 被杀之后可能留下），
        // 避免"过期残影 + 新活动"在同一块锁屏上短暂并存
        endExpired(now: now)

        // 硬规则 5：已有自己在跑的活动 → 立即心跳一次，绝不开第二个。
        // 这里绕过 heartbeat 的 10 分钟节流是刻意的：用户刚点开关，
        // "值没变"不能成为"点了没反应"的理由——这是显式意图，不是例行 tick
        if let existing = Self.runningActivities().first {
            heartbeat(existing, now: now)
            return
        }

        // 算不出日出日落（极昼 / 极夜）就不启动 —— 与 evaluate 同一条"不假装有太阳"
        guard let today = SunClock.times(on: now) else { return }

        // 窗口语义终点（deadline）：白天还有日落就用日落；夜里日落已过，
        // 倒计时口径 = 距下一阶段边界（与 Widget 侧 `SkyLightEntry` 一致）。
        // 兜底不用 today.sunset：走到这里说明日落已过，today 有值但前后一天
        // times 缺失且当日边界全部过点时，传入的 sunset 是已过期时刻
        // （windowEnd <= now），卡片一创建就 stale。改给足 8 小时窗口——
        // 算不准就放最宽，后续由 endExpired 与 60 秒 tick 兜住收尾。
        // 注：当前坐标硬编码北京，nextPhaseBoundary 不会返回 nil，该分支不可达；
        // 未来坐标动态化（高纬度可能连续数日算不出边界）后会可达，属预防性加固。
        let deadline: Date
        if today.sunset > now {
            deadline = today.sunset
        } else {
            deadline = Self.nextPhaseBoundary(after: now)
                ?? now.addingTimeInterval(Self.maxWindowSeconds)
        }

        start(sunrise: today.sunrise, sunset: today.sunset, deadline: deadline, now: now)
    }

    /// 关掉全部活动（关开关 / 到点 / 让位给红石，都走这里）。
    ///
    /// 一律 `.immediate`：卡片直接消失，不留"已结束"的残影 ——
    /// 天光不是一条通知，没有需要用户回看的收尾信息。
    func endAll() {
        let running = Activity<DaylightActivityAttributes>.activities
        for activity in running {
            let state = activity.content.state
            let content = ActivityContent(state: state, staleDate: state.windowEnd)
            Task { await activity.end(content, dismissalPolicy: .immediate) }
        }
        // 内部记录一并清干净：下一次 tick 要按"从零开始"判定，
        // 否则残留的 `lastWeatherSignature` / `lastPhase` 会让重启后的第一次
        // update 被"值没变"挡掉
        lastStartAt = nil
        lastUpdateAt = nil
        lastWeatherSignature = ""
        lastPhase = nil
        if !running.isEmpty {
            reloadWidgets()
        }
        // 3.10.0：收完立刻刷新状态 —— 设置页按钮的「关闭」动作就是这里，
        // 不刷的话按钮会显示"关闭中"的旧态直到下一次 60 秒 tick。
        // 但 `activity.end` 本身是异步的（活动要等系统处理完才从列表摘掉），
        // 立刻刷新仍可能读到旧态 —— 所以再延迟 1 秒补刷一次，按钮最迟一秒内跟上。
        refreshActivityState()
        if !running.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self.refreshActivityState()
            }
        }
    }

    // MARK: - 启动

    /// 启动一次活动。`windowEnd` 在这里定死，之后永不改变。
    ///
    /// `deadline` 是这次窗口的**语义终点**，由调用方按场景给：
    /// - `evaluate`（白天自动启动）传 `today.sunset`——卡片跟着太阳走；
    /// - `startNow`（夜间手动启动）传下一阶段边界——夜间卡的倒计时口径与 Widget 一致。
    /// 上界仍由创建时刻 + 8h 兜住：两个取 min，见文件头规则 4。
    /// 3.8.2 前签名只有 sunset，隐含"启动必在白天"的假设——夜间手动启动不成立，故拆出。
    private func start(sunrise: Date, sunset: Date, deadline: Date, now: Date) {
        // min(deadline, 创建 + 8h)：见文件头规则 4
        let windowEnd = min(deadline, now.addingTimeInterval(Self.maxWindowSeconds))
        let weather = Self.currentWeather()

        let state = DaylightActivityAttributes.ContentState(
            sunrise: sunrise,
            sunset: sunset,
            windowEnd: windowEnd,
            weatherCode: weather?.code,
            weatherText: weather?.text,
            tempC: weather?.temp
        )
        // 日期文案放 attributes：创建后不变，不参与 update 的 diff
        let attributes = DaylightActivityAttributes(dayText: Formatters.todayHeader(now))
        // staleDate = 窗口上界：到点之后系统把它标记为过期（视觉上提示"数据不再更新"）
        let content = ActivityContent(state: state, staleDate: windowEnd)

        do {
            // pushType: nil —— 本版没有服务端 push-to-start，走本地 request
            _ = try Activity<DaylightActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            lastErrorDescription = nil
            lastStartAt = now
            lastUpdateAt = now
            lastWeatherSignature = Self.signature(of: weather)
            lastPhase = SunClock.phase(at: now)
            reloadWidgets()
        } catch {
            // 启动失败（系统限制 / 用户在设置里关了实时活动）不该影响 App 任何功能
            lastErrorDescription = error.localizedDescription
        }
    }

    // MARK: - 心跳

    /// 保活更新（§1.3）：只有「距上次 update ≥ 10 分钟」「天气值变了」或「阶段变了」才推。
    ///
    /// 为什么不是每 tick 都推：update 是带唤醒成本的推送帧。太阳位置与天色由视图按
    /// `Date()` **现算**，update 唯一要送的是**本进程之外拿不到的东西** —— 天气，
    /// 以及"到下一阶段边界该重绘"这个提示（staleDate）。
    ///
    /// 3.8.1 追加的阶段变更路径：换档（蓝调→日出→黄金→白天→日落→蓝调→夜）那一刻
    /// 卡片的颜色 / 阶段名 / 倒计时目标同时变，**不受 `heartbeatSeconds` 节流** ——
    /// 太阳落了卡片还蓝着 10 分钟，是用户看得见的错。
    /// 同时把 `staleDate` 设为下一阶段边界（不越过窗口上界）：让系统知道
    /// "到这一刻数据该翻篇"，而不是把整段窗口当成一次性的过期提示。
    private func heartbeat(_ activity: Activity<DaylightActivityAttributes>, now: Date) {
        let weather = Self.currentWeather()
        let signature = Self.signature(of: weather)
        let phase = SunClock.phase(at: now)
        let due = lastUpdateAt.map { now.timeIntervalSince($0) >= Self.heartbeatSeconds } ?? true
        let phaseChanged = (lastPhase != phase)
        guard due || signature != lastWeatherSignature || phaseChanged else { return }

        var state = activity.content.state
        state.weatherCode = weather?.code
        state.weatherText = weather?.text
        state.tempC = weather?.temp

        let boundary = Self.nextPhaseBoundary(after: now) ?? state.windowEnd
        let content = ActivityContent(state: state, staleDate: min(boundary, state.windowEnd))
        Task { await activity.update(content) }

        lastUpdateAt = now
        lastWeatherSignature = signature
        lastPhase = phase
    }

    // MARK: - 阶段边界

    /// 严格晚于 `now` 的下一个天光阶段边界时刻。
    ///
    /// **跨 target 的复制表，必须同步**：权威出处是 Widget 侧的
    /// `SkyLightEntry.nextPhaseBoundary(after:on:)`（Sources/Widget/SkyLightProvider.swift），
    /// 但 `Sources/Services` 不编译 Widget target，这里只能复制一份。七个偏移
    /// （日出 −24min / 日出 / +24min / +70min；日落 −70min / 日落 / +30min）
    /// 与 `SunClock.phase(at:)` 的判定阈值、与 Widget 侧那张表**逐条一一对应** ——
    /// 改任何一处必须三处同步，否则会出现"卡片换档了、staleDate 还没到"。
    /// 取前后各一天共三天的边界再筛 `> now` 取最小：跨子夜、跨年都不需要特殊分支。
    private static func nextPhaseBoundary(after now: Date) -> Date? {
        var candidates: [Date] = []
        for offset in [-1, 0, 1] {
            guard let day = RedstoneClock.calendar.date(byAdding: .day, value: offset, to: now) else {
                continue
            }
            guard let times = SunClock.times(on: day) else { continue }
            candidates.append(times.sunrise.addingTimeInterval(-24 * 60))
            candidates.append(times.sunrise)
            candidates.append(times.sunrise.addingTimeInterval(24 * 60))
            candidates.append(times.sunrise.addingTimeInterval(70 * 60))
            candidates.append(times.sunset.addingTimeInterval(-70 * 60))
            candidates.append(times.sunset)
            candidates.append(times.sunset.addingTimeInterval(30 * 60))
        }
        return candidates.filter { $0 > now }.min()
    }

    // MARK: - 收尾

    /// 收掉已经过了窗口上界的活动（`windowEnd` 在创建时已定死）。
    private func endExpired(now: Date) {
        let expired = Activity<DaylightActivityAttributes>.activities.filter {
            now >= $0.content.state.windowEnd
        }
        guard !expired.isEmpty else { return }
        for activity in expired {
            let state = activity.content.state
            let content = ActivityContent(state: state, staleDate: state.windowEnd)
            Task { await activity.end(content, dismissalPolicy: .immediate) }
        }
        reloadWidgets()
    }

    // MARK: - 天气

    /// 此刻的天气。
    ///
    /// **只读 `WeatherStore.shared.current`，不在这里发请求**：协调器由 60 秒一次的前台循环
    /// 驱动，让它触碰网络等于把一次网络往返绑到 UI 心跳上；而 `WeatherStore` 自己在首页
    /// 进也就拉了、内部有 10 分钟缓存 —— 这里的数据本来就在。
    /// 拉不到（首次安装还没拉 / 一直断网）就返回 nil，卡片不画天气元素（缺数据不猜）。
    private static func currentWeather() -> WeatherNow? {
        guard let current = WeatherStore.shared.current, current.ok else { return nil }
        return current
    }

    /// 天气指纹：三个值拼成一个字符串，比逐个比 Optional 简单，也天然可 diff。
    private static func signature(of weather: WeatherNow?) -> String {
        guard let weather else { return "nil" }
        let code = weather.code.map { String($0) } ?? "-"
        let temp = weather.temp.map { String(format: "%.1f", $0) } ?? "-"
        return "\(code)|\(weather.text ?? "-")|\(temp)"
    }

    // MARK: - 小组件

    /// 活动增删之后推一次 Timeline（让桌面组件上的天光与实时活动口径一致）
    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
