import Foundation

/// **全工程唯一的 URL 常量来源**（设计文档 §8.1）。
///
/// 其他文件一律通过 `API.feed(page:size:)` 这类方法拿 URL，不允许再手写域名常量
/// （QA 用 grep 卡这一条：全工程只有本文件出现协议前缀）。
///
/// 三个端点都是公开只读、无 Token、无 Cookie：
///   · feed / article  → 博客站 `skyzyf335.top`
///   · brief           → 简报站 `app.skyzyf335.top`（只读快照，绝不触发 daily-brief 生成）
enum API {
    /// 博客站（文章列表 / 详情）
    static let blogHost = "https://skyzyf335.top"
    /// 简报站（光遇版本 + 今日简报）
    static let briefHost = "https://app.skyzyf335.top"

    static let feedPath = "/api/app/feed"
    static let articlePath = "/api/app/article"
    static let briefPath = "/api/app/brief"

    /// 列表：`page` 从 1 开始，`size` 默认 15、服务端上限 30（超了会被 clamp，这里先夹一次省一次无效请求）
    static func feed(page: Int = 1, size: Int = 15) -> URL? {
        var components = URLComponents(string: blogHost + feedPath)
        let safePage = max(1, page)
        let safeSize = min(max(1, size), 30)
        components?.queryItems = [
            URLQueryItem(name: "page", value: String(safePage)),
            URLQueryItem(name: "size", value: String(safeSize))
        ]
        return components?.url
    }

    /// 详情：`id` 走 URLQueryItem，自动做百分号转义（id 里不会有特殊字符，但边界不猜）
    static func article(id: String) -> URL? {
        var components = URLComponents(string: blogHost + articlePath)
        components?.queryItems = [URLQueryItem(name: "id", value: id)]
        return components?.url
    }

    /// 简报：无参数
    static func brief() -> URL? {
        return URL(string: briefHost + briefPath)
    }
}
