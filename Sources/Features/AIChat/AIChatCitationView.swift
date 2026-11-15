import SwiftUI

/// 回答气泡内的引用区（5.1.2 · R4a，架构 §1.5.3 / §1.4 R4c）。
///
/// 三条纪律：
/// 1. **拿不到就整块不渲染**：`citations` 为空 / nil 时不画空壳（§7-13）。
///    流式引用由 `AIChatStore` 挂到 `AIChatMessage.citations`，历史回放由服务端
///    原样回传 —— 两条来源走同一份渲染路径。
/// 2. **App 不解析 URL**：`domain` 由后端 `new URL(u).hostname` 算好下发，
///    避免 `www.` / 端口 / 国际化域名在两端分叉（架构 §1.5.3）。
/// 3. **零颜色字面量**：序号 `.monospacedDigit()`、域名 `Theme.textTertiary`、
///    外链沿用工程现役形态 `UIApplication.shared.open`（同 `AnnouncementBanner`）。
struct AIChatCitationView: View {

    let citations: [AICitation]

    /// iPad rail 档两列（AC4-6），其余 1 列。由 `AIChatView` 按 `metrics.pageTier` 注入。
    var columns: Int = 1

    var body: some View {
        // 空数组直接不画：这是「不渲染空壳」最直白的一处
        if !citations.isEmpty {
            GlassCard(level: .card, cornerRadius: Radius.smallCard) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("引用")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)

                    LazyVGrid(columns: gridColumns, spacing: 8) {
                        ForEach(citations) { citation in
                            citationRow(citation)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private var gridColumns: [GridItem] {
        let count = max(1, columns)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    private func citationRow(_ citation: AICitation) -> some View {
        Button {
            open(citation)
        } label: {
            HStack(alignment: .top, spacing: 7) {
                Text(String(citation.index))
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .frame(minWidth: 14, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(citation.title)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(citation.domain)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("引用 \(citation.index)，\(citation.title)，\(citation.domain)")
    }

    /// 只接受 https?://：后端已校验过，这里再兜一层，避免 file:// / 自定义 scheme 被打开。
    private func open(_ citation: AICitation) {
        Haptics.light()
        guard let url = URL(string: citation.url),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #endif
    }
}
