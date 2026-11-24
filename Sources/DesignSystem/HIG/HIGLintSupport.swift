import Foundation

/// HIG 迭代的静态契约常量（纯文档，不参与运行时逻辑）。
///
/// `scripts/lint-hig.sh` 与代码注释都引用这里的名字：玻璃唯一入口、图标 API 形态、
/// 最小触控边长为三条闸门提供"代码里可查的真相源"。数值与 `Spacing.tapMinSide`
/// 同源（44）；这里用 `Int` 是为了让 shell 脚本无需 import SwiftUI 就能比对。
enum HIGContract {
    /// 全工程唯一的真玻璃入口名（`View.glassSurface`）
    static let glassEntrypoint = "glassSurface"
    /// 允许出现裸玻璃 API 的文件（与 README §四 的白名单逐字一致）
    static let glassAllowedFiles = [
        "GlassCompat.swift",
        "GlassGroup.swift",
        "GlassButtonStyles.swift"
    ]
    /// 系统图标的唯一构造形态：SF Symbols
    static let symbolAPIPrefix = "Image(systemName:)"
    /// HIG 最小触控边长（与 `Spacing.tapMinSide` 同源）
    static let minTapSide: Int = 44
    /// 触控叠加 modifier 名
    static let tapTargetModifier = "tapTarget"
    /// 语义色命名空间
    static let semanticColorNamespace = "Theme.Semantic"
}
