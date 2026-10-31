import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 列表态文章卡（PRD §3.2「文章卡（列表态）」）。
///
/// 三个规格细节：
/// · 缩略封面 56×56、圆角 14（`Radius.smallCard`）；
/// · `pinned` 卡高度 +8pt、玻璃 tint +2%（PRD 要求**不靠颜色**也能分辨置顶）；
/// · `置顶` 徽标压在封面左上、`公告` 徽标跟随标题行内，两者同时出现互不遮挡。
///
/// 长按菜单（设计文档 §7.3）：打开 / 分享 / 复制链接。分享复用工程里已有的 `ShareSheet`，
/// 复制走 `UIPasteboard`（与 `SettingsView.copyToPasteboard` 同一手法）——
/// 两处都不新造面板、不新造颜色。
struct ArticleRowCard: View {
    let article: ArticleSummary
    var pinned: Bool = false
    let action: () -> Void

    /// 长按菜单里的「分享」/「复制链接」。**默认 nil**，于是现有调用点（`ArticlesView` 两处）
    /// 一个字都不用改；不给默认值的话，那两个调用点会立刻编译失败（§9.3 T4 风险点 ②）。
    /// 给闭包是为了让调用方在需要时接管（例如以后带来源追踪参数的分享链接）。
    var onShare: (() -> Void)? = nil
    var onCopyLink: (() -> Void)? = nil

    /// 调用方没接管分享时，卡片自己弹工程里已有的 `ShareSheet`
    @State private var showsShare: Bool = false

    /// 显式 init：`@State` 是 private 存储属性，会把自动生成的 memberwise init 降级成 private，
    /// 跨文件构造就调不到了（`ArticlesView` 就是这么构造它的）。
    ///
    /// 参数顺序不能改：`action` **必须排在两个可选闭包之前**。Swift 的尾随闭包向前配对规则
    /// 会把 `ArticleRowCard(article:) { … }` 里的闭包交给"扫描到的第一个函数类型参数"，
    /// 若 `onShare` 排在前面，现有调用点的尾随闭包会被错配到 `onShare` 上。
    init(
        article: ArticleSummary,
        pinned: Bool = false,
        action: @escaping () -> Void,
        onShare: (() -> Void)? = nil,
        onCopyLink: (() -> Void)? = nil
    ) {
        self.article = article
        self.pinned = pinned
        self.action = action
        self.onShare = onShare
        self.onCopyLink = onCopyLink
    }

    var body: some View {
        // B1：列表卡改二级静态玻璃（glassStatic）。一屏几十张列表行，真玻璃每层都要 backdrop 采样，
        // 静态配方不采样背景、GPU 成本≈0，视觉接近真玻璃；真玻璃留给 Tab 栏 / 置顶卡。
        Button {
            Haptics.light()
            action()
        } label: {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassStatic(
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous),
                tint: pinned ? Theme.surfaceTint1 : nil
            )
        }
        .buttonStyle(PressableStyle())
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        // 长按菜单：三个动作与卡片自己的点击（打开）职责不重叠 ——
        // 点击是"看这篇"，长按是"把这篇拿去别处用"。
        // iPhone 上长按会同时出现按压缩放与菜单，`contentShape` 已在上一行给出，不会漏触。
        .contextMenu {
            menuItems
        }
        // 指针悬停高亮（§7.2）：纯叠加，不改任何几何与字色。iPhone 上无指针 → 无影响。
        // 刻意用 `.highlight` 不用 `.lift`：卡片已经有 `glassStatic` 的投影，lift 再叠一层会"跳一下"。
        .hoverEffect(.highlight)
        .sheet(isPresented: $showsShare) {
            ShareSheet(items: shareItems)
        }
    }

    // MARK: - 长按菜单

    @ViewBuilder
    private var menuItems: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Label("打开", systemImage: "doc.text")
        }

        Button {
            performShare()
        } label: {
            Label("分享", systemImage: "square.and.arrow.up")
        }

        Button {
            performCopyLink()
        } label: {
            Label("复制链接", systemImage: "link")
        }
    }

    /// 分享：调用方接管就交给它，否则弹内置 `ShareSheet`（仍然走 `.sheet`，
    /// 在 iPad 上是 form sheet —— **不要改成 `.popover`**，那需要 `sourceRect`，会崩，§6）
    private func performShare() {
        Haptics.light()
        if let onShare = onShare {
            onShare()
            return
        }
        showsShare = true
    }

    /// 复制链接：链接一律取自 `ShareSheet.link(articleID:)`，页面里不写协议字面量
    private func performCopyLink() {
        Haptics.light()
        if let onCopyLink = onCopyLink {
            onCopyLink()
            return
        }
        #if canImport(UIKit)
        if let url = ShareSheet.link(articleID: article.id) {
            UIPasteboard.general.string = url.absoluteString
            Haptics.success()
        }
        #endif
    }

    /// 与详情页的分享内容同源（标题 + 文章链接），标题为空时只分享链接
    private var shareItems: [Any] {
        return ShareSheet.items(title: article.title, articleID: article.id)
    }

    // MARK: - 内容

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
