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
    /// 天气实况（**属于简报站**：与 `briefPath` 同一台机器、同一份上游缓存）
    ///
    /// 为什么归简报站而不是红石站：简报里的 `weather` / `windText` / `rain` 三处就是从它派生的，
    /// 两者共用一次上游请求。分到别的站根下，迟早会出现"卡片说小雨、简报说晴"的分叉。
    static let weatherPath = "/api/app/weather"
    /// 收益总览（**需要 `ce_auth` 会话**，是 `/api/app/*` 里唯一不给匿名豁免的接口）
    static let earningsPath = "/api/app/earnings"
    /// 追加一笔收益条目（`POST`，同样**需要 `ce_auth`**）。
    ///
    /// 三个只有这个接口才有的行为（`EarningsStore.addEntry` 全部要接住）：
    /// · 请求体是 `EarningsEntryInput`（`title`/`type`、`amount`/`amountCents`、`date`/`time` 双写）；
    /// · `paid` 由服务端 `buildNewEntry` 决定（新记的恒为待发），请求体里**没有**这个字段；
    /// · 并发写冲突返回 **409 + `retry: true`**（服务端乐观锁），不是普通的参数错误。
    static let earningsEntryPath = "/api/app/earnings/entry"
    /// 云控更新：最新版本元数据（`GET`，**匿名可读**，`Cache-Control: public, max-age=60`）。
    ///
    /// 成功时 `latest` 是一个版本对象；站点**一次都没发布过**时 `latest` 是 `null`
    /// —— 那是"没有更新"，**不是**错误（App 侧据此不弹任何东西）。
    /// 失败时是统一信封 `{ok:false, error:{code,message}}`，传输层看不出来，由 `UpdateStore` 判。
    static let appVersionPath = "/api/app/version"
    /// 安装引导页（**静态页**，`app.skyzyf335.top/install/`）。
    ///
    /// 只有一个用处：唤起全能签失败（设备上没装那个 App）时的回退落点 ——
    /// 那页讲三件事：没有全能签怎么装、复制 ipa 直链、在「网页打开」里粘贴直链。
    /// 它是页面不是接口，所以**没有** `/api/` 前缀。
    static let installGuidePath = "/install/"

    /// 新建一个活动（`POST`，同样**需要 `ce_auth`**）。
    ///
    /// 为什么需要它：服务端的账本是两层结构（活动 → 条目），entry 的 `activityId` 必填。
    /// 没有这个接口时 App 只能在网页端建好活动再回来记账 —— 手机上就断了一环。
    ///
    /// 三个只有这个接口才有的行为（`EarningsStore.addActivity` 全部要接住）：
    /// · 请求体是 `{name, platform}` 两个字符串（平台不是独立实体，跟着活动走）；
    /// · 服务端用与网页端 `addActivity` 相同的读-改-写 + CAS 乐观锁写回，
    ///   **同平台重名 → 409 +「该平台下已有同名活动」**（这个 409 不可重试，是业务规则）；
    /// · 成功后活动列表会因为 `unshift` 而变长，`summary.activityCount / platformCount` 也跟着变
    ///   —— 所以 App 不本地拼接，直接重拉一次总览。
    static let earningsActivityPath = "/api/app/earnings/activity"

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
