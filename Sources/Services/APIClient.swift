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

    // MARK: - 批次 3 增补：问卷站需要「原始状态码 + 响应头」

    /// 发一次请求并**原样**返回结果（不判状态码、不解析 body）。
    ///
    /// 为什么不能复用 `get`：
    /// 1. 问卷站的管理凭证在 `Set-Cookie` 响应头里 —— JSON 里只有一个 `{"ok":true}`，
    ///    看不到响应头就拿不到 token；
    /// 2. 它的 401 响应体是 `{error:"字符串"}`（不是对象信封），且"密码错(401)"与
    ///    "后台未配置密码(503)"必须分开给文案 —— 折成 `.server` 就分不出来了。
    ///
    /// 传输入错（离线 / 超时 / 取消）仍然在这里归一成 `APIError`，
    /// 保证调用方只需要处理一种错误类型。
    func send(_ request: URLRequest) async throws -> APIRawResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.network }
            return APIRawResponse(data: data, response: http)
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

    /// `send` + 解码：2xx 才解码，其余抛 `.server`（message 取服务端原话）
    func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let raw = try await send(request)
        guard raw.isSuccess else {
            throw APIError.server(code: raw.statusCode, message: APIErrorEnvelope.anyMessage(from: raw.data))
        }
        do {
            return try APIJSON.decoder.decode(T.self, from: raw.data)
        } catch {
            throw APIError.decoding
        }
    }
}

// MARK: - 原始响应

/// 一次传输的结果：字节 + HTTP 响应（状态码 / 响应头）。
///
/// 只在"需要看响应头"或"需要分辨 401 / 503"的地方使用（问卷登录、提交、发布截止）；
/// 普通只读 GET 一律走 `get(_:as:)`，那条路径带协议缓存与统一错误归一。
struct APIRawResponse {
    let data: Data
    let response: HTTPURLResponse

    var statusCode: Int { response.statusCode }

    var isSuccess: Bool { (200..<300).contains(response.statusCode) }

    /// 响应头读取（大小写不敏感，`HTTPURLResponse` 自己处理）
    func header(_ name: String) -> String? {
        return response.value(forHTTPHeaderField: name)
    }

    /// 响应体文本（调试与"服务端说了什么"兜底用）
    var text: String {
        return String(data: data, encoding: .utf8) ?? ""
    }
}
