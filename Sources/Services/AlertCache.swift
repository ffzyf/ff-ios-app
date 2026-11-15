import Foundation

/// 预警响应的**跨启动缓存**（R1 · 架构 §1.1-2 / §3.5）。
///
/// ## 只存原文
/// 缓存的是 `/api/app/alerts` 返回的**原始 JSON `Data`**，不是 `[WeatherAlert]`。
/// 理由有两个：`WeatherAlert` 目前只有 `Decodable`，`Codable` 化要动模型；
/// 而存原文可以让模型将来加字段时老缓存照样读得出来，也不会出现
///「本地快照与线上响应字段漂移」。解码统一走 `APIJSON.decoder`。
///
/// ## 只在 `ok == true` 时写
/// `ok == false` / 传输失败 / 解码失败**绝不覆盖**（架构 §1.1-2 硬约束）。
/// 这道闸写在 `save(...)` 里而不是只靠调用方自觉：它在落盘前先把 `data`
/// 解一次 `AlertsResponse`，`ok != true` 直接返回。空列表（确认无预警）
/// 也是 `ok == true`，照常写 —— 那是 R1 四态里 `.confirmedNone` 的唯一依据。
///
/// 不用 `Codable` 存 `Date`：网络响应用 `APIJSON.decoder`（ISO8601 自定义策略），
/// 而 UserDefaults 字典里的时间统一存 `TimeInterval`（Double），两条解码路径
/// 谁也读不到对方的 `Date` 形态（同 `MonitorTime` 那条纪律）。
final class AlertCache {

    /// 一份缓存快照：原文 + 元信息
    struct Snapshot: Equatable, Sendable {
        /// 后端响应原始 JSON
        let data: Data
        /// 写下的时刻（首帧的 `lastSuccessAt` 取它）
        let savedAt: Date
        /// 这份数据来自哪个接口（诊断区显示）
        let endpoint: String
        /// 写入时的结果串，如 `ok:true · hit`
        let lastResult: String
        /// 当时的 `X-Alerts-Cache` 响应头
        let cacheHeader: String?

        init(data: Data,
             savedAt: Date,
             endpoint: String,
             lastResult: String,
             cacheHeader: String?) {
            self.data = data
            self.savedAt = savedAt
            self.endpoint = endpoint
            self.lastResult = lastResult
            self.cacheHeader = cacheHeader
        }
    }

    /// UserDefaults key（架构 §3.5；不要散落到别处）
    static let key = "weather.alert.snapshot.v2"

    /// 字典里的子键，集中在这里避免拼错
    private enum Field {
        static let data = "data"
        static let savedAt = "savedAt"
        static let endpoint = "endpoint"
        static let lastResult = "lastResult"
        static let cacheHeader = "cacheHeader"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 同步读出快照。`AlertStore.init()` 用它定首帧，必须 < 10ms 且不发请求。
    ///
    /// 任何字段缺失 / 类型不对都返回 nil —— 半份缓存不如没有缓存，
    /// 那样会落到 `.loadingFirst` 而不是渲染一份看不懂的数据。
    func load() -> Snapshot? {
        guard let raw = defaults.dictionary(forKey: Self.key),
              let data = raw[Field.data] as? Data,
              !data.isEmpty,
              let savedAt = raw[Field.savedAt] as? Double else {
            return nil
        }
        return Snapshot(
            data: data,
            savedAt: Date(timeIntervalSince1970: savedAt),
            endpoint: (raw[Field.endpoint] as? String) ?? Endpoint.alertsEndpointText,
            lastResult: (raw[Field.lastResult] as? String) ?? "ok:true",
            cacheHeader: raw[Field.cacheHeader] as? String
        )
    }

    /// 写入一份**已确认成功**的响应原文。
    ///
    /// - Parameters:
    ///   - data: `/api/app/alerts` 的原始响应字节（原样存，不重新序列化）
    ///   - endpoint: 完整接口地址
    ///   - result: 结果串（诊断区用）
    ///   - cacheHeader: `X-Alerts-Cache`，nil 就不写这个子键
    func save(data: Data, endpoint: String, result: String, cacheHeader: String?) {
        guard !data.isEmpty else { return }
        // 唯一守门：不是 ok:true 一律不落盘（含空壳、错误信封、坏 JSON）
        guard let response = try? APIJSON.decoder.decode(AlertsResponse.self, from: data),
              response.ok else {
            return
        }

        var raw: [String: Any] = [
            Field.data: data,
            Field.savedAt: Date().timeIntervalSince1970,
            Field.endpoint: endpoint,
            Field.lastResult: result
        ]
        if let header = cacheHeader, !header.isEmpty {
            raw[Field.cacheHeader] = header
        }
        defaults.set(raw, forKey: Self.key)
    }

    /// 把缓存原文解成 Domain 层可判定的快照（R1 首帧 / 失败兜底都用它）。
    ///
    /// 这一步是 `AlertCache.Snapshot` → `AlertCachedSnapshot` 的桥：
    /// `AlertPresentation.reduce` 在 `Sources/Shared/Domain`，不能反过来依赖
    /// `Sources/Services`（Widget target 不编译 Services）。
    func presentationSnapshot() -> AlertCachedSnapshot? {
        guard let snapshot = load(),
              let response = try? APIJSON.decoder.decode(AlertsResponse.self, from: snapshot.data),
              response.ok else {
            return nil
        }
        return AlertCachedSnapshot(
            items: response.warnings ?? [],
            savedAt: snapshot.savedAt,
            endpoint: snapshot.endpoint,
            lastResult: snapshot.lastResult,
            cacheHeader: snapshot.cacheHeader
        )
    }

    /// 清空（只给调试 / 未来「重置数据源」用；正常刷新路径绝不调用）
    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
