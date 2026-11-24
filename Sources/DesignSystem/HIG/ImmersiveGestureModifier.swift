import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 沉浸式 Home Indicator 策略（HIG 迭代 · L4 单行叠加）。
///
/// 用户拍板语义：**只在全屏沉浸页自动隐藏，退出即恢复，绝不全局永久隐藏**。
/// 因此本 modifier 同时满足三条约束：
/// 1. 只对 `.immersive` 策略生效（由 `immersiveChrome()` 显式传入；普通页面根本不挂本 modifier）；
/// 2. 只在**真正的 iPhone 设备**上 defer 底部手势 —— 判据是 `userInterfaceIdiom == .phone`，
///    不是 `horizontalSizeClass`：iPad 在 Slide Over / 1⁄3 分屏、Stage Manager 窄窗口里
///    同样会得到 `.compact`，按尺寸类判断会误抢 iPad 的多任务手势；
/// 3. `scenePhase` 一变就关掉沉浸授权，直到用户退出再进入（视图实例重建）才重新启用 ——
///    回前台后绝不留一个"指示器一直消失"的悬挂态。
///
/// 为什么策略用**构造参数**而不是 `@Environment(\.higChrome)`：SwiftUI 的环境向下传递，
/// `.environment()` 写在 modifier 之前时，modifier 自身（位于 content 的父层）向上查找
/// 读不到子树里的注入 —— 那会让 defer 永远不生效。显式传参不受视图树方向影响，
/// 也与类图里的 `policy` 属性一致。`higChrome` 环境仍由 `HIGChromeScope` 注入，
/// 作为表现层公开契约保留，不参与这里的判断。
///
/// 实现上刻意保持 **modifier 链形状恒定**：不写 `if` 分支包住 content，而是用
/// 空的 `Edge.Set` 与 `.automatic` 表达"不启用"。这样 content 的视图身份、`@State`
/// （滚动位置等）在策略复位时一个都不丢 —— 这是"叠加不改业务"的关键。
struct ImmersiveGestureModifier: ViewModifier {
    /// 由 `immersiveChrome()` 传入，恒 `.immersive`。
    let policy: HIGChromePolicy
    @Environment(\.scenePhase) private var scenePhase

    /// 一次性授权：scenePhase 变化即置 false，视图重建（退出再进）才回到 true。
    @State private var immersiveAllowed: Bool = true

    /// 真正的设备判定：用 idiom 而不是尺寸类。`UIDevice.current.userInterfaceIdiom`
    /// 是 iOS 2 起的 API，**不需要** `#available`；iPhone 上恒 `.phone`，行为与上一版一致。
    /// iPad 无论全屏还是分屏（尺寸类可能是 `.compact`）都返回 `.pad` → 一律不 defer。
    private var isIPhoneDevice: Bool {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        // 非 UIKit 平台保守不 defer，绝不抢系统手势
        return false
        #endif
    }

    /// 两个系统 API 都是 iOS 16+，部署目标 iOS 18 —— 不需要 `#available` 分流。
    private var shouldImmerse: Bool {
        return policy == .immersive && immersiveAllowed && isIPhoneDevice
    }

    func body(content: Content) -> some View {
        content
            // 空 Edge.Set = 不 defer 任何边；恒定链保证切换时不重建 content 子树。
            .defersSystemGestures(on: shouldImmerse ? Edge.Set.bottom : Edge.Set())
            // HIG：这是偏好而非强制（用户触摸即恢复），UI 不能依赖指示器真的消失。
            .persistentSystemOverlays(shouldImmerse ? Visibility.hidden : Visibility.automatic)
            .onChange(of: scenePhase) { _, _ in
                immersiveAllowed = false
            }
    }
}

extension View {
    /// 把当前视图声明为"全屏沉浸页"：挂上 defer / auto-hide 的可选行为。
    ///
    /// 用法只有一行，且必须挂在**链尾**（不进入内部子树）：
    /// `SkyRoomView(...).immersiveChrome()` / `ImageViewer(...).immersiveChrome()`。
    /// 不改 body 结构、不改 `@State`、不改 action、不改任何导航绑定。
    func immersiveChrome() -> some View {
        modifier(ImmersiveGestureModifier(policy: .immersive))
    }
}
