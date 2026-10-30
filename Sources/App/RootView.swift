import SwiftUI

/// 根视图。
///
/// 刻意**不用** `TabView`：PRD §2.1 / §4.3 要的是「浮动胶囊、左右内缩 24pt、高 56pt、距底 16pt」，
/// 系统 TabBar 无法满足（隐藏系统 bar 再自绘会让安全区塌陷）。
/// 所以：`ZStack` 内容 + `safeAreaInset(edge: .bottom)` 挂自绘 Tab 栏。
///
/// 五个页面**常驻**在层级里（`ZStack` + `opacity`），不用 `if` / `.id()` 重建：
/// 内容型页面一旦销毁重建，滚动位置和已加载的分页数据都会丢，
/// 而 `.opacity(0)` 的代价只是五个页面各留一份布局（本 App 单页内容量很小）。
///
/// 批次 1 的变化：3 Tab → 5 Tab（PRD §2.2）。红石与更多先用 `PagePlaceholder` 占位，
/// 批次 2 / 批次 3 各替换一行即可 —— 那时 Tab 顺序、图标、`AppTab` 都不用再动。
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: AppTab = .overview
    /// 当前打开的文章（nil = 没开详情）。详情用 `fullScreenCover` 呈现：
    /// 阅读页必须独占全屏（浮动 Tab 栏、青柠光斑都要让位给正文），
    /// 同时保留自己的玻璃导航条与返回手势。
    @State private var openedArticle: ArticleSummary?

    /// 显式写空 init：避免「私有属性把自动生成的 memberwise init 降级成 private」
    /// 导致跨文件 `RootView()` 编译不过。属性包装器各自用自己的默认值初始化。
    init() {}

    var body: some View {
        ZStack {
            // 文章列表是阅读页，保持中性（PRD §4.1：光斑只留在概览与简报）
            PageBackground(glow: tab != .articles)
            content
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

    private var content: some View {
        ZStack {
            OverviewView(selectedTab: $tab, onOpenArticle: openArticle)
                .modifier(TabVisibility(isActive: tab == .overview))

            // 批次 2 替换成 `RockCalendarView()`（红石日历）
            PagePlaceholder(
                title: AppTab.rock.title,
                icon: AppTab.rock.icon,
                summary: "月历、当日场次、规律说明和攻略都收在这一页。等排期接上就开门。"
            )
            .modifier(TabVisibility(isActive: tab == .rock))

            BriefView()
                .modifier(TabVisibility(isActive: tab == .brief))

            ArticlesView(isActive: tab == .articles, onOpenArticle: openArticle)
                .modifier(TabVisibility(isActive: tab == .articles))

            // 批次 3 替换成 `MoreView()`（问卷 / 监控 / 设置 / 关于）
            PagePlaceholder(
                title: AppTab.more.title,
                icon: AppTab.more.icon,
                summary: "问卷工作台、推送监控、设置和关于会收在这一页。"
            )
            .modifier(TabVisibility(isActive: tab == .more))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 打开文章详情：把选中的摘要交给 `fullScreenCover(item:)`。
    /// 详情页只认 `id`，正文由 `AppModel.loadArticle(id:)` 二次请求
    /// （列表接口不返回 content，PRD F3，不能拿列表数据兜底正文）。
    private func openArticle(_ article: ArticleSummary) {
        openedArticle = article
    }
}

/// Tab 切换的显隐修饰符：淡入淡出 + 轻微位移（PRD §4.6：不做横向滑动分页）。
///
/// 隐藏页必须同时关掉命中测试与无障碍焦点，否则 `opacity(0)` 仍然会吃掉点击。
private struct TabVisibility: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 8)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }
}
