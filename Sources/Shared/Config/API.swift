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
}
