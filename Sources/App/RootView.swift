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
    /// 尺寸模型（设计文档 §1.4）。Tab 栏只读 `tabBarWidth` 一个量；
    /// 页面不做任何尺寸判断，各自读环境自己算 —— 这里刻意**不**把 metrics 往下传。
    @Environment(\.layoutMetrics) private var metrics
    /// 前庭敏感用户：选中圆跨 90pt 的滑动是页面里唯一"有距离的动效"，关掉时硬切（§7.6）。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: AppTab = .overview
    /// 当前打开的文章（nil = 没开详情）。详情用 `fullScreenCover` 呈现：
    /// 阅读页必须独占全屏（浮动 Tab 栏、青柠光斑都要让位给正文），
    /// 同时保留自己的玻璃导航条与返回手势。
    @State private var openedArticle: ArticleSummary?
    /// 各页滚动偏移保活：只存「当前 tab 对应那页」的偏移，页面卸载也不丢（RootView 常驻）。
    @State private var scrollPositions: [AppTab: ScrollPosition] = [:]
    /// 设置浮层（⌘, 打开，设计文档 §7.1）。iPad 上 ⌘, 是肌肉记忆，
    /// iPhone 无外接键盘时它是死代码 —— 隐藏按钮不占布局、不改变任何像素。
    @State private var showsSettings: Bool = false
    /// 沉浸式天光页（3.11.0）。**深链只有一条**：小组件深链 `skyapp://sky`
    /// （天光 / 日弧 / 月相 / 风 四张卡，见 `WidgetDeepLink.sky`）。
    /// 概览第二张卡的那个入口在 `OverviewView` 自己身上 —— 两处 `SkyRoomView(` 就是全部，
    /// 不许再挂第三个（DESIGN-RULES §4）。
    @State private var showsSkyRoom: Bool = false
    /// 天光页 present 的「排队中」标记（3.11.0 深链重入守卫）。
    ///
    /// **为什么需要 pending 守卫**：同一个 `RootView` 上挂了两个 `fullScreenCover`，
    /// UIKit 同一时刻只允许一次转场。演示/深链在「正在 dismiss 文章详情」的窗口里
    /// 再次 present 时，UIKit 会**静默丢弃**这次 present —— 不报错、不崩溃、没有动画，
    /// 而 `showsSkyRoom` 这个状态位**已经被写成 true 了**。此后任何"再置一次 true"
    /// 都是 no-op（值没变 → SwiftUI 没有 diff、UIKit 也没有新请求），
    /// 于是天光页就**永远不弹**，用户只能杀进程重来。
    ///
    /// 所以「谁在看这个 350ms 窗口、谁负责最后那一次 present」必须显式记下来：
    /// 窗口内的重复深链一律被吞掉，绝不碰状态位；只有排队中的那个任务去写 true。
    @State private var skyRoomPending: Bool = false
    /// 配色主题。`Theme.*` 是全局静态 token，SwiftUI 不会替我们追踪它的变化，
    /// 所以切换时靠下面的 `.id(themeId)` 把内容区整块重建一次（滚动位置存在字典里，不受影响）。
    @ObservedObject private var appearance = AppearanceStore.shared
    /// 滚动光影（3.6.0）。放在根视图而不是页面里：**背景层与页面层是 `ZStack` 的兄弟节点**，
    /// 页面里量到的滚动偏移没有任何视图层级可以"传上去"，只能由共同祖先持有的对象中转。
    ///
    /// `@State` 而不是 `@StateObject`：`@StateObject` 是订阅式的，store 每变一次
    /// `RootView.body` 就要重算一次，滚动是每帧回调 —— 等于让整棵树跟着滚动帧率重算
    /// （3.5.0 那个 Tab 卡顿的同源问题，但频率高得多）。`RootView.body` 根本不读 `progress`，
    /// 它重算的唯一后果是 `page(for:)` 与 `scrollBinding` 被重建、当前页整棵子树跟着重算
    /// （概览页三张真玻璃卡会重新采样）。
    /// `@State` 只持有实例、不订阅；真正需要重绘的只有 `PageBackground` 里的 `ScrollLightHost`
    /// （它自己 `@ObservedObject`）。
    @State private var scrollLight: ScrollLightStore

    /// 显式写 init：避免「私有属性把自动生成的 memberwise init 降级成 private」
    /// 导致跨文件 `RootView()` 编译不过。属性包装器各自用自己的默认值初始化。
    ///
    /// `scrollLight` 走 `State(initialValue:)` 而不是存储属性默认值 ——
    /// 与 `FFWangApp.init()` 里 `RockStore()` 的写法保持一致：`@MainActor` 的类在
    /// View 的属性初始化器位置构造时，隔离上下文在 Swift 5 minimal 检查下不是稳的
    /// （`SurveyStore` 的类型注释里记过这个坑），显式包一层最稳。
    init() {
        _scrollLight = State(initialValue: ScrollLightStore())
    }

    var body: some View {
        tabChrome
        // 详情页全屏覆盖（盖在 Tab 栏之上）：`environmentObject` 显式再注入一遍，
        // 不依赖模态呈现是否继承环境（两行代码换掉一类「找不到 AppModel」的运行期崩溃）。
        // 关闭时清详情状态，避免下次进详情先看到上一篇的正文。
        .fullScreenCover(item: $openedArticle, onDismiss: {
            model.clearArticle()
        }) { article in
            ArticleDetailView(articleId: article.id)
                .environmentObject(model)
        }
        // ⌘, 打开的设置浮层（⌘, 的隐藏按钮挂在 `pageContent` 上，见 `settingsShortcut`）
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        // 沉浸式天光页（3.11.0）。与文章详情一样走 `fullScreenCover`：
        // 这一页要独占全屏（天空铺到状态栏与 Home Indicator 之外），浮动 Tab 栏必须让位。
        // 环境值（`layoutMetrics` / `themeMetrics` / `reduceMotion`）由模态自动继承，
        // 所以这里不重复注入 —— 只有它真的读 `AppModel` 时才需要 `.environmentObject`。
        .fullScreenCover(isPresented: $showsSkyRoom) {
            SkyRoomView()
        }
        .task {
            await model.loadOverview()
        }
        // 红石单独一个 task：与概览的两请求并行，互不阻塞（红石站与博客/简报站是三个域）
        .task {
            await rock.loadSchedule()
        }
        // 天气定位（3.7.0）：进 App 时补一次。
        //
        // 这里**只挂一个 `.task`**（视图出现时跑一次），不放进任何按帧 / 按秒的路径：
        // `refreshIfNeeded()` 内部会在"开关关着"或"坐标还在 6 小时有效期内"时直接短路，
        // 所以默认安装（开关默认关闭）**不会**弹权限框，也不会多一次定位。
        .task {
            // `LocationStore` 是 `@MainActor`，`refreshIfNeeded()` 是主 actor 上的同步方法；
            // 而 `.task` 的闭包是非隔离的 `@Sendable async` —— 这里必须 `await`，
            // 由编译器插一次 hop 到主 actor（对 MainActor 上的同步方法 `await` 合法）。
            // 相邻的两个 `.task`（`model.loadOverview()` / `rock.loadSchedule()`）就是同一写法。
            // 不要包 `Task { }`：那会多一层不带取消语义的嵌套任务。
            await LocationStore.shared.refreshIfNeeded()
        }
        // 深链：桌面小组件点一下 → skyapp://brief / skyapp://rock → 落到对应 Tab。
        //
        // 为什么挂在根视图的 `body` 上就够冷启动也生效：SwiftUI 会在视图进入层级后
        // 把「启动 App 的那个 URL」补发一次 `onOpenURL`。所以冷启动（App 没在跑）与
        // 热启动（App 在后台）走的是**同一条**路径，不需要在 `FFWangApp` 里再存一份待处理的 URL。
        .onOpenURL { url in
            open(deepLink: url)
        }
    }

    // MARK: - Tab 栏（宽档顶部 / 窄档底部）

    /// Tab 栏的两个形态（设计文档 §6.4）。**同一份 `tabs` / `selection` 传给两边**，
    /// 分叉只发生在"挂在屏幕哪条边"上。
    ///
    /// 为什么宽档不用 `NavigationSplitView`：它的 sidebar + detail 是两个常驻视图，
    /// 会让 B3 的"同一时刻只 1 页"变成 2 页，并与 `ScrollLightStore` 的单份 progress、
    /// `AppModel.articleState` 的单例状态直接冲突（设计文档 §7.3 的三条具体冲突）。
    @ViewBuilder
    private var tabChrome: some View {
        if metrics.usesTopTabStrip {
            // 宽档：顶部 44pt 居中胶囊条。**不加底部 inset** —— 底部腾出来的 90pt
            // 正是"viewport 700 → 760"的来源；`pageBottomInset` 3.8.1 起收为 96
            // （底部 Tab 栏压矮、底距收窄，内容底部留白跟着收，见 Spacing.pageBottomInset）
            pageContent
                .safeAreaInset(edge: .top, spacing: 0) {
                    WideTabStrip(tabs: tabBarTabs, selection: tabSelection)
                        // 水平居中：iPadOS 26 的窗口按钮浮在窗口左上角，居中的条让左上角
                        // 保持空白，页面标题在条**下面**一行，两者永远不在同一行打架（§6.3）。
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 6)
                }
        } else {
            // 窄档：今天这条，逐字不动。
            //
            // 限宽 + 居中（设计文档 §2.5）。顺序不能动：
            //
            // `maxWidth` 必须在 `padding(.horizontal, 8)` **之前**。今天栏宽 = 屏宽 − 16；
            // 放在 padding 之后，iPad 上实际栏宽会变成 480 + 16 = 496，且 iPhone 会变成 361（回归）。
            // 放在前面时 393 − 16 = 377 与今天逐像素一致。
            //
            // 限宽只能加在**外部**：`FloatingTabBar` 内部自带 `.frame(maxWidth: .infinity)`，
            // 在里面再塞一个 maxWidth 会和它打架，5 项就不再等分。
            pageContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    FloatingTabBar(tabs: tabBarTabs, selection: tabSelection)
                        .frame(maxWidth: metrics.tabBarWidth)
                        .padding(.horizontal, Spacing.tabBarInset)
                        .padding(.bottom, Spacing.tabBarBottomGap)
                        .padding(.top, 6)
                        // 窄屏下等价于今天的满宽（父级 proposal 本来就等于可用宽度）
                        .frame(maxWidth: .infinity, alignment: .center)
                }
        }
    }

    /// 两个形态共用的 Tab 数据（顺序即视觉顺序）。
    private var tabBarTabs: [TabSpec] {
        return AppTab.tabBarTabs.map { $0.spec }
    }

    /// 页面层：背景 + 当前页 + 滚动光影 + 主题重建 + ⌘, 的隐藏按钮。
    ///
    /// 这一段原来是 `body` 里的 `ZStack` 加上后面几个修饰器，抽成一个属性只为让 `tabChrome`
    /// 能在"顶部 / 底部"两条分支里都套同一份内容 —— 修饰器的**顺序与归属一个都没改**。
    private var pageContent: some View {
        ZStack {
            // 文章列表是阅读页，保持中性（PRD §4.1：光斑只留在概览与简报）
            //
            // `glow` 也随 `tab` 变（只有文章页关灯），所以这块全屏径向渐变同样会被
            // `withAnimation(Motion.tab)` 拖进动画事务里逐帧重算 —— 一起摘掉（原因见 `tabSelection`）。
            PageBackground(glow: tab != .articles)
                .transaction { $0.animation = nil }
            // 条件渲染：同一时刻只有 1 个页面在视图树里（B3）
            //
            // **卡顿修复的唯一一处关键改动**：页面子树不参与动画。
            // `tab` 一变，这里发生的不是"某个东西在移动"，而是「整页销毁 → 新建 → 布局 →
            // 页面内的 `.task` 重启 → 玻璃层重新采样」。把它塞进 `Motion.tab` 那条 spring
            // （response 0.35s ≈ 20 帧）里，等于让主线程在 20 帧内反复为一棵**新建的全屏子树**
            // 求值 —— 16.7ms 一帧的预算装不下，于是掉帧，手感就是用户说的"点着卡卡的"。
            //
            // 页面替换本来就该是瞬时的：用户期待的是"换了一页"，不是"这一页在滑过去"。
            // 所以这里把动画从这条子树上摘掉，而**选中圆的滑动仍然有动画**（见 `tabSelection`）——
            // 后者的代价是同一棵 TabBar 子树里的一个圆，和整页重建不是一个量级。
            //
            // 注意：这里只摘动画，**不动** B3 的"只渲染当前页"设计。5 个页面同时进视图树
            // 会更卡（真玻璃采样层 × 5），那是另一个方向的性能优化，不要为了这个 bug 去改它。
            page(for: tab)
                .transaction { $0.animation = nil }
        }
        // 滚动光影注入（3.6.0）。**挂在整个 ZStack 上，不是挂在 `page(for:)` 上**：
        // 生产者是页面里的 `ScrollView`（5 个页面各挂一个滚动修饰器上报偏移），
        // 消费者是上面那层 `PageBackground`（读 `@Environment(\.scrollLight)` 画光）—— 两者是**兄弟节点**。
        // 只注入页面子树的话，背景层永远拿到 `nil`，光会一动不动（"改了但没效果"）。
        // 挂在这里一次覆盖两者，且 `.transaction { $0.animation = nil }` 一个字都没动。
        .environment(\.scrollLight, scrollLight)
        // 换配色 → 整块重建。挂在 ZStack 上而不是 RootView 上，`tab` 等 @State 不会被重置。
        .id(appearance.themeId)
        // ⌘, 打开设置（设计文档 §7.1）。挂在页面层而不是 Tab 栏上：两条 Tab 栏分支都要有它，
        // 挂在共同祖先上就只有一份。无键盘时零影响（`frame(0,0)` + `opacity(0)`）。
        .settingsShortcut {
            showsSettings = true
        }
    }

    /// 自绘 Tab 栏只认 Int 索引，这里做一次桥接；切换动画统一在 setter 里给。
    ///
    /// **`withAnimation(Motion.tab)` 只该管「选中圆」，不该管「页面」。** 这个 setter 里的
    /// `tab` 同时驱动两件完全不同量级的事：
    ///
    /// 1. `FloatingTabBar` 里选中圆的 `matchedGeometryEffect` —— 圆从旧位置滑到新位置。
    ///    它和 TabBar 是同一棵极小的子树（六个小图标 + 一个圆），每帧求值可以忽略，**必须保留动画**：
    ///    去掉之后圆会硬跳，那正是上一版修掉的观感问题。
    /// 2. `page(for: tab)` 的整页替换 —— B3 条件渲染下这是「销毁一棵全屏子树 + 新建一棵」，
    ///    跟着 spring 走就是每帧为整页求值，必然掉帧。
    ///
    /// 所以分工是：**动画留在圆上（这里），页面侧用 `.transaction { $0.animation = nil }`
    /// 把动画摘掉（`body` 里）**。既不是"去掉 withAnimation"（圆会硬跳），
    /// 也不是"把页面也包进动画"（就是现在的卡顿）。
    ///
    /// `Haptics.light()` 保持同步调用，不做去抖也不挪到异步：它就是一次
    /// `UIImpactFeedbackGenerator.impactOccurred()`，几毫秒内返回，不是卡顿主因。
    /// （旁证：用户说的是"画面卡"，如果触觉是瓶颈，手感和声音会一起延迟 —— 那会描述成"点了没反应"。）
    private var tabSelection: Binding<Int> {
        Binding(
            get: { tab.rawValue },
            set: { newValue in
                guard let next = AppTab(rawValue: newValue), next != tab else { return }
                Haptics.light()
                // 换页先把光影的进度归零（3.6.0）：新页面挂载后会立刻上报自己的位置，
                // 但那之前有一帧背景层还挂着**上一页**的进度 —— 表现是"切页瞬间光斑跳一下"。
                // 放在 `tab = next` 之前：这样"归零"与"新页上报"在同一帧里完成，看不到中间态。
                scrollLight.reset()
                // Reduce Motion（设计文档 §7.6）：只影响「选中圆怎么过去」。
                // 关掉动画时圆硬切到位，用户要的结果（页面已换）完全一样。
                // 不能反过来把 `withAnimation` 整个删掉 —— 那样正常用户也会看到硬切。
                //
                // 页面侧那条 `.transaction { $0.animation = nil }` **不动**：
                // 它本来就是"无动画"（B3 性能点），与 reduceMotion 无关，两者不冲突。
                if reduceMotion {
                    tab = next
                } else {
                    withAnimation(Motion.tab) {
                        tab = next
                    }
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
        case .earnings:
            EarningsView(scrollPosition: scrollBinding(tab))
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

    // MARK: - 深链

    /// 处理小组件深链：解析 host → 切 Tab / 打开天光页。
    ///
    /// 走 `tabSelection` 这个 Binding 而**不是**直接写 `tab = next`：
    /// 触觉反馈与 `withAnimation(Motion.tab)` 都在它的 setter 里，绕过去就会出现
    /// "从桌面点进来，页面是硬切过去的、没有过渡"的割裂感 —— 同一个动作两套体验，
    /// 而且以后调切换动画会有一个人被漏掉。
    ///
    /// `skyapp://sky` 是**唯一**一个不落在 Tab 上的深链（3.11.0）：它全屏呈现 `SkyRoomView`，
    /// 与 Tab 选择互不影响 —— 关掉天光页回到的仍然是进来之前那个 Tab。
    ///
    /// 认不出的 host 一律忽略（不崩、不跳首页）：宁可不响应，也不要因为一个手打错的
    /// URL 把用户从当前页面踢走。
    private func open(deepLink url: URL) {
        guard url.scheme?.lowercased() == AppDeepLink.scheme else { return }

        // `skyapp://brief` 的 host 是 "brief"；也兼容 `skyapp:///brief`（host 为空、path 有值）
        let rawHost = url.host ?? url.path
        let host = rawHost
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        // 天光页：先把可能挂着的文章详情收起来（否则它盖在上面，用户看不到天光页）
        if AppDeepLink.isSky(host) {
            // 守卫 A（入口）：天光页已经在呈现，或者正在呈现的路上 —— 直接放弃本次。
            //
            // `showsSkyRoom` 是真的时候再置一次 true 是纯 no-op（值没变），不会带来
            // 第二次 present；但它也说明"上一次的意图已经被满足了"。这里 return 而不是
            // 继续往下走，是为了不让一次多余的深链把下面 `openedArticle = nil` 的
            // dismiss 也一起触发（用户明明在看天光页，后面的文章详情却在偷偷关掉）。
            guard !showsSkyRoom else { return }

            // 守卫 B（入口）：已经有一轮 present 排在 350ms 窗口里 —— 这一次直接放弃。
            //
            // 不能放行：此刻 `openedArticle` 早就是 nil 了，会掉进下面的 else 立刻
            // `showsSkyRoom = true`，正好撞上正在播的 dismiss 动画 → 被 UIKit 丢掉，
            // 状态位却留在 true；350ms 后排队任务再写一次 true 已是 no-op，
            // 整条链路就卡死在「永远不弹」。排队中的那一次会负责把天光页弹出来，
            // 重复触发不需要也不应该再插一脚。
            guard !skyRoomPending else { return }

            guard openedArticle != nil else {
                showsSkyRoom = true
                return
            }
            // 文章详情正开着：**不能**在同一个 update 里"收起详情 + 立刻 present 天光页"。
            // 两个 fullScreenCover（`$openedArticle` 与 `$showsSkyRoom`）挂在**同一个** RootView
            // 上，详情页还在播 dismiss 动画时立刻 present 第二个，UIKit 会判定
            // 「presenting in progress」并把这次 present 丢掉 —— 表现是"点了小组件深链没反应"，
            // 再点一次又好了（那份动画此时已经播完），是最难查的一类时序 bug。
            // 所以：先置 nil 触发 dismiss，把 present 推到下一个 runloop 并等满系统 dismiss
            // 动画（iOS 全屏 cover 约 350ms）再置 true。
            skyRoomPending = true
            openedArticle = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                // 守卫 C（出队时）：真正 present 之前**再判一次**文章详情是否关干净。
                //
                // 350ms 只是经验值：低端机 / 系统繁忙时 dismiss 动画可能还没播完，
                // 这时硬 present 依旧会被 UIKit 静默丢弃，而状态位一旦写成 true
                // 就再也没机会重来（值不变 = no-op）。所以这里宁可**放弃本次**
                // （清掉 pending，用户再点一下小组件就能正常弹），也不要把状态位写脏、
                // 连累后续所有深链。同理，`openedArticle` 非 nil 也可能是这 350ms 里
                // 用户自己又点开了一篇文章 —— 那就更该让位给用户当前的页面。
                guard openedArticle == nil else {
                    skyRoomPending = false
                    return
                }
                showsSkyRoom = true
                skyRoomPending = false
            }
            return
        }

        guard let target = AppDeepLink.tab(for: host) else { return }

        // 文章详情是全屏覆盖，盖在 Tab 栏之上 —— 不收起它，切 Tab 是"看不到"的
        if openedArticle != nil {
            openedArticle = nil
        }

        tabSelection.wrappedValue = target.rawValue
    }
}

// MARK: - 深链契约（App 侧）

/// App 侧对小组件深链的**唯一**认知：scheme + host → Tab / 全屏页。
///
/// 为什么不复用 Widget 侧的 `WidgetDeepLink`：那个类型属于 Widget target，
/// 主 App 的 sources 明确 `excludes: Widget`（见 project.yml 的 R1 —— 否则两个 @main
/// 会撞成 duplicate symbol），所以 App 引用不到它。两边各留一份，靠
/// `WidgetProvider.swift` 与 `Resources/Info.plist` 里的注释互相指认：
/// **改 scheme / host 必须三处一起改**，否则就是"点了没反应"（不报错、不崩溃）。
private enum AppDeepLink {

    /// 与 `Info.plist` 的 `CFBundleURLSchemes`、`WidgetDeepLink.scheme` 一致
    static let scheme = "skyapp"

    /// 天光页（3.11.0）。**不是 Tab**，走 `RootView.showsSkyRoom` 全屏呈现。
    /// 与 `WidgetDeepLink.skyHost` 逐字一致：天光 / 日弧 / 月相 / 风 四张卡都指向它。
    static let skyHost = "sky"

    /// 这个 host 是不是"打开天光页"
    static func isSky(_ host: String) -> Bool {
        return host == skyHost
    }

    /// host → 落在哪个 Tab。认不出返回 nil（调用方整条忽略）
    static func tab(for host: String) -> AppTab? {
        switch host {
        case "brief":
            return .brief
        case "rock":
            return .rock
        case "earnings":
            return .earnings
        default:
            return nil
        }
    }
}
