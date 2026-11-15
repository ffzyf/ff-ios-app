import Foundation

// MARK: - 小组件深链（App / Widget 双 target 共用）

/// 小组件深链的唯一出处（5.1.2 从 `WidgetProvider.swift` 下沉到 `Sources/Shared`）。
///
/// 为什么必须放 Shared：5.1.2 起 `*Face` 渲染层通过 `project.yml` 的独立 `path:` 条目
/// 同时被主 App target 编译（R5 调试面板要「App 进程内复用渲染层」），而各 Face 都写了
/// `.widgetURL(WidgetDeepLink.sky)`。若本类型只留在 `WidgetProvider.swift`（该文件
/// 不进主 App target），主 App 会报 `cannot find 'WidgetDeepLink' in scope`。
/// 下沉到 Shared 后 App / Widget 两个 target 引用同一份，天然不再需要第二套字面量。
///
/// scheme / host 仍是**跨 target 的契约**：这头是 `Info.plist` 的 `CFBundleURLTypes`
/// + 小组件的 `.widgetURL(...)`，那头是 `RootView.onOpenURL`。三处各写一份字符串、
/// 改一处忘两处就会出现「点了没反应」这种最难查的 bug，所以 Widget 侧只从这里取 URL。
///
/// 注：`RootView.swift` 里的 `AppDeepLink` 仍保留一份只含 scheme + host 映射的同构实现
/// （App 侧那份不依赖 WidgetKit），两边靠注释互相指认，逐字一致。
enum WidgetDeepLink {

    /// URL scheme，必须与 `Resources/Info.plist` 的 `CFBundleURLSchemes` 逐字一致
    static let scheme = "skyapp"

    /// 简报小组件 → 简报 Tab
    static let briefHost = "brief"
    /// 红石小组件 → 红石 Tab
    static let rockHost = "rock"
    /// 沉浸式天光页（3.11.0）。**不是 Tab** —— App 侧会全屏呈现 `SkyRoomView`。
    ///
    /// 为什么把天光 / 日弧 / 月相 / 风 四张卡一起改成它：这四张卡画的都是「此刻的天」
    /// （同一片天空、同一颗太阳、同一轮月亮、同一阵风），点开就该进那个更大的同一片天；
    /// 而 `brief` 是「今天有什么事」，与看天是两件事。
    /// App 侧同一份契约在 `RootView.swift` 的 `AppDeepLink.skyHost`，两边必须逐字一致。
    static let skyHost = "sky"

    /// 拼一个合法的深链；拼不出来返回 nil（`.widgetURL` 接受 nil，等于「这张卡不可点」）
    static func url(host: String) -> URL? {
        return URL(string: scheme + "://" + host)
    }

    /// 简报小组件整卡点击目标
    static let brief = url(host: briefHost)
    /// 红石小组件整卡点击目标
    static let rock = url(host: rockHost)
    /// 天光页（天光 / 日弧 / 月相 / 风 四张卡共用）
    static let sky = url(host: skyHost)
}
