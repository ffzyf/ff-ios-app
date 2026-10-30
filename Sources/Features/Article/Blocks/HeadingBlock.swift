import SwiftUI

/// 正文标题（h1–h6）。
///
/// 层级映射（PRD §3.3 + 设计系统现有字号阶）：
/// · h1 → `titleXL`（28 Bold），并在上方压一条 28×3pt 青柠短线做章节锚点
///   （这是全文唯一使用青柠大色块的地方，控制住频率）；
/// · h2 → `titleL`（22 Semibold）；
/// · h3 → `titleS`（17 Semibold）；
/// · h4–h6 → 15pt Semibold + `textSecondary`，与正文同字号，不再往下细分 ——
///   长文里出现四层标题会把阅读节奏打碎。
///
/// 留白：上方比下方大（块流本身已有 `blockGap`，这里只补一点向心力）。
struct HeadingBlock: View {
    let level: Int
    let text: String

    var body: some View {
        if !InlineMarkdown.isBlank(text) {
            VStack(alignment: .leading, spacing: 10) {
                if safeLevel == 1 {
                    anchorLine
                }
                Text(InlineMarkdown.attributed(text))
                    .font(font)
                    .foregroundStyle(foreground)
                    .lineSpacing(Typography.lineSpacing(fontSize: fontSize, multiple: 1.3))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, safeLevel <= 3 ? 10 : 4)
            .padding(.bottom, safeLevel <= 2 ? 2 : 0)
        }
    }

    /// h1 的 28×3pt 青柠短线（PRD §3.3「h1 上方压一条短线」）
    private var anchorLine: some View {
        Capsule()
            .fill(Theme.lime)
            .frame(width: 28, height: 3)
    }

    /// 服务端只会给 1–6，但 `%` 之外的脏数据不该让层级塌掉：一律夹到 1–6
    private var safeLevel: Int {
        return min(max(level, 1), 6)
    }

    private var font: Font {
        switch safeLevel {
        case 1:
            return Typography.titleXL
        case 2:
            return Typography.titleL
        case 3:
            return Typography.titleS
        default:
            return Typography.callout.weight(.semibold)
        }
    }

    private var fontSize: CGFloat {
        switch safeLevel {
        case 1:
            return 28
        case 2:
            return 22
        case 3:
            return 17
        default:
            return 15
        }
    }

    private var foreground: Color {
        return safeLevel <= 3 ? Theme.textPrimary : Theme.textSecondary
    }
}
