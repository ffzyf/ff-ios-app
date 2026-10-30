import SwiftUI

/// 行内 Markdown（`**粗体**` / `*斜体*` / `` `行内代码` `` / `[链接](url)`）。
///
/// 设计文档 §4.4 的决定：**服务端原样保留行内标记，App 交给 `AttributedString(markdown:)`**，
/// 不自己写 span 解析器 —— 本工程的行内需求只有四种标记，系统解析器原生支持。
///
/// 两条降级红线：
/// 1. 解析失败必须回落成纯文本（`AttributedString(text)`），绝不允许空白或丢字；
/// 2. 只用 `inlineOnlyPreservingWhitespace`：块级语法（`#` / `-`）不该在这里被吃成标题或列表，
///    块的分发已经由服务端做完了。
enum InlineMarkdown {

    /// 解析成富文本：链接染青柠 + 下划线，行内代码换等宽字体 + 青柠 12% 底。
    ///
    /// - Parameter text: 服务端原样下发的段落 / 标题 / 引用 / 列表项文本。
    /// - Returns: 可直接交给 `Text(_:)` 的富文本；解析失败时是原文。
    static func attributed(_ text: String) -> AttributedString {
        var result: AttributedString
        if let parsed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            result = parsed
        } else {
            return AttributedString(text)
        }

        // 先把要改的 run 收集出来再改：边遍历 `result.runs` 边写 `result[...]`
        // 会踩到值语义的独占访问（运行时 trap），这行 map 就是为了避开它。
        let targets = result.runs.map { run in
            (range: run.range,
             isLink: run.link != nil,
             isCode: run.inlinePresentationIntent?.contains(.code) == true)
        }
        for target in targets {
            if target.isLink {
                result[target.range].foregroundColor = Theme.lime
                // 显式构造 `Text.LineStyle`：不依赖 `.single` 这类简写成员能否推断出
                // `AttributedString` 的 `underlineStyle` 值类型。
                result[target.range].underlineStyle = Text.LineStyle(pattern: .solid)
            }
            if target.isCode {
                result[target.range].font = Typography.code
                result[target.range].backgroundColor = Theme.lime.opacity(0.12)
            }
        }
        return result
    }

    /// 用于判断「这段文字去掉空白后是否还有内容」：空段落整块不渲染，不留空行
    static func isBlank(_ text: String) -> Bool {
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
