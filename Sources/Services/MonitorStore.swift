import Foundation

/// 推送监控的唯一状态源（PRD P12 / 设计文档 §1.3.1）。
///
/// 与其他 Store 一致的职责边界：只做三件事 —— 发请求、把结果写进 `@Published`、维护「能不能再检查」。
/// 离线降级全部交给 `CachedLoader`（先缓存后网络、失败保留旧值），本文件没有一行自己实现的缓存。
///
/// 为什么是单例而不是注入 `@EnvironmentObject`：
/// 监控页是从「更多」用 `fullScreenCover` 推出来的，简报页底部那一行也要读同一份状态。
/// 单例 + `@ObservedObject` 少一条「模态是否继承环境对象」的隐形依赖（V2 在这上面踩过坑），
/// 也与批次 3 的 `SurveyStore.shared` 保持同一种写法。
final class MonitorStore: ObservableObject {

    /// 全 App 唯一实例
    static let shared = MonitorStore()

    /// 缓存键。改这里等于让所有用户的旧快照失效（只会多一次请求，不会出错）
    private static let cacheKey = "monitor.status.v1"

    /// 手动检查的服务端限频（秒）。服务端才是权威，这里只用于「按钮先自己冷却」的乐观提示
    static let rateLimitSeconds: Int = 60

    // MARK: - 对外只读状态

    /// 监控数据。`loaded` 里可能是缓存（`isStale` 由 `CachedLoader` 标注，本 Store 不重复表达）
    @Published private(set) var state: LoadState<MonitorResponse> = .idle
    /// 手动检查进行中（按钮转圈 + 禁用）
    @Published private(set) var isChecking: Bool = false
    /// 本次手动检查失败（只影响顶部提示，不清空已显示的版本卡）
    @Published private(set) var checkError: APIError?
    /// 429 后的剩余冷却秒数（> 0 时按钮禁用，并按秒就地提示）
    @Published private(set) var cooldownSeconds: Int = 0
    /// 底部轻提示（检查成功 / 失败）
    @Published private(set) var toast: String?
    /// 是否至少发起过一次加载（区分「还没开始」与「加载失败」）
    @Published private(set) var didRequestOnce: Bool = false

    // MARK: - 依赖

    private let loader: CachedLoader
    private let client: APIClient
    private var cooldownTask: Task<Void, Never>?
    private var isLoading: Bool = false

    init(loader: CachedLoader = .shared, client: APIClient = .shared) {
        self.loader = loader
        self.client = client
    }

    // MARK: - 派生

    /// 已加载到的响应（无数据时为 nil）
    var response: MonitorResponse? { state.value }

    /// 国服 + 国际服（服务端没给 apps 时为空数组，页面走「尚未检查」而不是假卡片）
    var apps: [MonitorAppVersion] { response?.apps ?? [] }

    /// 是否任一服有新版本（「更多」那一行与红点用）
    var hasNewVersion: Bool { response?.hasAnyNewVersion ?? false }

    /// 底部时段说明；取不到就是空串（调用方整行不渲染，绝不写「未知」）
    var pushWindowText: String {
        guard let window = response?.pushWindow else { return "" }
        return window.displayText
    }

    /// 最近一次成功检查的时刻
    var latestCheckedAt: Date? { response?.latestCheckedAt }

    /// 「更多」行右侧的状态字。不知道就返回 nil（不显示），绝不写「未知」
    var summaryText: String? {
        guard let response = response else { return nil }
        if response.hasAnyNewVersion { return "有新版本" }
        if response.hasAnyFailure { return "检查失败" }
        guard let checked = response.latestCheckedAt else { return nil }
        return "已是最新 · " + Formatters.relative(checked)
    }

    /// 检查按钮当前是否可点
    var canCheck: Bool { !isChecking && cooldownSeconds == 0 }

    // MARK: - 加载

    /// 拉一次监控状态。
    ///
    /// - Parameter force: 下拉刷新 / 手动检查成功后传 true（忽略「已加载过」的短路）
    ///
    /// 同一个 Store 可能被监控页与简报页同时触发，`isLoading` 挡掉并发重复请求
    /// （监控的 GET 没有限频，但没必要打两次）。
    @MainActor
    func load(force: Bool = false) async {
        if isLoading { return }
        if !force, state.hasContent { return }

        isLoading = true
        didRequestOnce = true

        await loader.load(
            key: Self.cacheKey,
            // 60 秒新鲜窗：服务端自己也是分钟级巡检，刷太勤只是白花流量
            maxAge: 60,
            fetch: { [self] in
                guard let url = Endpoint.url(base: Endpoint.briefBase, path: Endpoint.monitorPath) else {
                    throw APIError.server(code: 0, message: "地址拼错了。")
                }
                let response = try await self.client.get(url, as: MonitorResponse.self)
                guard response.ok else {
                    throw APIError.server(code: 200, message: "监控状态还没准备好，稍后再试。")
                }
                return response
            },
            emit: { [weak self] result in
                self?.apply(result)
            }
        )

        isLoading = false
    }

    /// 首帧用：只读磁盘快照（不发请求），避免「先骨架、后缓存」的两段跳
    @MainActor
    func loadFromCacheIfNeeded() async {
        guard !state.hasContent else { return }
        guard let cached = await loader.cachedValue(MonitorResponse.self, for: Self.cacheKey) else { return }
        guard !state.hasContent else { return }   // 期间网络已经回来了，别用旧快照盖掉新数据
        state = .loaded(cached)
    }

    // MARK: - 手动检查

    /// 手动触发一次服务端巡检。
    ///
    /// 三条纪律（PRD P12 空/错状态那一栏）：
    /// 1. 检查中按钮禁用（`isChecking`），不重复发请求；
    /// 2. 冷却中（429 之后）按钮同样禁用，并在原地倒计时剩余秒数；
    /// 3. 检查成功**不直接拿这个响应当页面数据** —— 该端点的响应结构与 GET 不同
    ///    （见 `MonitorCheckReceipt` 的注释），所以成功后回来源接口重拉一次。
    @MainActor
    func checkNow() async {
        guard canCheck else { return }

        isChecking = true
        checkError = nil
        defer { isChecking = false }

        guard let url = Endpoint.url(base: Endpoint.briefBase, path: Endpoint.monitorCheckPath) else {
            checkError = .server(code: 0, message: "地址拼错了。")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let raw = try await client.send(request)

            // 429：服务端限频（60 秒）。`Retry-After` 是权威剩余秒数，没有就按 60 兜底
            if raw.statusCode == 429 {
                let seconds = Self.retryAfterSeconds(from: raw) ?? Self.rateLimitSeconds
                startCooldown(seconds: seconds)
                checkError = .server(code: 429, message: "刚刚检查过，\(seconds) 秒后可以再试。")
                return
            }

            guard raw.isSuccess else {
                let message = APIErrorEnvelope.anyMessage(from: raw.data)
                checkError = .server(code: raw.statusCode, message: message)
                toast = message.isEmpty ? "检查没成功，待会儿再试。" : message
                return
            }

            // 回执只用来确认「这次真的跑完了」；喂给页面的是回来源接口重拉的权威状态
            let receipt = try? APIJSON.decoder.decode(MonitorCheckReceipt.self, from: raw.data)
            await load(force: true)

            if receipt?.ok == false {
                toast = "服务端说这次检查没成功，版本号可能没更新。"
            } else if let ageMin = receipt?.feed?.ageMin, ageMin > 180 {
                // 上游数据本身很旧：如实说，不假装"刚刚是最新的"
                toast = "已检查，但上游数据是 \(ageMin) 分钟前的。"
            } else {
                toast = "已检查，版本号已更新。"
            }
        } catch let error as APIError {
            checkError = error
            toast = error.userMessage
        } catch {
            checkError = .network
            toast = APIError.network.userMessage
        }
    }

    // MARK: - 冷却倒计时

    /// 读取 `Retry-After`。服务端可能给秒数，也可能给 HTTP 日期（RFC 7231 两种都合法），
    /// 这里只认秒数形态；日期形态退回默认 60 秒（宁可多等一会，也不要连发触发更长的封禁）。
    private static func retryAfterSeconds(from raw: APIRawResponse) -> Int? {
        guard let header = raw.header("Retry-After") else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = Int(trimmed) else { return nil }
        return min(max(seconds, 1), 600)
    }

    /// 启动按秒递减的冷却计时。重复调用会取消上一轮（不会出现两个计时器同时减）
    @MainActor
    private func startCooldown(seconds: Int) {
        cooldownTask?.cancel()
        cooldownSeconds = max(0, seconds)
        guard cooldownSeconds > 0 else { return }

        // 本方法是 @MainActor，`Task` 继承主 actor 隔离，所以循环里可以直接改 `cooldownSeconds`
        cooldownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                guard let self = self else { return }
                guard self.cooldownSeconds > 0 else { return }
                self.cooldownSeconds -= 1
            }
        }
    }

    /// 清掉提示（视图在 1.8s 后调用）
    @MainActor
    func clearToast() {
        toast = nil
    }

    /// App 退到后台时停掉计时器（省电，也避免回来时数字跳变）
    @MainActor
    func pauseCooldownTicking() {
        cooldownTask?.cancel()
        cooldownTask = nil
    }

    // MARK: - 落地

    /// 把一次 `LoadResult` 写进状态。
    ///
    /// `updated` 之类的去重键这个接口没有，所以只在「值真的不同」时才写 `@Published`：
    /// 每 60 秒刷新一次若每次都整页重建，监控页的卡片会闪。
    @MainActor
    private func apply(_ result: LoadResult<MonitorResponse>) {
        if let value = result.value {
            if state.value != value {
                state = .loaded(value)
            }
        } else if let error = result.error as? APIError {
            // 一点值都没有（首装 + 断网）：错误态；已有内容时不会走到这里
            state = .failed(error)
        } else if result.error != nil {
            state = .failed(.network)
        }
    }
}
