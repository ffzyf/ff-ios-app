import SwiftUI

/// 空态（PRD §5.2）：居中玻璃圆内一枚线框图标 + 两行文案。
///
/// 文案原则：一句现象 + 一句出路，不用「Oops」「哎呀」，不用感叹号。
struct EmptyStateView: View {
    var icon: String = "doc.text"
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.surfaceTint2)
                Circle()
                    .strokeBorder(Theme.divider, lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 76, height: 76)

            VStack(spacing: 6) {
                Text(title)
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, Spacing.page)
    }
}

/// 空文章列表的专用文案（PRD §5.2 第一行）
extension EmptyStateView {
    static var noArticles: EmptyStateView {
        EmptyStateView(
            icon: "doc.text",
            title: "这里还空着。",
            message: "等第一篇文章发出来，它就会出现在这儿。"
        )
    }
}
