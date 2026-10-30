import Foundation

/// **全工程唯一出现域名的地方**（设计文档 §2.1 / §5 数据层）：
/// 除本文件外，`Sources/` 下不允许出现任何协议前缀字面量，也不允许出现裸域名。
/// QA 用 `grep -rn "https://" Sources | grep -v Endpoint.swift` 卡这一条。
///
/// 四个站点各自的身份（PRD §1.1）：
///   · 红石（待发收益工作台 + 日程 + 攻略）→ `rockBase`
///   · 问卷工作台（列表 / 填答 / 结果）    → `surveyBase`
///   · 光遇简报 + 推送监控                 → `briefBase`
///   · 博客文章                            → `blogBase`
///
/// 为什么把域名和路径拆成两层：域名是"部署事实"（随时可能换域名），路径是"接口契约"（改一次要动后端）。
/// 拆开之后换域名只改 4 行，而 `API` / 各 Store 里全是路径常量的引用。
enum Endpoint {

    // MARK: - 站点根（唯四）

    /// 红石站：日程日历 / 规律 / 攻略
    static let rockBase = "https://creator-earnings-tracker.pages.dev"
    /// 问卷站：管理列表 / 公开填答 / 结果看板
    static let surveyBase = "https://wj.skyzyf335.top"
    /// 简报站：今日简报 / 光遇版本 / 推送监控（只读快照，绝不触发 brief 生成）
    static let briefBase = "https://app.skyzyf335.top"
    /// 博客站：文章列表 / 详情
    static let blogBase = "https://skyzyf335.top"

    // MARK: - 路径（本批先定稿命名，批次 2/3/4 直接引用，避免各写一遍拼错）

    /// 红石日程（合并 schedule + rules）
    static let redstonePath = "/api/app/redstone"
    /// 攻略图文流
    static let guidePath = "/api/app/guide"
    /// 攻略图片代理（**返回图片二进制**，`Content-Type` 由上游透传；批次 2 起不再返回 data URL）
    static let guideImagePath = "/api/app/guide/image"
    /// 推送监控状态（只读）
    static let monitorPath = "/api/app/monitor"
    /// 手动检查（有 60s 限频，超了 429）
    static let monitorCheckPath = "/api/app/monitor/check"
    /// 问卷列表
    static let surveysPath = "/api/app/surveys"
    /// 文章列表
    static let feedPath = "/api/app/feed"
    /// 文章详情
    static let articlePath = "/api/app/article"
    /// 今日简报
    static let briefPath = "/api/app/brief"

    // MARK: - 构造

    /// 统一的 URL 构造入口。`query` 为空时不写 `queryItems`，
    /// 否则 `URLComponents` 会给出一个带 `?` 尾巴的 URL（某些服务端会因此 400）。
    static func url(base: String, path: String, query: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: base + path) else { return nil }
        if !query.isEmpty {
            components.queryItems = query
        }
        return components.url
    }

    /// 问卷详情的路径（`id` 拼在路径里，不是 query）。
    /// 转义一次：问卷 id 目前是短随机串，但边界不猜 —— 一个带 `/` 的 id 会静默打到别的接口上。
    static func surveyDetailPath(id: String) -> String {
        return surveysPath + "/" + escapedPathComponent(id)
    }

    /// 问卷结果
    static func surveyResultPath(id: String) -> String {
        return surveysPath + "/" + escapedPathComponent(id) + "/result"
    }

    // MARK: - 问卷站的其余接口（批次 3：登录 / 公开填答 / 发布截止）

    /// 管理登录：`POST {password}` → 200 + `Set-Cookie: qw_auth=…`
    ///
    /// **凭证只能从响应头拿**：JSON 里只有 `{"ok":true}`，没有 token。
    static let authLoginPath = "/api/auth/login"
    /// 会话校验（30 天有效期内也可能失效，进工作台前查一次）
    static let authStatusPath = "/api/auth/status"
    /// 登出（失败也无所谓，本地清 Keychain 即可）
    static let authLogoutPath = "/api/auth/logout"

    /// 公开填答题面（**无需 Cookie**：survey 站中间件对 `/(public|submit)$` 白名单放行）
    static func surveyPublicPath(id: String) -> String {
        return "/api/surveys/" + escapedPathComponent(id) + "/public"
    }

    /// 公开提交答卷（无需 Cookie）
    static func surveySubmitPath(id: String) -> String {
        return "/api/surveys/" + escapedPathComponent(id) + "/submit"
    }

    /// 发布 / 截止（需要 Cookie，body 是 `{"action":"publish"|"close"}`）
    static func surveyActionsPath(id: String) -> String {
        return "/api/surveys/" + escapedPathComponent(id) + "/actions"
    }

    private static func escapedPathComponent(_ raw: String) -> String {
        return raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? raw
    }
}
