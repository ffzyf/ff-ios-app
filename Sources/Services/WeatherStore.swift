import CoreLocation
import Foundation

/// 天气实况的 App 侧缓存（`GET /api/app/weather`，匿名只读）。
///
/// 只做三件事：
/// 1. 拉一次天气，成功就替换 `current`；
/// 2. 内存里扛 30 分钟，期间重复调用直接返回（回前台会强制穿一次，见 `refreshOnForeground()`）；
/// 3. 失败**保留上一次的 `current`**、**不报错**。
///
/// 3.16.0 起多带一个数：`visibilityMeters`（能见度，米）。它与天气**并发**请求、
/// 独立落账 —— 见 `load(force:)` 与 `visibilityMeters` 的注释。
///
/// 三条策略各自的理由：
/// · **30 分钟内存缓存**（3.18.0 由 10 分钟放宽）：与后端 KV 的 TTL 对齐。
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
///
/// ## 3.7.0：跟着设备位置走
/// 请求前读一次 `LocationStore.shared.coordinate`，有就带给 `API.weather(lat:lon:)`。
///
/// ## 3.17.0：没有定位时用「家」坐标
/// 没有设备定位（开关关着 / 权限被拒 / 还没拿到）时，改用 `HomeCoordinate.cached()`
/// —— 那是 App 上次上报给服务端、桌面小组件也在读的同一条记录（见 `resolvedCoordinate()`）。
/// 两个都没有才不带坐标，服务端回落默认值，与 3.7.0 之前的行为完全一致。没权限时不弹错误 UI，静默回落。
@MainActor
final class WeatherStore: ObservableObject {

    static let shared = WeatherStore()

    /// 内存缓存窗口（秒）。与后端 KV 的 TTL 对齐，见类型注释。
    ///
    /// 3.18.0：600 → **1800**（30 分钟）。用户要求「这个天气能不能 30 分钟刷新一次」，
    /// 同时后端 `weather.js` 的 KV TTL 也改成了 1800 —— 两边必须同一个数：
    /// App 比后端短，只是把同一份缓存多读几次；App 比后端长，用户就会看到
    /// 「后端已经换了天，卡片还是旧的」。高德实况本身就是小时级更新，
    /// 30 分钟既够新、也够省额度（个人开发者配额按次计）。
    private static let freshWindow: TimeInterval = 1800

    /// 回到前台时允许强制刷新的最小间隔（秒）。
    ///
    /// 用户要的是「每次打开 App 都拉一次当地的天气」，但"打开"在系统里
    /// 包含切出去回条消息再回来 —— 60 秒内来回切三次不该打三次接口
    /// （高德配额按次算）。60 秒之后才认为这是一次真正的"重新打开"。
    private static let foregroundDebounce: TimeInterval = 60

    /// 坐标变化的作废阈值（0.05° ≈ 5.5km）。
    ///
    /// 天气按公里级网格算：移动不到 5km 换来的仍是同一份天气，作废缓存只是白打一次接口。
    private static let coordinateTolerance: Double = 0.05

    /// 最近一次成功拿到的天气。nil = 从来没成功过（首次安装 / 一直断网）
    @Published private(set) var current: WeatherNow?

    /// 请求在飞（UI 据此转圈，同时防连点 —— 快速切页不该打出三次同样的请求）
    @Published private(set) var isLoading: Bool = false

    /// 最近一次**成功**的时间。用成功而不是发起时间：
    /// 否则一次失败会把缓存窗重新计满 10 分钟，用户接下来点刷新也只能干等
    private var lastSuccessAt: Date?

    /// 当前能见度（米）—— 只服务画面（`SkyHaze` 的雾浓度），不参与任何天气文案。
    ///
    /// 为什么和 `current` 分开两个 `@Published`：两者的失败互不牵连。
    /// 天气接口 500 时能见度照样可以更新（它打的是另一台上游），
    /// 而能见度拿不到时画面只是"不起雾"，天气卡一个字都不用变。
    @Published private(set) var visibilityMeters: Double?

    /// 上一次**成功**拿到能见度的时间。与 `lastSuccessAt` 同一个 10 分钟窗口，
    /// 但各自计时：天气失败不该让能见度也跟着 10 分钟内不再重试。
    private var lastVisibilityAt: Date?

    /// 上一次请求用的坐标（`nil` = 用的服务端默认坐标）。
    ///
    /// 只做一件事：判断"地点换了没有"。有坐标和没坐标**不是同一份数据**
    /// （一个是当地、一个是默认城市），所以两种状态之间的切换也一律作废缓存，
    /// 否则用户会在大西洋两岸的天气之间来回看到同一个幻觉。
    private var lastQueryCoordinate: CLLocationCoordinate2D?

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    /// 有没有可显示的天气（决定卡片画天空还是走"天气未知"的降级外观）
    var hasData: Bool {
        return current != nil
    }

    /// 回到前台时调一次：**每次都重新拉当地天气**（3.18.0）。
    ///
    /// 与 `load(force: true)` 的区别只有一个 `foregroundDebounce` 闸门：
    /// 下拉刷新 / 设置页改定位要的是"立刻"，回前台要的是"每次打开都新"——
    /// 但两者都会落到同一个 `load`，不需要第二套请求逻辑。
    ///
    /// 冷启动也走这里：`lastSuccessAt` 是内存值，进程新起时必为 nil，闸门直接放行。
    func refreshOnForeground() async {
        if let last = lastSuccessAt, Date().timeIntervalSince(last) < Self.foregroundDebounce {
            return
        }
        await load(force: true)
    }

    /// 拉一次天气（顺带一次能见度）。
    ///
    /// - Parameter force: `true` 时忽略内存缓存（下拉刷新 / 从后台回到前台）。
    ///
    /// 全程**静默失败**：天气只是装饰性信息，不该弹 Toast 打断用户正在做的事，
    /// 也不该占用 `ToastStore`（那是"记账成功""登录过期"这类需要用户反应的提示的通道）。
    ///
    /// ## 两个请求是并发的，不是串行的
    ///
    /// 能见度打的是另一台上游（Open-Meteo），与天气没有先后依赖 ——
    /// 串行等两发就是让用户多等一个 RTT。所以用 `async let` 同时发出，
    /// 天气那条走完再 `await` 能见度那条（此时它多半已经到了）。
    ///
    /// 两个缓存窗各自独立：天气在窗口内而能见度过期了，就只补能见度那一发。
    func load(force: Bool = false) async {
        // 上一发还在飞：直接返回，别叠加请求
        guard !isLoading else { return }

        // 这次请求实际要用的坐标：设备定位优先，没有就回落到「家」坐标的本地缓存
        // （`HomeCoordinate` —— App 开定位时上报给服务端、桌面小组件也读同一条记录的那份）。
        //
        // 为什么必须回落：定位关着时如果直接用服务端默认坐标，App 会显示郑州，
        // 而小组件用"上次上报的城市"—— 同一块桌面上两个城市，正是这次要修的问题。
        // `HomeCoordinate.cached()` 是同步读 `UserDefaults`，不引入 await。
        let coordinate = Self.resolvedCoordinate()

        // 地点变了 → 内存里那份天气不是"这里"的天气，必须作废。
        // 不做这一步的话，用户飞到另一个城市后卡片会继续显示出发地的天空 —— 而且看起来完全正常。
        // 能见度同理（它是"这里的空气有多浑浊"），而且要连缓存时间一起清。
        if Self.hasMoved(from: lastQueryCoordinate, to: coordinate) {
            lastSuccessAt = nil
            lastVisibilityAt = nil
            visibilityMeters = nil
            // 天气本身也要清：只清时间戳的话，下一次请求失败（断网 / 后端 500）
            // 会把出发地的天空原样留在屏幕上，而且看起来完全正常 —— 没人会怀疑。
            current = nil
            lastQueryCoordinate = coordinate
        }

        let now = Date()
        let weatherFresh = !force && (lastSuccessAt.map { now.timeIntervalSince($0) < Self.freshWindow } ?? false)
        let visibilityFresh = !force && (lastVisibilityAt.map { now.timeIntervalSince($0) < Self.freshWindow } ?? false)

        // 两份缓存都还新：什么都不做。`current` / `visibilityMeters` 已经是它们了，
        // 重发只会多打两次网络
        if weatherFresh && visibilityFresh { return }

        isLoading = true
        defer { isLoading = false }

        // 3.19.0：能见度不再和天气**并发**打了。
        //
        // 原因：和风实况本身就带 `visibility`（服务端已换算成米），天气响应里就有这个数。
        // 既然如此，再并发打一次 Open-Meteo 就是纯浪费 —— 一次请求换一个精度更低的重复值。
        // 所以改成「先看天气带没带，没带才补一发」，见下面的 `visibilityFallback`。
        // 代价是极少数情况下多一个串行 RTT；换来的是常态下一次请求就够了。
        if !weatherFresh,
           // 地址拼错是代码问题，不该表现为"天气未知"之外的任何东西：静默即可
           let url = API.weather(lat: coordinate?.latitude, lon: coordinate?.longitude) {
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
                if response.ok {
                    current = response
                    lastSuccessAt = Date()
                }
            } catch {
                // 传输 / 解码失败一律静默（`APIError.cancelled` 也走这里：页面切走时取消是正常行为）
            }
        }

        // 能见度落账（3.19.0 改成两级）：
        //   ① 天气响应里带了 `visibilityMeters`（和风）→ 直接用它，不再打第三方；
        //   ② 没带（和风挂了 / 降级到 Open-Meteo）→ 补一发 `VisibilityProbe` 兜底。
        //
        // 这样「画面起不起雾」在任何降级路径下都还有得画，而不是和风一挂整个天空就永远清透。
        if let fromWeather = current?.visibilityMeters {
            visibilityMeters = fromWeather
            if let successAt = lastSuccessAt { lastVisibilityAt = successAt }
        } else if !visibilityFresh,
                  let meters = await Self.probeVisibility(latitude: coordinate?.latitude,
                                                          longitude: coordinate?.longitude,
                                                          cached: false) {
            visibilityMeters = meters
            lastVisibilityAt = Date()
        }
    }

    /// 能见度那一发。`cached == true`（10 分钟窗口内）时直接给 nil，连请求都不发。
    ///
    /// 单独一个 `static` 方法，是为了让 `async let` 那行读起来还是一件事：
    /// 「取能见度」—— 取不取、跳不跳由参数决定，而不是在 `load` 里铺一段 if。
    ///
    /// `nonisolated`：它不碰任何状态，没理由占用主 actor。
    private nonisolated static func probeVisibility(latitude: Double?,
                                                    longitude: Double?,
                                                    cached: Bool) async -> Double? {
        guard !cached else { return nil }
        return await VisibilityProbe.fetch(latitude: latitude, longitude: longitude)
    }

    // MARK: - 坐标

    /// 这次请求实际要用的坐标：设备定位优先，「家」坐标的本地缓存兜底。
    ///
    /// - 定位可用（开关开着且 6 小时内的坐标）→ 用它，与 3.7.0 起的行为逐字一致；
    /// - 定位不可用 → 用 `HomeCoordinate.cached()`：那是 App 上次上报给服务端、
    ///   桌面小组件此刻正在读的同一条记录，于是两处落在同一个城市；
    /// - 两个都没有（从没开过定位）→ nil，`API.weather(lat:lon:)` 不带参数，
    ///   服务端回落默认坐标，与 3.7.0 之前完全一样。
    ///
    /// `LocationStore` 与 `WeatherStore` 都是 `@MainActor`，这里可以直接读，不需要显式跳 actor。
    ///
    /// 3.19.0 起由 `private` 改为 internal：`AlertStore` / `MinutelyStore` 必须用**完全相同的**
    /// 坐标去请求各自端点。各写一份的话，只要有一处忘了回落 `HomeCoordinate`，
    /// 预警就会盯着默认城市（郑州）报，而天气卡显示的是当地 —— 那种不一致最难被发现。
    static func resolvedCoordinate() -> CLLocationCoordinate2D? {
        if let device = LocationStore.shared.coordinate { return device }
        guard let home = HomeCoordinate.cached() else { return nil }
        return CLLocationCoordinate2D(latitude: home.lat, longitude: home.lon)
    }

    // MARK: - 坐标变了没有

    /// 两次请求之间的坐标是否算"换了地方"（见 `coordinateTolerance`）。
    ///
    /// 三种情况各自的意义：
    /// · 都没有坐标 → 没换（一直是默认城市）；
    /// · 都有坐标 → 差得超过 0.05° 才算换（同城内的移动不换天气）；
    /// · 一边有一边没有 → **算换**。这是最容易漏的一条：从"有坐标"变成"没有"
    ///   （用户关了开关）如果不作废缓存，卡片会继续显示当地天气，
    ///   而设置页的文案说的是"关闭后沿用上次的位置"（`WeatherLocationSection`），
    ///   两者必须同时成立 —— 关掉开关那一刻就重拉一次，卡片与文案才不会各说各话。
    private static func hasMoved(from previous: CLLocationCoordinate2D?,
                                 to current: CLLocationCoordinate2D?) -> Bool {
        switch (previous, current) {
        case (nil, nil):
            return false
        case let (previous?, current?):
            return abs(previous.latitude - current.latitude) > coordinateTolerance
                || abs(previous.longitude - current.longitude) > coordinateTolerance
        default:
            return true
        }
    }
}
