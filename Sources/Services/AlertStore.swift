import Foundation
import UserNotifications

/// 天气预警的 App 侧状态 + 本地通知（3.19.0）。
///
/// ## 为什么单独一个 Store，而不是塞进 `WeatherStore`
/// 两者的**缓存周期差一个数量级**：天气 30 分钟，预警 5 分钟。
/// 塞在一起只有两种结局 —— 要么预警被天气的 30 分钟拖着（暴雨红色预警晚半小时才弹），
/// 要么天气被预警拖着（每 5 分钟重拉一次天气，白烧上游额度）。
///
/// ## 通知的现实边界（必须说清，别让用户以为这是真推送）
/// 侧载安装的 App 没有 APNs 证书，**收不到服务端推送**。这里用的是
/// `UNUserNotificationCenter` 的**本地通知**：只在 App 进程活着的时候才有机会调度。
///
/// 所以能保证的是：
///   · App 在前台时，每 10 分钟查一次，新预警立刻弹横幅（用户正在用手机，看得到）；
///   · 每次回到前台强制查一次（这是最常见的"打开手机看看"场景）；
///   · App 被系统挂起后**不会**有通知 —— 那段空窗只能靠每日简报的 Bark 推送兜底。
///
/// 这个限制来自签名方式，不是实现偷懒。要真推送必须换成有推送证书的安装方式（TestFlight / 正式签名）。
///
/// ## 去重
/// 同一条预警（同一个 `id`）只通知一次，记录留在 `UserDefaults` 里 7 天。
/// 不做去重的话，每 10 分钟轮询一次会把「暴雨黄色预警」重复弹 6 遍/小时 —— 用户会直接关掉通知权限，
/// 那才是真正的功能失效。
@MainActor
final class AlertStore: ObservableObject {

    static let shared = AlertStore()

    /// 当前生效的预警，按严重程度从高到低排好（服务端已排过，这里保持原序）。
    @Published private(set) var alerts: [WeatherAlert] = []

    /// 最近一次**成功**拿到数据的时间（`ok == true`，哪怕列表为空）。
    @Published private(set) var updatedAt: Date?

    /// 最近一次请求是否拿到了有效结果。
    ///
    /// `false` 时 `alerts` 保留上一次的值 —— 这是刻意的：一次网络抖动不该让
    /// 「暴雨红色预警」从屏幕上消失，那比不显示更危险。
    @Published private(set) var isAvailable: Bool = false

    /// 轮询间隔（秒）：10 分钟。
    ///
    /// 为什么不是 5 分钟（服务端缓存就是 5 分钟）：预警从"发布"到"用户看到"中间还有
    /// 系统通知送达的延迟，把轮询压到 5 分钟只能省下几分钟，代价是四倍的请求量。
    /// 而真正需要秒级感知的场景（雷暴大风）本来也不是靠 App 通知救命的。
    private static let pollInterval: TimeInterval = 600

    /// 已通知过的预警记录（`id → 时间戳`），存 `UserDefaults`。
    private static let notifiedKey = "weather.alert.notified.v1"

    /// 去重记录保留 7 天（预警本身的有效期远短于此，留久了只是占空间）。
    private static let notifiedMaxAge: TimeInterval = 7 * 24 * 3600

    private let client: APIClient
    private var lastFetchAt: Date?
    private var inFlight = false
    private var pollTask: Task<Void, Never>?

    init(client: APIClient = .shared) {
        self.client = client
    }

    /// 当前最该显示的那一条（服务端已按 severity 排序，取第一条即可）。
    var primary: WeatherAlert? {
        return alerts.first
    }

    var hasAlerts: Bool {
        return !alerts.isEmpty
    }

    // MARK: - 轮询

    /// 开始轮询（App 进前台时调）。重复调用无副作用。
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(force: false)
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

    /// 拉一次预警。
    ///
    /// - Parameter force: `true` 时忽略 10 分钟窗口（回前台 / 用户下拉刷新）。
    func refresh(force: Bool = false) async {
        guard !inFlight else { return }
        if !force, let last = lastFetchAt, Date().timeIntervalSince(last) < Self.pollInterval {
            return
        }

        let coordinate = WeatherStore.resolvedCoordinate()
        guard let url = API.alerts(lat: coordinate?.latitude, lon: coordinate?.longitude) else { return }

        inFlight = true
        defer { inFlight = false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 预警要"此刻"：协议缓存里那份哪怕只旧 2 分钟也可能是已解除的预警
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12

        do {
            let response = try await client.send(request, as: AlertsResponse.self)
            lastFetchAt = Date()
            // ok == false：拿不到。保留旧值、不动 isAvailable，下次立刻重试
            guard response.ok else { return }

            isAvailable = true
            updatedAt = response.updatedAt ?? Date()
            let list = response.warnings ?? []
            alerts = list
            await notifyNewOnes(list)
        } catch {
            // 传输 / 解码失败一律静默：预警是后台能力，不该弹 Toast 打断用户
        }
    }

    // MARK: - 本地通知

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
