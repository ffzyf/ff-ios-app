import SwiftUI

/// 外观偏好的唯一状态源（PRD §3.6：跟随系统 / 始终浅色 / 始终深色）。
///
/// 为什么是 `ObservableObject` 单例而不是在 View 里直接写 `@AppStorage`：
/// 1. `@AppStorage` 是 `DynamicProperty`，只有装进 `View` 才会随值变化刷新 ——
///    塞进 `ObservableObject` 里也不会发 `objectWillChange`。而外观要"立即整屏生效"，
///    必须让 App 级视图重新求值 `preferredColorScheme`；
/// 2. 需要**跨文件、跨层级**同时被两处读：`FFWangApp`（决定窗口外观）与设置页（决定选中态）。
///    单例 + `@StateObject` / `@ObservedObject` 是最省代码且不会出现"两份状态不同步"的写法。
///
/// 落盘仍然是 `UserDefaults`（键名 `appearance`，存 `AppearanceMode.rawValue`），
/// 与 `@AppStorage("appearance")` 完全等价 —— 换成 `@AppStorage` 只是少写两行，
/// 代价是外观开关点了不生效，不能接受。
final class AppearanceStore: ObservableObject {

    /// 全 App 唯一实例
    static let shared = AppearanceStore()

    /// `@AppStorage` 用的同一个键名。改这里等于让所有老用户回到"跟随系统"，不要随手改。
    static let storageKey = "appearance"

    /// 真正参与 `objectWillChange` 的存储（对外只暴露 `mode`）
    @Published private var stored: AppearanceMode

    private let defaults: UserDefaults

    /// 当前外观三态
    var mode: AppearanceMode {
        get { stored }
        set {
            // 同值赋值不发通知：设置页点同一项时会连带触发一次整窗重解析，白费
            guard newValue != stored else { return }
            stored = newValue
            defaults.set(newValue.rawValue, forKey: Self.storageKey)
        }
    }

    /// 直接喂给 `preferredColorScheme`。`nil` = 跟随系统。
    var scheme: ColorScheme? {
        return stored.scheme
    }

    /// 默认 `UserDefaults.standard`；测试或预览可注入独立 suite
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.storageKey) ?? AppearanceMode.system.rawValue
        // 存值损坏（手改 plist / 老版本枚举名变了）→ 回落到"跟随系统"，绝不让 App 起不来
        self.stored = AppearanceMode(rawValue: raw) ?? .system
    }
}
