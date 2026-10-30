import SwiftUI

/// 文章详情头部（PRD §3.3 第 2–5 条）：封面 → 标题 → 徽标行 → 元信息行 → 分割线。
///
/// 四个约定：
/// · 封面走 `CoverArt`（后端无 cover 字段，PRD F1），比例 16:10，与列表卡同一套视觉语言；
/// · 标题用 `Typography.display`，长标题不限行（`fixedSize` 保证不被裁）；
/// · 徽标只做**语义徽标**（公告 / 置顶 / 更新于 N 天前）—— 文章没有 tags 字段（PRD F2）；
/// · 元信息行的三段都可能缺（时间为空、字数为 0），缺的段整段不出现，不留 `· ·`。
struct ArticleHeaderView: View {
    let detail: ArticleDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cover
            title
            badgeRow
            metaLine
            divider
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 区块

    private var cover: some View {
        CoverArt(seed: detail.coverSeed, title: detail.title, watermarkSize: 64)
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var title: some View {
        Text(displayTitle)
            .font(Typography.display)
            .tracking(Typography.trackingLarge)
            .foregroundStyle(Theme.textPrimary)
            .lineSpacing(Typography.lineSpacing(fontSize: 34, multiple: 1.25))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var badgeRow: some View {
        if detail.announce || detail.pinned || updatedBadgeText != nil {
            HStack(spacing: 8) {
                if detail.announce {
                    BadgePill(kind: .announce, text: "公告")
                }
                if detail.pinned {
                    BadgePill(kind: .pinned, text: "置顶")
                }
                if let updated = updatedBadgeText {
                    BadgePill(kind: .neutral, text: updated)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var metaLine: some View {
        if !metaText.isEmpty {
            Text(metaText)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
                .lineLimit(2)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
    }

    // MARK: - 派生文案

    private var displayTitle: String {
        let trimmed = detail.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "无标题" : trimmed
    }

    /// 「更新于 3 天前」：没有 updatedAt 就整枚不渲染（不显示「更新于 —」）
    private var updatedBadgeText: String? {
        guard let updated = detail.updatedAt else { return nil }
        let stamp = Formatters.relative(updated)
        return stamp == "—" ? nil : "更新于 " + stamp
    }

    /// 「10月28日 发布 · 1,284 字 · 约 4 分钟」
    private var metaText: String {
        var parts: [String] = []
        if let created = detail.createdAt {
            parts.append(Formatters.absoluteCN(created) + " 发布")
        }
        if detail.wordCount > 0 {
            parts.append(detail.wordCountText)
        }
        if detail.readingMinutes > 0 {
            parts.append("约 \(detail.readingMinutes) 分钟")
        }
        return parts.joined(separator: " · ")
    }
}
