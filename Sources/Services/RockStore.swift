import Combine
import Foundation

/// 红石数据的唯一状态源。
///
/// 职责边界（设计文档 §1.3.1）：Store 只做三件事 —— 发请求、把结果写进 `@Published`、
/// 维护"当前看的是哪个月"。请求与离线降级全部交给批次 1 定稿的 `CachedLoader`，
/// 这里**一行 `URLSession` 都没有**，也没有自己实现的缓存。
///
/// 为什么按月缓存而不是一次拉全部月份：`coveredMonths` 线上有 6 个月，一次拉回来是 180 条
/// （≈40KB）而月历只用得到一个月。按月取 + 按月缓存之后，翻月是一次小请求，回翻直接命中缓存。
///
/// 为什么不能只保留"当前月"一份数据：概览页的红石倒计时卡与月历是两个页面，
/// 用户在月历翻到 11 月时，概览卡仍然要用 **10 月**（今天所在月）的数据算倒计时。
/// 所以内部按 `月份 → 响应` 存字典，`visibleMonth` 只决定月历画哪个月。
@MainActor
final class RockStore: ObservableObject {

    // MARK: - 状态

    /// `"2026-10"` → 该月响应（含 items / updated / coveredMonths / hasNextMonth）
    @Published private(set) var months: [String: RedstoneResponse] = [:]
    /// 月历当前显示的月份
    @Published private(set) var visibleMonth: String
    /// 有请求在飞（首屏骨架 / 翻月按钮态）
    @Published private(set) var isLoading: Bool = false
    /// 本次请求失败（有旧值时不清空内容，只挂顶部「离线」条）
    @Published private(set) var lastError: APIError?
    /// 是否处于"离线降级"（本次请求失败但保留了上次的值）
    @Published private(set) var isOffline: Bool = false
    /// 规律摘要（`?action=rules`）
    @Published private(set) var rules: RedstoneRules?
    /// true = 规律没拿到，页面正在用内置文案（PRD P05）
    @Published private(set) var rulesFallback: Bool = false
    @Published private(set) var rulesLoading: Bool = false

    // MARK: - 依赖

    private let loader: CachedLoader
    private let client: APIClient
    /// 正在飞的月份，防止翻月来回点触发同月重复请求
    private var loadingMonths: Set<String> = []
    private var rulesLoaded = false

    /// 缓存键前缀。按月分键：`rock.schedule.v1.2026-10`。
    /// 不分键会让"翻到 11 月"直接覆盖掉 10 月的快照，再翻回来只能重新请求（还看不到内容）。
    private static let scheduleKeyPrefix = "rock.schedule.v1."
    /// 规律一天变不了几次，缓存 7 天（设计文档 §1.3.3）
    private static let rulesCacheKey = "rock.rules.v1"

    init(loader: CachedLoader = .shared, client: APIClient = .shared, now: Date = Date()) {
        self.loader = loader
        self.client = client
        self.visibleMonth = RedstoneClock.monthKey(now)
    }

    // MARK: - 派生（页面只读这些，不再自己算）

    /// 今天所在月（概览倒计时卡用，与 `visibleMonth` 无关）
    var currentMonthKey: String { RedstoneClock.monthKey(Date()) }

    var visibleResponse: RedstoneResponse? { months[visibleMonth] }

    /// 月历要画的这个月的条目
    var visibleDays: [RedstoneDay] { visibleResponse?.items ?? [] }

    /// 今天所在月的条目（倒计时卡 / 顶部「下一场」条用）
    var currentDays: [RedstoneDay] { months[currentMonthKey]?.items ?? [] }

    /// 所有已加载月份的条目，按日期去重升序。
    ///
    /// 为什么要合并：用户在 10 月 31 日翻到 11 月后，"下一场"可能是 11 月 1 日 07:08，
    /// 只看 `currentDays` 会得到"排期未生成"这种明显错误的结论。
    var allLoadedDays: [RedstoneDay] {
        var seen = Set<String>()
        var result: [RedstoneDay] = []
        for response in months.values {
            for day in response.items where !seen.contains(day.date) {
                seen.insert(day.date)
                result.append(day)
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// 是否至少拿到过一份响应（决定卡片显示"暂无排期"还是"排期未生成"）
    var hasLoadedAnyMonth: Bool { !months.isEmpty }

    /// 服务端最后生成排期的时刻（毫秒）。多个月份取最大值
    var latestUpdated: Int { months.values.map { $0.updated }.max() ?? 0 }

    /// 数据是否超过 7 天（PRD §5.2「数据可能过期」黄条）。
    /// `updated == 0` 不算过期：那是"从未生成"，由空态文案负责，不该再叠一条黄条。
    var isDataOld: Bool {
        guard latestUpdated > 0 else { return false }
        return RedstoneTimeline.isStale(updatedMilliseconds: latestUpdated, now: Date())
    }

    /// 当前月份已生成的月份列表（月历翻月按钮用）
    var coveredMonths: [String] { visibleResponse?.coveredMonths ?? [] }

    /// 服务端给的人话提示（如「3 天缺场次时刻」）。无则 nil，整条不渲染
    var warningText: String? {
        guard let warning = visibleResponse?.warning else { return nil }
        let trimmed = warning.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 能不能往前翻：以服务端 `coveredMonths` 为准（未生成的月份翻过去只会看到空页）。
    /// 还没拿到任何响应时放行 —— 让用户在弱网下也能翻月自查，比禁死更合理。
    var canShiftForward: Bool {
        guard !coveredMonths.isEmpty else { return true }
        return coveredMonths.contains(RedstoneClock.month(adding: 1, to: visibleMonth))
    }

    var canShiftBackward: Bool {
        guard !coveredMonths.isEmpty else { return true }
        return coveredMonths.contains(RedstoneClock.month(adding: -1, to: visibleMonth))
    }

    // MARK: - 纯函数门面（页面与 Widget 都从这里取，保证同一套口径）

    func nextOccurrence(now: Date = Date()) -> Occurrence? {
        return RedstoneTimeline.nextEvent(in: allLoadedDays, now: now)
    }

    func currentOccurrence(now: Date = Date()) -> Occurrence? {
        return RedstoneTimeline.currentEvent(in: allLoadedDays, now: now)
    }

    func phase(now: Date = Date()) -> RockPhase {
        return RedstoneTimeline.phase(in: allLoadedDays, now: now)
    }

    // MARK: - 动作

    /// 加载某个月的排期。
    ///
    /// - Parameters:
    ///   - month: 目标月份，默认当前显示月
    ///   - force: 下拉刷新传 true（忽略"已加载过"的短路，但仍会先展示缓存）
    func loadSchedule(month: String? = nil, force: Bool = false) async {
        let target = month ?? visibleMonth
        if !force, months[target] != nil { return }
        guard !loadingMonths.contains(target) else { return }

        loadingMonths.insert(target)
        isLoading = true

        let cacheKey = RockStore.scheduleKeyPrefix + target
        await loader.load(
            key: cacheKey,
            // 5 分钟新鲜窗：只影响"缓存这次要不要标成可能过期"，不影响展示
            maxAge: 300,
            fetch: { [self] in
                guard let url = API.redstone(month: target) else {
                    throw APIError.server(code: 0, message: "地址拼错了。")
                }
                let response = try await self.client.get(url, as: RedstoneResponse.self)
                guard response.ok else {
                    throw APIError.server(code: 200, message: "排期还没准备好，稍后再试。")
                }
                return response
            },
            emit: { [weak self] result in
                self?.apply(result, month: target)
            }
        )

        loadingMonths.remove(target)
        isLoading = !loadingMonths.isEmpty
    }

    /// 加载规律摘要。失败不清空旧值，只把 `rulesFallback` 置 true，页面改用内置文案。
    func loadRules(force: Bool = false) async {
        if rulesLoading { return }
        if !force, rulesLoaded { return }

        rulesLoading = true
        let month = currentMonthKey

        await loader.load(
            key: RockStore.rulesCacheKey,
            // 7 天：规律是"月度变化"的信息，一天刷一次都嫌多
            maxAge: 7 * 24 * 3600,
            fetch: { [self] in
                guard let url = API.redstone(month: month, includeRules: true) else {
                    throw APIError.server(code: 0, message: "地址拼错了。")
                }
                let response = try await self.client.get(url, as: RedstoneResponse.self)
                guard let rules = response.rules else { throw APIError.decoding }
                return rules
            },
            emit: { [weak self] result in
                guard let self = self else { return }
                if let value = result.value {
                    self.rules = value
                    self.rulesFallback = false
                } else {
                    self.rulesFallback = true
                }
                self.rulesLoaded = true
                self.rulesLoading = false
            }
        )
    }

    /// 翻月。先切 `visibleMonth`（界面立刻响应 + 触觉），再按需加载。
    func shiftMonth(by offset: Int) {
        let target = RedstoneClock.month(adding: offset, to: visibleMonth)
        guard target != visibleMonth else { return }
        visibleMonth = target
        Task { await loadSchedule(month: target) }
    }

    /// 回到今天所在月（空态里的「回到本月」用）
    func returnToCurrentMonth() {
        let target = currentMonthKey
        guard target != visibleMonth else { return }
        visibleMonth = target
        Task { await loadSchedule(month: target) }
    }

    /// 下拉刷新：当前月 + 规律一起刷（两个 await 串行，避免同一站点并发打两次）
    func refresh() async {
        await loadSchedule(month: visibleMonth, force: true)
        await loadRules(force: true)
    }

    // MARK: - 结果落地

    /// 把一次 `LoadResult` 写进状态。
    ///
    /// 关键一条：`updated` 没变就**不重写**字典。`@Published` 一写就整页重建，
    /// 每 5 分钟刷新一次会让月历滚动位置和浮层闪一下 —— 内容没变就不该惊动视图。
    private func apply(_ result: LoadResult<RedstoneResponse>, month: String) {
        if let value = result.value {
            let existing = months[month]
            if existing == nil || existing?.updated != value.updated {
                months[month] = value
            }
            lastError = result.error as? APIError
            isOffline = (result.error != nil)
        } else {
            // 一点值都没有（首装 + 断网）：错误态；已有内容时不会走到这里
            lastError = (result.error as? APIError) ?? .network
            isOffline = true
        }
    }
}
