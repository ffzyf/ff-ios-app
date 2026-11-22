import Foundation
import UserNotifications

/// 本地通知的**全局展示代理**（5.6.2 BugFix）。
///
/// ## 修的是什么
/// iOS 的默认行为：App 处于前台（`active`）时，本地通知被系统静默处理 ——
/// 不弹横幅、不响铃、不更新角标，只有退到后台 / 锁屏才进通知中心。所以用户在前台点
/// 「发送测试通知」，`center.add(request)` 明明成功、页面也提示"已发送"，屏幕上却毫无反应。
/// 让前台也展示的标准做法只有一个：设置 `UNUserNotificationCenter.current().delegate`，
/// 并在 `willPresent` 里把 presentation options 交回给系统。
///
/// ## 为什么是单例，而不是 UIApplicationDelegateAdaptor
/// - 本项目是纯 SwiftUI 生命周期（`App` + `WindowGroup`，无 AppDelegate / SceneDelegate，
///   Info.plist 也不写 `UIApplicationSceneManifest`）；引一个 AppDelegate 只为挂代理，
///   多出一个与生命周期耦合的对象，侵入面更大。
/// - 代理是**全局**的：设置一次，设置页测试通知与 `AlertStore` 的天气预警同时生效，
///   两条链路的授权时机 / Bark 兜底顺序一行都不用改。
/// - `UNUserNotificationCenter.delegate` 的持有语义不要依赖系统版本的具体实现；
///   `static let shared` 强持有实例，保证代理对象在任何时候都不会被释放掉。
///
/// ## 并发
/// 系统从**非主线程**回调这两个代理方法，所以这里刻意不标 `@MainActor` —— 方法体只做
/// 一件事：调 completionHandler。若将来要在这里改 UI / 写 `@MainActor` 的 Store，
/// 用 `Task { @MainActor in ... }` 显式 hop，不要把整个类标成 `@MainActor`。
///
/// ## 版本
/// 部署目标 iOS 18.0，`.banner`（iOS 14+）恒可用，无需 `#available` 分支；
/// 也刻意不申请 `.criticalAlert` / `.communication` 之类需要额外 entitlement 的能力。
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {

    /// 全 App 唯一实例（`FFWangApp.init()` 通过 `install()` 挂到系统通知中心）。
    static let shared = NotificationCenterDelegate()

    /// 私有化构造：外部只能通过 `NotificationCenterDelegate.shared` 取用，
    /// 杜绝"创建了一个临时代理、出作用域就被释放"导致代理静默失效的经典坑。
    private override init() {
        super.init()
    }

    /// 把代理挂到系统通知中心。**幂等**：重复调用只是重新赋同一个实例，没有副作用。
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    // MARK: - 前台展示

    /// App 在前台收到通知时决定怎么展示。
    ///
    /// 返回 `[.banner, .sound, .badge]`：横幅 + 声音 + 角标，与后台 / 锁屏的系统表现一致。
    /// 不返回 `.list` / `.alert` —— 前者是"仅通知中心"，`.banner` 已经覆盖用户要的
    /// "眼前有反馈"；后者自 iOS 14 起已废弃。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let options: UNNotificationPresentationOptions = [.banner, .sound, .badge]
        completionHandler(options)
    }

    // MARK: - 点击响应

    /// 用户点了通知的响应。
    ///
    /// 只做一件事：立刻调用 completionHandler，让系统完成收尾（收起横幅、记录打开等）。
    /// **刻意不做路由跳转**：测试通知是纯验证消息；天气预警的 `skyapp://sky?focus=alerts`
    /// 是 Bark 链路自带的可选深链，由 `RootView.onOpenURL` 统一处理。
    /// 在这里再解析一次 `userInfo` / 构造 URL，等于把导航职责拆到两处，既增加时序复杂度，
    /// 也可能和正在进行的 fullScreenCover 转场打架（见 RootView 的深链守卫注释）。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
