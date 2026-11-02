import SwiftUI
import Foundation

/// 概览首页（Tab 1）。
///
/// 版式（设计报告 §4.1）：**1 大 + 1 中 + N 小 + 每组一条横滑**，组间 32 / 组内 12：
/// ```
/// 日期头
/// ─ 32 ─
/// 公告横幅（远程配置下发才有，3.9.0 热更通道）
/// ─ 32 ─
/// 红石 hero 240                    ┐ 组内 12
/// 简报 medium 168                  ┘
/// ─ 32 ─
/// 「今日一览」+ 两张 96 tile
/// ─ 32 ─
/// 「继续读」+ rail 140×188（无文章时整块不渲染）
/// ─ 32 ─
/// 「快捷」+ 3 枚胶囊
/// ```
///
/// 改版动机（报告 §1）：原来一页并存两套组距（12 与 24），三张大卡同宽同高同阴影，
/// 没有 22pt 分区标题、没有横向滚动、没有一张图 —— 空不是块少，是每块"内容占比"低且块间无差。
///
/// 职责边界不变：数据只从 `AppModel` / `RockStore` 读（页面绝不自己发请求），
/// Tab 状态由 `RootView` 通过 `selectedTab` 注入。
struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    /// 尺寸模型（设计文档 §3.2）：概览是**单列**页 —— 一屏一锚点，hero 与简报并排会让
    /// 两个"此刻"互相打架，且 240 与 168 不等高，并排必然一块矮一截。
    @Environment(\.layoutMetrics) private var metrics
    /// 红石数据不再由本页直读：hero 卡自己从环境取 `RockStore`。
    /// 请求仍由 `RootView` 的 task 统一发起（页面绝不自己开请求，§7.3）。
    @Binding private var selectedTab: AppTab
    /// 滚动偏移保活（B3）：由 RootView 持有字典并作为 Binding 注入，切 Tab 回来大致回到原位。
    private let scrollPosition: Binding<ScrollPosition>

    @State private var showsSettings: Bool = false
    /// 沉浸式天光页（3.11.0）。第二张卡（`TodayBriefTrackCard`）的「今日」是它**唯一**的 App 内入口。
    ///
    /// 为什么由本页持有而不是甩给 `RootView`：弹出状态跟着"谁发起"走，
    /// `RootView` 只需要管深链那一条（DESIGN-RULES §4：入口只有两处）。
    @State private var showsSkyRoom: Bool = false

    /// 公告横幅的数据源（3.9.0）。单例直读 + ObservedObject：配置到达时横幅原地出现，
    /// 不需要整页刷新。页面不发请求 —— 拉取由 `FFWangApp` 的 task 统一驱动（§7.3 同一条纪律）。
    @ObservedObject private var config = RemoteConfigStore.shared

    init(selectedTab: Binding<AppTab>, scrollPosition: Binding<ScrollPosition>) {
        self._selectedTab = selectedTab
        self.scrollPosition = scrollPosition
    }

    var body: some View {
        ScrollView {
            // 组间 32：`sectionGapLoose`（= 2.67 × 组内 12），层级靠间距差读出来
            VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
                OverviewHeader(lunar: lunarText) {
                    showsSettings = true
                }
                announcementSlot
                topPair
                loadedBlocks
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
            // 列宽：bento 行只在 rail 档出现（canvas ≥ 1040），此时读画布；否则 720（= 今天）。
            //
            // **不能用 `gridPageWidth`**：它在 canvas 760…1019（834 / 1024 竖屏）也会返回画布，
            // 而概览在那些尺寸上仍然是**单列 720** 的版式（设计文档 §3.2 注：rail 页在
            // rail 不成立时一律退回 single 720）。用 gridPageWidth 会让竖屏的首页正文
            // 从 680 变成 984 宽 —— 一行 60 多个汉字，正是 R9 禁止的事。
            //
            // `railPageWidth` 已经含页边距（宽档 = 1080 + 40），页面里不要再减 40。
            // 窄屏 393 < 720，`maxWidth` 不生效 → 与 3.7.0 逐像素一致。
            .pageColumn(metrics.railPageWidth)
        }
        .scrollPosition(scrollPosition)
        .pageScrollLight()
        .scrollIndicators(.hidden)
        // PRD §5.2「离线（有缓存）」：有内容但这次刷新失败 → 顶部细条。
        // 用 `safeAreaInset` 而不是 overlay：细条占据自己的高度，不压住标题、不遮内容。
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsOfflineBanner {
                OfflineBanner()
                    .padding(.horizontal, Spacing.page)
                    .padding(.bottom, 6)
                    // 细条与主体同列宽。**照抄 body 里那条表达式**而不是写死 720：
                    // 写死会让宽档（画布 1080）的胶囊比内容列窄 360、左右各缩进 180，
                    // 变成一条"没对齐"的横杠。窄屏 720 > 393，`maxWidth` 不生效 → 零影响。
                    .pageColumn(metrics.railPageWidth)
            }
        }
        .refreshable {
            await model.refresh()
        }
        // ⌘R（设计文档 §7.1）：走的就是下拉刷新同一个方法，不另开一条请求路径 ——
        // 两条路径会让"下拉能刷出来、⌘R 刷不出来"这种差异成为可能。
        .refreshShortcut {
            Task { await model.refresh() }
        }
        // 全站共享的轻提示（B2 后来源是 ToastStore，这里不传文案即读全局）
        .overlay(alignment: .bottom) {
            PageToast()
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        // 天光页（3.11.0）：全屏呈现，环境值（layoutMetrics / reduceMotion）由模态继承
        .fullScreenCover(isPresented: $showsSkyRoom) {
            // 同上：把简报快照带进去，朗读才有"宜/忌"可念
            SkyRoomView(brief: model.todayBrief)
        }
    }

    // MARK: - 公告横幅

    /// 远程配置下发的公告（3.9.0）。announcement 缺失 / 已被本 revision 关闭时整条不渲染
    /// —— 首页版式回到与 3.8.x 逐行一致，横幅是"叠加项"而不是"占位项"。
    @ViewBuilder
    private var announcementSlot: some View {
        if let announcement = config.latest?.values?.announcement,
           announcement.title.isEmpty == false || announcement.body.isEmpty == false {
            AnnouncementBanner(
                announcement: announcement,
                revision: config.latest?.revision ?? 0
            )
        }
    }

    // MARK: - 首屏两张主卡（同一组）

    /// hero + medium：它们回答同一件事（"此刻"），所以组内 12、不与下一组等距。
    ///
    /// 两张卡**恒定渲染**、与 feed 的加载状态解耦 —— feed 慢或挂了，首页上半屏依然是完整内容，
    /// 不会出现"整页灰骨架"（红石卡的数据源与 feed 完全不同域，没有理由被连坐）。
    ///
    /// **宽档（rail / bento）改横排**：712 的大卡 + 344 的右栏（设计文档 §4.1）。
    /// 分叉只有这一处，两个分支里的卡片、组件、动作全部是同一批定义 —— 宽档改的是"谁在谁旁边"，
    /// 不是"再写一套首页"。窄档分支与 3.7.0 逐字一致（纵向 hero 240 + medium 168）。
    ///
    /// 判据用 `usesRail` 而不是 `gridColumns == 3`：概览的 bento 行只在"画布 ≥ 1040"时成立，
    /// 1020…1039 那条窄带里它按 §3.2 的约定退回单列（与红石 / 简报 / 更多一致）。
    @ViewBuilder
    private var topPair: some View {
        if metrics.usesRail {
            HStack(alignment: .top, spacing: Layout.gridGutter) {
                RedstoneCountdownCard(tier: .hero, onOpenRock: openRock)
                    // 712 由"344×2 + 24"推出来，但这里用 `maxWidth: .infinity` 让它自己吃掉
                    // 剩余宽度：1020…1039 那条窄带里列宽不是 344，写死 712 会横向溢出被裁。
                    .frame(maxWidth: .infinity)
                overviewSideColumn
                    // 高度给死 344（= `cardHeight(.hero)`）：
                    // ① 右栏里的简报卡用 `maxHeight: .infinity` 撑满剩余空间（168 → 172），
                    // ② 左右两块底边因此严格齐平，不需要任何 `Spacer` / 测量。
                    // 不给高度的话，`ScrollView` 里 `HStack` 拿到的是"高度未定"的 proposal，
                    // 右栏只会按内容自然高排，简报卡撑不到 172、底边差 4–8pt。
                    .frame(
                        width: metrics.gridColumnWidth,
                        height: metrics.cardHeight(.hero),
                        alignment: .top
                    )
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                RedstoneCountdownCard(tier: .hero, onOpenRock: openRock)

                TodayBriefTrackCard(snapshot: model.todayBrief) {
                    openSkyRoom()
                }
            }
        }
    }

    /// grid3 档 Row A 的右栏：简报摘要（168 → 172，被拉伸）+「今日一览」两张 tile。
    ///
    /// 172 + 12 + 40（分区标题）+ 120（tile）= 344 = hero 高 —— 这是"两个数字来自同一张栅格"
    /// 的直接结果（设计文档 §4.1），不是凑出来的。
    private var overviewSideColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            TodayBriefTrackCard(snapshot: model.todayBrief) {
                openSkyRoom()
            }
            .frame(maxHeight: .infinity)

            versionsSection
        }
    }

    // MARK: - 状态分发

    /// 有内容就渲染内容；第一次就失败才整页错误态（PRD §7：错误态不清空已有内容）
    @ViewBuilder
    private var loadedBlocks: some View {
        if model.hasAnyContent {
            VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
                // 「今日一览」在 grid3 档被搬进 Row A 的右栏（它现在与 hero 同一行），
                // 这里就不再重复渲染一次 —— 同一屏出现两组完全相同的版本 tile 是最典型的"半成品"。
                if showsVersionsInline {
                    versionsSection
                }
                if continueReadingArticles.isEmpty == false {
                    continueReadingSection
                }
                quickSection
            }
        } else if let error = firstError {
            ErrorStateView(
                icon: error.icon,
                title: error.title,
                message: error.hint,
                onRetry: {
                    Task { await model.refresh() }
                }
            )
        } else {
            // 轻量骨架：只托住还没到的分区，不再整页铺 6 块灰条。
            // 高度走 `cardHeight(.tile)`：宽档是 120，与最终渲染出来的 tile 等高，收起时不跳。
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                SkeletonBlock(height: metrics.cardHeight(.tile), cornerRadius: Radius.card)
                SkeletonBlock(height: metrics.cardHeight(.tile), cornerRadius: Radius.card)
            }
        }
    }

    /// 「今日一览」留在正文流里吗？bento 档它在 Row A 的右栏里。
    private var showsVersionsInline: Bool {
        return !metrics.usesRail
    }

    /// 「今日一览」：两张 96 tile（原 `SkyStatusCard` 整卡留给简报页）
    private var versionsSection: some View {
        // spacing 0：`SectionHeader` 自带 12pt 下距，这里再加一次会变成 24（等于又造一套组距）
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "今日一览", actionTitle: "全部", action: openBrief)
            VersionTileRow(status: model.skyStatus, onTap: openBrief)
        }
    }

    /// 「继续读」：**窄档横滑 rail / 宽档 3 列网格**，同一份数据、同一个入口。
    ///
    /// 为什么宽档不继续用 rail：140×188 的竖卡在 1080 的画布上一行只放 6 张、还露出半张，
    /// 而它横向只看得到 8 篇里的 4 篇 —— 屏幕宽了 3 倍、信息量却没变（设计文档 §1.1 的"唯一没退化的一块"）。
    /// 换成 3 列 344×116 的列表卡，一行 3 篇、两行 6 篇，是高宽比 2.97:1（≈ iPhone 的 3.04:1）。
    ///
    /// **没有文章就整块不渲染** —— 宁可少一组，不画空卡。
    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "继续读", actionTitle: "更多", action: openArticles)
            if metrics.usesRail {
                LazyVGrid(
                    columns: continueReadingColumns,
                    alignment: .leading,
                    // 行距用 12（组内节奏），栏距由 `GridItem.spacing` 给 24（栅格）。
                    // 两个方向本来就不同：栅格是"画布怎么切"，行距是"同组内两张卡隔多远"。
                    spacing: Spacing.cardGap
                ) {
                    ForEach(continueReadingArticles) { article in
                        ArticleRowCard(article: article) {
                            openArticles()
                        }
                    }
                }
            } else {
                // 出血只对"列宽 = 屏宽"成立。宽屏列宽 720 < 1194，继续出血会让卡片滑到列外
                // 压在空白上（§4.3），所以由 `allowsRailBleed` 决定。窄屏它恒为 true → 与今天一致。
                Rail(bleeds: metrics.allowsRailBleed) {
                    ForEach(continueReadingArticles) { article in
                        ArticleRailCard(article: article) {
                            openArticles()
                        }
                    }
                }
            }
        }
    }

    /// 3 列网格的列定义（栏距 24 = `Layout.gridGutter`，对齐 1080 = 344×3 + 24×2）
    private var continueReadingColumns: [GridItem] {
        return Array(
            repeating: GridItem(.flexible(), spacing: Layout.gridGutter),
            count: 3
        )
    }

    /// 「快捷」：分组标题 + 3 枚胶囊（组件保留不动，只升格进分组）
    private var quickSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "快捷")
            QuickEntryRow(entries: quickEntries, onSelect: handleQuickEntry)
        }
    }

    // MARK: - 快捷入口

    private var quickEntries: [QuickEntry] {
        return [
            QuickEntry(id: 0, title: "全部文章", icon: "doc.text"),
            QuickEntry(id: 1, title: "光遇简报", icon: "bell.badge"),
            QuickEntry(id: 2, title: "关于", icon: "gearshape")
        ]
    }

    private func handleQuickEntry(_ entry: QuickEntry) {
        switch entry.id {
        case 0:
            openArticles()
        case 1:
            openBrief()
        default:
            showsSettings = true
        }
    }

    // MARK: - 派生数据

    /// 「继续读」的数据源：横滑 8 篇 / bento 3 列网格 6 篇（2 行 × 3）。
    ///
    /// 为什么不是全量：rail 是"看看还有什么"的入口，不是列表页；
    /// 全量塞进 `LazyHStack` 会让首帧多算几十个 `CoverArt`（每个都带 Canvas 噪点）。
    /// 宽档取 6 而不是 8：3 列网格里 8 篇会留一行只有 2 格的"半行"，比少两篇更显眼。
    private var continueReadingArticles: [ArticleSummary] {
        return Array(model.articles.prefix(metrics.usesRail ? 6 : 8))
    }

    /// 农历 / 节气副行：取不到就返回 nil，整行不占位（PRD §3.1 第 3 条）
    private var lunarText: String? {
        guard let brief = model.todayBrief else { return nil }
        guard let lunar = brief.lunar else { return nil }
        let trimmed = lunar.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var firstError: APIError? {
        if let error = model.feedState.error {
            return error
        }
        return model.briefState.error
    }

    /// PRD §5.2「离线（有缓存）」：手里有内容，但这次 feed 请求失败了（内容没被清空）。
    /// 不直接看 `feedState.error`：`.loaded` 与 `.failed` 互斥，有内容时它恒为 nil。
    private var showsOfflineBanner: Bool {
        return model.feedState.hasContent && model.lastFeedError != nil
    }

    // MARK: - 动作

    /// 倒计时卡点击 → 切到红石 Tab。
    ///
    /// 走现有的 `selectedTab` binding，**不新建导航栈**：根视图是条件渲染的 6 个页面 + 自绘 Tab 栏，
    /// 再塞一个 `NavigationStack` 会让 Tab 栏与页面层级打架。
    private func openRock() {
        withAnimation(Motion.tab) {
            selectedTab = .rock
        }
    }

    /// 简报轨迹卡 / 版本 tile 点击 → 切到简报 Tab
    private func openBrief() {
        withAnimation(Motion.tab) {
            selectedTab = .brief
        }
    }

    /// 天光卡点击 → 全屏打开天光页（3.11.0）。
    ///
    /// 不走 `withAnimation(Motion.tab)`：这不是切 Tab，是一次模态呈现 ——
    /// 给它套 Tab 的弹簧只会让"弹出"多一层与本页无关的位移。
    private func openSkyRoom() {
        showsSkyRoom = true
    }

    /// rail 卡 / 「全部文章」→ 切到文章 Tab。
    ///
    /// 文章详情是 `RootView` 的全屏覆盖，入口只接受 `ArticleSummary`；
    /// 首页没有详情入口（B 批次已删掉那套参数），所以这里落到列表页而不是"假装打开详情"。
    private func openArticles() {
        withAnimation(Motion.tab) {
            selectedTab = .articles
        }
    }
}
