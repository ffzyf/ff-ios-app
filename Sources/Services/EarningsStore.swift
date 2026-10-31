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
    @Published private(set) var lastUpdated: Date?
    /// 这份数是本地缓存（这次请求没成功）
    @Published private(set) var isStale: Bool = false
    @Published private(set) var isLoading: Bool = false
    /// 写请求在飞（防连点重复提交；UI 的保存按钮也据此转圈）
    @Published private(set) var isWriting: Bool = false
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
