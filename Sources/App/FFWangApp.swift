import SwiftUI

/// App 入口。
///
/// 采用 SwiftUI 生命周期（`App` + `WindowGroup`），**没有** UIApplicationDelegate / SceneDelegate，
/// 因此 Info.plist 里也不写 `UIApplicationSceneManifest`（写了反而可能让 SwiftUI 找不到 scene）。
///
/// 视觉基线：固定深色（PRD §7 已拍板）。液态玻璃的折射高光只有落在深底上才成立。
@main
struct FFWangApp: App {
    /// 全局唯一的只读数据容器，向下用 environmentObject 注入。
    @StateObject private var model: AppModel

    init() {
        // 协议缓存必须在第一个请求之前配好：靠服务端 ETag 白拿 304，App 侧不手写 If-None-Match。
        ImageCache.configure()
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .environmentObject(model)
        }
    }
}
