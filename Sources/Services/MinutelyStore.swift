import Foundation

/// 分钟级降水的 App 侧状态（3.19.0）。
///
/// ## 为什么单独一个 Store
/// 与 `AlertStore` 同一个理由：这条数据的有效期是 5 分钟，天气整包是 30 分钟。
/// 挤在 `WeatherStore` 里，要么分钟降水永远比现实晚 25 分钟（那还不如不显示），
/// 要么整包缓存被拉成 5 分钟（上游额度四倍消耗）。
///
/// ## 只在中国境内有数据
/// 和风的分钟降水源自雷达外推，境外坐标上游直接无数据，服务端会返回 `ok:false`。
/// 这种情况 `rain` 保持 `nil`，UI 就是不显示这张卡 —— **不要**把"没有数据"渲染成
/// 「未来两小时无降水」，那是一句会误导人的假承诺。
@MainActor
final class MinutelyStore: ObservableObject {

    static let shared = MinutelyStore()

    /// 最近一次拿到的分钟降水。`nil` = 没有这项服务（境外 / 未配 key / 上游挂了）。
    @Published private(set) var rain: MinutelyRain?

    /// 轮询间隔（秒）：10 分钟。
    ///
    /// 比服务端 5 分钟的缓存略长一点：多打那一次只会命中缓存，
    /// 省下来的请求额度留给预警（那个才是真的等不起）。
    private static let pollInterval: TimeInterval = 600

    private let client: APIClient
    private var lastFetchAt: Date?
    private var inFlight = false
    private var pollTask: Task<Void, Never>?

    init(client: APIClient = .shared) {
        self.client = client
    }

    /// 有没有值得显示的内容（有结论或有数据点）。
    var hasData: Bool {
        guard let rain, rain.ok else { return false }
        return (rain.summary?.isEmpty == false) || (rain.points?.isEmpty == false)
    }

    /// 现在是不是正在下（用来决定卡片要不要强调）。
    var isWet: Bool {
        return rain?.isWet ?? false
    }

    // MARK: - 轮询

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(force: false)
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// 拉一次分钟降水。
    ///
    /// - Parameter force: `true` 时忽略 10 分钟窗口。
    func refresh(force: Bool = false) async {
        guard !inFlight else { return }
        if !force, let last = lastFetchAt, Date().timeIntervalSince(last) < Self.pollInterval {
            return
        }

        let coordinate = WeatherStore.resolvedCoordinate()
        guard let url = API.minutely(lat: coordinate?.latitude, lon: coordinate?.longitude) else { return }

        inFlight = true
        defer { inFlight = false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12

        do {
            let response = try await client.send(request, as: MinutelyRain.self)
            lastFetchAt = Date()
            // 业务失败（境外无数据 / 没配 key）：**清空**而不是保留旧值。
            // 与预警相反 —— 这里保留旧值等于告诉用户"还在下"，而那条数据可能已经过期一小时。
            rain = response.ok ? response : nil
        } catch {
            // 传输失败：保留旧值（网络抖动不该让"雨 20 分钟后停"突然消失）
        }
    }
}
