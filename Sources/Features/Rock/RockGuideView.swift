import SwiftUI

/// 攻略图文流（P06）：4:3 图片卡 + 文字卡，点图片全屏（`matchedGeometryEffect` 转场）。
///
/// 为什么是"二级入口 + 全屏覆盖"而不是第六个 Tab：攻略是"偶尔看一眼"的内容，
/// 放进 Tab 会稀释 5 个主功能（PRD §2.2 的取舍）。全屏覆盖让它独占阅读空间，
/// 又不必新建导航栈 —— 根视图没有 `NavigationStack`，硬塞一个会打乱 Tab 的层级。
///
/// 状态四段（PRD P06）：骨架（首次）→ 内容 → 空态 → 错误态。
/// 「部分源失败」是内容态上的一条顶部细条，不是错误页：有内容就先看内容。
struct RockGuideView: View {
    @EnvironmentObject private var store: RockGuideStore
    @Environment(\.dismiss) private var dismiss

    /// 图片转场命名空间（来源卡与全屏图共享）
    @Namespace private var zoomNamespace: Namespace.ID
    /// 正在全屏看的图（nil = 没在全屏）
    @State private var zoomedIndex: Int?
    @State private var zoomedItem: GuideItem?

    /// 显式空 init：见 `RockCalendarView.init()` 的同一条说明（private 存储属性 → memberwise init 降级）
    init() {}

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground(glow: false)
            scrollContent
            topBar
            zoomOverlay
        }
        .task {
            await store.load()
        }
    }

    // MARK: - 内容

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 顶部给玻璃导航条让位（内容会从条下滚过，这正是材质的意义）
                Color.clear.frame(height: 52)
                if store.isPartial {
                    OfflineBanner(kind: .partialFailure)
                }
                contentArea
                Text(store.cacheNote)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await store.load(force: true)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if !store.items.isEmpty {
            itemList
        } else if let error = store.state.error {
            ErrorStateView(
                icon: "wifi.slash",
                title: error.title,
                message: error.hint,
                onRetry: {
                    Task { await store.load(force: true) }
                }
            )
        } else if store.isLoading {
            skeletonList
        } else {
            emptyState
        }
    }

    private var itemList: some View {
        ForEach(store.items.indices, id: \.self) { index in
            row(index: index, item: store.items[index])
        }
    }

    @ViewBuilder
    private func row(index: Int, item: GuideItem) -> some View {
        if item.isImage {
            GuideImageCard(
                item: item,
                transitionID: index,
                namespace: zoomNamespace,
                onTap: { openZoom(index: index, item: item) }
            )
        } else {
            textCard(item)
        }
    }

    /// 文字卡：标题（可空）+ 正文。正文最多 12 行，超出折起 —— 图墙里一条长文会把后面全挤走
    private func textCard(_ item: GuideItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !item.title.isEmpty {
                Text(item.title)
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(item.content ?? "")
                .font(Typography.callout)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(Typography.lineSpacing(fontSize: 15, multiple: 1.65))
                .lineLimit(12)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            EmptyStateView(
                icon: "photo.on.rectangle",
                title: "攻略内容暂未更新。",
                message: "等攻略源有新内容，刷新一下就会出现。"
            )
            Button {
                Haptics.light()
                Task { await store.load(force: true) }
            } label: {
                Text("刷新")
            }
            .buttonStyle(PrimaryCTAStyle())
        }
        .frame(maxWidth: .infinity)
    }

    /// 骨架：一张 4:3 大块 + 两行文字块（尺寸与真实卡误差 <4pt，收起不跳动）
    private var skeletonList: some View {
        VStack(alignment: .leading, spacing: 14) {
            SkeletonBlock(height: 210, cornerRadius: Radius.smallCard)
            SkeletonBlock(width: 180, height: 14)
            SkeletonBlock(width: 240, height: 14)
            SkeletonBlock(height: 120, cornerRadius: Radius.smallCard)
        }
    }

    // MARK: - 顶部条

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .glassSurface(.floating, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("返回")

            Text("攻略")
                .font(Typography.titleS)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Button {
                Haptics.light()
                Task { await store.load(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.limeInk)
                    .frame(width: 32, height: 32)
                    .glassSurface(.floating, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("刷新攻略")
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    // MARK: - 全屏看图

    @ViewBuilder
    private var zoomOverlay: some View {
        if let item = zoomedItem, let index = zoomedIndex {
            GuideZoomView(
                item: item,
                transitionID: index,
                namespace: zoomNamespace,
                onClose: { closeZoom() }
            )
            .zIndex(3)
        }
    }

    private func openZoom(index: Int, item: GuideItem) {
        withAnimation(Motion.imageResize) {
            zoomedIndex = index
            zoomedItem = item
        }
    }

    private func closeZoom() {
        withAnimation(Motion.imageResize) {
            zoomedIndex = nil
            zoomedItem = nil
        }
    }
}
