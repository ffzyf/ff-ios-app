import SwiftUI

/// 代码块（PRD §3.3 code 行）。
///
/// 规格逐条落地：
/// · 底 `Theme.codeBg`（#0D1117，比页面更深一档）、圆角 `Radius.smallCard`；
/// · 等宽 13pt（`Typography.code` = SF Mono）+ 行高 1.6；
/// · **横向滚动、绝不折行**（折行会把缩进结构毁掉）—— 靠 `fixedSize(horizontal: true)`；
/// · 左上角语言标签，`lang` 为空时整块不占位；
/// · 不做语法高亮（P1，见 PRD P1-8），不猜配色。
struct CodeBlockBlock: View {
    let lang: String?
    let text: String

    var body: some View {
        if !InlineMarkdown.isBlank(text) {
            VStack(alignment: .leading, spacing: 8) {
                if let label = languageLabel {
                    Text(label)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text)
                        .font(Typography.code)
                        .foregroundStyle(Theme.textBody)
                        .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                        .textSelection(.enabled)
                        // 不折行：宽度按内容自然展开，交给横向 ScrollView 承接
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.top, languageLabel == nil ? 12 : 0)
                        .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                    .fill(Theme.codeBg)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            }
        }
    }

    /// 语言标签：只去掉空白并转小写，不改写内容（`swift` / `js` 原样上屏）
    private var languageLabel: String? {
        guard let lang = lang else { return nil }
        let trimmed = lang.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }
}
