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

    /// 正文列宽（**不含**左右页边距）。5.5.3 新增。
    ///
    /// 为什么封面和标题要单独拿宽度：外层虽然已经 `.frame(width: column)`，
    /// 但那个宽度只是"提议"—— `aspectRatio` 在高度提案为 nil 时、以及 `Text` 在
    /// 某些换行路径下，都可能报出比提议更大的理想宽度，然后**向右溢出**（leading 对齐不会往左跑）。
    /// 传进来的这个数会被写成确定的 `frame(width:)`，封面的高度也由它算出来，
    /// 于是哪怕外部提案再离谱，这两块也不会超出这一列。
    var contentWidth: CGFloat? = nil

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
        let art = CoverArt(seed: detail.coverSeed, title: detail.title, coverURL: detail.cover?.imageURL, watermarkSize: 64)
        return Group {
            if let width = contentWidth {
                // 宽高都写死：比例仍是 16:10，但不再依赖 `aspectRatio` 去推高度
                art.frame(width: width, height: width * 10.0 / 16.0)
            } else {
                art.aspectRatio(16.0 / 10.0, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var title: some View {
        Text(displayTitle)
            .font(titleFont)
            // 长标题降一档：34pt 在 350 宽的手机列里，一行只放得下十来个字，
            // 视觉上会压过封面（用户原话「图片跟标题又太大了」）。
            // 短标题仍用 display，保住"大标题"的气势。
            .tracking(Typography.trackingLarge)
            .foregroundStyle(Theme.textPrimary)
            .lineSpacing(Typography.lineSpacing(fontSize: titleFontSize, multiple: 1.25))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// 标题字号：短标题 34（`display`），长标题降到 28（`titleXL`）。
    ///
    /// 14 个字符是分界点：手机列宽 350、34pt 中文一行约 10 字，
    /// 超过 14 字必然折到第三行，而三行 34pt 标题会把封面压成配角。
    private var titleFontSize: CGFloat {
        displayTitle.count > 14 ? 28 : 34
    }

    private var titleFont: Font {
        titleFontSize > 30 ? Typography.display : Typography.titleXL
    }

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
