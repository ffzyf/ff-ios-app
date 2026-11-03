import Foundation
import Security

/// AI 通行证（`x-ai-token`）的 Keychain 存取。
///
/// 写作方式照抄 `EarningsKeychain`（`import Security` + `SecItemAdd/CopyMatching/Delete`
/// + `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`），只换了 `service` / `account`。
///
/// 为什么不和收益站 / 问卷站共用一把钥匙：三套凭证的生命周期完全不同 ——
/// 收益 Cookie 会过期、要用户登录；AI token 是本机常驻的窄权限凭证。混在一个 service 里，
/// 用户登出收益站就会把 AI 也一起清掉（或者反过来），而那种 bug 只会在真机上偶发。
///
/// ## ⚠️ 这不是安全边界（必须写清楚，不许自欺）
///
/// 首次访问 Keychain 为空时，本文件会写入编译进 App 的常量 `builtInToken`，
/// 让 App 开箱即用。**但客户端里的任何字符串都能被提取** —— 解包 ipa、反编译、
/// 或者干脆在越狱设备上 hook `SecItemCopyMatching`，几十秒的事。
/// 把它当成"密钥"来讨论是没有意义的：它不是防线，只是一张记在客户端上的门牌号。
///
/// 真正的防线有三条，都在服务端：
/// 1. **每日配额**（`ai:quota:<yyyyMMdd>`，超 200 条 → 429）：被拿走也只能烧掉一天的额度；
/// 2. **token 可轮换**：改一行 `AI_TOKEN` 环境变量，旧 token 当场作废；
/// 3. **绝不进 URL / 日志**：只放在 `x-ai-token` 请求头里（`API.aiRequest` 唯一一处写它），
///    否则 Cloudflare 的访问日志里就躺着明文 token。
///
/// 上线后应该做的事：**改成服务端下发 / 轮换**（启动时用设备既有的弱标识换一张短效票），
/// 那时 `builtInToken` 这个常量应当整段删掉，`token()` 的"读不到就播种"也一并删掉 ——
/// 拿不到票就是拿不到，而不是回落到一个全世界都知道的值。
enum AIKeychain {

    /// 服务名（独立命名空间，避免与 `top.skyzyf.skyapp.ce` / `top.skyzyf.skyapp.survey` 串号）
    static let service = "top.skyzyf.skyapp.ai"

    /// 账号名（就是请求头名，与后端 `ai-auth.js` 一致）
    static let account = "x-ai-token"

    /// 内置的初始 token（**不是秘密**，理由见类型注释）。
    ///
    /// 只在 Keychain 为空时写一次 —— 写进去之后，后续读的都是 Keychain 里那份，
    /// 所以服务端轮换 token 后，App 侧只需 `save(_:)` 一个新值就能立刻生效，
    /// 不需要发版（发版是最后的办法，不是第一选择）。
    private static let builtInToken = "ffai_9c41d7a2b6e83f05a1c74d9e2b60f8c3"

    /// 取 token（**唯一入口**，调用方不需要关心"有没有播种"这件事）。
    ///
    /// Keychain 为空时写入 `builtInToken` 并返回它，于是首次安装就是可用的。
    /// 写入失败（极少：设备锁死 / 钥匙串损坏）也照样返回 token —— 这一次请求能成，
    /// 下一次再试播种。HTTP 请求路径上不该因为"存不进去"而失败。
    ///
    /// 不做内存缓存：Keychain 读一次是微秒级，而静态可变缓存在 Swift 5 并发检查下
    /// 需要一把锁或一个 actor 才说得清 —— 为一个微秒级调用引入这些不值得。
    static func token() -> String {
        if let stored = read() {
            return stored
        }
        save(builtInToken)
        return builtInToken
    }

    /// 读 token。没有 / 读失败一律返回 nil（读不到等同于"还没播种"，不做修复尝试）
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

    /// 写 token。先删后加（幂等，重复写不会留多份副本）
    @discardableResult
    static func save(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // 只在本机可用、不进 iCloud 钥匙串漫游、不进 iTunes 明文备份
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// 删 token（服务端轮换后要清掉旧的；一般不需要手工调）
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

    /// 轮换 token（服务端换 `AI_TOKEN` 之后，App 侧调一次即可，不用发版）。
    ///
    /// 与 `save(_:)` 分开命名，是为了让调用处一眼看出这是"换个新票"而不是"存一下"。
    @discardableResult
    static func rotate(to newToken: String) -> Bool {
        return save(newToken)
    }
}
