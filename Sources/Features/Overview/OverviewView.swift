import SwiftUI
import Foundation

/// 概览首页（Tab 1）。
///
/// 版式（设计报告 §4.1）：**1 大 + 1 中 + N 小 + 每组一条横滑**，组间 32 / 组内 12：
/// ```
/// 日期头
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
                topPair
                loadedBlocks
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
            // 列宽 720 居中（含 page padding 20×2 → 文字 680）。
            // 挂在最外层：`Spacing.page` 是"列边距"的一部分，720 必须把它算在里面，
            // 否则 iPad 上文字会变成 720 − 40 = 680 之外再被裁一次。
            // 窄屏 393 < 720，`maxWidth` 不生效 —— 与 3.4.0 逐像素一致。
            .pageColumn(Layout.contentMaxWidth)
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
                    // 细条与主体同列宽（720 含 page padding 20×2 = 680 的胶囊）。
                    // 细条本身是 `.frame(maxWidth: .infinity)` 的胶囊，不吃列宽的话
                    // iPad 上它会比下面的内容列宽出整整 (1194 − 40) − 680，左右各探出一大截。
                    // 窄屏 393 < 720，`maxWidth` 不生效 → 与今天逐像素一致。
                    .pageColumn(Layout.contentMaxWidth)
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
    }

    // MARK: - 首屏两张主卡（同一组）

    /// hero + medium：它们回答同一件事（"此刻"），所以组内 12、不与下一组等距。
    ///
    /// 两张卡**恒定渲染**、与 feed 的加载状态解耦 —— feed 慢或挂了，首页上半屏依然是完整内容，
    /// 不会出现"整页灰骨架"（红石卡的数据源与 feed 完全不同域，没有理由被连坐）。
    private var topPair: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            RedstoneCountdownCard(tier: .hero, onOpenRock: openRock)

            TodayBriefTrackCard(snapshot: model.todayBrief) {
                openBrief()
            }
        }
    }

    // MARK: - 状态分发

    /// 有内容就渲染内容；第一次就失败才整页错误态（PRD §7：错误态不清空已有内容）
    @ViewBuilder
    private var loadedBlocks: some View {
        if model.hasAnyContent {
            VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
                versionsSection
                if railArticles.isEmpty == false {
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
            // 轻量骨架：只托住还没到的分区，不再整页铺 6 块灰条
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                SkeletonBlock(height: CardTier.tile.height, cornerRadius: Radius.card)
                SkeletonBlock(height: CardTier.tile.height, cornerRadius: Radius.card)
            }
        }
    }

    /// 「今日一览」：两张 96 tile（原 `SkyStatusCard` 整卡留给简报页）
    private var versionsSection: some View {
        // spacing 0：`SectionHeader` 自带 12pt 下距，这里再加一次会变成 24（等于又造一套组距）
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "今日一览", actionTitle: "全部", action: openBrief)
            VersionTileRow(status: model.skyStatus, onTap: openBrief)
        }
    }

    /// 「继续读」：横向 rail。**没有文章就整块不渲染** —— 宁可少一组，不画空卡
    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "继续读", actionTitle: "更多", action: openArticles)
            // 出血只对"列宽 = 屏宽"成立。宽屏列宽 720 < 1194，继续出血会让卡片滑到列外
            // 压在空白上（§4.3），所以由 `allowsRailBleed` 决定。窄屏它恒为 true → 与今天一致。
            Rail(bleeds: metrics.allowsRailBleed) {
                ForEach(railArticles) { article in
                    ArticleRailCard(article: article) {
                        openArticles()
                    }
                }
            }
        }
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

    /// 「继续读」的数据源：已加载文章的前 8 篇。
    ///
    /// 只取 8 篇而不是全量：rail 是"看看还有什么"的入口，不是列表页；
    /// 全量塞进 `LazyHStack` 会让首帧多算几十个 `CoverArt`（每个都带 Canvas 噪点）。
    private var railArticles: [ArticleSummary] {
        return Array(model.articles.prefix(8))
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
