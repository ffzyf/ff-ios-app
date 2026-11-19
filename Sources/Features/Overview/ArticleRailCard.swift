import SwiftUI

/// 「继续读」rail 里的文章卡（P0-6，设计报告 §4.1）。
///
/// 140×188：封面 4:3（140 − 2×12 = 116 宽 → 87 高）+ 标题 17pt 两行 + 元信息 11pt。
/// 为什么首页要有它：改版前首页 0 张图、0 个横向滚动区，读完三张卡就到底 —— "空"的直接来源。
/// 缩略图与列表卡共用 `CoverArt`，所以同一篇文章在首页与列表页有同一个渐变身份。
struct ArticleRailCard: View {
    let article: ArticleSummary
    let action: () -> Void

    /// 封面比例：4:3 横构图。
    ///
    /// 为什么不是继续用固定 `frame(height: 96)`：96 是"看着差不多"的魔数，在 116 的卡内宽下
    /// 算出来是 **1.21:1** —— 方不方、横不横，竖构图文章（一根灯管、一张立绘）被裁得只剩中间一条。
    /// 4:3 是文章缩略图的通行比例：比 1.21 更像"一张图"，又比 16:9 裁得少（16:9 会切掉封面上下 25%）。
    static let coverAspect: CGFloat = 4.0 / 3.0

    /// 封面高度 = 卡内宽 ÷ 4/3。
    ///
    /// 为什么把高度算出来、而不是只靠 `aspectRatio` 自适应：
    /// `VStack` 给子视图的"剩余高度"是个不确定的提案（本次约为 188 − 标题/meta/padding 后的一半），
    /// 而 `.aspectRatio(contentMode: .fill)` 在**提案高度大于"卡内宽 ÷ 比例"**时会反过来按高度算宽度
    /// （116 宽 → 提案高一旦超过 87，就会算出 133 宽），把卡撑出边界。
    /// rail 卡是全工程唯一固定宽的卡（`CardTier.railWidth`），宽度不是变量，所以这里可以直接钉住高度：
    /// 提案恒为 (116, 87)，`.fill` 稳定走"按宽度"分支，`CoverArt` 内部的 `.clipped()` 才裁得对。
    static let coverHeight: CGFloat =
        (CardTier.railWidth - Spacing.smallCardPadding * 2) / ArticleRailCard.coverAspect

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
            CoverArt(seed: article.coverSeed, title: article.title, coverURL: article.cover?.imageURL, watermarkSize: 34, showsGrain: false)
                .aspectRatio(Self.coverAspect, contentMode: .fill)
                // 宽度交给父级（卡内宽 116），不由图片反推 —— 否则图片的理想尺寸会把卡撑宽
                .frame(maxWidth: .infinity)
                // 高度锚在 4:3 算出的 87 上：见 `coverHeight` 的注释，这是防 `.fill` 翻成"按高度反算宽度"的保险
                .frame(height: Self.coverHeight)
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
