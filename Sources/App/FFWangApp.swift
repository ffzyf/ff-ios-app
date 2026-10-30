import SwiftUI

/// App 入口。
///
/// 采用 SwiftUI 生命周期（`App` + `WindowGroup`），**没有** UIApplicationDelegate / SceneDelegate，
/// 因此 Info.plist 里也不写 `UIApplicationSceneManifest`（写了反而可能让 SwiftUI 找不到 scene）。
///
/// 外观（批次 1 改动，PRD §3.4 第 4 条）：
/// V2 这里写死了 `.preferredColorScheme(.dark)`，并且 `Info.plist` 里还有
/// `UIUserInterfaceStyle = Dark` —— 两条一起把整个 App 的 trait 钉在深色上，
/// 设置里的三态开关会"点了没反应且编译器不报错"。现在：
///   · 写死的 `.dark` 换成 `AppearanceStore.shared.scheme`（`ColorScheme?`，nil = 跟随系统）；
///   · `Info.plist` 里那两条 key 已删除（见 Resources/Info.plist）；
///   · 根视图外面套 `ThemeScope`，把"生效后的外观"翻译成数值 token（光斑半径/强度）往下传。
///
/// 为什么 `preferredColorScheme` 挂在根视图而不是每个页面：
/// 它是窗口级偏好，值一变，整棵树用新的 trait **重新解析动态色**（不重建视图树，Tab 选中、
/// 滚动位置、已加载分页全部保留）。绝对不能用 `.id(appearance)` 强制重建 ——
/// 那会把 5 个常驻页面销毁，等于每次切外观都"重启一次 App"。
@main
struct FFWangApp: App {
    /// 全局唯一的只读数据容器，向下用 environmentObject 注入。
    @StateObject private var model: AppModel
    /// 外观三态的唯一状态源。用 `@StateObject` 包住单例，是为了让 App 的 body 订阅它的变化。
    @StateObject private var appearance: AppearanceStore

    init() {
        // 协议缓存必须在第一个请求之前配好：靠服务端 ETag 白拿 304，App 侧不手写 If-None-Match。
        ImageCache.configure()
        _model = StateObject(wrappedValue: AppModel())
        _appearance = StateObject(wrappedValue: AppearanceStore.shared)
    }

    var body: some Scene {
        WindowGroup {
            // ThemeScope 必须在 preferredColorScheme 的子树里才拿得到"生效后"的外观
            ThemeScope {
                RootView()
            }
            .environmentObject(model)
            .preferredColorScheme(appearance.scheme)
        }
    }
}
