import SwiftUI

/// 问卷列表（PRD P08）。
///
/// 数据约定：**每次进页面都重拉**（`loadList(force: true)`），不做缓存优先 ——
/// 答卷数每天都在变，看到 3 天前的"共 48 份"比多转半秒圈更糟（PRD P08 明写）。
/// 失败时不清空已有内容：有旧值就挂顶部「离线」条，没旧值才整页错误态（PRD §7）。
struct SurveyListView: View {
    @ObservedObject private var store = SurveyStore.shared

    private let onBack: () -> Void
    private let onOpenSurvey: (String) -> Void

    init(onBack: @escaping () -> Void, onOpenSurvey: @escaping (String) -> Void) {
        self.onBack = onBack
        self.onOpenSurvey = onOpenSurvey
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                SurveyPageHeader(
                    title: "问卷",
                    subtitle: subtitle,
                    trailingIcon: "arrow.clockwise",
                    onTrailing: refresh,
                    onBack: onBack
                )
                statsCard
                listBody
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 6)
            .padding(.bottom, Spacing.pageBottomInset)
            // 问卷列表列宽 720（§3.9）。页头在 ScrollView 里，所以跟着同列走 ——
            // 这正是"返回钮与内容对齐"不需要另外处理的原因。
            .pageColumn(Layout.contentMaxWidth)
        }
        .scrollIndicators(.hidden)
        // 顶部细条占自己的高度，不压标题
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.isListDegraded {
                OfflineBanner(kind: .offline)
                    .padding(.horizontal, Spacing.page)
                    .padding(.bottom, 6)
                    // 与主体同一个列宽（720，见 body 里的 `pageColumn`）：细条挂在
                    // `safeAreaInset` 上拿的是满宽，不限的话 iPad 上胶囊会左右各探出 97。
                    // 窄屏 393 < 720，`maxWidth` 不生效 → 零影响。
                    .pageColumn(Layout.contentMaxWidth)
            }
        }
        .refreshable {
            await store.loadList(force: true)
        }
        .overlay(alignment: .bottom) {
            PageToast(message: store.toast)
        }
        // toast 1.8 秒自动消失，不打断任何操作
        .task(id: store.toast) {
            guard store.toast != nil else { return }
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(Motion.glassOut) {
                store.clearToast()
            }
        }
        .task {
            // PRD P08：每次进页面刷新（`force` 会跳过"已加载"的短路）
            await store.loadList(force: true)
        }
    }

    // MARK: - 头部

    private var subtitle: String {
        guard store.list != nil else { return "管理密码登录后可见" }
        let counts = store.counts
        if counts.total == 0 { return "还没有问卷" }
        return "共 \(counts.total) 份 · \(counts.published) 份在收"
    }

    private func refresh() {
        Task {
            await store.loadList(force: true)
        }
    }

    // MARK: - 三个统计

    private var statsCard: some View {
        GlassCard {
            HStack(spacing: 0) {
                statColumn(value: store.counts.total, title: "问卷数")
                statDivider
                statColumn(value: store.counts.published, title: "已发布")
                statDivider
                statColumn(value: store.counts.responses, title: "总答卷")
            }
            .padding(.vertical, Spacing.smallCardPadding)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("共 \(store.counts.total) 份问卷，\(store.counts.published) 份已发布，累计 \(store.counts.responses) 份答卷")
    }

    private func statColumn(value: Int, title: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(Typography.titleL)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(title)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: 1, height: 30)
    }

    // MARK: - 列表

    @ViewBuilder
    private var listBody: some View {
        if !store.summaries.isEmpty {
            VStack(spacing: Spacing.cardGap) {
                ForEach(store.summaries) { summary in
                    Button(action: {
                        Haptics.light()
                        onOpenSurvey(summary.id)
                    }) {
                        SurveyRowCard(summary: summary)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        } else if store.isLoadingList || store.list == nil {
            // 首屏骨架：与真实卡片结构一致（标题行 + 元信息行），收起时不跳动
            VStack(spacing: Spacing.cardGap) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonBlock(height: 18)
                        SkeletonBlock(width: 180, height: 12)
                        SkeletonBlock(width: 120, height: 12)
                    }
                    .padding(Spacing.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
        } else if let error = store.listFailure {
            ErrorStateView(
                icon: error.icon,
                title: error.title,
                message: error.hint,
                retryTitle: "重新加载",
                onRetry: refresh
            )
        } else {
            EmptyStateView(
                icon: "doc.badge.plus",
                title: "还没有问卷。",
                message: "V3 不提供创建，先去网页端建一份，回来这里刷新就能看到。"
            )
        }
    }
}
