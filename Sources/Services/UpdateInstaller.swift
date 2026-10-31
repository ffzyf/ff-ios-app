import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 把 ipa 交到全能签手里的那一步（设计文档 §4.6）。
///
/// ## 为什么只能是 URL Scheme
/// 全能签**没有** HTTP 签名接口，官方只给三个 Scheme：`addsource` / `web` / `bookmark`
/// （本轮只用 `web`）。所以整条链路只能是：
///
/// ```
/// 我们托管未签名 ipa  →  nsk-sign://web?url=<我们域名的 ipa 直链>  →  全能签下载并用用户自己的证书重签
/// ```
///
/// 顺带排掉两个看起来更"正规"但走不通的方案：
/// · `itms-services://` 企业分发 —— 需要企业证书，我们没有，点了只会弹「无法安装」；
/// · 服务端签名后回传下载链接 —— 接口不存在（而且用户证书在用户手机上，服务端根本拿不到）。
///
/// ## 为什么先 `canOpenURL` 而不是直接 `open` 看 completion
/// 两条路都拿得到"有没有 App 接"，但 `canOpenURL` 的好处是：**分支发生在跳出去之前**。
/// 用 `open` 的 completion 判定的话，装了全能签的用户会先被系统跳走一次，
/// 没装的用户则是"跳一下、发现没人接、再跳去 Safari" —— 两段式跳转，中间那一下是纯粹的噪音。
/// 代价是要在 `Info.plist` 的 `LSApplicationQueriesSchemes` 里声明 `nsk-sign`
/// （iOS 9 起，未声明的 scheme `canOpenURL` 恒返回 `false`），这一步见 Resources/Info.plist。
enum UpdateInstaller {

    /// ipa 的绝对直链（站点根 + `ipaPath`）
    static func directURL(ipaPath: String) -> String {
        return Endpoint.briefBase + ipaPath
    }

    /// 安装引导页（静态页，匿名可访问）。
    ///
    /// 唯一的用处就是兜底：设备上没装全能签时，总得给一条能走通的路
    /// （那页讲三件事：没有全能签怎么装、复制 ipa 直链、在「网页打开」里粘贴直链）。
    static func installGuideURL() -> URL? {
        return Endpoint.url(base: Endpoint.briefBase, path: Endpoint.installGuidePath)
    }

    /// 唤起全能签的 URL：`nsk-sign://web?url=<直链>`。
    ///
    /// 用 `URLComponents` 拼而不是手搓字符串再 `addingPercentEncoding`：
    /// query 值里出现 `&` / `#` / `=` 时，手写转义容易漏，漏了就变成"全能签收到的 url 被截断"，
    /// 表现出来是"点了安装，全能签说地址不对"。`URLQueryItem` 会替我们处理值里的保留字符，
    /// 同时保留 `:` `/` 这种在 query 里合法的分隔符。
    static func signURL(ipaPath: String) -> URL? {
        var components = URLComponents()
        components.scheme = "nsk-sign"
        components.host = "web"
        components.queryItems = [URLQueryItem(name: "url", value: directURL(ipaPath: ipaPath))]
        return components.url
    }

    /// 把 ipa 交给全能签；接不住就走 `onFallback`。
    ///
    /// - Parameters:
    ///   - ipaPath: 服务端给的 `ipaPath`
    ///   - onFallback: 没装全能签 / 打不开时的兜底动作。**调用方必须在这里立刻跳安装引导页**，
    ///     不能只置一个状态位等着用户再点一次（见下面的理由）。
    ///
    /// 为什么不在这里直接跳 Safari：本文件只做"判定 + 唤起"，**离开 App 的动作由调用方决定**
    /// （要不要先弹一句说明、跳之前要不要记埋点，都是 UI 层的事，写进来会让这个工具层
    /// 没法被别的入口复用）。
    ///
    /// 但调用方那一边必须立刻跳：**沉默是 bug 的第一嫌疑人**。用户点主按钮，全能签唤起
    /// 失败、屏幕上什么都没发生，他只会读成"这个按钮坏了"，不会猜到"它换了个方案，
    /// 下面多了一行可以点"。一个动作要完成闭环 —— 置状态位只是**给跳出去又回来的用户**
    /// 留一个可点的入口，不能拿它代替第一次跳转。
    @MainActor
    static func install(ipaPath: String, onFallback: @escaping () -> Void) {
        guard let url = signURL(ipaPath: ipaPath) else {
            onFallback()
            return
        }
        // 未声明的 scheme 在这里恒为 false —— 所以 `Info.plist` 那条必须加，
        // 否则所有设备上都会走兜底（"明明装了全能签却提示没装"，且不报错）。
        guard UIApplication.shared.canOpenURL(url) else {
            onFallback()
            return
        }
        UIApplication.shared.open(url, options: [:]) { ok in
            // completion 已在主队列（Apple 文档），但"能不能接住"这件事查过一次也可能
            // 与真正打开时不同（卸载 / 被系统策略拦），所以这里再兜一次底
            if !ok {
                onFallback()
            }
        }
    }

    /// 打开安装引导页
    @MainActor
    static func openInstallGuide() {
        guard let url = installGuideURL() else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
