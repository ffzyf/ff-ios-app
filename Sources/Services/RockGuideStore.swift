import Combine
import Foundation

/// 攻略图文流的状态源（P06）。
///
/// 缓存策略（设计文档 §1.3.3）：24 小时，对齐服务端的 `guide_app_cache_v1`。
/// 理由很实际：攻略内容是"几天才变一次"的东西，每次进页面都请求一次纯属浪费流量，
/// 而 24h 又足够短 —— 用户不会看到一周前的地图。
///
/// 为什么单独一个 Store 而不是塞进 `RockStore`：两者的生命周期不同。
/// 日历页一进 App 就要有数据；攻略页是二级入口，可能一次都不打开。
/// 分开之后攻略失败不会连带日历进错误态（反过来也一样）。
@MainActor
final class RockGuideStore: ObservableObject {

    /// 攻略流（`LoadState` 装得下"内容 + 失败"三种态）
    @Published private(set) var state: LoadState<GuideResponse> = .idle
    @Published private(set) var isLoading: Bool = false
    /// 本次请求失败（有缓存时内容不清空，只在顶部挂一条）
    @Published private(set) var lastError: APIError?

    private let loader: CachedLoader
    private let client: APIClient
    /// 本进程内上次成功加载的时刻（用来做"1 小时内不重复请求"的短路）
    private var lastLoadedAt: Date?

    private static let cacheKey = "guide.feed.v1"
    /// 与服务端 TTL 一致：24 小时
    private static let maxAge: TimeInterval = 24 * 3600

    init(loader: CachedLoader = .shared, client: APIClient = .shared) {
        self.loader = loader
        self.client = client
    }

    // MARK: - 派生

    var items: [GuideItem] { state.value?.items ?? [] }

    /// 是否有源失败（PRD P06：顶部「部分内容拉取失败，已显示缓存」）
    var isPartial: Bool {
        if let response = state.value {
            return response.partial || response.sources.contains { !$0.ok }
        }
        return false
    }

    /// 是否完全没内容（空态）
    var isEmpty: Bool { items.isEmpty }

    /// 缓存新鲜度说明（PRD P06：页面注明「缓存 24 小时」）
    var cacheNote: String {
        return "攻略内容缓存 24 小时，下拉可手动刷新。"
    }

    // MARK: - 动作

    /// 加载攻略。`force = true` 是用户下拉刷新 / 点顶部刷新按钮。
    func load(force: Bool = false) async {
        guard !isLoading else { return }
        // 1 小时内且上次成功过：直接复用内存里的结果，连磁盘都不读
        if !force, let last = lastLoadedAt, Date().timeIntervalSince(last) < Self.maxAge, state.hasContent {
            return
        }

        isLoading = true
        if !state.hasContent {
            state = .loading
        }

        await loader.load(
            key: RockGuideStore.cacheKey,
            maxAge: RockGuideStore.maxAge,
            fetch: { [self] in
                guard let url = API.guide(refresh: force) else {
                    throw APIError.server(code: 0, message: "地址拼错了。")
                }
                let response = try await self.client.get(url, as: GuideResponse.self)
                guard response.ok else {
                    throw APIError.server(code: 200, message: "攻略还没准备好，稍后再试。")
                }
                return response
            },
            emit: { [weak self] result in
                guard let self = self else { return }
                if let response = result.value {
                    self.state = .loaded(response)
                    self.lastError = result.error as? APIError
                    if result.error == nil {
                        self.lastLoadedAt = Date()
                    }
                } else {
                    let error = (result.error as? APIError) ?? .network
                    self.lastError = error
                    // 没有任何缓存时才进整页错误态；有缓存则保留内容（PRD §7：错误态不清空内容）
                    if !self.state.hasContent {
                        self.state = .failed(error)
                    }
                }
                self.isLoading = false
            }
        )
    }
}
