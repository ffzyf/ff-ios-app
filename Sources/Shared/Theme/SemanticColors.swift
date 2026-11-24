import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Theme {

    /// 系统语义色出口（HIG 迭代 · L1）。
    ///
    /// 只供**新增元素**使用：背景 / 标签 / 分割线 / 填充 / tint 走 UIKit 语义色，
    /// 深浅模式与高对比度由系统自动解析，不需要在 View 里判 `colorScheme`。
    /// 既有品牌 token（`textPrimary` / `bgBase` / `lime` …）一个都不替换 ——
    /// 它们已与 8 套主题逐项对齐，换成系统色会让新元素与品牌色并排时显脏（设计文档 §5-2b）。
    ///
    /// 全部颜色用 `Color(uiColor:)` 表达，不写 hex，因此不触发 `lint-theme.sh` 规则 1。
    /// Widget target 也编译本文件，非 UIKit 平台回落到 SwiftUI 语义色，绝不 crash。
    enum Semantic {
        /// 页面 / 窗口主背景
        static var background: Color {
            #if canImport(UIKit)
            return Color(uiColor: .systemBackground)
            #else
            // 非 UIKit 平台仅作编译兜底（本工程只有 iOS target，走不到这里）
            return Color.white
            #endif
        }

        /// 次级分组背景（卡片底 / 分组底）
        static var secondaryBackground: Color {
            #if canImport(UIKit)
            return Color(uiColor: .secondarySystemBackground)
            #else
            return Color.primary.opacity(0.06)
            #endif
        }

        /// 主文字（等同系统 label）
        static var label: Color {
            #if canImport(UIKit)
            return Color(uiColor: .label)
            #else
            return Color.primary
            #endif
        }

        /// 次级文字
        static var secondaryLabel: Color {
            #if canImport(UIKit)
            return Color(uiColor: .secondaryLabel)
            #else
            return Color.secondary
            #endif
        }

        /// 三级文字（元信息 / 占位）
        static var tertiaryLabel: Color {
            #if canImport(UIKit)
            return Color(uiColor: .tertiaryLabel)
            #else
            return Color.secondary.opacity(0.7)
            #endif
        }

        /// 细分割线
        static var separator: Color {
            #if canImport(UIKit)
            return Color(uiColor: .separator)
            #else
            return Color.secondary.opacity(0.3)
            #endif
        }

        /// 不透明分割线（压在复杂底色上仍可辨）
        static var opaqueSeparator: Color {
            #if canImport(UIKit)
            return Color(uiColor: .opaqueSeparator)
            #else
            return Color.secondary.opacity(0.5)
            #endif
        }

        /// 系统填充块（无强调语义的控件底）
        static var systemFill: Color {
            #if canImport(UIKit)
            return Color(uiColor: .systemFill)
            #else
            return Color.primary.opacity(0.08)
            #endif
        }

        /// 系统 tint（跟随 AccentColor 与外观）
        static var tint: Color {
            #if canImport(UIKit)
            return Color(uiColor: .tintColor)
            #else
            return Color.accentColor
            #endif
        }
    }
}
