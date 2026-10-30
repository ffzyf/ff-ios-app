import Foundation
import Security

// MARK: - Keychain

/// Keychain 的最小封装：**只支持**「存一个字符串 / 读一个字符串 / 删掉」。
///
/// 为什么凭证不能放 `UserDefaults`：
/// `qw_auth` 是一张 30 天有效期的管理凭证（HMAC 签名，服务端无状态），
/// 拿到它就等于拿到问卷列表、全部答卷明细与「其他」选项里的自由文本。
/// `UserDefaults` 是明文 plist，iTunes 备份与越狱设备都能直接读出来 ——
/// 一份"看得见的凭证"比一份"看得见的答卷"更糟：前者可以继续用，后者只是历史数据。
///
/// 为什么不用第三方 Keychain 库（如 KeychainAccess）：这里只需要 3 个 API，
/// 引一个依赖换 40 行代码不划算，而且 V3 的硬约束之一就是零第三方依赖。
enum SurveyKeychain {

    /// 服务名（同一个 App 内用来分组，改它等于让所有老用户重新登录，不要随手改）
    static let service = "top.skyzyf.skyapp.survey"
    /// 账号名（Cookie 名，与服务端 `_lib/auth.js` 的 `COOKIE_NAME` 一致）
    static let account = "qw_auth"

    /// 写凭证。
    ///
    /// 采用「先删后加」而不是 `SecItemUpdate`：
    /// `SecItemAdd` 对已存在的项返回 `errSecDuplicateItem`，而 `SecItemUpdate` 需要
    /// 另外一套 `attributesToUpdate` 字典 —— 两条路径都要写，代码更长、错的机会更多。
    /// 删除 + 新增是幂等的，重复登录 100 次也不会留下 100 份副本。
    @discardableResult
    static func save(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // 仅本机 + 首次解锁后可读：App 只在前台用，不需要更宽松的授权；
            // 不跟 iCloud 钥匙串同步 —— 这份凭证是"这台设备上的这个站点"，不该漫游。
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// 读凭证。没有 / 读失败一律返回 nil（凭证读取失败等同于未登录，不做修复尝试）
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

    /// 删凭证（登出 / 会话失效都走这里）
    @discardableResult
    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound 也算成功：本来就没有，目标状态已经达成
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - 登录错误

/// 登录失败的四类原因。
///
/// 为什么单独一个枚举而不是直接用 `APIError`：登录失败的三件事**用户能做的动作完全不同** ——
/// 「密码错了」= 重输一次；「后台没配密码」= 去 Cloudflare 后台配，App 里怎么试都没用；
/// 「网络断了」= 等会儿再来。折成一句"登录失败"等于让用户瞎试。
enum SurveyAuthError: Error, Equatable {
    /// 401：密码不对
    case wrongPassword
    /// 503：服务端没配 `ADMIN_PASSWORD`（管理功能整体锁定）
    case notConfigured
    /// 传输入错（离线 / 超时）
    case network
    /// 其他：带上服务端原话（可能是 429 / 500）
    case server(String)

    /// 可直接上屏的一句现象 + 一句出路
    var userMessage: String {
        switch self {
        case .wrongPassword:
            return "密码不对，再试一次。"
        case .notConfigured:
            return "后台还没设置管理密码，App 里登录不了。先去网页端把 ADMIN_PASSWORD 配好。"
        case .network:
            return "网络好像断了一下，等会儿再登录。"
        case .server(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "登录没成功，稍后再试。" : trimmed
        }
    }
}

// MARK: - 鉴权

/// 问卷站管理凭证的唯一持有者。
///
/// 三条硬规则：
/// 1. **凭证只在 Keychain**，内存里留一份只为了解决"每次请求都读 Keychain 太慢"；
/// 2. **凭证只从 `Set-Cookie` 响应头拿** —— `/api/auth/login` 的 JSON 里只有 `{"ok":true}`，
///    没有 token（这一点已在真实响应上核实过，不要试图从 body 里找）；
/// 3. **任何受保护接口回 401 就立刻清凭证**（`invalidate()`），由页面回到登录引导页 ——
///    绝不让 App 揣着一张过期 Cookie 反复打 401。
///
/// 为什么是单例而不是 `@EnvironmentObject`：设置页的「问卷管理」分组会从两处弹出
/// （概览右上齿轮 / 更多 → 设置），模态呈现不保证继承环境对象；单例 + `@ObservedObject`
/// 能彻底绕开这条依赖（`AppearanceSection` 已用同一套办法解决过同一个问题）。
///
/// 为什么标 `final class` 但**不标** `@MainActor`：它被 View 的默认值直接初始化
/// （`@ObservedObject private var auth = SurveyAuth.shared`），而 View 的属性初始化器是
/// 非隔离上下文 —— 标了 `@MainActor` 在 Swift 5 的 minimal 检查下会报"actor-isolated
/// 属性不能在非隔离上下文引用"。所有调用点都在主线程（View 的 task / 按钮回调），
/// 行为上等价。
final class SurveyAuth: ObservableObject {

    /// 全 App 唯一实例
    static let shared = SurveyAuth()

    /// 是否持有凭证（**不等于凭证有效**：30 天内服务端可能改了密码，所以进工作台前还会 `verify()`）
    @Published private(set) var isLoggedIn: Bool

    /// 登录请求在飞（按钮转圈 + 防重复提交）
    @Published private(set) var isBusy: Bool = false

    private let client: APIClient

    /// 内存里的凭证值（不含 `qw_auth=` 前缀）
    private var token: String?

    init(client: APIClient = .shared) {
        self.client = client
        let stored = SurveyKeychain.read()
        self.token = stored
        self.isLoggedIn = (stored != nil)
    }

    /// 请求时手写 `Cookie` 头用的字符串；未登录返回 nil
    var cookieHeader: String? {
        guard let token = token, !token.isEmpty else { return nil }
        return "qw_auth=" + token
    }

    // MARK: - 登录

    /// 用管理密码换 Cookie。
    ///
    /// 成功 = 从 `Set-Cookie` 里抠出 `qw_auth` 并存进 Keychain。
    /// 失败按状态码分流（401 密码错 / 503 未配置 / 其他带服务端原话）。
    ///
    /// - Parameter password: 用户输入的明文密码（只在内存里存在这一瞬间，不落盘、不日志）
    func login(password: String) async throws {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SurveyAuthError.wrongPassword }
        guard let url = API.authLogin() else {
            let reason = "地址拼错了。"
            throw SurveyAuthError.server(reason)
        }

        isBusy = true
        defer { isBusy = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        // no-store 端点：不读取任何本地缓存
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let payload: [String: Any] = ["password": trimmed]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let raw: APIRawResponse
        do {
            raw = try await client.send(request)
        } catch let error as APIError {
            if case .cancelled = error { throw error }
            throw SurveyAuthError.network
        } catch {
            throw SurveyAuthError.network
        }

        switch raw.statusCode {
        case 200:
            guard let setCookie = raw.header("Set-Cookie"),
                  let value = SurveyAuth.cookieValue(fromSetCookie: setCookie) else {
                // 200 但没给 Cookie：服务端行为变了，明确告知而不是假装成功
                let reason = "登录成功了但没拿到凭证，请再试一次。"
                throw SurveyAuthError.server(reason)
            }
            SurveyKeychain.save(value)
            token = value
            isLoggedIn = true
        case 401:
            throw SurveyAuthError.wrongPassword
        case 503:
            throw SurveyAuthError.notConfigured
        default:
            throw SurveyAuthError.server(APIErrorEnvelope.anyMessage(from: raw.data))
        }
    }

    // MARK: - 校验

    /// 校验现有凭证是否还活着（进问卷工作台前调一次）。
    ///
    /// 返回 true 表示"可以继续"：
    /// · 明确 `authed: false` / 401 → 清凭证 + 返回 false；
    /// · **网络失败 → 返回原状态**（不能因为地铁里没信号就把用户踢出去，
    ///   那会让"离线打开 App"变成"每次都要重新输密码"）。
    @discardableResult
    func verify() async -> Bool {
        guard isLoggedIn else { return false }
        guard let url = API.authStatus(), let cookie = cookieHeader else {
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
                  let status = try? APIJSON.decoder.decode(SessionStatus.self, from: raw.data) else {
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

    /// 清凭证。
    ///
    /// 顺序固定为「尽力通知服务端 → 本机必清」：
    /// 服务端 Cookie 是无状态 HMAC，本地删掉就等于失效，所以通知失败也不影响结果。
    ///
    /// **同时删掉所有 `survey.*` 快照**（设计文档 R20）：退出登录后如果还能看到
    /// 上一个账号的问卷列表 / 答卷明细，那是数据泄露级别的问题。
    /// 把"删凭证"和"删快照"放在同一个函数里，是为了将来没有人能只做一半。
    func logout() async {
        if let url = API.authLogout(), let cookie = cookieHeader {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10
            _ = try? await client.send(request)
        }
        invalidate()
        await SnapshotCache.shared.removeAll(withPrefix: SurveyStore.snapshotPrefix)
    }

    /// 只清本机状态（401 / 会话失效时用，不发网络请求 —— 已经 401 了再请求一次没有意义）
    func invalidate() {
        SurveyKeychain.delete()
        token = nil
        isLoggedIn = false
    }

    // MARK: - 工具

    /// 从 `Set-Cookie` 里抠出 `qw_auth` 的值。
    ///
    /// 两种写法都要能吃：
    /// · `qw_auth=abc.def.123; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000`
    /// · 多条 Cookie 被网关用逗号拼起来：`other=1, qw_auth=abc.def.123; Path=/…`
    /// 所以先按 `;` 和 `,` 全部切开，再找带 `qw_auth=` 的那一段。
    static func cookieValue(fromSetCookie header: String) -> String? {
        let pieces = header.components(separatedBy: CharacterSet(charactersIn: ";,"))
        for piece in pieces {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let range = trimmed.range(of: "qw_auth=") else { continue }
            let raw = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { continue }
            // 服务端写 Cookie 时做过 encodeURIComponent，读回来解一次（token 里只有 . 与十六进制，通常原样）
            return raw.removingPercentEncoding ?? raw
        }
        return nil
    }

    /// `/api/auth/status` 的响应（这个端点没有 `ok` 字段，只有这几个布尔）
    private struct SessionStatus: Decodable {
        var authed: Bool?
        var passwordSet: Bool?
    }
}
