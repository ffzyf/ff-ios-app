import Foundation
import Security

// MARK: - Keychain

/// 收益站凭证的 Keychain 封装：存一个字符串 / 读一个字符串 / 删掉。
///
/// 为什么不用 `UserDefaults`：收益金额是高隐私数据，`ce_auth` 是 30 天有效的会话 Cookie，
/// 拿到它就能读走全部收益。Keychain 的 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// 不随 iCloud 钥匙串漫游、不进 iTunes 明文备份，比 `UserDefaults` 的 plist 安全得多。
///
/// 为什么单独一套 `service`：**必须与问卷站的 `SurveyKeychain` 用不同的 service 名**
/// （`top.skyzyf.skyapp.ce` vs `top.skyzyf.skyapp.survey`），否则两套凭证会落到同一把钥匙上互相串号 ——
/// 用户登出问卷却把收益凭证也清掉，或反过来。Cookie 名 `ce_auth` 与后端 `_lib/earnings-auth.js`、`[[path]].js` 一致。
enum EarningsKeychain {

    /// 服务名（独立命名空间，避免与问卷站串号）
    static let service = "top.skyzyf.skyapp.ce"
    /// 账号名（Cookie 名，与后端一致）
    static let account = "ce_auth"

    /// 写凭证。先删后加（幂等，重复登录不会留多份副本）。
    @discardableResult
    static func save(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// 读凭证。没有 / 读失败一律返回 nil（读不到等同于未登录，不做修复尝试）。
    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 删凭证（登出 / 会话失效都走这里）。
    @discardableResult
    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound 也算成功：本来就没有，目标状态已达成
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - 登录错误

/// 收益登录失败的几种原因（用户能做的动作不同，文案分开）。
enum EarningsAuthError: Error, Equatable {
    /// 401：密码不对
    case wrongPassword
    /// 503：服务端没配访问密码（整体锁定）
    case notConfigured
    /// 传输入错（离线 / 超时）
    case network
    /// 其他：带上服务端原话（429 / 500 等）
    case server(String)

    /// 可直接上屏的一句现象 + 一句出路
    var userMessage: String {
        switch self {
        case .wrongPassword:
            return "密码不对，再试一次。"
        case .notConfigured:
            return "后台还没设置收益站访问密码，App 里登录不了。先去网页端把 ACCESS_PASSWORD 配好。"
        case .network:
            return "网络好像断了一下，等会儿再登录。"
        case .server(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "登录没成功，稍后再试。" : trimmed
        }
    }
}

// MARK: - 鉴权

/// 收益站凭证的唯一持有者（镜像 `SurveyAuth`）。
///
/// 三条硬规则（与 `SurveyAuth` 完全一致）：
/// 1. 凭证只在 Keychain，内存里留一份只为少读 Keychain；
/// 2. **凭证只从 `Set-Cookie` 响应头拿** —— `/api/auth/login` 的 JSON 只有 `{"ok":true}`，没有 token；
/// 3. 任何受保护接口回 401 立刻清凭证（`invalidate()`），由页面回到登录引导 —— 绝不让 App 揣着过期 Cookie 反复打 401。
///
/// 登录机制（已核实 `site/functions/api/auth/[[path]].js`）：`POST /api/auth/login` 带 `{password}`，
/// 成功返回 `200 + Set-Cookie: ce_auth=<token>; HttpOnly; ...`，**不是** JSON token。
/// 所以这里与 `SurveyAuth` 同款：从 `Set-Cookie` 抠 `ce_auth` 存 Keychain，请求时手写 `Cookie` 头。
///
/// 为什么是单例而非 `@EnvironmentObject`：收益页是从「更多」用 `fullScreenCover` 打开的，
/// 模态呈现不保证继承环境对象，单例 + `@ObservedObject` 能彻底绕开这条依赖。
final class EarningsAuth: ObservableObject {

    /// 全 App 唯一实例
    static let shared = EarningsAuth()

    /// 是否持有凭证（≠ 有效：30 天内服务端可能改密码，进收益页前还会 `verify()`）
    @Published private(set) var isLoggedIn: Bool

    /// 登录请求在飞（按钮转圈 + 防重复提交）
    @Published private(set) var isBusy: Bool = false

    private let client: APIClient
    /// 内存里的凭证值（不含 `ce_auth=` 前缀）
    private var token: String?

    init(client: APIClient = .shared) {
        self.client = client
        let stored = EarningsKeychain.read()
        self.token = stored
        self.isLoggedIn = (stored != nil)
    }

    /// 请求时手写 `Cookie` 头用的字符串；未登录返回 nil
    var cookieHeader: String? {
        guard let token = token, !token.isEmpty else { return nil }
        return "ce_auth=" + token
    }

    // MARK: - 登录

    /// 用访问密码换 Cookie（从 `Set-Cookie` 抠 `ce_auth` 存 Keychain）。
    /// 失败按状态码分流（401 密码错 / 503 未配置 / 其他带服务端原话）。
    func login(password: String) async throws {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EarningsAuthError.wrongPassword }
        guard let url = API.earningsAuthLogin() else {
            throw EarningsAuthError.server("地址拼错了。")
        }

        isBusy = true
        defer { isBusy = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        // 登录端点不读本地缓存
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let payload: [String: Any] = ["password": trimmed]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let raw: APIRawResponse
        do {
            raw = try await client.send(request)
        } catch let error as APIError {
            if case .cancelled = error { throw error }
            throw EarningsAuthError.network
        } catch {
            throw EarningsAuthError.network
        }

        switch raw.statusCode {
        case 200:
            guard let setCookie = raw.header("Set-Cookie"),
                  let value = EarningsAuth.cookieValue(fromSetCookie: setCookie) else {
                // 200 但没给 Cookie：服务端行为变了，明确告知而不是假装成功
                throw EarningsAuthError.server("登录成功了但没拿到凭证，请再试一次。")
            }
            EarningsKeychain.save(value)
            token = value
            isLoggedIn = true
        case 401:
            throw EarningsAuthError.wrongPassword
        case 503:
            throw EarningsAuthError.notConfigured
        default:
            throw EarningsAuthError.server(APIErrorEnvelope.anyMessage(from: raw.data))
        }
    }

    // MARK: - 校验

    /// 校验现有凭证是否还活着（进收益工作台前调一次）。
    /// 返回 true 表示「可以继续」：明确 `authed:false` / 401 → 清凭证 + 返回 false；
    /// 网络失败 → 返回原状态（不能因地铁里没信号就把用户踢出去）。
    @discardableResult
    func verify() async -> Bool {
        guard isLoggedIn else { return false }
        guard let url = API.earningsAuthStatus(), let cookie = cookieHeader else {
            return isLoggedIn
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        do {
            let raw = try await client.send(request)
            if raw.statusCode == 401 {
                invalidate()
                return false
            }
            guard raw.isSuccess,
                  let status = try? APIJSON.decoder.decode(EarningsSessionStatus.self, from: raw.data) else {
                // 5xx / 解析失败：服务端的问题，不注销用户
                return isLoggedIn
            }
            if status.authed == false {
                invalidate()
                return false
            }
            return true
        } catch {
            return isLoggedIn
        }
    }

    // MARK: - 登出

    /// 清凭证。顺序固定为「尽力通知服务端 → 本机必清」：
    /// 服务端 Cookie 无状态，本地删掉即失效，通知失败也不影响结果。
    ///
    /// **同时删掉所有 `earnings.*` 快照键**（设计文档 R20）：退出后如果还能看到
    /// 上一个账号的收益数据，那是数据泄露级别的问题。把「删凭证」与「删快照」放同一入口，
    /// 避免将来有人只做一半。
    func logout() async {
        if let url = API.earningsAuthLogout(), let cookie = cookieHeader {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10
            _ = try? await client.send(request)
        }
        invalidate()
        await SnapshotCache.shared.removeAll(withPrefix: EarningsStore.snapshotPrefix)
    }

    /// 只清本机状态（401 / 会话失效时用，不发网络请求 —— 已经 401 了再请求一次没有意义）
    func invalidate() {
        EarningsKeychain.delete()
        token = nil
        isLoggedIn = false
    }

    // MARK: - 工具

    /// 从 `Set-Cookie` 里抠出 `ce_auth` 的值。
    /// 两种写法都兼容：单条 `ce_auth=abc` 或多条被网关用逗号拼起来 `other=1, ce_auth=abc; Path=/…`。
    /// 先按 `;` 和 `,` 全部切开，再找带 `ce_auth=` 的那一段。
    static func cookieValue(fromSetCookie header: String) -> String? {
        let pieces = header.components(separatedBy: CharacterSet(charactersIn: ";,"))
        for piece in pieces {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let range = trimmed.range(of: "ce_auth=") else { continue }
            let raw = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { continue }
            // 服务端写 Cookie 时做过 encodeURIComponent，读回来解一次（token 里只有 . 与十六进制，通常原样）
            return raw.removingPercentEncoding ?? raw
        }
        return nil
    }

    /// `/api/auth/status` 的响应（无 `ok` 字段，只有几个布尔）
    private struct EarningsSessionStatus: Decodable {
        var authed: Bool?
    }
}
