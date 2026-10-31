import Foundation

/// 天气实况的 App 侧缓存（`GET /api/app/weather`，匿名只读）。
///
/// 只做三件事：
/// 1. 拉一次天气，成功就替换 `current`；
/// 2. 内存里扛 10 分钟，期间重复调用直接返回；
/// 3. 失败**保留上一次的 `current`**、**不报错**。
///
/// 三条策略各自的理由：
/// · **10 分钟内存缓存**：与后端 KV 的 TTL 对齐（上游 Open-Meteo 也是 5~10 分钟粒度）。
///   比 TTL 更短只是白打接口，更长就会拿着过期天气画天空 —— 两者都没有意义，
///   所以干脆对齐，用户下拉刷新想看到新数据时后端也确实有新数据。
/// · **失败保留旧值**：天气是卡片上的装饰性背景。拉失败就让卡片退化成"无天气"，
///   等于用一次网络抖动换掉用户眼前一片好好的天空 —— 明显是更差的结果。
///   旧值最多旧 10 分钟，比"什么都没有"诚实得多。
/// · **不落盘**：天气是分钟级数据。存到磁盘只会在第二天早上打开 App 时，
///   给用户一个昨天的"晴"——那是最糟的一类错误：看起来正常、且没人会怀疑。
///   同样因此**不复用 `CachedLoader`**（那套的三步降级以落盘为前提）。
///
/// 与 Widget 的关系：两个小组件**不引用本类**（Widget target 不编译 `Sources/Services`），
/// 它们各自按 Timeline 直接请求，本类只服务主 App。
@MainActor
final class WeatherStore: ObservableObject {

    static let shared = WeatherStore()

    /// 内存缓存窗口（秒）。与后端 KV 的 TTL 对齐，见类型注释
    private static let freshWindow: TimeInterval = 600

    /// 最近一次成功拿到的天气。nil = 从来没成功过（首次安装 / 一直断网）
    @Published private(set) var current: WeatherNow?

    /// 请求在飞（UI 据此转圈，同时防连点 —— 快速切页不该打出三次同样的请求）
    @Published private(set) var isLoading: Bool = false

    /// 最近一次**成功**的时间。用成功而不是发起时间：
    /// 否则一次失败会把缓存窗重新计满 10 分钟，用户接下来点刷新也只能干等
    private var lastSuccessAt: Date?

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    /// 有没有可显示的天气（决定卡片画天空还是走"天气未知"的降级外观）
    var hasData: Bool {
        return current != nil
    }

    /// 拉一次天气。
    ///
    /// - Parameter force: `true` 时忽略内存缓存（下拉刷新 / 从后台回到前台）。
    ///
    /// 全程**静默失败**：天气只是装饰性信息，不该弹 Toast 打断用户正在做的事，
    /// 也不该占用 `ToastStore`（那是"记账成功""登录过期"这类需要用户反应的提示的通道）。
    func load(force: Bool = false) async {
        // 上一发还在飞：直接返回，别叠加请求
        guard !isLoading else { return }

        // 缓存命中：什么都不做。`current` 已经是它了，重发只会多一次网络往返
        if !force, let lastSuccessAt = lastSuccessAt,
           Date().timeIntervalSince(lastSuccessAt) < Self.freshWindow {
            return
        }

        // 地址拼错是代码问题，不该表现为"天气未知"之外的任何东西：静默即可
        guard let url = API.weather() else { return }

        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 天气要"现在"：让 URLSession 的协议缓存别拿 304 糊弄我们
        // （`APIClient` 默认 `useProtocolCachePolicy`，对这类分钟级数据不合适）
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        do {
            let response = try await client.send(request, as: WeatherNow.self)
            // 业务失败（HTTP 200 + `ok == false`）：保留旧值，不更新成功时间，
            // 这样下一次调用会立刻重试，而不是被缓存窗挡住 10 分钟
            guard response.ok else { return }
            current = response
            lastSuccessAt = Date()
        } catch {
            // 传输 / 解码失败一律静默（`APIError.cancelled` 也走这里：页面切走时取消是正常行为）
            return
        }
    }
}
