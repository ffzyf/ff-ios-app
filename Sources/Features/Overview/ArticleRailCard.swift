import SwiftUI

/// 「继续读」rail 里的文章卡（P0-6，设计报告 §4.1）。
///
/// 140×168：封面 1216:704（140 − 2×12 = 116 宽 → 67 高）+ 标题 17pt 两行 + 元信息 11pt。
/// 为什么首页要有它：改版前首页 0 张图、0 个横向滚动区，读完三张卡就到底 —— "空"的直接来源。
/// 缩略图与列表卡共用 `CoverArt`，所以同一篇文章在首页与列表页有同一个渐变身份。
///
/// 高度 188 → 168（5.5.1）：封面比例换成 AI 原生比例后，封面高从 87 掉到 67，
/// 188 会在 meta 之上留下 30+pt 空白；168 让「封面 67 + 标题两行 + meta + 间距」刚好贴满一整张卡。
struct ArticleRailCard: View {
    let article: ArticleSummary
    let action: () -> Void

    /// 封面比例 = **AI 封面的原生比例** 1216×704 ≈ 1.7273:1
    /// （博客侧 `post-ai.service.ts` 的 `COVER_WIDTH = 1216` / `COVER_HEIGHT = 704`）。
    ///
    /// 为什么必须等于生成图的比例：服务端下发的封面就是 1216×704 的横图，框比它更方（5.5.0 用过
    /// 4:3 = 1.333）时，`scaledToFill` 只能靠**左右各裁约 12%** 去填满，构图（标题字、主体位置）
    /// 被切掉一截 —— 用户说的"比例不正常"就是这次裁切。用原生比例时缩放比刚好是 1:1，零裁切。
    ///
    /// 也不要回去用固定 `frame(height: 96)`：96 是"看着差不多"的魔数，在 116 的卡内宽下算出来
    /// 是 **1.21:1** —— 方不方、横不横，横图会被上下裁掉，竖构图文章（一根灯管、一张立绘）
    /// 被裁得只剩中间一条。
    static let coverAspect: CGFloat = 1216.0 / 704.0

    /// 封面高度 = 卡内宽 ÷ 1216:704（116 ÷ 1.7273 ≈ 67.2）。
    ///
    /// 为什么把高度算出来、而不是只靠 `aspectRatio` 自适应：
    /// `VStack` 给子视图的"剩余高度"是个不确定的提案（本次约为 168 − 标题/meta/padding 后的一半），
    /// 而 `.aspectRatio(contentMode: .fill)` 在**提案高度大于"卡内宽 ÷ 比例"**时会反过来按高度算宽度
    /// （116 宽 → 提案高一旦超过 67，就会算出 150 宽），把卡撑出边界。
    /// rail 卡是全工程唯一固定宽的卡（`CardTier.railWidth`），宽度不是变量，所以这里可以直接钉住高度：
    /// 提案恒为 (116, 67.2)，`.fill` 稳定走"按宽度"分支，`CoverArt` 内部的 `.clipped()` 才裁得对。
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
                // `.fill` + 内部 `.clipped()`：横图与卡片同比例时零裁切；竖构图文章裁成中间一条，
                // 与列表缩略图同一行为（不做 letterbox，留白会让 rail 里出现四种不同"图片块"高度）
                .aspectRatio(Self.coverAspect, contentMode: .fill)
                // 宽度交给父级（卡内宽 116），不由图片反推 —— 否则图片的理想尺寸会把卡撑宽
                .frame(maxWidth: .infinity)
                // 高度锚在 AI 原生比例算出的 67.2 上：见 `coverHeight` 的注释，这是防 `.fill` 翻成"按高度反算宽度"的保险
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
