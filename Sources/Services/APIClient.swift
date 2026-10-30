import Foundation

// MARK: - 解码器

/// 全工程共用的 `JSONDecoder`。
///
/// 日期策略**必须自定义**：服务端所有时间字段都是 `new Date(ms).toISOString()`，
/// 形如 `"2026-10-30T13:04:11.000Z"`（**带毫秒**），而 `JSONDecoder.DateDecodingStrategy.iso8601`
/// 用的 `ISO8601DateFormatter` 默认不带 `.withFractionalSeconds`，直接解析会失败。
/// 这里两个 formatter 都试：带毫秒的优先，纯秒的兜底（`pushedAt` 的值可能是历史写入的旧格式）。
///
/// `keyDecodingStrategy` 不设：后端 JSON 已经是 camelCase，与模型属性逐字一致，
/// 设成 `convertFromSnakeCase` 反而会让 `createdAt` 这种字段名被误伤。
enum APIJSON {
    static let decoder: JSONDecoder = makeDecoder()

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()

        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        withFractional.timeZone = TimeZone(secondsFromGMT: 0)

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        plain.timeZone = TimeZone(secondsFromGMT: 0)

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = withFractional.date(from: raw) {
                return date
            }
            if let date = plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "无法解析的时间字符串: \(raw)"
                )
            )
        }

        return decoder
    }
}

// MARK: - 客户端

/// `URLSession` 封装。零第三方依赖。
///
/// 缓存策略（设计文档 §3.6）：**协议缓存交给系统**。
/// 服务端给了 `Cache-Control` 与弱 `ETag`，`URLSession` 会自己带 `If-None-Match`、
/// 自己处理 304、自己回填缓存 —— App 侧一行条件请求代码都不写，白拿省流量。
///
/// 该类不是 `@MainActor`：网络请求不该占主线程。
/// 所有状态写入都在 `AppModel`（`@MainActor`）里做，UI 永远在主线程更新。
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        // 默认就是 useProtocolCachePolicy，这里显式写出来，避免被后人「优化」成 reloadIgnoringCache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = URLCache.shared
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpAdditionalHeaders = ["User-Agent": "FFWang/2.0 (iOS)"]
        self.session = URLSession(configuration: configuration)
    }

    /// 泛型 GET + 解码。
    func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let data = try await loadData(from: url)
        do {
            return try APIJSON.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    /// 只取字节（图片、调试用）
    func getData(_ url: URL) async throws -> Data {
        return try await loadData(from: url)
    }

    private func loadData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            return try validate(data: data, response: response)
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled {
                throw APIError.cancelled
            }
            throw APIError.network
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.network
        }
    }

    private func validate(data: Data, response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network
        }
        if (200..<300).contains(http.statusCode) {
            return data
        }
        if http.statusCode == 304 {
            // 正常情况 304 已被 URLSession 吃掉（回填缓存后当 200 返回）。
            // 真走到这里说明缓存没命中又没有 body，当网络问题处理，让用户下拉重试。
            throw APIError.network
        }
        throw APIError.server(code: http.statusCode, message: APIErrorEnvelope.message(from: data))
    }
}
