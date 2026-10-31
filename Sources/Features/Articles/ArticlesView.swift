import SwiftUI

/// 文章列表页（Tab 2，PRD §3.2 / 设计文档 T06）。
///
/// 分页语义（本批基础层已补齐）：`AppModel.loadFeed(page:append:)` 的 `append: true` 会把
/// 新一页**追加**到已有 items 后面，所以本页不再自己攒一份缓冲 —— 直接读 `model.articles`，
/// 页码读 `model.feedPage`。这样概览页与列表页看到的是同一份数据，翻页不会把首页顶掉。
///
/// 滚动位置保持（B3）：本页在 RootView 里**条件渲染**（切走即卸载），所以靠 RootView 注入的
/// `scrollPosition` Binding 把偏移存到常驻字典，切回时 `ScrollView` 读回，大致回到原位。
struct ArticlesView: View {
    @EnvironmentObject private var model: AppModel
    /// 尺寸模型（设计文档 §3.6）：文章是列表型内容，宽屏走 **2 列网格**（一屏 8 篇）。
    @Environment(\.layoutMetrics) private var metrics
    /// 滚动偏移保活（B3）：由 RootView 持有字典并作为 Binding 注入。
    private let scrollPosition: Binding<ScrollPosition>
    private let onOpenArticle: (ArticleSummary) -> Void

    /// 宽屏 2 列网格的列定义。每列 474 = (960 − 12) / 2。
    ///
    /// 为什么不用 `.adaptive(minimum:)`：adaptive 会随宽度自己变成 3–4 列，
    /// 一屏从 8 篇变成 16 篇的同时每张卡的标题可读宽度也变了 —— 版式就不再"所有设备一致"。
    /// 固定两列让窄屏 = 单列、宽屏 = 两列，中间没有第三种形态。
    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: Spacing.cardGap),
        GridItem(.flexible(), spacing: Spacing.cardGap)
    ]

    /// 只在「本页正在追加」时置真，避免同一页被触发两次
    @State private var isLoadingMore: Bool = false
    /// 追加失败（不是首屏失败）：停止自动翻页，把决定权还给用户的「下拉刷新」
    @State private var didFailLoadingMore: Bool = false

    init(scrollPosition: Binding<ScrollPosition>, onOpenArticle: @escaping (ArticleSummary) -> Void) {
        self.scrollPosition = scrollPosition
        self.onOpenArticle = onOpenArticle
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.cardGap) {
                ArticlesHeader(
                    count: model.articles.count + model.pinnedArticles.count,
                    isRefreshing: model.isRefreshing,
                    lastUpdatedAt: model.lastUpdatedAt
                )
                contentRows
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
            // 窄屏 393 < 720 → 无影响。宽屏时 960 是**列区**宽度（2 × 474 + 12），
            // 页边距 20×2 在它外面，所以要加回去（与红石 / 收益两页同一处推导）。
            .pageColumn(
                metrics.isTwoColumn
                    ? Layout.twoColumnMaxWidth + Spacing.page * 2
                    : Layout.contentMaxWidth
            )
        }
        .scrollPosition(scrollPosition)
        .scrollIndicators(.hidden)
        // PRD §5.2「离线（有缓存）」：有内容但这次刷新失败 → 顶部细条。
        // 用 `safeAreaInset` 而不是 overlay：细条占据自己的高度，不压住标题、不遮内容。
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsOfflineBanner {
                OfflineBanner()
                    .padding(.horizontal, Spacing.page)
                    .padding(.bottom, 6)
                    // 细条必须和上面那个 ScrollView 的列宽一模一样（两列时 960，单列时 720），
                    // 否则 iPad 上胶囊比内容列宽出 194、左右各探出 97 —— 一条"出血"的横杠。
                    // 所以这里照抄 body 里 `pageColumn` 的表达式，而不是写死 720：
                    // 写死的 720 在两列时又会比内容列窄 240，变成另一种错位。
                    // 窄屏两个值都 > 393，`maxWidth` 不生效 → 零影响。
                    .pageColumn(
                        metrics.isTwoColumn
                            ? Layout.twoColumnMaxWidth + Spacing.page * 2
                            : Layout.contentMaxWidth
                    )
            }
        }
        .refreshable {
            await refreshArticles()
        }
        // 全站共享的轻提示（B2 后来源是 ToastStore，这里不传文案即读全局）：
        // 刷新失败不清空内容，只弹这一条（2.5s 自动消失）
        .overlay(alignment: .bottom) {
            PageToast()
        }
        .onChange(of: feedIDs) { _, _ in
            resetPagingFlags()
        }
        .onAppear {
            resetPagingFlags()
        }
    }

    // MARK: - 主体

    @ViewBuilder
    private var contentRows: some View {
        if showsSkeleton {
            SkeletonList()
        } else if let error = model.feedState.error, !model.feedState.hasContent {
            ErrorStateView(
                icon: error.icon,
                title: error.title,
                message: error.hint,
                onRetry: {
                    Task { await reload() }
                }
            )
        } else if model.articles.isEmpty && model.pinnedArticles.isEmpty {
            EmptyStateView.noArticles
        } else {
            if metrics.isTwoColumn {
                // 宽屏：置顶卡不单独加「置顶」小标题，直接当网格第一格 ——
                // 卡片自带 `置顶` 徽标，一行只有两格时再加一个 11pt 小标题会把网格切成两段。
                // 这个分叉只在这里，窄屏的「置顶」分段标题一行都没动。
                twoColumnGrid
            } else {
                if !model.pinnedArticles.isEmpty {
                    sectionLabel("置顶")
                    ForEach(model.pinnedArticles) { article in
                        ArticleRowCard(article: article, pinned: true) {
                            onOpenArticle(article)
                        }
                    }
                }
                ForEach(model.articles) { article in
                    ArticleRowCard(article: article) {
                        onOpenArticle(article)
                    }
                }
            }
            footer
        }
    }

    /// 宽屏 2 列网格。置顶在前、普通在后（与服务端给的顺序一致，不在客户端重排）。
    private var twoColumnGrid: some View {
        LazyVGrid(
            columns: gridColumns,
            alignment: .leading,
            spacing: Spacing.cardGap
        ) {
            ForEach(model.pinnedArticles) { article in
                ArticleRowCard(article: article, pinned: true) {
                    onOpenArticle(article)
                }
            }
            ForEach(model.articles) { article in
                ArticleRowCard(article: article) {
                    onOpenArticle(article)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Typography.captionXS)
            .foregroundStyle(Theme.textTertiary)
            .padding(.top, 4)
    }

    /// 底部：加载环 / 失败提示 /「已经到底了」。三者必居其一，绝不留悬停空白
    private var footer: some View {
        // 外层 ZStack 把「身份」固定住：`.task(id:)` 挂在它上面，
        // 里面 footerBody 换分支（Loading ↔ 到底了）不会改变外层身份，
        // 否则身份一变就会把自己正在跑的那个协程取消掉。
        ZStack {
            footerBody
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        // `.task(id:)` 是分页唯一触发器：条数变化 → id 变化 → 重跑一次。
        // 它挂在 LazyVStack 最后一项上，没滚到底时这一项根本没被创建，天然做到「触底才加载」。
        .task(id: paginationKey) {
            await loadMoreIfNeeded()
        }
    }

    @ViewBuilder
    private var footerBody: some View {
        if isLoadingMore {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(Theme.limeInk)
                    .scaleEffect(0.8)
                Text("正在加载更多")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
        } else if didFailLoadingMore {
            Text("没加载出来，下拉刷新试试。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.statusError)
        } else if !model.hasMoreArticles {
            Text("已经到底了")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
        } else {
            Color.clear
                .frame(height: 1)
        }
    }

    // MARK: - 派生数据

    private var showsSkeleton: Bool {
        return !model.feedState.hasContent && model.feedState.error == nil
    }

    /// PRD §5.2「离线（有缓存）」：手里有内容，但这次 feed 请求失败了（内容没被清空）。
    /// 不直接看 `feedState.error`：`.loaded` 与 `.failed` 互斥，有内容时它恒为 nil。
    private var showsOfflineBanner: Bool {
        return model.feedState.hasContent && model.lastFeedError != nil
    }

    /// 只比 id 的轻量指纹（`LoadState` 不是 `Equatable`，不能直接 onChange 整个状态）
    private var feedIDs: [String] {
        return model.articles.map { $0.id }
    }

    private var paginationKey: String {
        return "\(model.articles.count)-\(model.hasMoreArticles)-\(didFailLoadingMore)"
    }

    // MARK: - 动作

    @MainActor
    private func refreshArticles() async {
        await model.refresh()
        resetPagingFlags()
    }

    /// 首屏失败后的「重新加载」：显式重取第一页（`append: false` = 整体替换）
    @MainActor
    private func reload() async {
        await model.loadFeed(page: 1)
        resetPagingFlags()
    }

    private func resetPagingFlags() {
        didFailLoadingMore = false
    }

    /// 触底追加下一页。三个不变量：
    /// · 本页在 RootView 里条件渲染，挂载即表示「当前可见」，所以不必再判 isActive；
    /// · `hasMore` 是唯一判停依据（`total` 只用于展示，不拿来算页码）；
    /// · 一页什么都没追加进来就停手，避免 `hasMore` 恒真时死循环。
    ///
    /// 数据守卫：`feedState.hasContent` 为真才追加（首屏数据由 `RootView.task` 的
    /// `loadOverview` 拉取，切 Tab 回来时早已存在，因此「已有数据就不重载」，不会闪烁/重复请求，B3）。
    @MainActor
    private func loadMoreIfNeeded() async {
        guard !isLoadingMore, !didFailLoadingMore else { return }
        guard model.feedState.hasContent, model.hasMoreArticles else { return }

        isLoadingMore = true
        let before = model.articles.count
        let next = model.feedPage + 1
        await model.loadFeed(page: next, append: true)

        // 触底项被滚出视口时 `.task` 会取消本次协程：这不算加载失败，下次触底再来
        if Task.isCancelled {
            isLoadingMore = false
            return
        }

        // 成功判据：条数确实增加，或服务端把 page 推到了 next（空页 + hasMore=false 也属正常收尾）
        let grew = model.articles.count > before
        if !grew && model.feedPage < next && model.hasMoreArticles {
            didFailLoadingMore = true
        }
        isLoadingMore = false
    }
}
