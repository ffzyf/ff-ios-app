import SwiftUI

/// 概览页「最近写的」区块（PRD §3.1 第 6–7 条）。
///
/// 结构：区块标题 +「全部 ›」+ 两张 16:10 封面大卡。
/// 文章数据没有 `cover` 字段（PRD F1），封面一律走设计系统的 `CoverArt` 程序化渐变，
/// 不在这里画任何占位灰块。
struct LatestArticlesSection: View {
    let articles: [ArticleSummary]
    let onSelect: (ArticleSummary) -> Void
    let onOpenAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionTitleGap) {
            header
            if articles.isEmpty {
                EmptyStateView.noArticles
            } else {
                ForEach(articles) { article in
                    LatestArticleCard(article: article) {
                        onSelect(article)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("最近写的")
                .font(Typography.titleL)
                .tracking(Typography.trackingLarge)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Button(action: {
                Haptics.light()
                onOpenAll()
            }) {
                Text("全部 ›")
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.limeInk)
                    .padding(.vertical, 6)
                    .padding(.leading, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看全部文章")
        }
    }
}

/// 概览大卡：上 16:10 程序化封面（出血到卡边）+ 下文字区。
///
/// 封面用 `aspectRatio(1.6, contentMode: .fit)` 而不是固定高度：
/// 不同机型宽度不同，固定 120pt 会让「16:10」在窄屏上失效。
struct LatestArticleCard: View {
    let article: ArticleSummary
    let onSelect: () -> Void

    var body: some View {
        PressableGlassCard(level: .card, action: {
            onSelect()
        }) {
            VStack(alignment: .leading, spacing: 0) {
                cover
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(Typography.titleS)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !article.summary.isEmpty {
                        Text(article.summary)
                            .font(Typography.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    if !metaText.isEmpty {
                        Text(metaText)
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.cardPadding)
            }
            // 封面出血到卡边，必须按卡片圆角裁一次，否则上方两角是直角
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private var cover: some View {
        CoverArt(seed: article.coverSeed, title: article.title)
            .aspectRatio(1.6, contentMode: .fit)
            .overlay(alignment: .bottomTrailing) {
                badgeRow.padding(12)
            }
    }

    /// 公告 / 置顶各一枚，不合并（PRD §3.2：三种标记不可混用同一套样式）
    private var badgeRow: some View {
        HStack(spacing: 6) {
            if article.pinned {
                BadgePill(kind: .pinned, text: "置顶")
            }
            if article.announce {
                BadgePill(kind: .announce, text: "公告")
            }
        }
    }

    /// 「10月28日 · 更新于 3 天前」，两个时间都缺时不渲染整行
    private var metaText: String {
        var parts: [String] = []
        if let created = article.createdAt {
            parts.append(Formatters.absoluteCN(created))
        }
        if let updated = article.updatedAt {
            parts.append("更新于 " + Formatters.relative(updated))
        }
        return parts.joined(separator: " · ")
    }
}
