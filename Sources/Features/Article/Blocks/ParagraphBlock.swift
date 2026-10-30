import SwiftUI

/// 正文段落（PRD §3.3：17pt / 行高 1.75 / `textBody` / 段间距由块流统一给）。
///
/// 三个细节：
/// 1. **行内格式必须生效**：粗体、行内代码、链接走 `InlineMarkdown`，解析失败回落纯文本；
/// 2. 中文不做首行缩进（移动端缩进会破坏左对齐的视觉基线）；
/// 3. 不用纯白（`textBody` #E6EAF2 比 `textPrimary` 柔和，长文不刺眼）。
struct ParagraphBlock: View {
    let text: String

    var body: some View {
        if !InlineMarkdown.isBlank(text) {
            Text(InlineMarkdown.attributed(text))
                .font(Typography.body)
                .foregroundStyle(Theme.textBody)
                .lineSpacing(lineSpacing)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    /// 行高取 `ReaderScale.standard.lineHeightMultiple`（1.75，PRD §4.2 的正文字号档位约定），
    /// 换算方式统一走 `Typography.lineSpacing`，不在页面里手写常数。
    private var lineSpacing: CGFloat {
        return Typography.lineSpacing(
            fontSize: ReaderScale.standard.pointSize,
            multiple: ReaderScale.standard.lineHeightMultiple
        )
    }
}
