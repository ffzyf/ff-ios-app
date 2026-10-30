import SwiftUI

/// 外观三态（PRD §3.6 / 设计文档 §1.1.5）。
///
/// 存 `String` 原始值而不是 `Int`：以后加选项（比如"仅夜间自动"）不会因为顺序变化导致老用户
/// 的存值错位。`@AppStorage` / `UserDefaults` 里存的就是这里的 `rawValue`。
enum AppearanceMode: String, CaseIterable, Identifiable {
    /// 跟随系统（默认值：没设置过的人都走这一档）
    case system
    /// 始终浅色
    case light
    /// 始终深色
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "始终浅色"
        case .dark: return "始终深色"
        }
    }

    /// 一句话解释，写在设置项副标题里（三档的差别不解释用户会反复试）
    var detail: String {
        switch self {
        case .system: return "白天浅色、夜里深色，跟 iOS 的自动切换走"
        case .light: return "一直用浅色，不看系统设置"
        case .dark: return "一直用深空黑，就是之前的样子"
        }
    }

    /// 交给 `preferredColorScheme` 的值。
    ///
    /// `nil` 就是"跟随系统" —— `ColorScheme` 没有 `.system` 这个 case，
    /// 所以这个属性必须是可选类型，写成非可选编译不过。
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
