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

    /// 天气实况：`GET /api/app/weather`，无参数、匿名可读。
    ///
    /// base 用 `briefHost`（**不是 `rockBase`**）：天气挂在简报站上，
    /// 与 `brief()` 打同一台机器、共用一份上游缓存；换成红石站域名会 404。
    ///
    /// 业务失败时服务端仍返回 HTTP 200 + `{"ok":false,"error":"…"}` ——
    /// 传输层判不出来，由调用方（`WeatherStore`）看 `ok` 决定，本层只拼地址。
    static func weather() -> URL? {
        return Endpoint.url(base: briefHost, path: Endpoint.weatherPath)
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
}
