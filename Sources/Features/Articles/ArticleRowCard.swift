import SwiftUI

/// 列表态文章卡（PRD §3.2「文章卡（列表态）」）。
///
/// 三个规格细节：
/// · 缩略封面 56×56、圆角 14（`Radius.smallCard`）；
/// · `pinned` 卡高度 +8pt、玻璃 tint +2%（PRD 要求**不靠颜色**也能分辨置顶）；
/// · `置顶` 徽标压在封面左上、`公告` 徽标跟随标题行内，两者同时出现互不遮挡。
struct ArticleRowCard: View {
    let article: ArticleSummary
    var pinned: Bool = false
    let action: () -> Void

    var body: some View {
        PressableGlassCard(
            level: .card,
            tint: pinned ? Color.white.opacity(0.02) : nil,
            action: {
                action()
            }
        ) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 6) {
                    titleRow
                    if !article.summary.isEmpty {
                        Text(article.summary)
                            .font(Typography.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if !metaText.isEmpty {
                        Text(metaText)
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.smallCardPadding)
            // 用 minHeight 而不是固定高度：大字号（AX1+）下文字会换行，固定高会裁字
            .frame(minHeight: pinned ? 124 : 116, alignment: .top)
        }
    }

    private var thumbnail: some View {
        CoverArt(seed: article.coverSeed, title: article.title, watermarkSize: 20, showsGrain: false)
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
            .overlay(alignment: .topLeading) {
                if pinned {
                    BadgePill(kind: .pinned, text: "置顶")
                        .offset(x: -4, y: -6)
                }
            }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(article.title)
                .font(Typography.titleS)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if article.announce {
                BadgePill(kind: .announce, text: "公告")
            }
            Spacer(minLength: 0)
        }
    }

    /// 「3 天前 · 阅读 4 分钟」，缺的项不占位
    private var metaText: String {
        var parts: [String] = []
        let stamp = Formatters.relative(article.displayDate)
        if stamp != "—" {
            parts.append(stamp)
        }
        if let minutes = article.readingMinutes, minutes > 0 {
            parts.append("阅读 \(minutes) 分钟")
        }
        return parts.joined(separator: " · ")
    }
}
