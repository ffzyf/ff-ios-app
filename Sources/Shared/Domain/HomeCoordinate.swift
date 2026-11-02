import Foundation

/// 主 App 与桌面小组件共享的「家」坐标。
///
/// 为什么需要它：Widget 跑在独立进程，工程没有 App Group（无签名 CI 开不了共享容器），
/// 读不到 App 的 `UserDefaults` 里的定位。结果是 App 显示上海、小组件显示服务端默认的郑州。
///
/// ## 为什么不需要设备标识（3.17.0 修 —— 别再改回去）
/// 3.17.0 用 `UIDevice` 的 IDFV 当设备键，前提是「同一个 App 的主程序与其扩展
/// 返回**同一个** IDFV」。**这个前提在本工程的安装方式下不成立**：
/// 项目是未签名 ipa + 侧载，非 App Store 安装时 IDFV 由 bundle ID 推导（去掉最后一段）——
///
/// ```
/// 主 App            top.skyzyf.skyapp         → IDFV 基于 top.skyzyf
/// Widget Extension  top.skyzyf.skyapp.widget  → IDFV 基于 top.skyzyf.skyapp
/// ```
///
/// 两端不是同一个值：App 上报的坐标 Widget 永远读不到，而且**完全静默** ——
/// KV 里只是多了一条没人读的记录，接口一直 200，日志里一个字都没有。
///
/// 所以方案改成：**服务端只存一条「当前位置」记录**，不需要任何设备标识，
/// 两端读写同一条，天然对齐。代价是多台设备会互相覆盖（谁最后上报谁生效）——
/// 这是单人自用 App 的合理简化：远好过"静默不同步"，且不引入任何标识符。
///
/// **不要再用 IDFV（或任何 `UIDevice` 的东西）**：一是上面这条推导规则让两端对不上；
/// 二是 `UIDevice` 是 `@MainActor`，在 `nonisolated` 上下文（比如本类型的 `static` 属性）
/// 里读会**直接编译失败** —— 这正是那个 IDFV 计算属性必须删干净、连一行注释都不留的原因。
/// 顺带：Widget target 也就不再需要 `import UIKit` 了。
///
/// ## 数据流（3.17.0）
/// ```
/// CLLocationManager → LocationStore（App，主 actor）
///        │ 拿到坐标立刻上报（2km + 6h 节流，地名到手后再补报一次带 name 的）
///        ▼
/// POST /api/app/home  {lat, lon, name}        ← 只有一条记录，无 id
///        ▲
///        │ GET /api/app/home                   ← 不带任何 query
///        │
/// HomeCoordinate.resolved() → WidgetFetch.weather() / SkyLightProvider
/// ```
/// 两端**各自**缓存一份（各自的 `UserDefaults.standard`），但缓存的内容来自服务端同一条记录 ——
/// 这就是"没有 App Group 也能对齐"的全部秘密。
///
/// ## 三条纪律
/// 1. **不抛错、不打扰用户**：这是让小组件对齐的附属动作，失败就静默（App 侧不上 Toast）；
/// 2. **资源紧张**：Widget 的刷新预算很贵，所以有 45 分钟本地缓存 + 4 秒读超时；
/// 3. **域名只在 `Endpoint`**：URL 一律走 `Endpoint` / `API`，本文件不出现任何域名。
///
/// 本文件在 `Sources/Shared`，**App 与 Widget 两个 target 都编译** —— 这是它能同时被两边用的前提。
struct HomeCoordinate: Equatable {

    /// 纬度（度）
    let lat: Double
    /// 经度（度）
    let lon: Double
    /// 两级地名（"上海市 · 浦东新区"）。服务端没记录 / App 还没反查出来时是 nil。
    let name: String?

    // MARK: - 常量

    /// 缓存键。App 进程与 Widget 进程各有自己的 `standard`，互不干扰 —— 见类型注释。
    private static let cacheKey = "home.coordinate"

    /// 本地缓存有效期：45 分钟。
    ///
    /// 先说清它量的是什么：这是**Widget 上次拉取的时间**，不是"坐标本身的新鲜度"。
    /// App 在另一侧上报了上海，本进程的缓存并不会因此失效 —— 缓存只认自己那次 GET。
    ///
    /// 3.17.0 这里是 6 小时，理由写的是"Widget 预算贵"。但 6 小时意味着
    /// 「App 里换了城市、小组件还是旧城市」的窗口长达半天 —— 而命中缓存时零网络开销，
    /// 一轮刷新省下的那一个 RTT 远不值得让用户看半天错误城市。
    /// 45 分钟是「不明显变慢」与「跟得上换城市」的折中：一天最多的几十轮刷新里，
    /// 绝大多数仍然命中缓存（timeline 的刷新间隔本来就大于这个值）。
    private static let cacheLifetime: TimeInterval = 45 * 60

    /// 读超时：4 秒。Widget 不能为了一个坐标把整轮 timeline 的交付往后拖。
    private static let readTimeout: TimeInterval = 4

    /// 写超时：8 秒。App 侧慢慢来 —— 它本来就跑在后台任务里，失败也没人等。
    private static let writeTimeout: TimeInterval = 8

    /// 沿用旧地名的容差（0.02° ≈ 2.2km）：与 `WeatherLocationSetting.placeTolerance` 同一个数量级，
    /// 这个范围内地名不会变（同一个区）。见 `carriedName(_:lat:lon:)`。
    private static let nameCarryTolerance: Double = 0.02

    // MARK: - 本地缓存

    /// 同步读本地缓存（不看有效期）。
    ///
    /// 供 App 侧在"定位关着"时回落用（`WeatherStore.resolvedCoordinate()`）——
    /// 那里不能 `await`，而"宁可旧也不要空"在这里同样成立。
    ///
    /// 天光页的 `placeLabel` 也读它：定位关着时天气用的是这条坐标，
    /// 界面文案就必须说这条坐标的地名，而不是服务端默认城市（见 `SkyRoomView`）。
    static func cached() -> HomeCoordinate? {
        guard let payload = loadPayload() else { return nil }
        return coordinate(from: payload)
    }

    /// 写本地缓存（同时刷新 `updatedAt`）。坐标不合法时什么都不做。
    static func save(_ value: HomeCoordinate) {
        guard isValid(lat: value.lat, lon: value.lon) else { return }
        let payload = Payload(lat: value.lat,
                              lon: value.lon,
                              name: normalize(value.name),
                              updatedAt: Date())
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    /// 清本地缓存。目前只在"记录坏了"这类边缘场景手动调，App 关定位**不**清它 ——
    /// 关掉定位后 App 与小组件都该继续显示同一座（上次上报的）城市，而不是各自退到默认值。
    static func clear() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    // MARK: - 解析

    /// 优先用缓存（45 分钟内），过期才走网络；网络失败回退旧缓存（宁可旧不要空）。
    ///
    /// 五条路径，逐条都有明确的落点：
    /// 1. 有缓存且 `updatedAt` 在 45 分钟内 → 直接返回（**不发请求**：Widget 刷新预算很贵）；
    /// 2. 否则 GET（超时 4 秒）；
    /// 3. 成功且有坐标 → 存缓存并返回；
    /// 4. 成功但 `lat`/`lon` 为 `null`（服务端还没有任何记录）→ 返回**旧缓存**（如果有），否则 nil；
    /// 5. 失败 → 返回旧缓存，否则 nil。
    ///
    /// 全程不抛错：本方法的返回值只有"有坐标"和"没有坐标"两种语义，
    /// 调用方（`WidgetFetch.weather()` / `SkyLightProvider`）据此决定带不带 `lat/lon`，
    /// 不带就是服务端默认坐标 —— 与 3.16.0 及之前的行为一致，不是错误态。
    static func resolved() async -> HomeCoordinate? {
        // 1. 缓存新鲜：连请求都不发
        if let payload = loadPayload(),
           let fresh = coordinate(from: payload),
           Date().timeIntervalSince(payload.updatedAt) < cacheLifetime {
            return fresh
        }

        // 过期缓存：网络任何一处失败都回退到它
        let stale = cached()

        // 服务端只有一条记录，读它不需要带任何标识（见类型注释「为什么不需要设备标识」）
        guard let url = API.homeRead() else { return stale }
        guard let response = await read(HomeReadResponse.self, url: url) else { return stale }
        guard response.ok,
              let lat = response.lat,
              let lon = response.lon,
              isValid(lat: lat, lon: lon) else {
            // 4. `lat`/`lon` 为 null = 服务端还没有记录：旧缓存比"没有"有用（如果它是真的旧数据）
            return stale
        }

        let value = HomeCoordinate(lat: lat, lon: lon, name: normalize(response.name))
        save(value)
        return value
    }

    /// App 定位成功后上报。失败静默（这只是让小组件对齐，不该打扰用户）。
    ///
    /// **不在这里做节流**：节流由调用方（`LocationStore`）负责 —— 本方法只负责"把一条坐标送出去"，
    /// 把"多久送一次"塞进来会让它同时管两件事。
    ///
    /// ## 返回值的语义：**服务端是不是已经站在这次坐标上**
    /// 既不是"HTTP 成不成功"，也不是"服务端收没收到" —— 是"小组件下次 `GET` 拿到的是不是这个点"。
    /// 服务端有四种回应，逐条对应一个落点：
    ///
    /// | 服务端回应 | 服务端那条记录 | 本地缓存 | 返回 |
    /// | --- | --- | --- | --- |
    /// | `saved: true` | 就是这次坐标 | 写 | `true` |
    /// | `saved: false, reason: "unchanged"` | 已经是同点同 name | 写 | `true` |
    /// | `saved: false, reason: "throttled"` | **可能是上一座城市** | 写 | `false` |
    /// | `ok: false` / 非 2xx / 网络失败 / 认不出的 reason | 不知道 | 不写 | `false` |
    ///
    /// ### `throttled` ≠ `unchanged`（这一行别再合并成一个 `!saved`）
    /// 两者都是 `saved: false`，含义**正好相反**：
    ///
    /// - `unchanged` 是**「已经一样了」** —— 服务端手上那条就是这个点、这个 name，
    ///   小组件读到的已经是最新值。所以算**接受**：调用方可以推进节流状态，也可以推小组件。
    /// - `throttled` 是**「别写太快」** —— 60 秒内刚有人报过，服务端**丢掉了**这次坐标，
    ///   它那条记录可能就是上一座城市。所以必须返回 `false`：调用方不推进节流状态
    ///   （下一次定位要重试，直到真报进去为止），也不能把小组件当成已对齐。
    ///
    /// 3.17.0–3.17.0 的写法是"只要 `ok == true` 就算成功"，把 `throttled` 一起吞了：
    /// 用户在 60 秒窗口内换城市（郑州 → 上海，正好落在窗口里），App 认为已同步、
    /// 6 小时内不再重试，而小组件那边一直是郑州 —— 最长 6 小时分叉。
    ///
    /// ### 为什么 `throttled` 仍然写本地缓存
    /// 这份坐标是**刚定位到的真实值**，对 App 自己有用（关掉定位后 `WeatherStore` 的回落、
    /// 天光页 `placeLabel` 都读这条缓存）。服务端没收下，不代表本地该继续显示旧城市。
    /// 缓存与"节流状态"是两件事：前者记"我知道的最新事实"，后者记"服务端跟上了没有"。
    @discardableResult
    static func publish(lat: Double, lon: Double, name: String?) async -> Bool {
        guard isValid(lat: lat, lon: lon) else { return false }
        guard let url = API.homeWrite() else { return false }

        // 请求体没有 id：服务端只存一条「当前位置」，见类型注释
        let body = WriteBody(lat: rounded(lat),
                             lon: rounded(lon),
                             name: normalize(name))
        guard let data = try? JSONEncoder().encode(body) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = writeTimeout
        // 坐标是"现在这个值"，别让协议缓存糊弄我们
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return false }
            guard let result = try? JSONDecoder().decode(WriteResponse.self, from: responseData),
                  result.ok else { return false }

            // 走到这里 = 服务端应答了、且没报错。下面按"服务端站在哪"分流（见方法注释里的表）。
            let accepted: Bool
            if result.saved == true {
                // 真写进去了：服务端那条就是这次坐标
                accepted = true
            } else if result.reason == "unchanged" {
                // 「已经一样了」：服务端那条已是同点同 name，小组件读到的就是它 → 算接受
                accepted = true
            } else if result.reason == "throttled" {
                // 「别写太快」：服务端**没接受**这次坐标，它那条可能是上一座城市 → 不能算接受。
                // 返回 false 让调用方不推进节流状态，下一次定位继续重试。
                accepted = false
            } else {
                // `saved:false` 但原因认不出（服务端将来新增的 reason / 干脆没给 reason）：
                // 不能说"服务端已站在这次坐标上"。既不算接受，也不写缓存 ——
                // 与"没拿到确认"的失败路径保持同一口径。
                return false
            }

            // 本地这**一条**缓存三种情形都写：它记的是"我刚定位到的真实坐标"，
            // 与"服务端跟没跟上"无关（`throttled` 也要写，理由见方法注释最后一节）。
            save(HomeCoordinate(lat: lat,
                                lon: lon,
                                name: carriedName(name, lat: lat, lon: lon)))
            return accepted
        } catch {
            // 超时 / 断网 / 解码失败：一律静默（理由见类型注释第 1 条）
            return false
        }
    }

    // MARK: - 私有：缓存载荷

    /// 落盘的载荷。存一个 `JSON` `Data` 而不是四个散键：一次读写、要么全有要么全无，
    /// 不会出现"经纬度更新了、`updatedAt` 还是旧的"这种半截状态。
    private struct Payload: Codable {
        let lat: Double
        let lon: Double
        let name: String?
        let updatedAt: Date
    }

    private static func loadPayload() -> Payload? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// 载荷 → 值（坐标不合法就当没有）
    private static func coordinate(from payload: Payload) -> HomeCoordinate? {
        guard isValid(lat: payload.lat, lon: payload.lon) else { return nil }
        return HomeCoordinate(lat: payload.lat, lon: payload.lon, name: payload.name)
    }

    /// 上报时 `name` 常为 nil（定位一到就上报，地名反查还在路上）。此时若旧缓存的
    /// 地名说的**就是这片地方**（0.02° 内），沿用它 —— 否则一次 name 为 nil 的上报
    /// 会把刚反查出来的地名从缓存里抹掉，天光页的"上次位置 · …"随之退化成默认城市。
    /// 坐标差得多时**不能**沿用：那是上一座城市的名字，比没有名字更糟。
    private static func carriedName(_ name: String?, lat: Double, lon: Double) -> String? {
        if let normalized = normalize(name) { return normalized }
        guard let previous = cached(), let previousName = normalize(previous.name) else { return nil }
        guard abs(previous.lat - lat) <= nameCarryTolerance,
              abs(previous.lon - lon) <= nameCarryTolerance else { return nil }
        return previousName
    }

    // MARK: - 私有：网络信封

    /// `GET /api/app/home` 的响应。
    ///
    /// 无记录时是 `{"ok":true,"lat":null,"lon":null,"name":null,"updatedAt":null}` ——
    /// `lat`/`lon` 全部可选，`null` 就是"没有记录"，**不是**错误。
    /// `updatedAt` 不参与判断（我们以"本地什么时候存下它"为准，见 `Payload.updatedAt`）。
    private struct HomeReadResponse: Decodable {
        let ok: Bool
        let lat: Double?
        let lon: Double?
        let name: String?
    }

    /// `POST /api/app/home` 的请求体：**没有 `id`**（服务端只有一条记录）。
    /// `name` 为 nil 时由合成的 `encode(to:)` 直接省略该键
    /// （服务端把"没有键"与"null"当同一件事，省略少一层歧义）。
    private struct WriteBody: Encodable {
        let lat: Double
        let lon: Double
        let name: String?
    }

    /// 上报响应：`{"ok":true,"saved":true}` / `{"ok":true,"saved":false,"reason":"throttled"}`
    /// / `{"ok":true,"saved":false,"reason":"unchanged"}`
    ///
    /// `reason` **参与判断**：服务端只在 `saved == false` 时给，两个已知值
    /// `"throttled"`（限频，这次坐标被丢掉）与 `"unchanged"`（已存记录就是同点同 name）
    /// 含义相反 —— `publish` 的返回值就靠区分它俩，**别再合并成一个 `!saved`**。
    /// `saved` 声明成可选：正常契约里一定有，但缺键时宁可当"没说"，
    /// 也不要为了一行 JSON 让整次上报解码失败（那会退化成"永远不同步"）。
    private struct WriteResponse: Decodable {
        let ok: Bool
        let saved: Bool?
        let reason: String?
    }

    // MARK: - 私有：请求

    /// 极简 GET + 解码：任何失败（拼不出 URL / 超时 / 非 2xx / 解码失败）都返回 nil。
    ///
    /// 为什么不复用 Widget 侧的 `WidgetFetch.get(_:url:)`：它在 `Sources/Widget`，
    /// 而本文件属于 `Sources/Shared` —— Shared 不能反向依赖 Widget（App target 不编译 Widget）。
    /// 为什么不复用 Services 的 `APIClient`：同上，且 Widget target 不编译 Services。
    /// 所以这里自己写一份，只有十几行，且超时是 4 秒（比那两处都短，理由见 `readTimeout`）。
    private static func read<T: Decodable>(_ type: T.Type, url: URL) async -> T? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = readTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - 私有：清洗

    /// 坐标合法性：有限、在经纬度范围内、且不是 `(0, 0)`。
    ///
    /// `(0, 0)` 单独排除：那是几内亚湾，CoreLocation 刚启动时偶尔会给这个空值，
    /// 服务端也可能因为上游缺参落成 0 —— 拿它算出来的天气比"没有坐标"糟得多。
    private static func isValid(lat: Double, lon: Double) -> Bool {
        guard lat.isFinite, lon.isFinite else { return false }
        guard (-90.0...90.0).contains(lat), (-180.0...180.0).contains(lon) else { return false }
        return !(lat == 0 && lon == 0)
    }

    /// 上报前保留四位小数（0.0001° ≈ 11m）：足够区分到区，又不会因为浮点尾数抖动
    /// 让服务端每次都认为"坐标变了"。
    private static func rounded(_ value: Double) -> Double {
        return (value * 10_000).rounded() / 10_000
    }

    /// 地名清洗：去空白，空串按 nil（服务端偶尔给 `" "`，落盘后会让小组件显示一行空白）
    private static func normalize(_ name: String?) -> String? {
        guard let name = name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
