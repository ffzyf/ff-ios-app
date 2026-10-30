import SwiftUI

/// 列表块（无序：青柠小圆点；有序：青柠序号，宽度固定 24pt 右对齐）。
///
/// 不支持嵌套（后端解析器把缩进行拍平成同级项，设计文档 E11），所以这里只有一层。
/// 每项支持行内 markdown —— 服务端下发的是原始文本，解析统一走 `InlineMarkdown`。
struct ListBlock: View {
    let ordered: Bool
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { entry in
                if !InlineMarkdown.isBlank(entry.element) {
                    row(index: entry.offset, text: entry.element)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func row(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            marker(index: index)
            Text(InlineMarkdown.attributed(text))
                .font(Typography.body)
                .foregroundStyle(Theme.textBody)
                .lineSpacing(Typography.lineSpacing(fontSize: 17, multiple: 1.7))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func marker(index: Int) -> some View {
        // 固定 24pt 宽的标号列：1. 与 10. 的宽度差不会把正文推歪
        if ordered {
            Text("\(index + 1).")
                .font(Typography.callout.weight(.semibold))
                .foregroundStyle(Theme.lime)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
                .padding(.top, 1)
        } else {
            Circle()
                .fill(Theme.lime)
                .frame(width: 5, height: 5)
                .frame(width: 24, alignment: .trailing)
                .padding(.top, 9)
        }
    }
}
