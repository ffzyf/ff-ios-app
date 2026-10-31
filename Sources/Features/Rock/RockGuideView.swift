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
    /// 尺寸模型（设计文档 §4.10）：图墙最该吃满宽度 —— 1194 上一列 680 的 4:3 图
    /// 等于把一半屏幕留成空白，2 列各 528 才是"看攻略"的密度。
    @Environment(\.layoutMetrics) private var metrics

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
            // 列宽：单列 720（= 今天）/ 多列时画布 1080。这是全屏覆盖页，没有 Tab 栏兜底，
            // 所以必须自己限宽：不限的话 iPad 横屏正文行宽会到 1154，一行塞 60 多个汉字。
            // 窄屏 393 < 720，`maxWidth` 不生效 → 与今天逐像素一致。
            .pageColumn(metrics.gridPageWidth)
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

    /// 图墙：**窄档单列 / 宽档 2 列**（各 528，图 528×396 仍是 4:3）。
    ///
    /// 分叉只有容器这一处：`row(index:item:)` 的定义只有一份，图卡 / 文字卡两种长相也在这一个
    /// 函数里分派 —— 网格只决定"几列"，不影响任何一张卡的内部结构。
    ///
    /// 文字卡也进同一栅格（没有固定高度，`LazyVGrid` 按行取高）：严格对齐要给文字卡也上
    /// `minHeight: 396`，本次不做（设计文档 §4.10 明确），因为文字卡极少。
    ///
    /// `matchedGeometryEffect` 的 `zoomNamespace` 与 `transitionID`（= 序号）**一个字都没动**：
    /// 缩放转场靠"来源与目标同一个 namespace + 同一个 id"，换栅格不改变 id。
    @ViewBuilder
    private var itemList: some View {
        if metrics.gridColumns > 1 {
            LazyVGrid(columns: guideColumns, alignment: .leading, spacing: 14) {
                ForEach(store.items.indices, id: \.self) { index in
                    row(index: index, item: store.items[index])
                }
            }
        } else {
            // 窄档：与今天一字不差（外层 VStack 的 14pt 组距仍在，这里只放列表项）
            ForEach(store.items.indices, id: \.self) { index in
                row(index: index, item: store.items[index])
            }
        }
    }

    /// 宽档 2 列（栏距 24 = `Layout.gridGutter`，列宽 = (1080 − 24) / 2 = 528）
    private var guideColumns: [GridItem] {
        return Array(repeating: GridItem(.flexible(), spacing: Layout.gridGutter), count: 2)
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
        // 按钮行与正文同列：`topBar` 是浮在内容上的独立 HStack（ZStack 的一层），
        // 不是 VStack 流里的一员，也没有自己的背景 —— 所以 `pageColumn` 加在这个 HStack
        // 自己身上（在 page padding *之后*，与 `scrollContent` 的顺序一致：列宽含 padding 20×2，
        // 内宽与正文逐像素对齐）。加在外层 ZStack 上无效（ZStack 已被
        // `PageBackground` 撑满），加 `PageBackground` 则会把满屏渐变缩成窄条。
        //
        // 宽档跟着正文一起用画布（1080）：返回钮留在左上角 x≈57，而不是跑到屏幕中间偏左的
        // x≈237 —— 全屏页的按钮不在角落比"视线横跨"更伤手感（同 §4.8 对文章详情的判断）。
        // 窄屏 393 < 720，两次 frame 都不生效 → iPhone 零影响。
        .pageColumn(metrics.gridPageWidth)
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
