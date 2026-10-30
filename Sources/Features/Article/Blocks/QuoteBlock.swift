import SwiftUI

/// 引用块（PRD §3.3）。
///
/// **刻意不用斜体**：中文字体的斜体是算法伪斜，观感廉价且不利长文阅读。
/// 区分层次靠三重非字体手段：左侧 3pt 青柠竖线 + 青柠 6% 底 + 稍弱的文字色（`textSecondary`）。
struct QuoteBlock: View {
    let text: String

    var body: some View {
        if !InlineMarkdown.isBlank(text) {
            HStack(alignment: .top, spacing: 12) {
                Capsule()
                    .fill(Theme.lime)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                Text(InlineMarkdown.attributed(text))
                    .font(Typography.bodySmall)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 16, multiple: 1.8))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                    .fill(Theme.lime.opacity(0.06))
            }
        }
    }
}
