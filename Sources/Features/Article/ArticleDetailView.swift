import SwiftUI

/// 文章详情（T07，PRD §3.3）。
///
/// **呈现方式：`fullScreenCover`（全屏覆盖）**，理由与配套：
/// · 阅读页要独占全屏 —— 浮动 Tab 栏、青柠光斑都要让位，正文才有完整的行宽；
/// · `fullScreenCover` 没有系统自带的下滑关闭，所以这里补两件事：
///   ① 导航条返回钮（点按关闭）；② 滚到顶部时下滑超过 110pt 关闭（`simultaneousGesture`，
///      不抢 ScrollView 的纵向手势）。
///
/// 结构：玻璃导航条（返回 / 分享）→ 滚动内容（头部 + 块流 + 文末签名）→ 底部留白。
/// 导航条材质随滚动插值：0–8pt 全透明，8–40pt 线性到 `.chrome`（PRD §4.4，硬切会「闪一下」）。
/// 偏移用 `PreferenceKey` 采（不用 iOS 18 的 `onScrollGeometryChange`：签名没把握，稳优先）。
///
/// **关于「离开时清空详情」**：清理动作挂在 `RootView` 的 `fullScreenCover(onDismiss:)` 上，
/// 没有用本视图的 `.onDisappear`。原因很具体：正文里点开一张图会再叠一层 `fullScreenCover`，
/// 那会让本视图触发一次 `onDisappear` —— 如果在那里清 `articleState`，用户看完图回来
/// 正文就变成骨架屏（`.task(id:)` 不会因为回到前台重跑，因为它没被销毁）。
/// 清空语义不变，只是把时机挪到「详情真的被关掉」这一刻。
struct ArticleDetailView: View {
    let articleId: String

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var showsShare: Bool = false
    /// 内容顶边在滚动坐标系里的 minY：0 = 顶部，往上滚为负数
    @State private var scrollOffset: CGFloat = 0

    private static let scrollSpace: String = "article-detail-scroll"

    /// 显式 init：`@State` 都是 private，会把自动生成的 memberwise init 降级成 private，
    /// 跨文件 `ArticleDetailView(articleId:)` 就调不到了。
    init(articleId: String) {
        self.articleId = articleId
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 阅读页不加青柠光斑：大面积彩色会干扰正文对比度（PRD §4.1）
            PageBackground(glow: false)
            content
            navigationBar
        }
        .task(id: articleId) {
            await model.loadArticle(id: articleId)
        }
        .sheet(isPresented: $showsShare) {
            ShareSheet(items: shareItems)
        }
        .simultaneousGesture(dismissGesture)
    }

    // MARK: - 状态分发

    @ViewBuilder
    private var content: some View {
        switch model.articleState {
        case .loaded(let detail):
            articleScroll(detail)
        case .failed(let error):
            failureView(error)
        case .idle, .loading:
            // 详情必须有自己的骨架屏：列表接口不返回 content（PRD F3），没有可兜底的正文
            SkeletonDetail()
        }
    }

    private func articleScroll(_ detail: ArticleDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.blockGap) {
                offsetMarker
                ArticleHeaderView(detail: detail)
                BlockListView(blocks: detail.blocks)
                if detail.blocksTruncated && detail.omittedBlocks > 0 {
                    Text("内容太长，后面 \(detail.omittedBlocks) 段省略了。")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                }
                signature
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            // 顶部给玻璃导航条让位（内容仍会从条下滚过，这正是材质渐变的意义）
            .padding(.top, 56)
            // 详情页没有浮动 Tab 栏，底部留白比列表页小一档
            .padding(.bottom, 64)
        }
        .scrollIndicators(.hidden)
        // 用字符串版 `coordinateSpace(name:)`：iOS 17 起有 `coordinateSpace(.named(...))` 新写法，
        // 但它与 `NamedCoordinateSpace` 的组合签名在两个 SDK 里改过，这边取「确定能编译」的那个
        //（旧 API 只是 deprecated，行为与新版完全一致）。
        .coordinateSpace(name: Self.scrollSpace)
        .onPreferenceChange(ArticleScrollOffsetKey.self) { value in
            scrollOffset = value
        }
    }

    // MARK: - 导航条

    private var navigationBar: some View {
        HStack(spacing: 12) {
            IconGlassButton(icon: "chevron.left", size: 36) {
                dismiss()
            }
            .accessibilityLabel("返回")

            Spacer(minLength: 8)

            IconGlassButton(icon: "square.and.arrow.up", size: 36) {
                showsShare = true
            }
            .accessibilityLabel("分享")
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background {
            chromeBackground
        }
    }

    /// 滚动后才出现的玻璃底：`glassSurface(.chrome, in: Rectangle())` + 透明度插值
    private var chromeBackground: some View {
        Rectangle()
            .fill(Color.clear)
            .glassSurface(.chrome, in: Rectangle())
            .opacity(chromeOpacity)
            .ignoresSafeArea(edges: .top)
    }

    /// 0–8pt 完全透明，8–40pt 线性升到 1（位移插值，不是动画，避免滚动跟手性变差）
    private var chromeOpacity: Double {
        let scrolled = max(0, -scrollOffset)
        guard scrolled > 8 else { return 0 }
        return Double(min(1, (scrolled - 8) / 32))
    }

    // MARK: - 错误态

    private func failureView(_ error: APIError) -> some View {
        let notFound = isNotFound(error)
        return VStack(spacing: 0) {
            Spacer(minLength: 96)
            ErrorStateView(
                icon: error.icon,
                title: error.title,
                message: error.hint,
                // 404 是「这篇没了」，重试没有意义，给的是「返回列表」
                retryTitle: notFound ? "返回列表" : "重新加载",
                onRetry: {
                    if notFound {
                        dismiss()
                        return
                    }
                    Task { await model.loadArticle(id: articleId) }
                }
            )
            Spacer(minLength: 0)
        }
    }

    /// 只对 404 做特殊处理：其余（网络 / 解码 / 500）一律给「重新加载」
    private func isNotFound(_ error: APIError) -> Bool {
        if case .server(let code, _) = error {
            return code == 404
        }
        return false
    }

    // MARK: - 文末

    private var signature: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Capsule()
                .fill(Theme.lime)
                .frame(width: 40, height: 3)
            Text("—— FF大王")
                .font(Typography.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 12)
    }

    // MARK: - 滚动偏移采集

    /// 0 高度的哨兵：贴在滚动内容最顶部，把「内容顶边距离滚动容器顶边多少」报上来
    private var offsetMarker: some View {
        Color.clear
            .frame(height: 0)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ArticleScrollOffsetKey.self,
                        value: proxy.frame(in: .named(Self.scrollSpace)).minY
                    )
                }
            }
    }

    // MARK: - 手势

    /// 下滑关闭：只在「已经滚到顶」时受理，否则会跟正文滚动打架
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard scrollOffset >= -4 else { return }
                guard value.translation.height > 110 else { return }
                dismiss()
            }
    }

    // MARK: - 分享

    private var shareItems: [Any] {
        let detail = model.articleState.value
        return ShareSheet.items(
            title: detail?.title ?? "",
            articleID: detail?.id ?? articleId
        )
    }
}

/// 滚动偏移（内容顶边 minY）。用 `PreferenceKey` 而不是 iOS 18 的 `onScrollGeometryChange`：
/// 后者的签名与行为在两个 SDK 小版本间改过，这边不赌。
private struct ArticleScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
