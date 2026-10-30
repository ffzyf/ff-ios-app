import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Color(hex:)

extension Color {
    /// 十六进制颜色。
    ///
    /// 支持 `"6BDB5C"` / `"#6BDB5C"`（6 位 = RRGGBB，不透明）与
    /// `"6BDB5CFF"` / `"#6BDB5CFF"`（8 位 = RRGGBBAA）。
    /// 非法输入（长度不对、含非十六进制字符）一律回退为黑色，**绝不 crash**——
    /// 颜色是设计 token，写错了应该在评审里被看出来，而不是让 App 崩在启动路径上。
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed

        let isValidLength = (body.count == 6 || body.count == 8)
        let digits = isValidLength ? body : "000000"
        let value = UInt64(digits, radix: 16) ?? 0

        if digits.count == 8 {
            let red = Double((value >> 24) & 0xFF) / 255.0
            let green = Double((value >> 16) & 0xFF) / 255.0
            let blue = Double((value >> 8) & 0xFF) / 255.0
            let alpha = Double(value & 0xFF) / 255.0
            self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
        } else {
            let red = Double((value >> 16) & 0xFF) / 255.0
            let green = Double((value >> 8) & 0xFF) / 255.0
            let blue = Double(value & 0xFF) / 255.0
            self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
        }
    }
}

// MARK: - View.conditional

extension View {
    /// 条件修饰符：避免为了一个 `if` 把整段视图擦成 `AnyView`（AnyView 会打断 diff）。
    @ViewBuilder
    func conditional<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - 触觉

/// 触觉反馈封装。PRD §4.6：卡片按压 .light、刷新完成 / 复制 .success、错误 .error。
/// 全部走系统生成器，不申请任何权限。
enum Haptics {
    /// 轻触（卡片按压、Tab 切换）。
    static func light() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    /// 成功（刷新完成、复制完成）。
    static func success() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    /// 选择（翻月、切换分段控件）。PRD §4 #7 单独一层：翻月是"在同一页里移动"，比 Tab 切换更轻
    static func selection() {
        #if canImport(UIKit)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }

    /// 失败（刷新失败、请求报错）。
    static func error() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        #endif
    }
}
