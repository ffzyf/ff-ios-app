import Foundation

/// 收益工作台的数据源（V3.2 新增）。
///
/// 只做四件事：
/// 1. 拉 `GET /api/app/earnings`（**唯一需要 `ce_auth` 的 app 接口**）；
/// 2. 把上一份成功响应缓存下来，断网 / 地铁里也能看昨天的数；
/// 3. 401 时让 `EarningsAuth` 清凭证、并**连带清掉本模块缓存**（避免退出后还看得到上一个账号的钱）；
/// 4. 把 `amountUnit` 写回 `EarningsMoney` —— 金额换算只发生在那里，本层不做任何 `÷100`。
@MainActor
final class EarningsStore: ObservableObject {

    static let shared = EarningsStore()
    /// 快照键前缀（`EarningsAuth` 登出时按这个前缀整段清）
    static let snapshotPrefix = EarningsAuth.snapshotPrefix
    /// 总览的缓存键（前缀 + 端点名 + 版本）
    private static let cacheKey = "earnings.overview.v1"

    @Published private(set) var summary: EarningsSummary?
    @Published private(set) var activities: [EarningsActivity] = []
    @Published private(set) var platforms: [EarningsPlatform] = []
    @Published private(set) var lastUpdated: Date?
    /// 这份数是本地缓存（这次请求没成功）
    @Published private(set) var isStale: Bool = false
    @Published private(set) var isLoading: Bool = false
    /// 可直接上屏的一句话；nil = 没问题
    @Published private(set) var errorText: String?

    private let client: APIClient
    private let auth: EarningsAuth

    init(client: APIClient = .shared, auth: EarningsAuth = .shared) {
        self.client = client
        self.auth = auth
    }

    /// 有没有可用数据（决定页面显示总览还是空态）
    var hasData: Bool { summary != nil }

    /// 最近一次更新的相对时间（「刚刚 / N 分钟前 / 时间」）
    var updatedText: String? {
        guard let lastUpdated else { return nil }
        let seconds = Date().timeIntervalSince(lastUpdated)
        if seconds < 60 { return "刚刚更新" }
        if seconds < 3600 { return String(Int(seconds / 60)) + " 分钟前更新" }
        return Formatters.timeHHmm(lastUpdated) + " 更新"
    }

    // MARK: - 加载

    /// 拉取总览。`force = true` 时把新鲜窗压到 0（下拉刷新 / 点「刷新」按钮）。
    func load(force: Bool = false) async {
        // 没凭证就别打接口：直接呈现未登录态，少一次必然 401 的请求
        guard let cookie = auth.cookieHeader else {
            clear()
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let client = self.client
        await CachedLoader.shared.load(
            key: Self.cacheKey,
            maxAge: force ? 0 : 120,
            fetch: {
                guard let url = API.earnings() else {
                    throw APIError.server(code: 0, message: "地址拼错了。")
                }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 15
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
                let response = try await client.send(request, as: EarningsResponse.self)
                guard response.ok else {
                    throw APIError.server(code: 200, message: "收益数据暂时读不到，稍后再试。")
                }
                return response
            },
            emit: { [weak self] loaded in
                guard let self else { return }
                // 401：不是"网络不好"，是凭证废了 —— 清凭证 + 清缓存，回登录引导
                if let apiError = loaded.error as? APIError,
                   case .server(let code, _) = apiError, code == 401 {
                    self.errorText = "登录已过期，重新登录一下。"
                    Task { await self.handleExpired() }
                    return
                }
                if let value = loaded.value {
                    self.apply(value, stale: loaded.isStale)
                } else if let error = loaded.error {
                    self.errorText = (error as? APIError)?.userMessage ?? "读取收益失败，稍后再试。"
                }
            }
        )
    }

    // MARK: - 内部

    private func apply(_ response: EarningsResponse, stale: Bool) {
        // 单位只在这里落地：全工程其它地方都靠 `EarningsMoney.formatCents` 读这个值
        EarningsMoney.currentUnit = response.amountUnit
        summary = response.summary
        activities = response.activities
        platforms = response.platforms
        lastUpdated = Date()
        isStale = stale
        errorText = nil
    }

    private func clear() {
        summary = nil
        activities = []
        platforms = []
        lastUpdated = nil
        isStale = false
        errorText = nil
    }

    /// 会话失效：清凭证 → 清内存 → 清缓存（三件一起做，少一件都会留下上一个账号的痕迹）
    private func handleExpired() async {
        auth.invalidate()
        clear()
        await SnapshotCache.shared.removeAll(withPrefix: Self.snapshotPrefix)
    }
}
