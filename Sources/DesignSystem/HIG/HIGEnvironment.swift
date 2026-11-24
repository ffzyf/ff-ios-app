import SwiftUI

/// 沉浸 chrome 策略（HIG 迭代 · L2 环境契约）。
///
/// 只有两个值：普通页面 `.automatic`，全屏沉浸页 `.immersive`。
/// 环境值由 `HIGChromeScope` 在 App 根注入**基准值**（恒 `.automatic`），
/// 作为表现层公开契约与未来扩展点保留。沉浸页的实际策略由 `immersiveChrome()`
/// 显式传给 `ImmersiveGestureModifier`（环境向下传递，modifier 不能可靠读到子树注入），
/// 因此业务代码一律只读、不写这个环境值。
enum HIGChromePolicy: Equatable {
    /// 系统默认：不 defer 底部手势、不隐藏浮层（绝大多数页面）
    case automatic
    /// 全屏沉浸：允许 defer 底部手势 + 自动隐藏浮层（仍受设备档与 scenePhase 约束）
    case immersive
}

/// `EnvironmentValues.higChrome` 的键。默认值 `.automatic` 保证漏注入时零行为变化。
struct HIGChromeKey: EnvironmentKey {
    static let defaultValue: HIGChromePolicy = .automatic
}

extension EnvironmentValues {
    /// 当前视图子树的沉浸 chrome 策略。只读为主，写入仅发生在 `HIGChromeScope` 与 `immersiveChrome()`。
    var higChrome: HIGChromePolicy {
        get { self[HIGChromeKey.self] }
        set { self[HIGChromeKey.self] = newValue }
    }
}

/// 全局挂载层：在 `FFWangApp.WindowGroup` 的最外层包裹一次。
///
/// 职责只有两件：
/// 1. 注入 `higChrome` 的**基准值** `.automatic`（普通页面因此永远拿默认行为）；
/// 2. 监听 `scenePhase`，任何变化都把基准值复位 —— 杜绝"回前台后指示器仍被隐藏"的悬挂态。
///
/// 它不持有 Store、不订阅网络、不参与导航，也不改任何 `.task(id: scenePhase)`：
/// 原来的 task 全部留在这层 Scope 的 content 内部，逐字不变。
struct HIGChromeScope<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    /// 基准策略。恒为 `.automatic`；保留状态与复位逻辑是为了让"根层唯一写入口"显式可见，
    /// 也为将来需要全局策略时留一处收敛点（沉浸页的策略由 modifier 显式持有，互不影响）。
    @State private var policy: HIGChromePolicy = .automatic
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.higChrome, policy)
            .onChange(of: scenePhase) { _, _ in
                // 切后台 / 回前台一律复位基准策略；沉浸页自己的一次性授权由
                // ImmersiveGestureModifier 独立处理，两层复位互不覆盖。
                policy = .automatic
            }
    }
}
