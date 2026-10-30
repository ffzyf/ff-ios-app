import Foundation
import Combine

/// 全局只读数据容器（`ObservableObject` + `@Published`）。
///
/// 线程约定：`@MainActor`，所有状态写入在主线程；网络在 `APIClient` 里跑。
/// 文件分工：状态与请求在本文件，只读派生数据在 `AppModel+Derived.swift`，
/// 分页合并在 `FeedPaging.swift`。
@MainActor
final class AppModel: ObservableObject {

    // MARK: - 状态

    @Published private(set) var feedState: LoadState<FeedResponse> = .idle
    @Published private(set) var briefState: LoadState<BriefResponse> = .idle
    /// 文章详情（T07）。进详情页才请求，详情关掉时 `clearArticle()`
    @Published private(set) var articleState: LoadState<ArticleDetail> = .idle
    @Published private(set) var isRefreshing: Bool = false
    /// 底部 toast（1.8s 自动消失）。刷新失败不清空内容，只弹这个。
    @Published var toastMessage: String?
    @Published private(set) var lastUpdatedAt: Date?
    /// 最近一次 feed 失败（**即使内容没丢**也记下来）：PRD §5.2「离线（有缓存）」的顶部细条依据。
    ///
    /// 不能拿 `feedState.error` 当依据：`LoadState` 的 `.loaded` 与 `.failed` 互斥，
    /// 有缓存内容时状态仍是 `.loaded`，`feedState.error` 恒为 nil（见 `applyFeedFailure`）。
    /// 成功取到 feed 时清回 nil。仅用于展示，不参与任何数据判定。
    @Published private(set) var lastFeedError: APIError?

    // MARK: - 依赖

    private let client: APIClient
    private var didLoad = false
    private var toastTask: Task<Void, Never>?

    init(client: APIClient = APIClient.shared) {
        self.client = client
    }

    // MARK: - 加载

    /// 首屏：两请求并发，**任一返回即渲染该区块**，不「等齐了再显示」。只用一次。
    func loadOverview() async {
        guard !didLoad else { return }
        didLoad = true

        if !feedState.hasContent {
            feedState = .loading
        }
        if !briefState.hasContent {
            briefState = .loading
        }

        let feedTask = Task { await self.loadFeed(page: 1) }
        let briefTask = Task { await self.loadBrief() }
        await feedTask.value
        await briefTask.value

        setLastUpdatedIfNeeded()
    }

    /// 下拉刷新：两请求并发，全部返回才收起；**失败不清空已显示内容**。
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        let feedTask = Task { await self.loadFeed(page: 1) }
        let briefTask = Task { await self.loadBrief() }
        await feedTask.value
        await briefTask.value

        isRefreshing = false
        setLastUpdatedIfNeeded()
    }

    /// 拉文章列表。`append: true` = 追加下一页（保留已加载的 items，更新 page/hasMore）；
    /// `append: false`（默认）= 整体替换，第一页与下拉刷新用这个语义。
    func loadFeed(page: Int = 1, append: Bool = false) async {
        guard let url = API.feed(page: page, size: 15) else {
            applyFeedFailure(.server(code: 0, message: "地址拼错了。"))
            return
        }
        do {
            let response = try await client.get(url, as: FeedResponse.self)
            guard response.ok else {
                applyFeedFailure(.server(code: 200, message: "数据没准备好，稍后再试。"))
                return
            }
            if append, let existing = feedState.value {
                feedState = .loaded(response.merging(existing: existing))
            } else {
                feedState = .loaded(response)
            }
            lastFeedError = nil
        } catch let error as APIError {
            applyFeedFailure(error)
        } catch {
            applyFeedFailure(.network)
        }
    }

    /// 拉今日简报（只读快照，**不触发生成**）。
    func loadBrief() async {
        guard let url = API.brief() else {
            applyBriefFailure(.server(code: 0, message: "地址拼错了。"))
            return
        }
        do {
            let response = try await client.get(url, as: BriefResponse.self)
            guard response.ok else {
                applyBriefFailure(.server(code: 200, message: "数据没准备好，稍后再试。"))
                return
            }
            briefState = .loaded(response)
        } catch let error as APIError {
            applyBriefFailure(error)
        } catch {
            applyBriefFailure(.network)
        }
    }

    /// 文章详情（T07）。进页面调一次，详情关掉时 `clearArticle()`。
    /// `?id=` 用 `URLComponents` 拼（不手拼字符串）：`URLQueryItem` 会做百分号转义，边界不猜。
    func loadArticle(id: String) async {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            articleState = .failed(.server(code: 404, message: "这篇文章找不到了。"))
            return
        }
        guard var components = URLComponents(string: API.blogHost + API.articlePath) else {
            articleState = .failed(.server(code: 0, message: "地址拼错了。"))
            return
        }
        components.queryItems = [URLQueryItem(name: "id", value: trimmed)]
        guard let url = components.url else {
            articleState = .failed(.server(code: 0, message: "地址拼错了。"))
            return
        }

        articleState = .loading
        do {
            let response = try await client.get(url, as: ArticleResponse.self)
            guard response.ok else {
                articleState = .failed(.server(code: 200, message: "这篇文章没拿到，稍后再试。"))
                return
            }
            guard let detail = response.article else {
                articleState = .failed(.server(code: 404, message: "这篇文章找不到了。"))
                return
            }
            articleState = .loaded(detail)
        } catch let error as APIError {
            // 页面被关掉时会取消请求：这不是错误，别把状态写成失败
            if error.isCancelled { return }
            articleState = .failed(error)
        } catch {
            articleState = .failed(.network)
        }
    }

    /// 关掉详情时清空，避免下次进来先看到上一篇的正文
    func clearArticle() {
        articleState = .idle
    }

    // MARK: - toast

    /// 弹一条 toast，1.8s 后自动消失（PRD §5.2）。先取消旧任务（否则旧任务会按自己的节奏
    /// 清掉新 toast）；用 `[weak self]`；清理前比对文案（已换一条或已被清空就不动手）。
    func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            guard let self = self else { return }
            if self.toastMessage == message {
                self.toastMessage = nil
            }
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        toastMessage = nil
    }

    // MARK: - 失败归并（铁律：有内容就绝不清空，只弹 toast）

    private func applyFeedFailure(_ error: APIError) {
        if error.isCancelled { return }
        lastFeedError = error
        if feedState.hasContent { showToast(error.userMessage); return }
        feedState = .failed(error)
    }

    private func applyBriefFailure(_ error: APIError) {
        if error.isCancelled { return }
        if briefState.hasContent { showToast(error.userMessage); return }
        briefState = .failed(error)
    }

    private func setLastUpdatedIfNeeded() {
        if feedState.hasContent || briefState.hasContent {
            lastUpdatedAt = Date()
        }
    }
}
