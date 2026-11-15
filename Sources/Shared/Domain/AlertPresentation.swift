import Foundation

// MARK: - 失败原因

/// 预警「拿不到」的原因（R1 · 架构 §3.2）。
///
/// 这不是第五种状态，而是 `.hasAlerts` / `.confirmedNone` 上的**附加标记**：
/// 断网、`ok == false`、超时只要本地有缓存，状态照旧渲染，只多一行
///「最近成功 HH:mm · 显示的是缓存」+ 重试。只有连缓存都没有才单独落到 `.failed`。
///
/// 文案铁律（PRD AC1-2 / §7-13）：**「读取失败」绝不冒充「当前无天气预警」**。
/// 所以 `userText` 一律以「预警读取失败」开头，且不带任何时间 / 数值。
enum AlertFailure: Equatable, Sendable {

    /// 服务端没配和风 key（响应头 `X-Alerts-Cache: no_key`）
    case noKey

    /// 业务失败：HTTP 200 但 `{ok:false, error}`
    case okFalse

    /// 请求超时（12 秒窗口）
    case timeout

    /// 断网 / 传输层失败 / 非 2xx
    case transport

    /// 响应不是约定的 JSON
    case decode

    /// 可直接上屏的一句人话
    var userText: String {
        switch self {
        case .noKey:
            return "预警读取失败：服务端还没配好数据源"
        case .okFalse:
            return "预警读取失败：服务暂时没拿到数据"
        case .timeout:
            return "预警读取失败：请求超时了"
        case .transport:
            return "预警读取失败：网络没连上"
        case .decode:
            return "预警读取失败：返回的数据看不懂"
        }
    }

    /// 诊断区的简短结果码（如实写，不编造）
    var resultText: String {
        switch self {
        case .noKey:     return "no_key"
        case .okFalse:   return "ok:false"
        case .timeout:   return "timeout"
        case .transport: return "transport"
        case .decode:    return "decode"
        }
    }
}

// MARK: - 一次请求的结果

/// 一次预警请求的结果快照，是 `reduce` 的「本次输入」。
///
/// `ok == nil` 与 `ok == false` 都归到失败分支：前者是「根本没发出去」，
/// 后者是「服务端明确说拿不到」，两者都**不许**覆盖缓存，也**不许**据此说「没有预警」。
struct AlertFetchOutcome: Equatable, Sendable {

    /// `nil` = 传输 / 解码失败，根本没拿到业务结论
    let ok: Bool?

    /// 本次拿到的预警列表（`ok == true` 时缺失等价于空数组 = 确实没有预警）
    let warnings: [WeatherAlert]

    /// 失败原因；成功时恒为 nil
    let failure: AlertFailure?

    /// 这次请求收尾的时刻（诊断区用）
    let finishedAt: Date

    /// 响应头 `X-Alerts-Cache`（`hit` / `miss` / `no_key` / `error`）
    let cacheHeader: String?

    init(ok: Bool? = nil,
         warnings: [WeatherAlert] = [],
         failure: AlertFailure? = nil,
         finishedAt: Date,
         cacheHeader: String? = nil) {
        self.ok = ok
        self.warnings = warnings
        self.failure = failure
        self.finishedAt = finishedAt
        self.cacheHeader = cacheHeader
    }
}

// MARK: - 数据源诊断

/// 预警区右侧那行可复制的诊断信息（AC1-5 / Q7）。
///
/// 接口一栏固定显示 `Endpoint.alertsEndpointText`：预警只认这一条上游，
/// 诊断区不许出现第二个地址，也不许把「上次成功的时刻」写成「现在的数据」。
struct AlertDiagnostics: Equatable, Sendable {

    /// 完整接口地址（`Endpoint.briefBase + Endpoint.alertsPath`）
    let endpoint: String

    /// 最近一次请求的结果，如 `ok:true · hit` / `ok:false` / `timeout`
    let lastResult: String

    /// 最近一次发起请求的时刻；从未请求为 nil
    let lastAttemptAt: Date?

    /// 最近一次**成功**（`ok == true`）的时刻；从未成功为 nil
    let lastSuccessAt: Date?

    /// 当前显示是否来自缓存兜底（= `state.isStale`）
    let cacheUsed: Bool

    /// 最近一次响应的 `X-Alerts-Cache`
    let cacheHeader: String?

    init(endpoint: String = Endpoint.alertsEndpointText,
         lastResult: String,
         lastAttemptAt: Date? = nil,
         lastSuccessAt: Date? = nil,
         cacheUsed: Bool = false,
         cacheHeader: String? = nil) {
        self.endpoint = endpoint
        self.lastResult = lastResult
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.cacheUsed = cacheUsed
        self.cacheHeader = cacheHeader
    }

    /// 冷启动、还没发过任何一发时的初值。
    /// 「尚未请求」是实话，不是「当前无天气预警」。
    static var empty: AlertDiagnostics {
        return AlertDiagnostics(lastResult: "尚未请求")
    }

    /// 长按 / 点击复制的整段文本。
    ///
    /// 时间一律 `Formatters`（北京 UTC+8）；缺时刻就整行不写，
    /// 绝不拿 `Date()` 兜一个「刚刚」出来。
    var copyText: String {
        var lines: [String] = [
            "接口：\(endpoint)",
            "最近结果：\(lastResult)"
        ]
        if let attempt = lastAttemptAt {
            lines.append("最近请求：\(Formatters.relativeDay(attempt))")
        }
        if let success = lastSuccessAt {
            lines.append("最近成功：\(Formatters.relativeDay(success))")
        }
        if let header = cacheHeader, !header.isEmpty {
            lines.append("缓存：\(header)")
        }
        lines.append(cacheUsed ? "当前显示：缓存兜底" : "当前显示：实时结果")
        return lines.joined(separator: "\n")
    }
}

// MARK: - 四态

/// 预警首屏的**四个互斥状态**（R1 · 架构 §1.1 / §3.2）。
///
/// 任一时刻只渲染一种，View 里只允许 `switch`，不许在 `if` 里重算语义。
/// `failure` 是前两态的附加信息，不是第五态 —— 这正是 AC1-2「四态互斥」
/// 与 AC1-3「已有横幅不得消失」能同时成立的原因。
enum AlertPresentationState: Equatable, Sendable {

    /// 确认有预警（服务端 `ok:true` 且列表非空，或缓存里存着这个结论）
    case hasAlerts([WeatherAlert], lastSuccessAt: Date, stale: Bool, failure: AlertFailure?)

    /// 确认**没有**预警（服务端 `ok:true` 且列表为空，或缓存里存着这个结论）
    case confirmedNone(lastSuccessAt: Date, stale: Bool, failure: AlertFailure?)

    /// 首次加载：既没有缓存、也没有任何一次请求结果。
    /// 文案固定「正在获取预警…」，**禁止出现「取不到」**
    case loadingFirst

    /// 彻底失败：连缓存都没有。关联值带上原因与「上次成功时刻」（可能为 nil）
    case failed(reason: AlertFailure, lastSuccessAt: Date?)

    /// 当前生效的预警列表（其余三态为空数组）
    var warnings: [WeatherAlert] {
        if case .hasAlerts(let list, _, _, _) = self { return list }
        return []
    }

    /// 是否在显示缓存兜底数据
    var isStale: Bool {
        switch self {
        case .hasAlerts(_, _, let stale, _), .confirmedNone(_, let stale, _):
            return stale
        case .loadingFirst, .failed:
            return false
        }
    }

    /// 附加的失败信息（UI 据此追加一行人话 + 重试按钮）
    var failure: AlertFailure? {
        switch self {
        case .hasAlerts(_, _, _, let failure), .confirmedNone(_, _, let failure):
            return failure
        case .failed(let reason, _):
            return reason
        case .loadingFirst:
            return nil
        }
    }

    /// 最近一次成功拿到数据的时刻
    var lastSuccessAt: Date? {
        switch self {
        case .hasAlerts(_, let at, _, _), .confirmedNone(let at, _, _):
            return at
        case .failed(_, let at):
            return at
        case .loadingFirst:
            return nil
        }
    }

    /// 是不是「第一次加载」（T03 画骨架态用）
    var isLoadingFirst: Bool {
        if case .loadingFirst = self { return true }
        return false
    }
}

// MARK: - 缓存在 Domain 层的视图

/// `AlertCache.Snapshot` 在 Domain 层的「已解码视图」。
///
/// ## 为什么不直接让 `reduce` 吃 `AlertCache.Snapshot`
/// `AlertCache` 在 `Sources/Services`，而 Widget target 只编译
/// `Sources/Widget` + `Sources/Shared` —— 若 `Shared/Domain` 反向依赖 Services，
/// Widget target 编译本文件时会找不到 `AlertCache.Snapshot` 这个类型。
/// 所以 Services 侧只负责读写**后端响应原始 JSON Data**，由 `AlertStore` 解码成
/// 这个纯值类型再喂给 `reduce`。判定逻辑因此完全留在 Shared，零跨层依赖。
///
/// 这是本批对架构 §3.2 签名 `reduce(snapshot: AlertCache.Snapshot?, …)` 的
/// 唯一一处收窄：类型换成 Domain 层等价物，判定表与不变量逐字不变。
struct AlertCachedSnapshot: Equatable, Sendable {

    /// 缓存原文解出来的预警列表；空数组 = 缓存里存的是「确认无预警」
    let items: [WeatherAlert]

    /// 这份缓存写下的时刻（首帧 `lastSuccessAt` 取它）
    let savedAt: Date

    let endpoint: String
    let lastResult: String
    let cacheHeader: String?

    init(items: [WeatherAlert] = [],
         savedAt: Date,
         endpoint: String = Endpoint.alertsEndpointText,
         lastResult: String = "ok:true",
         cacheHeader: String? = nil) {
        self.items = items
        self.savedAt = savedAt
        self.endpoint = endpoint
        self.lastResult = lastResult
        self.cacheHeader = cacheHeader
    }
}

// MARK: - 唯一判定入口

/// 四态判定的**唯一**纯函数（架构 §3.2 判定表，QA 用附录 B `alertState` 做 JS 镜像）。
///
/// ```
///  fetch == ok:true + 列表非空  -> .hasAlerts(list, now, stale:false, failure:nil)  并写缓存
///  fetch == ok:true + 列表为空  -> .confirmedNone(now, stale:false, failure:nil)    并写缓存
///  fetch == 失败 / ok:false     -> 有 snapshot ? 保持 snapshot 的态 + stale:true + failure
///                                  : .failed(failure, lastSuccessAt:nil)
///  fetch == nil                 -> 有 snapshot ? snapshot 的态 + stale:true（首帧）
///                                  : .loadingFirst
/// ```
///
/// ## 两条不变量
/// 1. **`ok == false` / 超时 / 断网不会「新作出」一个无预警结论**：失败分支只可能
///    `.failed`，或者**沿用**缓存里已经确认过的结论（且强制 `stale:true` +
///    `failure != nil`，UI 会写「显示的是缓存」，不会冒充实时结论）。
/// 2. **没有成功数据就绝不产出 `.hasAlerts`**：无缓存的失败分支只落 `.failed`；
///    `.hasAlerts` 只来自 `ok:true` 的非空列表，或一份确实存着预警的缓存。
enum AlertPresentation {

    /// - Parameters:
    ///   - snapshot: 本地缓存的已解码视图；nil = 从未成功过
    ///   - fetch: 本次请求结果；nil = 首帧（还没发请求）
    ///   - now: 判定参照时刻（成功态的 `lastSuccessAt` 取它）
    static func reduce(snapshot: AlertCachedSnapshot?,
                       fetch: AlertFetchOutcome?,
                       now: Date) -> AlertPresentationState {
        if let fetch = fetch {
            // 只有 ok == true 才配称作「确定的现状」，空列表也算确定（= 确实没有预警）
            if fetch.ok == true {
                let list = fetch.warnings
                if list.isEmpty {
                    return .confirmedNone(lastSuccessAt: now, stale: false, failure: nil)
                }
                return .hasAlerts(list, lastSuccessAt: now, stale: false, failure: nil)
            }

            // 失败：ok == false / nil（含超时、断网、解码失败）
            let failure = fetch.failure ?? .transport
            guard let snapshot = snapshot else {
                // 连缓存都没有：明确报错，绝不说「当前无天气预警」
                return .failed(reason: failure, lastSuccessAt: nil)
            }
            // 有缓存：保持缓存的态，横幅照旧渲染，只追加 stale + failure（AC1-3）
            return cachedState(snapshot, stale: true, failure: failure)
        }

        // fetch == nil：冷启动首帧
        guard let snapshot = snapshot else {
            return .loadingFirst
        }
        return cachedState(snapshot, stale: true, failure: nil)
    }

    /// 把缓存里已确认的结论搬成当前状态。
    /// `stale` 与 `failure` 只改附加信息，不改「有预警 / 无预警」这个结论本身。
    private static func cachedState(_ snapshot: AlertCachedSnapshot,
                                    stale: Bool,
                                    failure: AlertFailure?) -> AlertPresentationState {
        if snapshot.items.isEmpty {
            return .confirmedNone(lastSuccessAt: snapshot.savedAt,
                                  stale: stale,
                                  failure: failure)
        }
        return .hasAlerts(snapshot.items,
                          lastSuccessAt: snapshot.savedAt,
                          stale: stale,
                          failure: failure)
    }
}
