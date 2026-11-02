import Foundation

/// 从 Open-Meteo 取当前能见度（米）。
///
/// 为什么直连而不是走 `/api/app/weather`：那个后端已经上线、源码不在本仓库，
/// 加字段等于赌它下次部署不会覆盖掉。Open-Meteo 免费、无密钥、和后端用的是同一个上游，
/// 数值口径天然一致。
///
/// ## 三条纪律
///
/// 1. **任何失败都返回 nil**：不抛错、不兜底成 24km —— 那会让雾天显示成通透天，
///    而这正是本文件存在的理由（见 `SkyHaze` 的"不做兜底"那条）；
/// 2. **超时 6 秒**：它只服务画面，一行天气卡不该为了一缕雾多等 15 秒；
/// 3. **域名只在 `Endpoint` 里**（`Endpoint.openMeteoBase`）—— 全工程唯一允许出现
///    域名的地方就是那个文件，这条规矩比"少写一个常量"重要得多。
///
/// 本文件被主 App 与 Widget target 同时编译（`Sources/Shared`），所以只依赖
/// `Foundation` + `Endpoint`，不碰任何 UI 类型。
enum VisibilityProbe {

    // MARK: - 常量

    /// 请求超时（秒）。见类型注释第 2 条
    private static let timeout: TimeInterval = 6

    /// 坐标缺省时的落点：郑州。
    /// 与 `/api/app/weather` 不带 `lat/lon` 时的服务端默认坐标一致 ——
    /// 两处一致才不会出现"能见度按上海算、天气按郑州算"的错配。
    private static let defaultLatitude: Double = 34.7466
    private static let defaultLongitude: Double = 113.6254

    /// 字段路径（只读一个字段，`current` 是 Open-Meteo 的当前实况块）
    private static let forecastPath = "/v1/forecast"

    // MARK: - 取数

    /// 取当前能见度（米）。
    ///
    /// - Parameters:
    ///   - latitude: 纬度（度）。nil / 非法值 → 用郑州
    ///   - longitude: 经度（度）。nil / 非法值 → 用郑州
    /// - Returns: 能见度（米）；网络 / 解码 / 业务异常一律 nil（理由见类型注释第 1 条）
    static func fetch(latitude: Double?, longitude: Double?) async -> Double? {
        // 半对半错的坐标比"没有坐标"更糟（会得到另一个半球的能见度），所以成对判定
        let lat = sanitized(latitude, limit: 90) ?? defaultLatitude
        let lon = sanitized(longitude, limit: 180) ?? defaultLongitude

        guard let url = Endpoint.url(
            base: Endpoint.openMeteoBase,
            path: forecastPath,
            query: [
                URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
                URLQueryItem(name: "longitude", value: String(format: "%.4f", lon)),
                URLQueryItem(name: "current", value: "visibility"),
                // `auto` 让上游按坐标所在时区给时刻；本文件只读一个与时间无关的标量，
                // 但保持与后端的请求口径一致，将来要读 `current.time` 时不会突然错 8 小时
                URLQueryItem(name: "timezone", value: "auto")
            ]
        ) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 能见度是分钟级的量：别让协议缓存拿 304 糊弄我们
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // 只有 `URLRequest` 能带自定义超时（`data(from: URL)` 用会话默认的 60s）
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                return nil
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard let visibility = decoded.current?.visibility,
                  visibility.isFinite,
                  // 严格大于 0：上游若把"缺测"写成 0，会被 SkyHaze 夹成满格浓雾，
                  // 整片天莫名其妙糊成灰白 —— 那是比"没有数据"糟得多的错误。
                  visibility > 0 else {
                return nil
            }
            return visibility
        } catch {
            // 传输失败 / 取消 / 解码失败：一律当作"没有数据"，交给 `SkyHaze` 的类型底值
            return nil
        }
    }

    // MARK: - 私有

    /// 坐标合法性：必须是有限数，且落在 ±limit 之内。
    private static func sanitized(_ value: Double?, limit: Double) -> Double? {
        guard let value = value, value.isFinite, abs(value) <= limit else { return nil }
        return value
    }

    /// Open-Meteo 的响应信封：`{"current":{"visibility":12345.0}}`
    ///
    /// 两个字段都是可选：`current` 之外还有很多字段我们不关心，
    /// 而 `visibility` 在极端情况下可能缺省 —— 缺了就是"没数据"，不是 0。
    private struct Response: Decodable {
        let current: Current?

        struct Current: Decodable {
            let visibility: Double?
        }
    }
}
