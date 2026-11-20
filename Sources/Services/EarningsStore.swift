import Foundation

/// 收益工作台的数据源（V3.2 新增）。
///
/// 只做五件事：
/// 1. 拉 `GET /api/app/earnings`（**唯一需要 `ce_auth` 的 app 接口**）；
/// 2. 把上一份成功响应缓存下来，断网 / 地铁里也能看昨天的数；
/// 3. 401 时让 `EarningsAuth` 清凭证、并**连带清掉本模块缓存**（避免退出后还看得到上一个账号的钱）；
/// 4. 把 `amountUnit` 写回 `EarningsMoney` —— 金额换算只发生在那里，本层不做任何 `÷100`；
/// 5. 追加一笔收入（`POST /api/app/earnings/entry`）。**写服务端、不写本地** ——
///    账只有一份，App 与网页端读的是同一个 KV；本地落一份就成了第二个真相源，必然对不上账。
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
    /// 平台公告（5.5.2，与 `activities` 同一次响应）。只喂 AI 上下文，不上界面。
    @Published private(set) var notices: [EarningsNotice] = []
    @Published private(set) var lastUpdated: Date?
    /// 这份数是本地缓存（这次请求没成功）
    @Published private(set) var isStale: Bool = false
    @Published private(set) var isLoading: Bool = false
    /// 写请求在飞（防连点重复提交；UI 的保存按钮也据此转圈）
    @Published private(set) var isWriting: Bool = false
    /// 可直接上屏的一句话；nil = 没问题
    @Published private(set) var errorText: String?

    // MARK: - 追光计划瓜分（T11，只读渲染服务端结果）
    /// 服务端最近一次瓜分结果（金额整数分，端侧零计算）
    @Published private(set) var zgResult: ZGResult?
    @Published private(set) var zgTopics: ZGTopicsData?
    @Published private(set) var zgMerge: ZGMergeData?
    @Published private(set) var zgRules: ZGRules?
    @Published private(set) var zgClean: ZGCleanReport?
    /// 这些数来自本地缓存（这次没拉到新的）—— UI 据此显示「离线数据，可能不是最新」
    @Published private(set) var zgIsStale: Bool = false
    @Published private(set) var zgIsLoading: Bool = false

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

    // MARK: - 记账（写接口）

    /// 写请求的最大尝试次数：**409 乐观锁冲突只自动重试一次**（共 2 次）。
    /// 再失败就交给人 —— 连续重试会把"两个端同时在改"变成打服务端。
    private static let writeMaxAttempts = 2

    /// 追加一笔收入（`POST /api/app/earnings/entry`）。
    ///
    /// 三条与 `load()` 完全一致的硬约束（同一个真相源，不允许另起一套）：
    /// 1. 凭证只从 `auth.cookieHeader` 取（底层是 `EarningsKeychain`），与 `load()` 同一来源；
    /// 2. 401 → `handleExpired()`（清凭证 + 清内存 + 清快照），与 `load()` 的失效路径一字不差；
    /// 3. 金额一律整数分；`EarningsEntryInput.amount`（Double，元）只是契约要求的兼容字段。
    ///
    /// 错误策略：
    /// · **409**（服务端乐观锁冲突，body 里 `retry: true`）→ 自动重试一次；再失败抛
    ///   `APIError.server(code: 409, message: "数据已变更，请重试")`，用户看到的是可读的一句话；
    /// · 其他 4xx/5xx → 服务端原话（抽不到就让 `APIError` 的兜底文案接管）；
    /// · 传输入错（离线 / 超时）→ `APIError.network`，由 `userMessage` 给一句人话。
    ///
    /// 成功后**不做本地算账**：`summary` 直接取服务端返回的那一份（它是唯一可信来源）。
    /// - Parameter input: 请求体（`title`/`type`、`amount`/`amountCents`、`date`/`time` 双写）
    /// - Returns: 服务端返回的 `{ok, entry, summary}`
    @discardableResult
    func addEntry(_ input: EarningsEntryInput) async throws -> EarningsAddResponse {
        // 没凭证就别打接口：这次必然 401，还会白清一次缓存
        guard let cookie = auth.cookieHeader else {
            throw APIError.server(code: 401, message: "登录已过期，重新登录一下。")
        }
        // 防连点：上一笔还在飞就不要再发一条（否则记两笔一模一样的账）
        guard !isWriting else {
            throw APIError.server(code: 429, message: "上一笔还在保存，稍等一下。")
        }
        isWriting = true
        defer { isWriting = false }

        var attempt = 1
        while true {
            let raw = try await client.send(makeEntryRequest(input, cookie: cookie))
            switch raw.statusCode {
            case 200..<300:
                guard let decoded = try? APIJSON.decoder.decode(EarningsAddResponse.self, from: raw.data),
                      decoded.ok else {
                    throw APIError.decoding
                }
                await applyAddition(decoded, activityId: input.activityId)
                return decoded
            case 401:
                // 与 load() 一致：不是"网络不好"，是凭证废了
                errorText = "登录已过期，重新登录一下。"
                await handleExpired()
                throw APIError.server(code: 401, message: "登录已过期，重新登录一下。")
            case 409:
                // 服务端乐观锁冲突：`retry: true` 表示"原样再发一次就行"
                if Self.isRetryableConflict(raw.data), attempt < Self.writeMaxAttempts {
                    attempt += 1
                    continue
                }
                throw APIError.server(code: 409, message: "数据已变更，请重试")
            default:
                throw APIError.server(code: raw.statusCode, message: APIErrorEnvelope.anyMessage(from: raw.data))
            }
        }
    }

    // MARK: - 建活动（写接口）

    /// 新建一个活动（`POST /api/app/earnings/activity`）。
    ///
    /// 与 `addEntry` 完全同一套规矩（同一个真相源，不允许另起一套）：
    /// 1. 凭证只从 `auth.cookieHeader` 取，与 `load()` 同一来源；
    /// 2. 401 → `handleExpired()`（清凭证 + 清内存 + 清快照），与 `load()` 的失效路径一字不差；
    /// 3. 防连点：`isWriting` 在飞时直接拒（否则双击会建出两个同名活动 —— 第二个会被服务端 409 挡下，
    ///    但没必要多打一次接口）。
    ///
    /// 错误策略（与 `addEntry` 一致的"服务端说了人话就照原样转给用户"）：
    /// · **409**（同平台重名 / 乐观锁耗尽）→ 抛 `APIError.server(code: 409, message: 服务端原话)`。
    ///   注意这里**不自动重试**：`entry` 的 409 是"数据变了，原样再发一次"，而建活动的 409
    ///   是业务结论（该平台下已有同名活动），重发一百次也是同一个结果；
    /// · 其他 4xx/5xx → 服务端原话（抽不到就让 `APIError` 的兜底文案接管）；
    /// · 传输入错 → `APIError.network`，由 `userMessage` 给一句人话。
    ///
    /// 成功后**不本地拼接**，而是 `await load(force: true)` 重拉一遍：
    /// 新建活动会改 `summary.activityCount` / `platformCount` / `platforms[]` 三处口径，
    /// 本地拼一条活动出来容易和服务端算法漂移（尤其平台聚合是按金额排序的），
    /// 直接读服务端那份最省心 —— 一次活动创建对网络往返不敏感，慢一点没关系。
    /// - Parameters:
    ///   - name: 活动名（调用方已 trim；服务端还会再校验 ≤ 30 字）
    ///   - platform: 归属平台（固定 5 个之一，或用户自定义；服务端校验 ≤ 12 字）
    /// - Returns: 服务端返回的新活动（id 由服务端生成，App 不能自己造）
    @discardableResult
    func addActivity(name: String, platform: String) async throws -> EarningsActivity {
        guard let cookie = auth.cookieHeader else {
            throw APIError.server(code: 401, message: "登录已过期，重新登录一下。")
        }
        guard !isWriting else {
            throw APIError.server(code: 429, message: "上一步还在保存，稍等一下。")
        }
        isWriting = true
        defer { isWriting = false }

        let raw = try await client.send(makeActivityRequest(name: name, platform: platform, cookie: cookie))
        switch raw.statusCode {
        case 200..<300:
            guard let decoded = try? APIJSON.decoder.decode(EarningsActivityAddResponse.self, from: raw.data),
                  decoded.ok else {
                throw APIError.decoding
            }
            // 写成功 → 让缓存失效 → 重拉（活动数与平台数都变了，交给服务端算）
            await SnapshotCache.shared.remove(for: Self.cacheKey)
            await load(force: true)
            // 兜底：上一次 `load` 若正好有请求在飞会被它的 `guard !isLoading` 跳过，
            // 此时列表里还没有这条新活动。用服务端返回的对象补一条到头部（与 web 端 unshift 一致），
            // 保证弹页能立刻选中它记账；`summary` 一个数都不动，等下一次 `load` 自然对齐。
            if activities.contains(where: { $0.id == decoded.activity.id }) == false,
               decoded.activity.id.isEmpty == false {
                activities.insert(decoded.activity, at: 0)
            }
            return decoded.activity
        case 401:
            errorText = "登录已过期，重新登录一下。"
            await handleExpired()
            throw APIError.server(code: 401, message: "登录已过期，重新登录一下。")
        case 409:
            // 业务型冲突（同平台重名）：服务端原话最准确，抽不到才用兜底文案。**不重试**。
            let message = APIErrorEnvelope.anyMessage(from: raw.data)
            throw APIError.server(code: 409, message: message.isEmpty ? "该平台下已有同名活动" : message)
        default:
            throw APIError.server(code: raw.statusCode, message: APIErrorEnvelope.anyMessage(from: raw.data))
        }
    }

    /// 构造建活动请求：POST + `{name, platform}` + `Cookie: ce_auth=…`。
    private func makeActivityRequest(name: String, platform: String, cookie: String) throws -> URLRequest {
        guard let url = API.earningsActivity() else {
            throw APIError.server(code: 0, message: "地址拼错了。")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        do {
            request.httpBody = try JSONEncoder().encode(EarningsActivityInput(name: name, platform: platform))
        } catch {
            throw APIError.decoding
        }
        return request
    }

    // MARK: - 内部

    /// 构造写请求：POST + JSON body + `Cookie: ce_auth=…`（凭证来源与 `load()` 相同）。
    private func makeEntryRequest(_ input: EarningsEntryInput, cookie: String) throws -> URLRequest {
        guard let url = API.earningsEntry() else {
            throw APIError.server(code: 0, message: "地址拼错了。")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        do {
            request.httpBody = try JSONEncoder().encode(input)
        } catch {
            // 编码都失败了就别发一个空 body 去撞服务端
            throw APIError.decoding
        }
        return request
    }

    /// 409 的响应体里 `retry: true` 表示「服务端乐观锁冲突，可原样重试」。
    /// 解析不出来按**可重试**处理：这个接口上的 409 只可能是冲突，不是参数错误。
    private static func isRetryableConflict(_ data: Data) -> Bool {
        struct ConflictBody: Decodable { let retry: Bool? }
        guard let body = try? APIJSON.decoder.decode(ConflictBody.self, from: data) else { return true }
        return body.retry ?? true
    }

    /// 写完之后的本地落地，四件事：
    ///
    /// 1. `summary` 用服务端返回的那一份 —— 不在本地加金额，避免与网页端对不上账；
    /// 2. 新 entry 并入对应活动的 `entries` —— 「活动流水」立刻多出这一行，
    ///    即使紧接着断网也不会显示成"没记上"；
    /// 3. **删掉快照缓存** —— 否则下一次 `load()`（120s 新鲜窗内）会先把「加之前」的
    ///    旧快照 emit 出来，页面数字先跳回去再跳回来；
    /// 4. **后台补拉一次全量** —— 平台聚合 / 平台占比这些只有 `GET` 才带得全，
    ///    用 `Task` 补而不是 `await`，是为了不让「再记一笔」等这一次请求。
    ///
    /// 本地找不到这个活动（网页端刚建的，App 还没拉到）也不慌：第 4 步的全量响应会把它带回来。
    private func applyAddition(_ response: EarningsAddResponse, activityId: String) async {
        summary = response.summary
        lastUpdated = Date()
        isStale = false
        errorText = nil
        mergeEntry(response.entry, activityId: activityId)
        await SnapshotCache.shared.remove(for: Self.cacheKey)
        // 显式 `self`：`Task` 的闭包是 escaping 的，引用实例成员必须写出来
        Task { await self.load(force: true) }
    }

    /// 把新 entry 并入对应活动（幂等：同一 id 不重复插入，重试 / 重复响应都不会记两遍）。
    private func mergeEntry(_ entry: EarningsEntry, activityId: String) {
        guard let index = activities.firstIndex(where: { $0.id == activityId }) else { return }
        let activity = activities[index]
        var entries = activity.entries.filter { $0.id != entry.id }
        entries.append(entry)
        activities[index] = EarningsActivity(
            id: activity.id,
            name: activity.name,
            platform: activity.platform,
            time: activity.time,
            closedAt: activity.closedAt,
            entries: entries
        )
    }

    private func apply(_ response: EarningsResponse, stale: Bool) {
        // 单位只在这里落地：全工程其它地方都靠 `EarningsMoney.formatCents` 读这个值
        EarningsMoney.currentUnit = response.amountUnit
        summary = response.summary
        activities = response.activities
        platforms = response.platforms
        // 公告跟着同一次响应走：AI 那边随时可能来读，不能等用户点进公告模块
        notices = response.notices
        lastUpdated = Date()
        isStale = stale
        errorText = nil
    }

    private func clear() {
        summary = nil
        activities = []
        platforms = []
        notices = []
        lastUpdated = nil
        isStale = false
        errorText = nil
        // 瓜分结果与收益同属一个账号，登出一起清（不留上一个账号的账）
        zgResult = nil
        zgTopics = nil
        zgMerge = nil
        zgRules = nil
        zgClean = nil
        zgIsStale = false
    }

    /// 会话失效：清凭证 → 清内存 → 清缓存（三件一起做，少一件都会留下上一个账号的痕迹）
    private func handleExpired() async {
        auth.invalidate()
        clear()
        await SnapshotCache.shared.removeAll(withPrefix: Self.snapshotPrefix)
    }
}

// MARK: - 追光计划瓜分计算（T11，ZG-032/033）
//
// 三条硬约束与既有 `load()` 完全一致：
// 1. 凭证只从 `auth.cookieHeader` 取（同一个真相源）；
// 2. 缓存 + 离线降级统一走 `CachedLoader` —— 先给旧值、再发请求、失败保留旧值并置 `zgIsStale`；
// 3. **端侧零计算**：金额是服务端 `zg-calc.js` 算好的整数分，本层只解码、只缓存、不碰公式。
extension EarningsStore {

    /// 瓜分模块的缓存键。带 `snapshotPrefix`，登出时会被 `handleExpired()` 一并清掉。
    private static func zgKey(_ name: String, period: Int) -> String {
        return "\(snapshotPrefix)zg.\(name).\(period)"
    }

    /// 构造只读 GET 请求：注入 Cookie + JSON Accept。
    private func zgGetRequest(_ url: URL?, cookie: String) throws -> URLRequest {
        guard let url else { throw APIError.server(code: 0, message: "地址拼错了。") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        return request
    }

    /// 解码信封：HTTP 200 但 `ok:false` 也算业务失败（服务端 fail() 的约定）。
    private func zgUnwrap<T: Codable & Sendable>(_ envelope: ZGEnvelope<T>) throws -> T {
        guard envelope.ok, let data = envelope.data else {
            throw APIError.server(code: envelope.status ?? 200, message: envelope.error ?? "数据暂时读不到。")
        }
        return data
    }

    /// 通用只读拉取（缓存优先 + 联网刷新 + 离线降级）。
    private func zgLoad<T: Codable & Sendable>(
        name: String,
        period: Int,
        maxAge: TimeInterval = 120,
        url: URL?,
        emit: @escaping (T?, Bool) -> Void
    ) async {
        emit(nil, false)
        guard let cookie = auth.cookieHeader else {
            // 未登录不带凭证硬打接口：直接给"离线"空态，不发必然 401 的请求
            emit(nil, true)
            return
        }
        guard !zgIsLoading else { return }
        zgIsLoading = true
        defer { zgIsLoading = false }

        let client = self.client
        await CachedLoader.shared.load(
            key: Self.zgKey(name, period: period),
            maxAge: maxAge,
            fetch: {
                let request = try self.zgGetRequest(url, cookie: cookie)
                let envelope = try await client.send(request, as: ZGEnvelope<T>.self)
                return try self.zgUnwrap(envelope)
            },
            emit: { loaded in
                emit(loaded.value, loaded.isStale)
            }
        )
    }

    /// 拉瓜分结果（服务端算好的整数分）。`force=true` 压缩新鲜窗。
    func fetchZGResult(period: Int, force: Bool = false) async {
        await zgLoad<ZGResult>(
            name: "result", period: period, maxAge: force ? 0 : 120,
            url: API.zgResult(period: period)
        ) { [weak self] value, stale in
            guard let self else { return }
            // 离线降级：本次没拉到就保留上一次的值，绝不清空已上屏的结果
            if let value {
                self.zgResult = value
                self.zgIsStale = stale
            } else if self.zgResult == nil {
                self.zgIsStale = true
            }
        }
    }

    /// 拉话题告警。
    func fetchZGTopics(period: Int) async {
        await zgLoad<ZGTopicsData>(name: "topics", period: period, url: API.zgTopics(period: period)) { [weak self] value, _ in
            guard let self else { return }
            if let value { self.zgTopics = value }
        }
    }

    /// 拉合并建议。
    func fetchZGMerge(period: Int) async {
        await zgLoad<ZGMergeData>(name: "merge", period: period, url: API.zgMerge(period: period)) { [weak self] value, _ in
            guard let self else { return }
            if let value { self.zgMerge = value }
        }
    }

    /// 拉规则口径。
    func fetchZGRules(period: Int) async {
        await zgLoad<ZGRules>(name: "rules", period: period, url: API.zgRules(period: period)) { [weak self] value, _ in
            guard let self else { return }
            if let value { self.zgRules = value }
        }
    }

    /// 拉清洗报告。
    func fetchZGCleanReport(period: Int) async {
        await zgLoad<ZGCleanReport>(name: "clean", period: period, url: API.zgCleanReport(period: period)) { [weak self] value, _ in
            guard let self else { return }
            if let value { self.zgClean = value }
        }
    }

    /// 一次把瓜分页所需的五份只读数据都拉齐。
    ///
    /// 串行而非并行：`zgLoad` 用 `zgIsLoading` 做单飞门闩（防同一接口并发刷新），
    /// 并行调用会互相把对方的请求挡掉。五个接口都是小 JSON，串行的延迟可接受。
    func loadZGAll(period: Int) async {
        await fetchZGResult(period: period)
        await fetchZGTopics(period: period)
        await fetchZGMerge(period: period)
        await fetchZGRules(period: period)
        await fetchZGCleanReport(period: period)
    }

    /// 构造写请求（POST + JSON body + Cookie）。admins 由服务端判定，端侧不自行判断权限。
    private func zgPostRequest(_ url: URL?, cookie: String, body: [String: Any]) throws -> URLRequest {
        guard let url else { throw APIError.server(code: 0, message: "地址拼错了。") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    /// 手动忽略 / 取消忽略一条话题告警（写服务端，成功后再刷新）。
    @discardableResult
    func setZGTopicIgnore(period: Int, workId: String, ignore: Bool) async throws -> Bool {
        guard let cookie = auth.cookieHeader else {
            throw APIError.server(code: 401, message: "登录已过期，重新登录一下。")
        }
        let request = try zgPostRequest(
            API.zgTopicIgnore(), cookie: cookie,
            body: ["period": period, "workId": workId, "ignore": ignore]
        )
        let raw = try await client.send(request)
        guard raw.isSuccess else {
            throw APIError.server(code: raw.statusCode, message: APIErrorEnvelope.anyMessage(from: raw.data))
        }
        let env = try? APIJSON.decoder.decode(ZGEnvelope<ZGIgnoreResponse>.self, from: raw.data)
        if let ids = env?.data?.ignoredIds {
            var current = zgTopics?.ignoredIds ?? [:]
            current[workId] = ignore
            _ = ids // 以服务端回包为准刷新时由 fetch 覆盖；这里保留本地即时反馈
            zgTopics = ZGTopicsData(
                warnings: zgTopics?.warnings ?? [],
                ignoredIds: current,
                effectiveIds: zgTopics?.effectiveIds ?? [],
                distributionRecords: zgTopics?.distributionRecords
            )
        }
        return true
    }

    /// 确认 / 取消确认一对合并关系（写服务端）。
    @discardableResult
    func confirmZGMerge(period: Int, douyin: String, kuaishou: String, confirm: Bool) async throws -> Bool {
        guard let cookie = auth.cookieHeader else {
            throw APIError.server(code: 401, message: "登录已过期，重新登录一下。")
        }
        let pair: [String: Any] = [
            "douyin": douyin, "kuaishou": kuaishou, "confirm": confirm
        ]
        let request = try zgPostRequest(
            API.zgMergeConfirm(), cookie: cookie,
            body: ["period": period, "pairs": [pair]]
        )
        let raw = try await client.send(request)
        guard raw.isSuccess else {
            throw APIError.server(code: raw.statusCode, message: APIErrorEnvelope.anyMessage(from: raw.data))
        }
        return true
    }

    /// 触发服务端计算（manual/auto）。金额由服务端产出，端侧不参与。
    /// 成功后刷新 result，UI 只读 `zgResult`。
    @discardableResult
    func submitZGCalc(period: Int, mode: String, inputs: [String: Any]) async throws -> Bool {
        guard let cookie = auth.cookieHeader else {
            throw APIError.server(code: 401, message: "登录已过期，重新登录一下。")
        }
        var body: [String: Any] = ["period": period, "mode": mode, "inputs": inputs]
        for (key, value) in inputs { body[key] = value } // 兼容服务端把部分字段放在顶层读取
        let request = try zgPostRequest(API.zgCalc(), cookie: cookie, body: body)
        let raw = try await client.send(request)
        guard raw.isSuccess else {
            throw APIError.server(code: raw.statusCode, message: APIErrorEnvelope.anyMessage(from: raw.data))
        }
        await fetchZGResult(period: period, force: true)
        return true
    }
}

// 让 ZGTopicsData 支持就地重建（忽略勾选后即时反馈用）。
extension ZGTopicsData {
    init(warnings: [ZGTopicWarning], ignoredIds: [String: Bool], effectiveIds: [String], distributionRecords: [ZGJSONValue]?) {
        self.warnings = warnings
        self.ignoredIds = ignoredIds
        self.effectiveIds = effectiveIds
        self.distributionRecords = distributionRecords
    }
}
