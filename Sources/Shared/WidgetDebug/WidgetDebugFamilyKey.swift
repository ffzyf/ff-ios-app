import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - 预览用尺寸档环境值（5.1.2 · R5，架构 §8-4 的退路）

/// 调试面板专用的「尺寸档」环境值。
///
/// ## 为什么不能直接用 `\.widgetFamily`
/// 系统的 `EnvironmentValues.widgetFamily` 是**只读** `KeyPath`（WidgetKit 自己写入，
/// 主 App 进程里没有谁去改它），而 `.environment(...)` 要求 `WritableKeyPath` ——
/// 直接写 `.environment(\.widgetFamily, family)` 编译报
/// `cannot convert 'KeyPath<EnvironmentValues, WidgetFamily>' to 'WritableKeyPath<...>'`。
///
/// 架构 §8-4 给的退路就是这里：**自定义一个可写环境值**，调试面板注入它，
/// 各 `*Face` 读取时用 `debugFamily ?? family`（见各文件的 `effectiveFamily`）。
/// 只改「档位从哪里来」，**不改任何视觉 / 布局 / 断点**：
/// 桌面上这个值恒为 `nil`，Face 读到的仍然是系统给的 `\.widgetFamily`。
///
/// 为什么放在 `Sources/Shared`：主 App（调试面板 + Face）与 Widget（Face）都要编译到它，
/// Shared 是两个 target 的共同源目录，不需要改 `project.yml`。

/// `nil` = 没有预览注入 —— 各处都应回落到系统 `\.widgetFamily`。
struct WidgetDebugFamilyKey: EnvironmentKey {
    static let defaultValue: WidgetFamily? = nil
}

extension EnvironmentValues {
    /// 调试面板注入的尺寸档。桌面上永远是 `nil`（没有人写它）。
    var widgetDebugFamily: WidgetFamily? {
        get { self[WidgetDebugFamilyKey.self] }
        set { self[WidgetDebugFamilyKey.self] = newValue }
    }
}
