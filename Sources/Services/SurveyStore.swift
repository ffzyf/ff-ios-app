import Foundation
import Network

/// 问卷数据的唯一状态源（列表 / 详情 / 结果 / 公开填答）。
///
/// 职责边界（设计文档 §1.3.1）：Store 只做三件事 —— 发请求、把结果写进 `@Published`、
/// 维护"当前看的是哪一份"。请求与离线降级交给批次 1 定稿的 `CachedLoader`，
/// 这里一行 `URLSession` 都没有。
///
/// 为什么是单例（而不是 `@EnvironmentObject`）：
/// 1. 问卷的「一份列表 / 一份详情 / 一份结果」本来就是**一个账号一份数据**，
///    全局一份状态比每页一份更不容易串号；
/// 2. 「问卷管理」分组在设置页里（会从概览齿轮与更多页两处弹出），
///    模态呈现不保证继承环境对象 —— 单例 + `@ObservedObject` 能彻底绕开这条依赖
///    （`AppearanceSection` 已经用同一套办法解决过同一个问题）。
///
/// 为什么不标 `@MainActor`：它被 View 的默认值直接初始化，而 View 的属性初始化器是
/// 非隔离上下文，标了会在 Swift 5 的 minimal 并发检查下报"隔离属性被非隔离上下文引用"。
/// 所有调用点都在主线程（View 的 `.task` / 按钮回调），行为上等价。
final class SurveyStore: ObservableObject {

    // MARK: - 单例

    /// 全 App 唯一实例
    static let shared = SurveyStore()

    /// 问卷快照的键前缀。**退出登录必须整段删掉**（设计文档 R20），
    /// 所以这里与 `SurveyAuth.logout()` 共用同一个常量，不允许各写一份字符串。
    static let snapshotPrefix = "survey."

    // MARK: - 列表状态

    /// 列表（PRD P08）。`nil` = 还没请求过
    @Published private(set) var list: LoadResult<SurveyListResponse>?
    @Published private(set) var isLoadingList: Bool = false

    // MARK: - 详情状态

    @Published private(set) var detail: LoadResult<SurveyDetail>?
    /// 当前详情属于哪份问卷（`nil` = 没在看详情）
    @Published private(set) var detailId: String?
    @Published private(set) var isLoadingDetail: Bool = false

    // MARK: - 结果状态

    @Published private(set) var result: LoadResult<SurveyResultResponse>?
    @Published private(set) var resultId: String?
    @Published private(set) var isLoadingResult: Bool = false

    // MARK: - 填答状态

    @Published private(set) var form: LoadResult<SurveyPublicResponse>?
    @Published private(set) var formId: String?
    @Published private(set) var isLoadingForm: Bool = false
    @Published private(set) var isSubmitting: Bool = false

    // MARK: - 通用状态

    /// 发布 / 截止请求在飞
    @Published private(set) var isPublishing: Bool = false
    /// 当前是否联网（`NWPathMonitor`）。填答页用它禁掉「提交」按钮
    @Published private(set) var isOnline: Bool = true
    /// 一次性轻提示（复制成功 / 已发布 / 请求失败），页面用 `PageToast` 渲染
    @Published private(set) var toast: String?

    // MARK: - 依赖

    private let client: APIClient
    private let auth: SurveyAuth
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "top.skyzyf.survey.path")

    init(client: APIClient = .shared, auth: SurveyAuth = .shared) {
        self.client = client
        self.auth = auth
        // 断网时"禁止提交"必须是真的知道断网，而不是等提交失败才提示。
        // 首帧默认 true（假定有网）：路径监视器的第一次回调有几十毫秒延迟，
        // 期间把按钮画成灰色会让正常用户莫名其妙地点不动。
        monitor.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            DispatchQueue.main.async {
                self?.isOnline = online
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - 派生

    /// 列表数据（有值就渲染）
    var summaries: [SurveySummary] { list?.value?.surveys ?? [] }

    /// 顶部三个计数（拿不到全 0，不编造）
    var counts: SurveyCounts {
        return list?.value?.counts ?? SurveyCounts(total: 0, published: 0, responses: 0)
    }

    /// 列表本次是否失败但有旧内容（页面挂顶部「离线」条）
    var isListDegraded: Bool {
        guard let list = list else { return false }
        return list.error != nil && list.value != nil
    }

    /// 本次失败的原因（没有任何内容时给整页错误态用）
    var listFailure: APIError? {
        guard let list = list else { return nil }
        guard list.value == nil else { return nil }
        return list.error as? APIError
    }

    var detailFailure: APIError? {
        guard let detail = detail, detail.value == nil else { return nil }
        return detail.error as? APIError
    }

    var resultFailure: APIError? {
        guard let result = result, result.value == nil else { return nil }
        return result.error as? APIError
    }

    var formFailure: APIError? {
        guard let form = form, form.value == nil else { return nil }
        return form.error as? APIError
    }

    /// 当前填答的问卷（有缓存就先给缓存）
    var publicForm: SurveyPublic? { form?.value?.survey }

    // MARK: - 列表

    /// 加载列表。
    ///
    /// **刻意不做「缓存优先」**（PRD P08：列表每次进页面都刷新）：问卷的答卷数每天都在变，
    /// 给用户看一份 3 天前的「共 48 份」比转 0.5 秒圈更糟。所以这里既不读快照也不写快照，
    /// 失败时保留**内存里**上一次的值 —— 用户从详情退回来时不会看到空白。
    func loadList(force: Bool = false) async {
        guard !isLoadingList else { return }
        if !force, list?.value != nil { return }

        guard let url = API.surveyList() else {
            list = .degraded(list?.value, error: APIError.server(code: 0, message: "地址拼错了。"))
            return
        }

        isLoadingList = true
        defer { isLoadingList = false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 服务端对所有问卷响应都写了 `Cache-Control: no-store`，这里再关一次本地缓存：
        // 列表会随答卷数变化，"看到昨天的数字"比"多转半秒"更糟。
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        if let cookie = auth.cookieHeader {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        do {
            let response = try await client.send(request, as: SurveyListResponse.self)
            guard response.ok else {
                throw APIError.server(code: 200, message: "问卷列表没准备好，稍后再试。")
            }
            list = .fresh(response)
        } catch {
            applyListFailure(error)
        }
    }

    private func applyListFailure(_ error: Error) {
        if isUnauthorized(error) {
            // 401：凭证过期。清掉凭证，页面会因为 `auth.isLoggedIn == false` 自动回到登录引导
            auth.invalidate()
            list = nil
            return
        }
        if let existing = list?.value {
            list = .degraded(existing, error: error)
        } else {
            list = .failed(error)
        }
    }

    // MARK: - 详情

    /// 加载单问卷详情（缓存优先：进详情页先给上次的结构，再静默换成新的）。
    func loadDetail(id: String, force: Bool = false) async {
        guard !id.isEmpty else { return }
        if !force, detailId == id, detail?.value != nil { return }
        await loadDetailOnMain(id: id)
    }

    /// 加载主体（`@MainActor`）。
    ///
    /// 为什么单独拆一个 `@MainActor` 方法：`CachedLoader` 是 `@MainActor` 的类，
    /// 而本类刻意不标 `@MainActor`（见类型注释）。让"取 loader + 用它"整个发生在主 actor 上，
    /// 比把 loader 引用跨 actor 传回来更稳 —— 非 Sendable 的类型不该跨隔离边界。
    @MainActor
    private func loadDetailOnMain(id: String) async {
        detailId = id
        isLoadingDetail = true

        let key = SurveyStore.snapshotPrefix + "detail." + id + ".v1"
        let client = self.client
        let cookie = auth.cookieHeader

        await CachedLoader.shared.load(
            key: key,
            // 60 秒新鲜窗：只影响"缓存这次要不要标成可能过期"，不影响是否展示
            maxAge: 60,
            fetch: { () async throws -> SurveyDetail in
                guard let url = API.surveyDetail(id: id) else {
                    throw APIError.server(code: 0, message: "地址拼错了。")
                }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 15
                if let cookie = cookie {
                    request.setValue(cookie, forHTTPHeaderField: "Cookie")
                }
                let response = try await client.send(request, as: SurveyDetailResponse.self)
                guard response.ok else {
                    throw APIError.server(code: 200, message: "这份问卷暂时读不到，稍后再试。")
                }
                return response.survey
            },
            emit: { [weak self] loaded in
                guard let self = self else { return }
                if self.isUnauthorized(loaded.error) {
                    self.auth.invalidate()
                    self.detail = nil
                    return
                }
                if let value = loaded.value {
                    self.detail = LoadResult(value: value, isStale: loaded.isStale, error: loaded.error)
                } else if let existing = self.detail?.value {
                    // 没有任何可用值（首装 + 断网）：保留上一次成功的详情，别把页面清空
                    self.detail = .degraded(existing, error: loaded.error)
                } else {
                    self.detail = loaded
                }
            }
        )

        isLoadingDetail = false
    }

    // MARK: - 结果

    /// 加载结果看板（PRD P11）。缓存优先：进来先看到上次的分布，再换成最新。
    func loadResult(id: String, force: Bool = false) async {
        guard !id.isEmpty else { return }
        if !force, resultId == id, result?.value != nil { return }
        await loadResultOnMain(id: id)
    }

    /// 加载主体（`@MainActor`，理由同 `loadDetailOnMain`）
    @MainActor
    private func loadResultOnMain(id: String) async {
        resultId = id
        isLoadingResult = true

        let key = SurveyStore.snapshotPrefix + "result." + id + ".v1"
        let client = self.client
        let cookie = auth.cookieHeader

        await CachedLoader.shared.load(
            key: key,
            maxAge: 60,
            fetch: { () async throws -> SurveyResultResponse in
                guard let url = API.surveyResult(id: id) else {
                    throw APIError.server(code: 0, message: "地址拼错了。")
                }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 20
                if let cookie = cookie {
                    request.setValue(cookie, forHTTPHeaderField: "Cookie")
                }
                let response = try await client.send(request, as: SurveyResultResponse.self)
                guard response.ok else {
                    throw APIError.server(code: 200, message: "统计还没出来，稍后再试。")
                }
                return response
            },
            emit: { [weak self] loaded in
                guard let self = self else { return }
                if self.isUnauthorized(loaded.error) {
                    self.auth.invalidate()
                    self.result = nil
                    return
                }
                if let value = loaded.value {
                    self.result = LoadResult(value: value, isStale: loaded.isStale, error: loaded.error)
                } else if let existing = self.result?.value {
                    self.result = .degraded(existing, error: loaded.error)
                } else {
                    self.result = loaded
                }
            }
        )

        isLoadingResult = false
    }

    // MARK: - 公开填答

    /// 加载填答题面（公开接口，不需要 Cookie）。
    ///
    /// **刻意不缓存**：题面可能刚被发布者改过，用户按旧题作答提交会被服务端拒掉；
    /// 断网时给一张明确的错误卡 + 重试，比给一份可能过期的题面更诚实。
    func loadForm(id: String, force: Bool = false) async {
        guard !id.isEmpty else { return }
        if !force, formId == id, form?.value != nil { return }

        // 先记住"同一份问卷"上次的题面（失败时可以退回它，绝不退回另一份问卷的题面）
        let previous: SurveyPublic? = (formId == id) ? form?.value?.survey : nil
        formId = id
        isLoadingForm = true
        defer { isLoadingForm = false }

        guard let url = API.surveyPublicForm(id: id) else {
            form = .failed(APIError.server(code: 0, message: "地址拼错了。"))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 公开接口给了 `max-age=60`，但填答页必须拿到"现在的"题面，所以绕过本地缓存
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        do {
            let raw = try await client.send(request)
            if raw.statusCode == 403 || raw.statusCode == 404 {
                // 未发布 / 已截止 / 不存在：服务端说的原话最准，直接用。
                // 这里**不退回旧题面** —— 问卷已经关了，还让用户填就是骗他。
                let message = APIErrorEnvelope.anyMessage(from: raw.data)
                form = .failed(APIError.server(code: raw.statusCode, message: message))
                return
            }
            guard raw.isSuccess else {
                throw APIError.server(code: raw.statusCode, message: APIErrorEnvelope.anyMessage(from: raw.data))
            }
            let response = try APIJSON.decoder.decode(SurveyPublicResponse.self, from: raw.data)
            form = .fresh(response)
        } catch {
            if let previous = previous {
                form = LoadResult(value: SurveyPublicResponse(ok: true, survey: previous, responseCount: nil),
                                  isStale: true,
                                  error: error)
            } else {
                form = .failed(error)
            }
        }
    }

    /// 提交答卷（公开接口，不需要 Cookie）。
    ///
    /// 失败时**不清理任何本地状态**：用户填了 20 题，不能因为一次断网就清空
    /// （PRD P10「提交失败 → 保留已填内容」）。清理动作由页面在"提交成功"后自己做。
    func submit(id: String, answers: [String: SurveyAnswerValue]) async -> SurveySubmitOutcome {
        guard !id.isEmpty else { return .failure("问卷 id 丢了，回上一页重进一次。") }
        guard !isSubmitting else { return .failure("正在提交，稍等一下。") }
        guard let url = API.surveySubmit(id: id) else { return .failure("地址拼错了。") }

        isSubmitting = true
        defer { isSubmitting = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.httpBody = try? JSONEncoder().encode(SubmitBody(answers: answers))

        do {
            let raw = try await client.send(request)
            guard raw.isSuccess else {
                let message = APIErrorEnvelope.anyMessage(from: raw.data)
                return .failure(message.isEmpty ? "提交没成功，再试一次。" : message)
            }
            let ack = try? APIJSON.decoder.decode(SurveySubmitResponse.self, from: raw.data)
            let tip = (ack?.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // 答题后列表 / 结果都变了，让下一次进页面必然重拉
            invalidateAggregates()
            return .success(tip.isEmpty ? "提交成功，感谢参与！" : tip)
        } catch let error as APIError {
            if case .cancelled = error { return .failure("提交已取消。") }
            return .failure(SurveyStore.networkMessage(error))
        } catch {
            return .failure("提交没成功，再试一次。")
        }
    }

    // MARK: - 发布 / 截止

    /// 发布（PRD P09「发布设置」，App 侧必须二次确认后才调）
    func publish(id: String) async -> Bool {
        return await performAction("publish", id: id)
    }

    /// 截止
    func close(id: String) async -> Bool {
        return await performAction("close", id: id)
    }

    private func performAction(_ action: String, id: String) async -> Bool {
        guard let url = API.surveyActions(id: id) else {
            toast = "地址拼错了。"
            return false
        }
        guard let cookie = auth.cookieHeader else {
            auth.invalidate()
            return false
        }

        isPublishing = true
        defer { isPublishing = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let payload: [String: Any] = ["action": action]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let raw = try await client.send(request)
            if raw.statusCode == 401 {
                auth.invalidate()
                return false
            }
            guard raw.isSuccess else {
                let message = APIErrorEnvelope.anyMessage(from: raw.data)
                toast = message.isEmpty ? "没操作成功，稍后再试。" : message
                return false
            }
            toast = (action == "publish") ? "已发布，可以开始收答卷了。" : "已截止，填答入口已关闭。"
            // 状态变了：详情与列表都要重拉（列表的徽标、详情的按钮可用性都跟着变）
            await loadDetail(id: id, force: true)
            await loadList(force: true)
            return true
        } catch let error as APIError {
            if case .cancelled = error { return false }
            toast = SurveyStore.networkMessage(error)
            return false
        } catch {
            toast = "没操作成功，稍后再试。"
            return false
        }
    }

    // MARK: - 会话

    /// 进工作台前校验一次凭证（30 天有效期内也可能已失效）
    func verifySession() async {
        guard auth.isLoggedIn else { return }
        let alive = await auth.verify()
        if !alive {
            resetMemory()
        }
    }

    /// 退出登录：清凭证 + 清快照 + 清内存。
    ///
    /// 三件事必须在同一个入口发生（设计文档 R20）：只清凭证的话，
    /// 下一个账号进来会先看到上一个账号的列表快照（`CachedLoader` 的缓存优先会照给）。
    func signOut() async {
        await auth.logout()
        resetMemory()
    }

    /// 只清内存（登录态变化 / 会话失效时调；不动 Keychain 与快照）
    func resetMemory() {
        list = nil
        detail = nil
        detailId = nil
        result = nil
        resultId = nil
        form = nil
        formId = nil
        isLoadingList = false
        isLoadingDetail = false
        isLoadingResult = false
        isLoadingForm = false
    }

    /// 答卷数变了：把"聚合类"缓存清掉，保证下次进列表 / 结果一定重拉
    private func invalidateAggregates() {
        list = nil
        if let id = resultId {
            result = nil
            resultId = nil
            Task { await removeSnapshot(SurveyStore.snapshotPrefix + "result." + id + ".v1") }
        }
        if let id = detailId {
            detail = nil
            detailId = nil
            Task { await removeSnapshot(SurveyStore.snapshotPrefix + "detail." + id + ".v1") }
        }
    }

    private func removeSnapshot(_ key: String) async {
        await SnapshotCache.shared.remove(for: key)
    }

    // MARK: - 提示

    /// 手动挂一条 toast（页面复制链接之类的动作复用同一套提示）
    func showToast(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        toast = trimmed.isEmpty ? nil : trimmed
    }

    func clearToast() {
        toast = nil
    }

    // MARK: - 私有工具

    /// 401 = 会话失效（唯一的"清凭证"信号）。
    ///
    /// 为什么不看响应体：中间件与 `util.js` 的 401 体是 `{error:"字符串"}`，
    /// 没有错误码字段可用 —— 状态码才是唯一可靠的判据。
    private func isUnauthorized(_ error: Error?) -> Bool {
        guard let apiError = error as? APIError else { return false }
        guard case .server(let code, _) = apiError else { return false }
        return code == 401
    }

    private static func networkMessage(_ error: APIError) -> String {
        switch error {
        case .network:
            return "网络断了，检查一下再试。"
        case .cancelled:
            return "请求已取消。"
        case .decoding:
            return "数据没读懂，稍后再试。"
        case .server(_, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "服务器没答上来，稍后再试。" : trimmed
        }
    }

    /// 提交用的信封：`{"answers": { qid: 值 }}`
    private struct SubmitBody: Encodable {
        let answers: [String: SurveyAnswerValue]
    }
}
