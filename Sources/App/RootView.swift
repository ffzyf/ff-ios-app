import SwiftUI

/// 根视图。
///
/// 刻意**不用** `TabView`：PRD §2.1 / §4.3 要的是「浮动胶囊、左右内缩 24pt、高 56pt、距底 16pt」，
/// 系统 TabBar 无法满足（隐藏系统 bar 再自绘会让安全区塌陷）。
/// 所以：`ZStack` 内容 + `safeAreaInset(edge: .bottom)` 挂自绘 Tab 栏。
///
/// 五个页面**条件渲染**（B 批次性能点 B3）：只渲染当前 `tab` 对应的 1 个页面，其余不进视图树。
/// 这样「参与渲染的全屏视图」从 5 降到 1，真玻璃采样层、body 重算量都随之骤降。
/// 滚动位置用 `RootView` 持有的 `scrollPositions` 字典保活（键值随 RootView 常驻，不随页面卸载丢），
/// 切回 Tab 时 `ScrollView.scrollPosition(_:)` 读回上次偏移，大致回到原位。
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    /// 红石数据（批次 2）。根视图只负责"启动时先拉一次" —— 概览卡与红石日历都要用，
    /// 谁先出现就先有数据；重复调用由 Store 内部短路（同月已加载即返回）。
    @EnvironmentObject private var rock: RockStore
    @State private var tab: AppTab = .overview
    /// 当前打开的文章（nil = 没开详情）。详情用 `fullScreenCover` 呈现：
    /// 阅读页必须独占全屏（浮动 Tab 栏、青柠光斑都要让位给正文），
    /// 同时保留自己的玻璃导航条与返回手势。
    @State private var openedArticle: ArticleSummary?
    /// 各页滚动偏移保活：只存「当前 tab 对应那页」的偏移，页面卸载也不丢（RootView 常驻）。
    @State private var scrollPositions: [AppTab: ScrollPosition] = [:]

    /// 显式写空 init：避免「私有属性把自动生成的 memberwise init 降级成 private」
    /// 导致跨文件 `RootView()` 编译不过。属性包装器各自用自己的默认值初始化。
    init() {}

    var body: some View {
        ZStack {
            // 文章列表是阅读页，保持中性（PRD §4.1：光斑只留在概览与简报）
            PageBackground(glow: tab != .articles)
            // 条件渲染：同一时刻只有 1 个页面在视图树里（B3）
            page(for: tab)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(tabs: AppTab.allCases.map { $0.spec }, selection: tabSelection)
                .padding(.horizontal, Spacing.tabBarInset)
                .padding(.bottom, Spacing.tabBarBottomGap)
                .padding(.top, 6)
        }
        // 详情页全屏覆盖（盖在 Tab 栏之上）：`environmentObject` 显式再注入一遍，
        // 不依赖模态呈现是否继承环境（两行代码换掉一类「找不到 AppModel」的运行期崩溃）。
        // 关闭时清详情状态，避免下次进详情先看到上一篇的正文。
        .fullScreenCover(item: $openedArticle, onDismiss: {
            model.clearArticle()
        }) { article in
            ArticleDetailView(articleId: article.id)
                .environmentObject(model)
        }
        .task {
            await model.loadOverview()
        }
        // 红石单独一个 task：与概览的两请求并行，互不阻塞（红石站与博客/简报站是三个域）
        .task {
            await rock.loadSchedule()
        }
    }

    /// 自绘 Tab 栏只认 Int 索引，这里做一次桥接；切换动画统一在 setter 里给。
    private var tabSelection: Binding<Int> {
        Binding(
            get: { tab.rawValue },
            set: { newValue in
                guard let next = AppTab(rawValue: newValue), next != tab else { return }
                Haptics.light()
                withAnimation(Motion.tab) {
                    tab = next
                }
            }
        )
    }

    /// 把某个 tab 的滚动偏移做成 `Binding<ScrollPosition>`：读自 `scrollPositions` 字典，
    /// 写回字典。字典挂在 RootView（常驻），页面切走再切回时偏移仍在，大致回到原位。
    private func scrollBinding(_ tab: AppTab) -> Binding<ScrollPosition> {
        Binding(
            get: { scrollPositions[tab] ?? ScrollPosition(point: .zero) },
            set: { scrollPositions[tab] = $0 }
        )
    }

    /// 条件渲染：只实例化当前 tab 对应的 1 个页面（B3）。其余页面不进视图树，不参与渲染。
    @ViewBuilder
    private func page(for tab: AppTab) -> some View {
        switch tab {
        case .overview:
            OverviewView(selectedTab: $tab, scrollPosition: scrollBinding(tab))
        case .rock:
            RockCalendarView(scrollPosition: scrollBinding(tab))
        case .brief:
            BriefView(scrollPosition: scrollBinding(tab))
        case .articles:
            ArticlesView(scrollPosition: scrollBinding(tab), onOpenArticle: openArticle)
        case .more:
            MoreView(scrollPosition: scrollBinding(tab))
        }
    }

    /// 打开文章详情：把选中的摘要交给 `fullScreenCover(item:)`。
    /// 详情页只认 `id`，正文由 `AppModel.loadArticle(id:)` 二次请求
    /// （列表接口不返回 content，PRD F3，不能拿列表数据兜底正文）。
    private func openArticle(_ article: ArticleSummary) {
        openedArticle = article
    }
}
