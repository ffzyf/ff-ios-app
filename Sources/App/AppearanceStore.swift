import SwiftUI
import UIKit

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

    /// 配色主题的持久化键（与深浅分开存：两者是正交的，一套主题 × 三种深浅都要能组合）
    static let themeStorageKey = "app.theme.id"

    /// 真正参与 `objectWillChange` 的存储（对外只暴露 `mode`）
    @Published private var stored: AppearanceMode

    /// 当前配色主题的 id（`Theme.Palette.id`）。改它会立刻换肤。
    @Published private(set) var themeId: String

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

    /// 当前配色（只读，给设置页画选中态）
    var theme: Theme.Palette {
        return Theme.Palette.with(id: themeId)
    }

    /// 换配色。
    ///
    /// 只做三件事：写 `Theme.active`（全局 token 立刻改读新值）、落盘、发通知让 `RootView`
    /// 换 `.id` 重建子树。**不重建窗口** —— 深浅模式由 `preferredColorScheme` 单独管，
    /// 两者互不干扰，可以「暮紫 + 始终浅色」这样任意组合。
    func selectTheme(_ id: String) {
        guard id != themeId else { return }
        themeId = id
        Theme.active = Theme.Palette.with(id: id)
        defaults.set(id, forKey: Self.themeStorageKey)

        // 桌面图标联动是"附带动作"：换肤已经落盘，图标失败只记日志，绝不影响主题切换。
        // 8 套配色全部走备用图标（包括 lime —— 主图标是单色白 FF，不是彩色青柠），
        // 所以任何主题都不传 nil，行为一致；系统每次会弹确认框，这是用户明确接受的代价。
        let iconName = "icon-\(Theme.Palette.with(id: id).id)"
        // setAlternateIconName 必须主线程；从设置页点选已是主线程，这里再兜一层保险。
        DispatchQueue.main.async {
            // 模拟器 / 不支持备用图标的环境静默降级，不崩、不弹错误。
            guard UIApplication.shared.supportsAlternateIcons else {
                print("[AppearanceStore] alternate icons unsupported; skip icon switch")
                return
            }
            UIApplication.shared.setAlternateIconName(iconName) { error in
                if let error {
                    print("[AppearanceStore] setAlternateIconName(\(iconName)) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 默认 `UserDefaults.standard`；测试或预览可注入独立 suite
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.storageKey) ?? AppearanceMode.system.rawValue
        // 存值损坏（手改 plist / 老版本枚举名变了）→ 回落到"跟随系统"，绝不让 App 起不来
        self.stored = AppearanceMode(rawValue: raw) ?? .system

        // 配色：5.7.0 redesign 后，从未主动选过主题的（含老用户与全新安装）走新默认暮金；
        // 主动选过的照常读回自己的选择 —— 绝不擅自覆盖用户偏好。
        let savedTheme = defaults.string(forKey: Self.themeStorageKey) ?? Theme.Palette.dusk.id
        self.themeId = Theme.Palette.with(id: savedTheme).id
        // 启动即生效：不等设置页被打开，首帧就是用户上次选的那套
        Theme.active = Theme.Palette.with(id: savedTheme)

        // 刻意不在这里调 setAlternateIconName：iOS 会记住用户上次选中的备用图标，
        // 冷启动后桌面图标自动保持。这里再设一次会导致每次启动都弹系统确认框，
        // 体验很差。图标只在用户主动点选主题时（selectTheme）才切换。
    }
}
