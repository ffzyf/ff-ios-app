import SwiftUI

// MARK: - Color(hex:)

/// 这里只剩两个纯 SwiftUI 的东西：`Color(hex:)`（给 `Theme` 用）与 `View.conditional`。
///
/// 批次 4 把 `Haptics` 搬到了 `DesignSystem/Haptics.swift`：
/// `Shared/` 是 Widget 扩展复用的目录，而触觉生成器属于"宿主 App 才确定安全"的 API，
/// 留在 Shared 里等于让小组件跟着编译一段它根本用不到的 UIKit 代码。
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
