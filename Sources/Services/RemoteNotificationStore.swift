import Foundation
import UIKit
import UserNotifications

// MARK: - 远程通知接收 Store

/// 远程通知的通用接收端（设计 §3.3）：自己的 60s 轮询、拉取、时效判定、去重、
/// 授权、投递、已投递记账、冷启动基线、点击分发兜底。
///
/// ## 为什么不订阅 `RemoteConfigStore.$latest`
/// 后者有 **1 小时闸门**（公告/强更的 SLA），而通知的 SLA 是 ≤60s —— 订阅它会直接破坏 G2。
/// 两条链路只在**网络协议层**复用（`GET /api/app/config` + `RemoteConfigEnvelope`），
/// 在闸门层完全解耦：各拉各的，互不触发、互不等待。代价是前台每 60s 多一次 GET，
/// 该请求命中现有 `max-age=60` 边缘缓存，成本接近一次条件请求，可接受。
///
/// ## 去重键是 `msgId#seq`，不是 `msgId`
/// `msgId` 标识"哪一条通知"，`seq` 标识"第几次投递"。只用 msgId 会让页面「重发」被当成
/// 重复投递吞掉；只用时间戳则跨设备不可靠。记录属于**设备**（UserDefaults），不写 KV：
/// App 无写权限，且全局 KV 会让 A 设备的投递误抑制 B 设备。
///
/// ## 现实边界（与 AlertStore 同一条纪律）
/// 侧载无 APNs：只在 App 进程活着时（前台轮询 / 回前台首拉）才有机会投递。
/// 不注册后台 timer、不申请新 Capability、不制造"杀进程秒推"的错觉。
@MainActor
final class RemoteNotificationStore: ObservableObject {

    static let shared = RemoteNotificationStore()

    /// 前台轮询周期（秒）：与服务端 `max-age=60` 缓存对齐。
    static let pollInterval: TimeInterval = 60

    /// 内部拉取闸门（秒）：`refreshAndDeliver(force: true)` 无视它（回前台 / 冷启动首拉）。
    /// 失败时**不写**闸门时间，下一次轮询立刻重试。
    private static let refreshGate: TimeInterval = 60

    /// 已投递记录：`msgId#seq → 投递成功的 Unix 秒`。设计 §2.2。
    private static let keyDelivered = "remoteNotification.delivered"
    /// 冷启动基线标记：首次成功拉取时把当前队列全部记为已投递，避免历史重放。
    private static let keyBaselined = "remoteNotification.baselined"
    /// 点击时 `open` 失败的待重试 URL（回前台由 `flushPendingRoute()` 再试）。
    static let pendingURLKey = "remoteNotification.pendingURL"

    /// 已投递记录保留 7 天，与服务端队列的保留窗对齐。
    private static let deliveredMaxAge: TimeInterval = 7 * 24 * 3600

    // MARK: 依赖与私有状态

    private let client: APIClient
    private let defaults: UserDefaults

    /// 独立轮询任务。与 AlertStore 同一纪律：`.task(id: scenePhase)` 取消的是闭包，
    /// 闭包里起的 Task 生命周期独立，退后台必须显式 `stopPolling()`。
    private var pollTask: Task<Void, Never>?
    /// 上次**成功**拉取的时刻（仅进程内；失败不更新）
    private var lastSuccessAt: Date?
    /// 防止轮询与回前台首拉并发跑同一段投递逻辑（双记账 / 双弹）
    private var inFlight = false
    /// 本次刷新的已投递字典快照；`remember` 改它，收尾统一落盘
    private var delivered: [String: Double] = [:]

    nonisolated init(client: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    // MARK: - 轮询生命周期

    /// 开始轮询（App 进入 `.active` 时调）。重复调用无副作用。
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAndDeliver()
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                } catch {
                    break   // 被取消：正常退出，不空转
                }
            }
        }
    }

    /// 停止轮询（离开 `.active` 时调）。
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - 刷新入口

    /// 拉取 + 投递。
    ///
    /// - `force = true`（回前台 / 冷启动 / 首拉）：无视 60s 闸门立即拉一次；
    /// - `force = false`（轮询 tick）：受闸门约束，与服务端缓存同频。
    ///
    /// 失败一律静默：不清空已投递记录、不写闸门时间、不弹任何 UI（配置是附加能力）。
    func refreshAndDeliver(force: Bool = false) async {
        let now = Date()
        if !force, let last = lastSuccessAt,
           now.timeIntervalSince(last) < Self.refreshGate { return }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        guard let values = await fetchConfig() else { return }
        let items = (values.notification ?? []).filter { $0.isValid }

        // 顺序不能换：先载记录 → 打基线（把历史全部记成已投递）→ 才进入正常投递循环。
        // 反过来的话，冷启动首拉会把 7 天历史队列一次性全弹出来。
        delivered = loadDelivered()
        seedBaselineIfNeeded(items: items)
        await deliver(items: items)

        lastSuccessAt = Date()
    }

    /// 取配置：复用 `RemoteConfigStore` 同一个信封解码，但**不走它的 1h 闸门**。
    /// @returns nil 表示"这一次没拿到可用配置"（网络 / 解码失败 / ok:false / revision 为 0）
    private func fetchConfig() async -> RemoteConfigValues? {
        guard let url = Endpoint.url(base: Endpoint.briefBase, path: Endpoint.appConfigPath) else {
            // 地址拼错是代码问题，不该让用户看到任何东西
            return nil
        }
        do {
            let envelope = try await client.get(url, as: RemoteConfigEnvelope.self)
            guard envelope.ok, envelope.revision > 0 else { return nil }
            return envelope.values
        } catch {
            // 断网 / 超时 / 解码失败：静默，等下一轮
            return nil
        }
    }

    // MARK: - 投递

    /// 逐条投递。队列是 newest first；这里**倒序**遍历（oldest → newest），
    /// 这样通知中心里最新的一条排在最上面，与系统其它通知的时间顺序一致。
    private func deliver(items: [RemoteNotification]) async {
        var changed = false

        for item in items.reversed() {
            let key = item.dedupKey

            // 超过 24h：记账但不弹。用户离线几天后打开手机，不该被几十条历史通知轰炸。
            guard item.isFresh else {
                remember(key: key)
                changed = true
                continue
            }

            // 去重：同一 msgId#seq 已经投递过就跳过（多次拉取不双弹）
            guard !isDelivered(key: key) else { continue }

            // 只在真有可投递通知时才申请权限；.denied 视为"以后不用再试这一条"
            guard await ensureAuthorization() else {
                remember(key: key)
                changed = true
                continue
            }

            let content = makeContent(item: item)
            let request = UNNotificationRequest(
                identifier: "remotenot-" + key,
                content: content,
                trigger: nil
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
                // 只在 add 成功后记账（与 AlertStore L377-383 同一纪律）：
                // 提前记账会让这条通知永远不再重试；失败不记账则下一轮自然补上。
                remember(key: key)
                changed = true
            } catch {
                // 投递失败静默重试：identifier 由 msgId#seq 决定，重复 add 只会覆盖，不会双弹
            }
        }

        if changed { saveDelivered(delivered) }
    }

    /// 构造通知内容。字段映射表见设计 §3.3.3。
    ///
    /// 诚实标注 v1 能力边界：
    /// · `level` → 副标题中文文案（未知值降级 info，不写副标题）；
    /// · `url` → userInfo，点击时由 Dispatcher 读取并 open；
    /// · `msgId` / `seq` → userInfo，便于点击日志与追溯；
    /// · `icon` / `color` / `actionTitle` **不映射**：iOS 本地通知没有 tint / 自定义 icon，
    ///   v1 也没有注册 UNNotificationAction。字段继续在队列里透传，为未来富通知或其他客户端保留。
    private func makeContent(item: RemoteNotification) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default

        switch item.level?.lowercased() {
        case "warn"?:
            content.subtitle = "提醒"
        case "urgent"?:
            content.subtitle = "紧急通知"
        default:
            break   // info / 未知值：不产生副标题（宁轻勿重）
        }

        if let routable = item.routableURL {
            content.userInfo["url"] = routable.absoluteString
        }
        content.userInfo["msgId"] = item.msgId
        content.userInfo["seq"] = item.seq

        // 与设置页「设备通知测试」/ AlertStore 的体验一致（iOS 15+）。
        // 注意：历史上踩过 UNAuthorizationOptions.communication 编译失败的坑，
        // 这里申请的权限严格只用 .alert / .sound / .badge / .timeSensitive。
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        return content
    }

    /// 确保有可投递权限。`.notDetermined` 时才弹授权框；`.denied` 直接放弃。
    private func ensureAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .denied:
            return false
        case .notDetermined:
            do {
                if #available(iOS 15.0, *) {
                    return try await center.requestAuthorization(
                        options: [.alert, .sound, .badge, .timeSensitive]
                    )
                }
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        default:
            // .authorized / .provisional / .ephemeral 都能投递本地通知
            return true
        }
    }

    // MARK: - 冷启动基线

    /// 首次成功拉取时，把当前队列所有 `msgId#seq` 直接记为已投递。
    /// 解决"新装 / 清数据后首拉拿到 7 天历史队列一次性全弹"。
    /// 之后新写入的通知不在记录里，照常投递 —— 基线只吃"当时已有的那批"。
    private func seedBaselineIfNeeded(items: [RemoteNotification]) {
        guard defaults.bool(forKey: Self.keyBaselined) != true else { return }
        for item in items { remember(key: item.dedupKey) }
        defaults.set(true, forKey: Self.keyBaselined)
        // 基线标记与记录一起落盘：中途被杀也不会出现"标记已打、记录没写"的历史重放窗口
        saveDelivered(delivered)
    }

    // MARK: - 已投递记录（设备本地，不写 KV）

    private func remember(key: String) {
        delivered[key] = Date().timeIntervalSince1970
    }

    private func isDelivered(key: String) -> Bool {
        delivered[key] != nil
    }

    /// 读取并按 7 天裁剪。同时接受 Double / Int（老版本可能写过整数秒）。
    private func loadDelivered() -> [String: Double] {
        guard let raw = defaults.dictionary(forKey: Self.keyDelivered) else { return [:] }
        let now = Date().timeIntervalSince1970
        var out: [String: Double] = [:]
        for (key, value) in raw {
            let seconds: Double
            if let n = value as? Double { seconds = n }
            else if let n = value as? Int { seconds = Double(n) }
            else { continue }
            guard now - seconds < Self.deliveredMaxAge else { continue }
            out[key] = seconds
        }
        return out
    }

    private func saveDelivered(_ dictionary: [String: Double]) {
        defaults.set(dictionary, forKey: Self.keyDelivered)
    }

    // MARK: - 点击兜底

    /// 回前台时重试上次 `open` 失败的通知跳转。
    /// 由 `FFWangApp` 在 `.active` 的 scenePhase task 里调用。
    func flushPendingRoute() async {
        await NotificationRouteDispatcher.flushPending()
    }
}

// MARK: - 点击路由分发

/// 通知点击的统一分发口（设计 §3.3.4）。
///
/// ## 为什么不是直接改 `RootView`
/// `skyapp://` 必须回到 `RootView.onOpenURL → open(deepLink:)` 这个**单点路由**：
/// 未知 host 由现有逻辑忽略，不会把用户踢回首页；新增 host 也只需改一处。
/// `UIApplication.shared.open(url)` 对自有 scheme 会走系统回调，SwiftUI 再补发 `onOpenURL`，
/// 与桌面小组件深链完全同一条路径 —— 所以这里**不解析 host、不碰 Tab 选择**。
///
/// H5 同样交给 `UIApplication.shared.open(url)` → 系统浏览器；App 内不嵌 WebView。
@MainActor
enum NotificationRouteDispatcher {

    /// 分发一个来自 `userInfo["url"]` 的链接。
    /// 校验失败的 scheme 只收起横幅、不跳转；`open` 失败写 pendingURL，回前台重试。
    static func dispatch(url: URL) async {
        guard isValid(url: url) else { return }
        let opened = await UIApplication.shared.open(url)
        if !opened {
            UserDefaults.standard.set(
                url.absoluteString,
                forKey: RemoteNotificationStore.pendingURLKey
            )
        }
    }

    /// 回前台重试：先清键再 dispatch —— 否则 dispatch 失败重写时会和旧值叠加，
    /// 也无法区分"这次重试又失败"与"上次遗留"。
    static func flushPending() async {
        guard let raw = UserDefaults.standard.string(forKey: RemoteNotificationStore.pendingURLKey),
              let url = URL(string: raw),
              isValid(url: url) else {
            UserDefaults.standard.removeObject(forKey: RemoteNotificationStore.pendingURLKey)
            return
        }
        UserDefaults.standard.removeObject(forKey: RemoteNotificationStore.pendingURLKey)
        await dispatch(url: url)
    }

    /// 只放行两类 scheme：`skyapp://<host|/path>` 与 `http(s)://<host>`。
    /// 其它 scheme 视为无链接（与 `RemoteNotification.routableURL` 逐字一致）。
    private static func isValid(url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "skyapp" {
            return url.host != nil || !url.path.isEmpty
        }
        if scheme == "http" || scheme == "https" {
            return url.host != nil
        }
        return false
    }
}
