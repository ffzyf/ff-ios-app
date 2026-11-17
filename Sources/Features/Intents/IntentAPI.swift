import Foundation

// MARK: - 错误

/// Intent 侧的失败分类。
///
/// 为什么不用 `APIError`：那个枚举的 case 是按页面的重试语义设计的（`.cancelled` /
/// `.server(code:message:)` 都要给 UI 分别处理），而 Siri 只认「一句话」——
/// 这里先把失败收敛成"离线 / 超时 / 状态码 / 业务 / 解码"五档，
/// 再由各 Intent 的 `load()` 翻译成中文口语，**英文 `localizedDescription` 永远不出这个文件**。
enum IntentAPIError: Error, Equatable {
    /// `API.brief()` 之类的门面返回 nil（拼 URL 失败），现实中不会发生，但绝不 force unwrap
    case invalidURL
    /// 连不上（离线 / DNS / 证书 / 被取消之外的一切传输错误）
    case offline
    /// 超时。单独一档是因为它对用户的意思是"现在问不到"，不是"你网络不好"
    case timeout
    /// 非 2xx
    case badStatus(Int)
    /// HTTP 200 但服务端说 `ok == false`：契约里的业务失败，与站点挂掉对用户是同一种体验
    case business
    /// JSON 结构对不上（部署换了契约）
    case decoding
}

// MARK: - 只读网络层

/// Intent 专用的极简 GET。
///
/// ## 为什么不用现成的 `APIClient` / `BriefStore` / `RockStore`
/// · Store 都是 `@MainActor` 上的状态容器（`@Published` 一改就得回主线程），
///   而 Intent 的 `perform()` 跑在系统的非主线程上下文里 —— 借 Store 等于把 UI 状态拖进后台任务，
///   还会让"问一句 Siri"顺手改掉页面上的缓存与筛选态；
/// · `APIClient.shared` 的预算是 15 秒（等完整列表用的），语音场景等不了那么久。
///
/// 所以这里只有三件事：发 GET、用**项目同一份** decoder 解码、把失败归一成 `IntentAPIError`。
enum IntentAPI {

    /// 8 秒预算。
    ///
    /// 为什么是 8 而不是 `APIClient` 的 15：对着 Siri 说话时，超过 5 秒用户已经在怀疑
    /// "它是不是没听见"；8 秒是"再等一下就出结果"与"不如直接说连不上"的分界。
    /// 简报 / 红石这两个接口本身有 CDN 缓存，正常都在 1 秒内回来。
    static let timeout: TimeInterval = 8

    /// 泛型 GET + 解码。
    ///
    /// - Parameters:
    ///   - url: 由 `API.brief()` / `API.redstone(month:)` 拼好的地址；传 nil 抛 `.invalidURL`
    ///   - type: 目标模型（`BriefResponse` / `RedstoneResponse`）
    ///   - timeout: 单次请求预算，默认就是 `IntentAPI.timeout`（8 秒）。
    ///     需要"补一刀"的调用点（红石补下个月）可以传更小的值 —— 两发串行时
    ///     共用一个 8 秒预算会变成最坏 16 秒，用户早就把 Siri 划走了。
    static func get<T: Decodable>(_ url: URL?,
                                  as type: T.Type,
                                  timeout: TimeInterval = IntentAPI.timeout) async throws -> T {
        guard let url = url else { throw IntentAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // 缓存策略选**不读本地缓存**：语音问答是低频、单次、用户明确在问"现在"的动作。
        // 用 `.useProtocolCachePolicy` 会把 30 分钟内的旧快照直接念出来 ——
        // 早上七点半问"简报生成没"，服务端已经生成、本地缓存还说"还没生成"，这是最难解释的一类错。
        // 代价就是每次多下几 KB 的 JSON，对这条链路完全可以接受
        // （页面走协议缓存是为了翻页 / 滚动省流量，那是另一个场景）。
        //
        // 注意别写 `.reloadRevalidatingCacheData`：那个枚举值在 Foundation 里并未真正实现条件请求，
        // 实际等价于默认策略 —— 写上去只会让注释骗人。
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            // 用户中途划走卡片时系统会取消请求：这不是故障，交给上层按"取消"静默处理
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw IntentAPIError.timeout }
            throw IntentAPIError.offline
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw IntentAPIError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw IntentAPIError.offline }
        guard (200..<300).contains(http.statusCode) else {
            throw IntentAPIError.badStatus(http.statusCode)
        }

        do {
            // 复用 `APIJSON.decoder`：服务端时间字段是**带毫秒**的 ISO8601，
            // 与页面读到的必须是同一套解析（否则同一份数据在卡片和语音里差 8 小时）。
            return try APIJSON.decoder.decode(T.self, from: data)
        } catch {
            throw IntentAPIError.decoding
        }
    }

    /// 专用 session：只给 Intent 用，配置与 `APIClient` 同源但预算不同。
    ///
    /// 不申请 Cookie / 不读写 `httpCookieStorage`：这三个接口都是匿名只读，
    /// 顺带避免把网页端登录态带进一条会被 Siri 念出来的请求里。
    ///
    /// `urlCache = nil` 与上面的 `.reloadIgnoringLocalCacheData` 是同一个决定的两半：
    /// 既然每次都要真的去问服务端，就没有理由再往磁盘缓存里存一份（省一次写入，也少一处能读到旧数据的地方）。
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = IntentAPI.timeout
        configuration.timeoutIntervalForResource = IntentAPI.timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpAdditionalHeaders = ["User-Agent": "SkyApp/Intents (iOS)"]
        return URLSession(configuration: configuration)
    }()
}
