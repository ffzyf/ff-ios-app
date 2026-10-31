import SwiftUI

/// 「继续读」rail 里的文章卡（P0-6，设计报告 §4.1）。
///
/// 140×188：封面 96 高 + 标题 17pt 两行 + 元信息 11pt。
/// 为什么首页要有它：改版前首页 0 张图、0 个横向滚动区，读完三张卡就到底 —— "空"的直接来源。
/// 缩略图与列表卡共用 `CoverArt`，所以同一篇文章在首页与列表页有同一个渐变身份。
struct ArticleRailCard: View {
    let article: ArticleSummary
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            card
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(article.title)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 卡内图圆角走 `Radius.insideCard`（同心圆角：14 − 12 ≈ 8 级别），不是又一个新圆角
            CoverArt(seed: article.coverSeed, title: article.title, watermarkSize: 34, showsGrain: false)
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous))

            Text(article.title)
                .font(Typography.titleS)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 8)

            Spacer(minLength: 4)

            Text(metaText)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(Spacing.smallCardPadding)
        .frame(
            width: CardTier.railWidth,
            height: CardTier.rail.height,
            alignment: .topLeading
        )
        .glassStatic(in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
    }

    /// 「3 天前 · 阅读 4 分钟」，缺的项不占位（与列表卡的 `metaText` 同一套规则）
    private var metaText: String {
        var parts: [String] = []
        let stamp = Formatters.relative(article.displayDate)
        if stamp != "—" {
            parts.append(stamp)
        }
        if let minutes = article.readingMinutes, minutes > 0 {
            parts.append("阅读 \(minutes) 分钟")
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}
