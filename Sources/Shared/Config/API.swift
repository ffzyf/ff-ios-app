import Foundation

/// V2 已有的三个只读端点的 URL 门面（列表 / 详情 / 简报）。
///
/// 这一层**不再持有域名**：域名与路径全部下沉到 `Endpoint`（唯一允许写域名的地方），
/// `API` 只负责"把参数拼成 URL"这一件事，原有调用点（`AppModel` / `ShareSheet` / `SettingsView`）
/// 一个都不用改。
///
/// 三个端点都是公开只读、无 Token、无 Cookie：
///   · feed / article → 博客站
///   · brief          → 简报站（只读快照，绝不触发 daily-brief 生成）
enum API {
    /// 博客站根（别名，指向 `Endpoint`）
    static let blogHost = Endpoint.blogBase
    /// 简报站根（别名，指向 `Endpoint`）
    static let briefHost = Endpoint.briefBase

    /// 路径别名：`AppModel` 里拼过 `API.blogHost + API.articlePath`，保留原名不破坏调用点
    static let feedPath = Endpoint.feedPath
    static let articlePath = Endpoint.articlePath
    static let briefPath = Endpoint.briefPath

    /// 列表：`page` 从 1 开始，`size` 默认 15、服务端上限 30（超了会被 clamp，这里先夹一次省一次无效请求）
    static func feed(page: Int = 1, size: Int = 15) -> URL? {
        let safePage = max(1, page)
        let safeSize = min(max(1, size), 30)
        return Endpoint.url(
            base: blogHost,
            path: feedPath,
            query: [
                URLQueryItem(name: "page", value: String(safePage)),
                URLQueryItem(name: "size", value: String(safeSize))
            ]
        )
    }

    /// 详情：`id` 走 URLQueryItem，自动做百分号转义（id 里不会有特殊字符，但边界不猜）
    static func article(id: String) -> URL? {
        return Endpoint.url(
            base: blogHost,
            path: articlePath,
            query: [URLQueryItem(name: "id", value: id)]
        )
    }

    /// 简报：无参数
    static func brief() -> URL? {
        return Endpoint.url(base: briefHost, path: briefPath)
    }

    /// 天气实况：`GET /api/app/weather`，匿名可读。
    ///
    /// base 用 `briefHost`（**不是 `rockBase`**）：天气挂在简报站上，
    /// 与 `brief()` 打同一台机器、共用一份上游缓存；换成红石站域名会 404。
    ///
    /// 业务失败时服务端仍返回 HTTP 200 + `{"ok":false,"error":"…"}` ——
    /// 传输层判不出来，由调用方（`WeatherStore`）看 `ok` 决定，本层只拼地址。
    ///
    /// - Parameters:
    ///   - lat: 纬度。与 `lon` **成对出现**；任一为 nil（或超出合法范围）就不带参数。
    ///   - lon: 经度。
    ///
    /// ## 为什么要保留两个默认值
    /// 服务端不带 `lat/lon` 时用自己写死的默认坐标 —— 这正是 3.7.0 之前的行为。
    /// 仍然需要这条兜底：`HomeCoordinate` 没有记录（服务端从没收到过上报，即从没开过定位）时，
    /// 小组件与 App 都只能不带坐标，此时服务端默认坐标就是"唯一能给的东西"。
    /// 3.17.0 起两个 target 都会先读 `HomeCoordinate`，**有坐标就不再走这条默认路径** ——
    /// 这正是"App 和小组件天气在同一个地区"的修法。
    ///
    /// ## 为什么只保留两位小数
    /// 天气按公里级网格算，0.01° ≈ 1.1km，两位小数已经比网格细。
    /// 多给精度既没有意义，还会把同一片网格拆成多个缓存键（服务端与本机缓存都会命中变差）。
    static func weather(lat: Double? = nil, lon: Double? = nil) -> URL? {
        // 两个都有才拼 query；只有一个（或都不合法）时当作"没有坐标"，
        // 让服务端回落默认坐标 —— 半对半错的坐标拼出来只会得到另一处的天气。
        guard let lat = lat, let lon = lon,
              lat.isFinite, lon.isFinite,
              (-90.0...90.0).contains(lat),
              (-180.0...180.0).contains(lon) else {
            return Endpoint.url(base: briefHost, path: Endpoint.weatherPath)
        }

        return Endpoint.url(
            base: briefHost,
            path: Endpoint.weatherPath,
            query: [
                URLQueryItem(name: "lat", value: String(format: "%.2f", lat)),
                URLQueryItem(name: "lon", value: String(format: "%.2f", lon))
            ]
        )
    }

    /// 天气预警：`GET /api/app/alerts`（3.19.0）。
    ///
    /// 与 `weather()` 同一台机器、同一套坐标参数，但**缓存互不相干**：
    /// 它自己只压 5 分钟（见后端 `alerts.js`），因为预警的价值全在时效。
    ///
    /// 响应里 `ok == false` 表示「拿不到预警」（没配 key / 上游挂了），
    /// 调用方**不能**据此清空已有横幅 —— 一次网络抖动不该让红色预警从屏幕上消失。
    static func alerts(lat: Double? = nil, lon: Double? = nil) -> URL? {
        return coordinateURL(path: Endpoint.alertsPath, lat: lat, lon: lon)
    }

    /// 分钟级降水：`GET /api/app/minutely`（3.19.0）。同样独立端点、5 分钟缓存。
    static func minutely(lat: Double? = nil, lon: Double? = nil) -> URL? {
        return coordinateURL(path: Endpoint.minutelyPath, lat: lat, lon: lon)
    }

    /// 带坐标的 GET 地址（`weather` / `alerts` / `minutely` 共用一套拼法）。
    ///
    /// 抽出来的理由：三个端点的坐标规则必须**逐字相同** —— 只要有一个保留三位小数，
    /// 同一片 1 公里的网格就会被拆成两个缓存键，三个接口于是各说各的天气。
    ///
    /// - Parameters:
    ///   - path: 端点路径
    ///   - lat: 纬度；与 `lon` 成对出现，任一不合法就当作"没有坐标"
    ///   - lon: 经度
    private static func coordinateURL(path: String, lat: Double?, lon: Double?) -> URL? {
        guard let lat = lat, let lon = lon,
              lat.isFinite, lon.isFinite,
              (-90.0...90.0).contains(lat),
              (-180.0...180.0).contains(lon) else {
            return Endpoint.url(base: briefHost, path: path)
        }
        return Endpoint.url(
            base: briefHost,
            path: path,
            query: [
                URLQueryItem(name: "lat", value: String(format: "%.2f", lat)),
                URLQueryItem(name: "lon", value: String(format: "%.2f", lon))
            ]
        )
    }

    /// 语音合成：`POST /api/app/tts`。    ///
    /// base 用 `briefHost`（与 `weather()` 同一台机器）：密钥在服务端，App 只发文本。
    /// 请求方法 / body / 超时 / 解码都由 `SpeechStore` 负责 —— 本层只拼地址，
    /// 与 `weather()` / `brief()` 同一个分工。
    ///
    /// 成功时返回的是**预签名直链**（24 小时有效），不是音频字节：
    /// 所以这里只给 URL，播放交给 `AVPlayer` 流式取，App 不需要缓存音频。
    static func tts() -> URL? {
        return Endpoint.url(base: briefHost, path: Endpoint.ttsPath)
    }

    // MARK: - 共享「家」坐标（3.17.0，3.17.0 改为单条记录）

    /// 读取「当前位置」（**Widget 用**）。`GET /api/app/home`，**不带任何 query**。
    ///
    /// base 用 `briefHost`：与 `weather()` 同一台机器、同一份记录 ——
    /// 拆到别的站根就等于把"两边用同一个坐标"这件事拆散。
    ///
    /// 服务端只有**一条**记录，两端读的是同一条，所以不需要任何设备标识
    /// （为什么不用 IDFV：见 `HomeCoordinate` 的类型注释）。
    ///
    /// 业务失败 / 没有记录时服务端仍返回 HTTP 200（`{"ok":true,"lat":null,…}`），
    /// 由 `HomeCoordinate.resolved()` 判，本层只拼地址。
    static func homeRead() -> URL? {
        return Endpoint.url(base: briefHost, path: Endpoint.homePath)
    }

    /// 上报坐标（**App 用**）。`POST /api/app/home`。
    ///
    /// 请求体（`{lat, lon, name}`，**没有 id**）、超时、失败处理都由 `HomeCoordinate.publish` 负责 ——
    /// 本层只拼地址，与 `weather()` / `tts()` 同一个分工。
    ///
    /// 与 `homeRead()` **分开命名**（而不是同名重载）：调用处一眼能看出是读还是写。
    /// 两者的 base + path 必须永远一致（读写同一条记录），所以都引用 `Endpoint.homePath`，
    /// 不各写一遍字符串 —— 改路径时不会只改一半。
    static func homeWrite() -> URL? {
        return Endpoint.url(base: briefHost, path: Endpoint.homePath)
    }

    // MARK: - 红石站（批次 2）

    /// 红石日程。
    ///
    /// - Parameters:
    ///   - month: `"2026-10"`。**与 from/to 互斥**（服务端会 400），所以这里不提供三者同传的入口。
    ///     不给 month 时服务端返回「所有已生成月份」的并集 —— App 侧刻意不用这种大范围请求：
    ///     一次拉全部月份在 `coveredMonths` 有 6 个月时是 180 条，月历只用得到一个月。
    ///   - includeRules: `?action=rules`。线上实测就是这个名字（`rules=1` 服务端也兼容），
    ///     这里用实测的那一个，少一层"契约 vs 线上"的心智负担。
    static func redstone(month: String? = nil, includeRules: Bool = false) -> URL? {
        var query: [URLQueryItem] = []
        if let month = month, !month.isEmpty {
            query.append(URLQueryItem(name: "month", value: month))
        }
        if includeRules {
            query.append(URLQueryItem(name: "action", value: "rules"))
        }
        return Endpoint.url(base: Endpoint.rockBase, path: Endpoint.redstonePath, query: query)
    }

    /// 攻略图文流。`refresh = true` 会强制服务端重建缓存（有 300s 限频）
    static func guide(refresh: Bool = false) -> URL? {
        let query = refresh ? [URLQueryItem(name: "refresh", value: "1")] : []
        return Endpoint.url(base: Endpoint.rockBase, path: Endpoint.guidePath, query: query)
    }

    // MARK: - 问卷站（批次 3）
    //
    // 五个接口分两类：
    //   · 需要 Cookie：列表 / 详情 / 结果 / 发布截止（Cookie 由 `SurveyAuth` 提供，本层不碰凭证）
    //   · 公开：public / submit（不需要 Cookie，填答页给任何人用）
    // 域名一律取 `Endpoint.surveyBase`，本文件不出现任何协议前缀字面量。

    /// 问卷站根（用于设置页 / 关于页展示，别处请直接调具体端点）
    static let surveyHost = Endpoint.surveyBase

    /// 问卷列表。`status` 传 nil 拿全量（筛选会让顶部计数与列表条数不一致，App 默认不筛）
    static func surveyList(status: String? = nil) -> URL? {
        let trimmed = (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmed.isEmpty ? [] : [URLQueryItem(name: "status", value: trimmed)]
        return Endpoint.url(base: Endpoint.surveyBase, path: Endpoint.surveysPath, query: query)
    }

    /// 单问卷详情（id 拼在路径里，`Endpoint` 已做百分号转义）
    static func surveyDetail(id: String) -> URL? {
        return Endpoint.url(base: Endpoint.surveyBase, path: Endpoint.surveyDetailPath(id: id))
    }

    /// 问卷结果。`responseLimit` 只影响 `responses[]`（默认 200、上限 500），不影响统计
    static func surveyResult(id: String, responseLimit: Int = 200) -> URL? {
        let safeLimit = Swift.min(Swift.max(responseLimit, 1), 500)
        return Endpoint.url(
            base: Endpoint.surveyBase,
            path: Endpoint.surveyResultPath(id: id),
            query: [URLQueryItem(name: "responseLimit", value: String(safeLimit))]
        )
    }

    /// 公开填答题面（无需 Cookie）
    static func surveyPublicForm(id: String) -> URL? {
        return Endpoint.url(base: Endpoint.surveyBase, path: Endpoint.surveyPublicPath(id: id))
    }

    /// 公开提交答卷（无需 Cookie）
    static func surveySubmit(id: String) -> URL? {
        return Endpoint.url(base: Endpoint.surveyBase, path: Endpoint.surveySubmitPath(id: id))
    }

    /// 发布 / 截止（需要 Cookie）
    static func surveyActions(id: String) -> URL? {
        return Endpoint.url(base: Endpoint.surveyBase, path: Endpoint.surveyActionsPath(id: id))
    }

    /// 管理登录（body 只放密码，凭证从 `Set-Cookie` 响应头取）
    static func authLogin() -> URL? {
        return Endpoint.url(base: Endpoint.surveyBase, path: Endpoint.authLoginPath)
    }

    /// 会话校验
    static func authStatus() -> URL? {
        return Endpoint.url(base: Endpoint.surveyBase, path: Endpoint.authStatusPath)
    }

    /// 登出
    static func authLogout() -> URL? {
        return Endpoint.url(base: Endpoint.surveyBase, path: Endpoint.authLogoutPath)
    }

    /// 收益总览（`GET /api/app/earnings`）。必须带 `Cookie: ce_auth=…`，否则 401。
    static func earnings() -> URL? {
        return Endpoint.url(base: Endpoint.rockBase, path: Endpoint.earningsPath)
    }

    /// 追加一笔收益条目（`POST /api/app/earnings/entry`）。
    ///
    /// 与 `earnings()` 同一个 `rockBase`：读写打的是同一台机器、同一份 KV，
    /// 所以 App 记的账网页端立刻可见（存本地就会变成第二个真相源，跟网站对不上账）。
    /// 请求方法、请求体、Cookie 都由 `EarningsStore.addEntry` 填 —— 本层只拼地址。
    static func earningsEntry() -> URL? {
        return Endpoint.url(base: Endpoint.rockBase, path: Endpoint.earningsEntryPath)
    }

    /// 新建一个活动（`POST /api/app/earnings/activity`）。
    ///
    /// base 与 `earningsEntry()` 完全相同（`rockBase`）：建活动和记账写的是同一份 KV，
    /// 所以 App 建的活动在网页端立刻可见，反之亦然。
    /// Cookie / 请求体 / 错误映射都由 `EarningsStore.addActivity` 负责 —— 本层只拼地址。
    static func earningsActivity() -> URL? {
        return Endpoint.url(base: Endpoint.rockBase, path: Endpoint.earningsActivityPath)
    }

    // MARK: - 收益站鉴权（与问卷站同一套路径，但域名不同）

    /// 收益站登录。**路径与问卷站完全一致**（`/api/auth/login`），只有域名不同
    /// （`rockBase` vs `surveyBase`）—— 所以这里复用同一组 `auth*Path` 常量，不另起一份，
    /// 避免将来后端改路径时只改了一半。
    ///
    /// 凭证 Cookie 名不同（`ce_auth` vs `qw_auth`），那是 `EarningsKeychain` 的事，与本层无关。
    static func earningsAuthLogin() -> URL? {
        return Endpoint.url(base: Endpoint.rockBase, path: Endpoint.authLoginPath)
    }

    /// 会话校验（`GET /api/auth/status`，后端标注为公开接口）
    static func earningsAuthStatus() -> URL? {
        return Endpoint.url(base: Endpoint.rockBase, path: Endpoint.authStatusPath)
    }

    /// 登出
    static func earningsAuthLogout() -> URL? {
        return Endpoint.url(base: Endpoint.rockBase, path: Endpoint.authLogoutPath)
    }

    // MARK: - AI 聊天（`/api/ai/*`）
    //
    // 与上面所有端点同一个分工：**本层只拼地址 + 造 `URLRequest`**，
    // 解码交给 `APIClient.send(_:as:)`（复用 `APIJSON.decoder` 与
    // `{ok:false, error:{code,message}}` → `APIError` 的既有映射），
    // 业务状态（`ok == false` / 流式收尾）由各自的 Store 判。
    //
    // 唯一的额外责任是**构造带 `x-ai-token` 的请求**。它放在这里而不是各 Store 里，
    // 是因为"凭证只进请求头"这条纪律必须只有一处可改（风险清单第 3 条：
    // 绝不进 URL、绝不进日志）。token 由调用方从 `AIKeychain` 取好再传进来 ——
    // 本文件在 `Shared/` 里，会被编进小组件 target，而 `AIKeychain` 在 `Services/` 里，读不到。

    /// 模型清单（`GET /api/ai/models`）：可选模型 + auto 判据 + 今日配额
    static func aiModels() -> URL? {
        return Endpoint.url(base: briefHost, path: Endpoint.aiModelsPath)
    }

    /// 流式聊天（`POST /api/ai/chat`）。
    ///
    /// 只给地址：**不能**用 `APIClient` 发这个请求 —— 那个类的 `URLSession` 是私有且
    /// 按普通请求配的（`timeoutIntervalForResource = 30`），会把一条正常的长回复掐断。
    /// 流式那一发由 `AIChatStore` 用自己的 session 走 `bytes(for:)`。
    static func aiChat() -> URL? {
        return Endpoint.url(base: briefHost, path: Endpoint.aiChatPath)
    }

    /// 历史会话列表（`GET /api/ai/conversations`）。
    ///
    /// - Parameter cursor: 上一页返回的 `nextCursor`；nil / 空串表示从第一页开始
    ///   （空串要当"没有游标"处理，否则会拼出 `?cursor=` 这种半截参数）
    static func aiConversations(cursor: String? = nil) -> URL? {
        let trimmed = (cursor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmed.isEmpty ? [] : [URLQueryItem(name: "cursor", value: trimmed)]
        return Endpoint.url(base: briefHost, path: Endpoint.aiConversationsPath, query: query)
    }

    /// 单个会话（`GET ?id=` 读详情 / `DELETE ?id=` 删除）。
    ///
    /// `id` 走 `URLQueryItem`，百分号转义交给 `URLComponents`（服务端 id 是 22 位
    /// ULID 风格，理论上不会有特殊字符，但边界不猜）。
    static func aiConversation(id: String) -> URL? {
        return Endpoint.url(
            base: briefHost,
            path: Endpoint.aiConversationPath,
            query: [URLQueryItem(name: "id", value: id)]
        )
    }

    /// 新建一条空会话（`POST /api/ai/conversation`，无 query）。
    ///
    /// 聊天本身不需要它：第一轮 `POST /api/ai/chat` 会隐式建会话并在末帧回 `convId`。
    /// 它是给"先建空会话、再逐轮写"这种形态留的口子（历史列表里的「新建」）。
    static func aiConversationCreate() -> URL? {
        return Endpoint.url(base: briefHost, path: Endpoint.aiConversationPath)
    }

    /// 穿搭建议（`POST /api/ai/outfit`，非流式）
    static func aiOutfit() -> URL? {
        return Endpoint.url(base: briefHost, path: Endpoint.aiOutfitPath)
    }

    /// 造一个带 `x-ai-token` 的 AI 请求（全模块唯一一处写这个头名）。
    ///
    /// - Parameters:
    ///   - url: 上面几个 `ai*()` 给出的地址
    ///   - method: `"GET"` / `"POST"` / `"DELETE"`
    ///   - token: `AIKeychain.token()` 的返回值（**不要**在这里读 Keychain，理由见上）
    ///   - body: 已编码好的 JSON；nil 就不带 body、也不写 `Content-Type`
    ///   - accept: 默认 `application/json`；只有 `/api/ai/chat` 传 `text/event-stream`
    ///
    /// 缓存策略固定 `.reloadIgnoringLocalCacheData`：所有 AI 响应都是 `no-store`，
    /// 用一个可能过期的缓存去回答"我刚问了什么"是最难查的一类 bug。
    ///
    /// 超时这里给 30 秒（普通请求的语义）；流式那一发会自己再改一次 —— 它的 30 秒是
    /// **空闲**超时，不是整请求超时，两者的区别写在 `AIChatStore.idleTimeout` 的注释里。
    static func aiRequest(url: URL,
                          method: String = "GET",
                          token: String,
                          body: Data? = nil,
                          accept: String = "application/json") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue(token, forHTTPHeaderField: "x-ai-token")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }
}
