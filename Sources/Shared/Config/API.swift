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
}
