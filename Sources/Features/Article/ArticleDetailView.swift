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
    /// 尺寸模型（设计文档 §4.8）：**只给导航条用** —— 正文列宽一个字都不改（行宽由字形决定）。
    @Environment(\.layoutMetrics) private var metrics

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

    /// 正文滚动区。
    ///
    /// **5.5.2 修「打开文章会自己变大」**：症状是标题左边被切掉一个字、正文左右两头都被屏幕吃掉，
    /// 看起来像整页被放大了一档 —— 但字号其实一个 pt 都没变（量过：仍是 17pt / 34pt）。
    /// 真凶是**列宽**：`pageColumn` 的实现是 `.frame(maxWidth: 640)` + `.frame(maxWidth: .infinity, alignment: .center)`，
    /// 后一个 `frame` 是「把这块放到可用宽度中间」；只要有一条子视图报出比屏幕更宽的理想宽度
    /// （图片块、横向滚动的代码块、任何带 `fixedSize(horizontal:)` 的视图），`VStack` 就会长到那个宽度，
    /// 再被居中 —— 于是左右各溢出几十 pt，整列文字按更宽的行宽折行，肉眼看就是「变大了」。
    ///
    /// 所以这里不再依赖 `maxWidth`，改成**量出来再写死**：`GeometryReader` 拿到容器宽度（= 屏幕），
    /// 减掉左右页边距后作为 `VStack` 的确定宽度。定宽是一个"确定的 proposal"，
    /// 文字一定会按它折行；万一还有子视图不听话，溢出的也只是它自己那一块，推不动整列。
    private func articleScroll(_ detail: ArticleDetail) -> some View {
        GeometryReader { proxy in
            // 宽度的两个来源取较小值：
            // · `proxy.size.width` 是这个容器现在真实的宽度；
            // · `metrics.canvasPageWidth` 是**根视图量到的屏幕宽度**（导航条用的就是它，
            //   而导航条的返回/分享按钮位置一直是准的 —— 它可以当作"没有被撑宽的基准"）。
            // 万一这里的 GeometryReader 被某个子视图撑宽了，第二个值会把列宽拉回屏幕宽度。
            let screenWidth = min(proxy.size.width, metrics.canvasPageWidth)
            // 640 是含页边距的列宽上限（§3.8：17pt 下约 35 个汉字一行），文字实际宽度 = 列宽 − 40
            let column = max(0, min(screenWidth, Layout.readingMaxWidth) - Spacing.page * 2)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.blockGap) {
                    offsetMarker
                    ArticleHeaderView(detail: detail, contentWidth: column)
                    BlockListView(blocks: dedupedBlocks(detail.blocks, title: detail.title))
                    if detail.blocksTruncated && detail.omittedBlocks > 0 {
                        Text("内容太长，后面 \(detail.omittedBlocks) 段省略了。")
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    signature
                }
                .frame(width: column, alignment: .leading)
                .padding(.horizontal, Spacing.page)
                // 顶部给玻璃导航条让位（内容仍会从条下滚过，这正是材质渐变的意义）
                .padding(.top, 56)
                // 详情页没有浮动 Tab 栏，底部留白比列表页小一档
                .padding(.bottom, 64)
                // 宽屏（iPad / Stage Manager）居中，窄屏时 column + 40 恰好等于屏宽，这一步是空操作
                .frame(maxWidth: .infinity, alignment: .center)
            }
            // 滚动容器本身上下也钉死宽度：哪怕外层给了一个比屏幕更宽的 proposal，也不会横向跑偏
            .frame(width: screenWidth)
            .scrollIndicators(.hidden)
            // 用字符串版 `coordinateSpace(name:)`：iOS 17 起有 `coordinateSpace(.named(...))` 新写法，
            // 但它与 `NamedCoordinateSpace` 的组合签名在两个 SDK 里改过，这边取「确定能编译」的那个
            //（旧 API 只是 deprecated，行为与新版完全一致）。
            .coordinateSpace(name: Self.scrollSpace)
            .onPreferenceChange(ArticleScrollOffsetKey.self) { value in
                scrollOffset = value
            }
        }
    }

    // MARK: - 正文去重

    /// 去掉正文开头那个「和文章标题一模一样」的 h1/h2。
    ///
    /// 博客的 Markdown 习惯是第一行写 `# 标题`，服务端把它解析成 heading 块原样下发 ——
    /// 于是详情页会连着出现两次同样的标题（一次是 `ArticleHeaderView`，一次是正文首块）。
    /// 网页端已经在渲染层做了同样的归一化（`normalize-heading.ts`），App 这边现在对齐。
    ///
    /// 只扫前几块：正文中间某个章节标题恰好叫得和文章同名，那是作者有意为之，不该删。
    private func dedupedBlocks(_ blocks: [Block], title: String) -> [Block] {
        let key = Self.normalizedHeading(title)
        guard !key.isEmpty else { return blocks }

        for (index, block) in blocks.prefix(3).enumerated() {
            switch block {
            case .heading(let level, let text):
                guard level <= 2 else { return blocks }
                guard Self.normalizedHeading(text) == key else { return blocks }
                var copy = blocks
                copy.remove(at: index)
                return copy
            case .divider, .unknown:
                continue
            default:
                return blocks
            }
        }
        return blocks
    }

    /// 标题归一化：抹掉空白与常见标点、统一小写。
    ///
    /// 这样「更新 | iOS App 5.2.0 & 网站上线」与「更新｜iOS App 5.2.0 & 网站上线 2026-11-18」
    /// 这类"同一句话、标点写法不同"的重复才认得出。与网页端 `normalize-heading` 同一套判据。
    private static func normalizedHeading(_ text: String) -> String {
        let dropped = Set(" \t\n\r\u{3000}|｜·•—–-~、，,。.：:；;！!？?\"'“”‘’（）()【】[]《》〈〉<>…/\\")
        return String(text.lowercased().filter { !dropped.contains($0) })
    }

    // MARK: - 导航条

    private var navigationBar: some View {
        HStack(spacing: 12) {
            // ⌘[ 返回 / 关闭（§7.1）。iPhone 上无键盘时是死代码，不占布局、不改任何像素。
            // 快捷键由 `IconGlassButton` 挂到它内部那颗 `Button` 上 —— 挂在这一层（包装 View）
            // 不保证被注册进快捷键表，Apple 的说法是"assigns it to the modified control"。
            IconGlassButton(icon: "chevron.left", size: 36, shortcut: "[") {
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
        // 导航条走**画布**（宽档 1080 / 窄档 = 屏宽），正文仍是 640。
        //
        // 这一行是本次唯一改动的导航几何，理由与旧注释正好相反：
        // 旧文档写"导航条必须与正文同列"，那条在小屏成立；但在 1194 上，"同列"意味着返回钮
        // 距屏幕左边 277pt —— 拇指和指针都要往里够 277，**按钮不在角落**比"视线横跨"更伤手感。
        // 所以宽档把按钮放回左上角（x ≈ 57），正文继续在中间 640 里（那 277 的空白是行宽决定的，
        // 不是浪费）。窄屏 `canvasPageWidth` = 393，`maxWidth` 不生效 → 与今天逐像素一致。
        .pageColumn(metrics.canvasPageWidth)
        .padding(.top, 6)
        .padding(.bottom, 8)
        // 玻璃底必须满宽（它是"条"，不是"列"）：所以 `pageColumn` 加在 `.background` **之前**，
        // 限宽只作用在按钮那一行上。
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
