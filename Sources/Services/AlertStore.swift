import Foundation
import UserNotifications

/// 天气预警的 App 侧状态 + 本地通知（3.19.0，5.1.2 改为四态状态机）。
///
/// ## 为什么单独一个 Store，而不是塞进 `WeatherStore`
/// 两者的**缓存周期差一个数量级**：天气 30 分钟，预警 5 分钟。
/// 塞在一起只有两种结局 —— 要么预警被天气的 30 分钟拖着（暴雨红色预警晚半小时才弹），
/// 要么天气被预警拖着（每 5 分钟重拉一次天气，白烧上游额度）。
///
/// ## 5.1.2 · R1 的四件事
/// 1. **四态**：`@Published private(set) var state` 是唯一真相源，
///    `.hasAlerts / .confirmedNone / .loadingFirst / .failed` 互斥。
///    判定**只在** `AlertPresentation.reduce`（`Sources/Shared/Domain`，纯函数）里做，
///    本类只负责把「缓存 / 本次请求结果 / 当前时刻」喂进去。
/// 2. **跨启动缓存**：`init` 同步 `AlertCache.load()` 定首帧，
///    `ok == true` 才写缓存（空列表也写），`ok == false` / 传输失败绝不覆盖。
/// 3. **刷新收敛**：所有入口都过 `AlertRefreshPolicy.shouldRefresh`
///    （进场 / 回前台受 300 秒窗口，下拉 / 换城市恒发）→ 10 分钟内 ≤ 2 次请求。
/// 4. **数据源诊断**：每次请求收尾更新 `AlertDiagnostics`，含
///    `X-Alerts-Cache` 响应头（走 `APIRawResponse.header(_:)` 取）。
///
/// ## 通知的现实边界（必须说清，别让用户以为这是真推送）
/// 侧载安装的 App 没有 APNs 证书，**收不到服务端推送**。这里用的是
/// `UNUserNotificationCenter` 的**本地通知**：只在 App 进程活着的时候才有机会调度。
///
/// 所以能保证的是：
///   · App 在前台时，每轮检查到新预警立刻弹横幅（用户正在用手机，看得到）；
///   · 每次回到前台走一次收敛闸门（这是最常见的"打开手机看看"场景）；
///   · App 被系统挂起后**不会**有通知 —— 那段空窗靠 R2 的 Bark 推送兜底。
///
/// 这个限制来自签名方式，不是实现偷懒。要真推送必须换成有推送证书的安装方式（TestFlight / 正式签名）。
///
/// ## 去重
/// 同一条预警（同一个 `id`）只通知一次，记录留在 `UserDefaults` 里 7 天。
/// 不做去重的话，每轮检查都会把「暴雨黄色预警」重复弹一遍 —— 用户会直接关掉通知权限，
/// 那才是真正的功能失效。**前台本地通知与后端 Bark 各自按 id 独立去重，互不引用**（AC2-6）。
@MainActor
final class AlertStore: ObservableObject {

    static let shared = AlertStore()

    // MARK: - 对外状态（5.1.2 唯一真相源）

    /// 四态之一。View 只 `switch` 它，不许在 `if` 里重算语义。
    @Published private(set) var state: AlertPresentationState = .loadingFirst

    /// 数据源诊断（接口 / 最近结果 / 时刻 / 是否缓存兜底 / `X-Alerts-Cache`）
    @Published private(set) var diagnostics: AlertDiagnostics = .empty

    // MARK: - 对外兼容（由 `state` 派生，既有调用点零回归）
    //
    // 原三态字段不再各自持有真相，全部改成计算属性。T03 的 `SkyRoomView`
    // 会改成 `switch alerts.state`，但其他还在读 `alerts` / `isAvailable` /
    // `updatedAt` 的旧调用点不必同步改，也就不会出现编译断档。

    /// 当前生效的预警，按严重程度从高到低排好（服务端已排过，这里保持原序）
    var alerts: [WeatherAlert] { state.warnings }

    /// 最近一次**成功**拿到数据的时间
    var updatedAt: Date? { state.lastSuccessAt }

    /// 是否拿到了确定结论（`.hasAlerts` / `.confirmedNone`，含缓存兜底态）
    var isAvailable: Bool {
        switch state {
        case .hasAlerts, .confirmedNone:
            return true
        case .loadingFirst, .failed:
            return false
        }
    }

    /// 当前最该显示的那一条（服务端已按 severity 排序，取第一条即可）
    var primary: WeatherAlert? { alerts.first }

    var hasAlerts: Bool { !alerts.isEmpty }

    // MARK: - 常量

    /// 轮询 tick（秒）：只决定「多久看一眼该不该发」，不是请求间隔。
    /// 真正的窗口在 `AlertRefreshPolicy.minFetchInterval`（300s，与后端 s-maxage 对齐）。
    private static let pollInterval: TimeInterval = AlertRefreshPolicy.pollCheckInterval

    /// 已通知过的预警记录（`id → 时间戳`），存 `UserDefaults`。**R2 前台通道，逐字保留**
    private static let notifiedKey = "weather.alert.notified.v1"

    /// 去重记录保留 7 天（预警本身的有效期远短于此，留久了只是占空间）。
    private static let notifiedMaxAge: TimeInterval = 7 * 24 * 3600

    /// 单次请求超时（秒），与 3.19.0 一致
    private static let requestTimeout: TimeInterval = 12

    // MARK: - 私有状态

    private let client: APIClient
    private let cache: AlertCache
    private var lastFetchAt: Date?
    private var inFlight = false
    private var pollTask: Task<Void, Never>?

    /// 启动时载入的缓存快照（诊断初值用；判定仍以 `cache.presentationSnapshot()` 为准）
    private var cachedSnapshot: AlertCache.Snapshot?

    /// "有一次强制刷新因为上一发还在回来而被挡下了，收尾时补做"（3.26.0）。
    ///
    /// 预警比天气更不能留旧值：换城市后旧城市那条「暴雨红色预警」还挂在横幅上，
    /// 用户会按错误的城市做准备。所以 `force` 被 `inFlight` 挡回时必须记账 ——
    /// 否则只能等下一轮轮询，而那期间屏幕上写的是另一座城市的预警。
    private var needsForcedReload = false

    init(client: APIClient = .shared, cache: AlertCache = AlertCache()) {
        self.client = client
        self.cache = cache

        // 同步读 + 解码 < 10ms：`@Published state` 的初值在 init 结束前就定好，
        // 首屏直接拿到四态之一，没有 `.unknown`、没有「预警数据暂时取不到」（AC1-1）。
        let snapshot = cache.load()
        self.cachedSnapshot = snapshot
        self.state = AlertPresentation.reduce(snapshot: cache.presentationSnapshot(),
                                              fetch: nil,
                                              now: Date())
        if let snapshot = snapshot {
            // 冷启动显示的是缓存，诊断区如实写「缓存兜底」，不冒充刚拉到的实时结果
            self.diagnostics = AlertDiagnostics(
                endpoint: snapshot.endpoint,
                lastResult: snapshot.lastResult,
                lastAttemptAt: nil,
                lastSuccessAt: snapshot.savedAt,
                cacheUsed: true,
                cacheHeader: snapshot.cacheHeader
            )
        } else {
            self.diagnostics = .empty
        }
    }

    // MARK: - 轮询

    /// 开始轮询（App 进前台时调）。重复调用无副作用。
    ///
    /// tick 是 60 秒，但**每一发仍要过 `AlertRefreshPolicy` 的 300 秒闸门**，
    /// 所以 10 分钟内连续进出 10 次累计请求数 ≤ 2（AC1-4）。
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshIfNeeded(.enter)
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                } catch {
                    break   // 被取消：正常退出，别空转
                }
            }
        }
    }

    /// 停止轮询（App 退到后台时调）。
    ///
    /// 后台不该继续跑：iOS 会在几秒内挂起进程，`Task.sleep` 根本走不完一轮，
    /// 而保活尝试（`beginBackgroundTask`）只会换来一次系统审计记录，不值得。
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - 刷新入口

    /// 既有调用点的兼容口（3.19.0 起就有 `refresh(force:)`）。
    ///
    /// `force == true` 映射为 `.force`（恒发），否则走 `.enter`（受 300 秒窗口）。
    func refresh(force: Bool = false) async {
        await refreshIfNeeded(force ? .force : .enter)
    }

    /// **统一刷新入口**（T03 的 `SkyRoomView.refreshPolledData()` 调 `.enter`，
    /// 下拉与「重试」按钮调 `.force`，换城市调 `.coordinateChanged`）。
    ///
    /// 闸门是 `Sources/Shared/Domain` 里的纯函数，本类不自己判时间。
    func refreshIfNeeded(_ policy: AlertRefreshPolicy.Policy,
                         coordinateChanged: Bool = false) async {
        let now = Date()
        guard AlertRefreshPolicy.shouldRefresh(lastFetchAt: lastFetchAt,
                                               now: now,
                                               policy: policy,
                                               coordinateChanged: coordinateChanged) else {
            return
        }

        // 上一发还在飞：用户显式动作不能丢（理由见 `needsForcedReload`）
        guard !inFlight else {
            if policy == .force || policy == .coordinateChanged {
                needsForcedReload = true
            }
            return
        }

        await performFetch(now: now)
    }

    /// 用户点「重试」：等价于一次强制刷新（唯一对外重试口，R1 / AC1-3）
    func retry() async {
        await refreshIfNeeded(.force)
    }

    // MARK: - 请求与状态落地

    private func performFetch(now: Date) async {
        let coordinate = WeatherStore.resolvedCoordinate()
        guard let url = API.alerts(lat: coordinate?.latitude, lon: coordinate?.longitude) else {
            return
        }

        inFlight = true
        // 顺序不能换：先落 `inFlight`，再补那一发。反过来的话 `Task` 会在 `inFlight`
        // 还是 true 时开跑，又被上面那条 guard 拦住 —— 欠的这次永远补不上。
        defer {
            inFlight = false
            if needsForcedReload {
                needsForcedReload = false
                Task { await self.refreshIfNeeded(.force) }
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 预警要"此刻"：协议缓存里那份哪怕只旧 2 分钟也可能是已解除的预警
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = Self.requestTimeout

        let attemptAt = Date()

        do {
            // 用 `send(_:)` 而不是 `send(_:as:)`：要多拿响应头 `X-Alerts-Cache`，
            // 而且要保留**原始 JSON Data** 交给 `AlertCache`（缓存只存原文）。
            let raw = try await client.send(request)
            let cacheHeader = raw.header("X-Alerts-Cache")

            guard raw.isSuccess else {
                applyFailure(.transport,
                             attemptAt: attemptAt,
                             cacheHeader: cacheHeader,
                             statusCode: raw.statusCode)
                return
            }

            lastFetchAt = Date()

            let response: AlertsResponse
            do {
                response = try APIJSON.decoder.decode(AlertsResponse.self, from: raw.data)
            } catch {
                applyFailure(.decode,
                             attemptAt: attemptAt,
                             cacheHeader: cacheHeader,
                             statusCode: raw.statusCode)
                return
            }

            // `guard response.ok` 语义逐字保留：拿不到就**绝不覆盖缓存、绝不清空横幅**
            guard response.ok else {
                let failure: AlertFailure = (cacheHeader?.lowercased() == "no_key") ? .noKey : .okFalse
                let result = failure.resultText + Self.headerSuffix(cacheHeader)
                apply(fetch: AlertFetchOutcome(ok: false,
                                               warnings: [],
                                               failure: failure,
                                               finishedAt: Date(),
                                               cacheHeader: cacheHeader),
                      resultText: result,
                      cacheHeader: cacheHeader,
                      attemptAt: attemptAt)
                return
            }

            // ok == true：写缓存（空列表也写，`AlertCache.save` 内部还有一道 ok 守门）
            let result = Self.resultText(ok: true, cacheHeader: cacheHeader)
            cache.save(data: raw.data,
                       endpoint: Endpoint.alertsEndpointText,
                       result: result,
                       cacheHeader: cacheHeader)
            cachedSnapshot = cache.load()

            let list = response.warnings ?? []
            apply(fetch: AlertFetchOutcome(ok: true,
                                           warnings: list,
                                           failure: nil,
                                           finishedAt: Date(),
                                           cacheHeader: cacheHeader),
                  resultText: result,
                  cacheHeader: cacheHeader,
                  attemptAt: attemptAt)

            // R2 前台即时通道：本地通知去重（原样保留，AC2-6）
            await notifyNewOnes(list)
        } catch {
            // `APIClient.send(_:)` 把超时 / 断网 / 取消统一归一成 `APIError.network`，
            // 客户端这一层不再细分（`.timeout` 保留给纯函数判定与 QA 镜像用例）。
            // 传输失败**不更新 `lastFetchAt`**：下次进场可以立刻重试。
            applyFailure(.transport,
                         attemptAt: attemptAt,
                         cacheHeader: nil,
                         statusCode: nil)
        }
    }

    /// 把一次结果喂给唯一判定入口，并同步刷新诊断区。
    private func apply(fetch: AlertFetchOutcome,
                       resultText: String,
                       cacheHeader: String?,
                       attemptAt: Date) {
        state = AlertPresentation.reduce(snapshot: cache.presentationSnapshot(),
                                         fetch: fetch,
                                         now: fetch.finishedAt)
        diagnostics = AlertDiagnostics(
            endpoint: Endpoint.alertsEndpointText,
            lastResult: resultText,
            lastAttemptAt: attemptAt,
            lastSuccessAt: state.lastSuccessAt,
            cacheUsed: state.isStale,
            cacheHeader: cacheHeader
        )
    }

    /// 失败收尾：不写缓存、不清空横幅、不让 `ok==false` 冒充「无预警」。
    private func applyFailure(_ failure: AlertFailure,
                              attemptAt: Date,
                              cacheHeader: String?,
                              statusCode: Int?) {
        let suffix = statusCode.map { " · HTTP \($0)" } ?? ""
        apply(fetch: AlertFetchOutcome(ok: nil,
                                       warnings: [],
                                       failure: failure,
                                       finishedAt: Date(),
                                       cacheHeader: cacheHeader),
              resultText: failure.resultText + suffix,
              cacheHeader: cacheHeader,
              attemptAt: attemptAt)
    }

    // MARK: - 结果串（诊断区如实写，不编造数值）

    private static func resultText(ok: Bool, cacheHeader: String?) -> String {
        return (ok ? "ok:true" : "ok:false") + headerSuffix(cacheHeader)
    }

    private static func headerSuffix(_ cacheHeader: String?) -> String {
        guard let header = cacheHeader, !header.isEmpty else { return "" }
        return " · " + header
    }

    // MARK: - 本地通知
    //
    // 以下四段（`notifyNewOnes` / `deliver` / `loadNotified` / `saveNotified`）
    // 与 3.19.0 逐字一致，5.1.2 一行未改 —— R2 前台通道按 `id` 独立去重，
    // 后端 Bark 用另一套 KV `alert_push_sent:<id>`，两条链互不引用、互不叠加。

    /// 对"没见过"的预警逐条发本地通知。
    ///
    /// 只有**新**预警才发：服务端每 5 分钟刷一次列表，不筛的话同一条预警会被反复弹。
    /// 轻微级别（`minor`）也发，但用安静一点的措辞 —— 用户要的是"有预警就告诉我"，
    /// 由他自己决定忽略，而不是我们替他过滤掉。
    private func notifyNewOnes(_ list: [WeatherAlert]) async {
        guard !list.isEmpty else { return }

        var seen = loadNotified()
        let now = Date()

        // 先清过期记录，避免字典无限膨胀
        seen = seen.filter { now.timeIntervalSince1970 - $0.value < Self.notifiedMaxAge }

        var changed = false
        for alert in list where seen[alert.id] == nil {
            let delivered = await deliver(alert)
            // 只有真的投递出去（或被用户明确拒绝授权）才记账：
            // 授权弹窗还没点、或调度失败时记账，会导致这条预警永远不再提醒
            if delivered {
                seen[alert.id] = now.timeIntervalSince1970
                changed = true
            }
        }

        if changed { saveNotified(seen) }
    }

    /// 投递一条本地通知。返回 `true` 表示"以后不用再试这一条"。
    ///
    /// 授权被拒也返回 `true`：用户已经表达过"不要通知"，反复重试只是白耗电。
    private func deliver(_ alert: WeatherAlert) async -> Bool {
        let center = UNUserNotificationCenter.current()

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .denied:
            return true
        case .notDetermined:
            // 第一次遇到预警时才要权限 —— 冷启动就弹权限框，用户多半会随手拒绝，
            // 而在他刚看到「暴雨预警」时请求，通过率高得多。
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            if !granted { return true }
        default:
            break
        }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.shortText
        content.sound = .default
        content.userInfo = ["alertId": alert.id]
        // 严重级别给个更明显的标记：通知列表里一眼能看出这条要紧
        if alert.isSevere {
            content.subtitle = alert.severityText.map { "\($0)预警" } ?? "重要预警"
        }

        // identifier 用 alert.id：同一条预警即使被重复调度，系统也只会留一条
        let request = UNNotificationRequest(identifier: "wx-alert-\(alert.id)", content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    private func loadNotified() -> [String: TimeInterval] {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.notifiedKey) else { return [:] }
        var out: [String: TimeInterval] = [:]
        for (key, value) in raw {
            if let n = value as? Double { out[key] = n }
            else if let n = value as? Int { out[key] = TimeInterval(n) }
        }
        return out
    }

    private func saveNotified(_ map: [String: TimeInterval]) {
        UserDefaults.standard.set(map, forKey: Self.notifiedKey)
    }
}
