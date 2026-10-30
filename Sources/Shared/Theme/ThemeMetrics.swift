import SwiftUI

/// 随外观变化的**数值** token。
///
/// 为什么 `Color` 能自动跟随 trait 而 `CGFloat` 不能：动态 `UIColor` 的 provider 每次解析都会重跑，
/// 但一个 `CGFloat` 存下来就是死值。所以工程里只挑「必须变、且变了肉眼能看出来」的两个数值走环境注入：
/// 页面光斑的半径与不透明度。其余的（阴影半径、描边宽度）按设计文档 §1.1.4 的取舍**几何固定**，
/// 差 6pt 肉眼不可辨，而"浅色不发灰"这个真正的观感目标由 `glassShadow` 换成灰蓝 + 双层阴影达成。
///
/// 这两个值的来源是 PRD §3.3：`glowRadius / glowOpacity` 深 220 / 0.35，浅 160 / 0.16。
struct ThemeMetrics: Equatable {
    /// 光斑半径基准（PRD §3.3）
    var glowRadius: CGFloat
    /// 光斑强度基准（PRD §3.3）
    var glowOpacity: Double

    static let dark = ThemeMetrics(glowRadius: 220, glowOpacity: 0.35)
    static let light = ThemeMetrics(glowRadius: 160, glowOpacity: 0.16)

    /// `colorScheme` → 数值。只有 `ThemeScope` 会调用它。
    static func resolve(_ scheme: ColorScheme) -> ThemeMetrics {
        return scheme == .light ? .light : .dark
    }
}

private struct ThemeMetricsKey: EnvironmentKey {
    /// 默认值取深色：与 `Theme` 里 `dyn` 的兜底策略保持一致（没拿到外观时按 V2 基线走）
    static let defaultValue: ThemeMetrics = .dark
}

extension EnvironmentValues {
    /// 由 `ThemeScope` 注入的数值 token。
    ///
    /// 刻意**存派生结果而不是原始 `ColorScheme`**：这样下游组件根本拿不到 `colorScheme`，
    /// 也就无法写出 `if colorScheme == .dark`（PRD §3.4 第 2 条）。闸门是"不给入口"，不是"靠自觉"。
    var themeMetrics: ThemeMetrics {
        get { self[ThemeMetricsKey.self] }
        set { self[ThemeMetricsKey.self] = newValue }
    }
}

/// **全工程唯一读取 `colorScheme` 的视图。**
///
/// 必须挂在 `preferredColorScheme(...)` 的子树内部才拿得到"生效后"的外观
/// （`preferredColorScheme` 是窗口级偏好，值一变，整棵树用新的 trait 重新解析）。
///
/// 用法：根视图套一层 `ThemeScope { RootView() }`，之后任何页面都只写
/// `@Environment(\.themeMetrics)`，不需要、也没办法再判深浅。
struct ThemeScope<Content: View>: View {
    /// lint:allow —— 唯一允许判 colorScheme 的位置（PRD §3.4 第 2 条）
    @Environment(\.colorScheme) private var scheme
    private let content: Content

    /// 手写 init 而不是依赖 `@ViewBuilder` 修饰存储属性：后者在跨文件构造时
    /// 偶尔会因为隐式 memberwise init 的可见性被降级而报"无法推断泛型参数"。
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.themeMetrics, ThemeMetrics.resolve(scheme))
    }
}
