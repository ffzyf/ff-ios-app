import SwiftUI
import Foundation

/// 概览首页（Tab 1，PRD §3.1 / 设计文档 T05）。
///
/// 职责边界（这里比 PRD 少一样东西，写清楚免得被当成漏做）：
/// · 本页负责「日期头 + 光遇状态卡 + 快捷入口」三段；
/// · PRD §3.1 第 5 条「今日简报摘要卡」的数据域归简报页（T08）。
///
/// 数据只从 `AppModel` 读（页面绝不自己发请求），Tab 状态由 RootView 通过 `selectedTab` 注入。
///
/// B 批次首页精简（任务 5）：删除「最近写的」区块（连同其整文件、快照属性、变更订阅与同步逻辑、
/// 以及只为它服务的 `onOpenArticle` 参数一并移除）。
/// 首页只留：红石倒计时卡 / 光遇状态卡 / 快捷入口，整体更短更清爽。
struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    /// 红石数据（批次 2 新增）。概览只读它来画置顶倒计时卡，不发任何红石请求
    /// （请求由 `RootView` 的 task 统一发起，页面绝不自己开请求，§7.3）
    @EnvironmentObject private var rock: RockStore
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
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                OverviewHeader(lunar: lunarText) {
                    showsSettings = true
                }
                bodyContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
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
            }
        }
        .refreshable {
            await model.refresh()
        }
        // 全站共享的轻提示（B2 后来源是 ToastStore，这里不传文案即读全局）：
        // 刷新失败不清空内容，只弹这一条（2.5s 自动消失）
        .overlay(alignment: .bottom) {
            PageToast()
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
    }

    // MARK: - 状态分发

    /// 有内容就渲染内容；第一次就失败才整页错误态（PRD §7：错误态不清空已有内容）
    ///
    /// 批次 2：红石倒计时卡**恒定置顶**（P01），哪怕 feed 挂了也先让用户看到"下一场还有多久" ——
    /// 这张卡的数据源与 feed 完全独立（红石站 vs 博客站），没有理由被 feed 的失败连坐。
    @ViewBuilder
    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            // 两张「轨迹卡」恒定占位：红石（自己的请求）+ 简报（自己的请求）。
            // 刻意与 feed 的加载状态解耦 —— feed 慢/挂了，首页上半屏依然是完整的一屏内容，
            // 不会出现"整页灰骨架"（V3.1 返工的核心：骨架只留给还在加载的那一块）。
            RedstoneCountdownCard(onOpenRock: openRock)

            TodayBriefTrackCard(snapshot: model.todayBrief) {
                openBrief()
            }

            if model.hasAnyContent {
                loadedBlocks
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
                // 轻量骨架：只为「版本卡 + 快捷入口」这一块占位（不再整页铺 6 块灰条）。
                // 上半屏两张轨迹卡已经是真实内容，这里只需要把还没到的部分轻轻托住。
                VStack(alignment: .leading, spacing: Spacing.cardGap) {
                    SkeletonBlock(height: 132, cornerRadius: Radius.card)
                    SkeletonBlock(height: 76, cornerRadius: Radius.card)
                }
            }
        }
    }

    private var loadedBlocks: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionGap) {
            SkyStatusCard(status: model.skyStatus) {
                withAnimation(Motion.tab) {
                    selectedTab = .brief
                }
            }
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
            withAnimation(Motion.tab) {
                selectedTab = .articles
            }
        case 1:
            withAnimation(Motion.tab) {
                selectedTab = .brief
            }
        default:
            showsSettings = true
        }
    }

    // MARK: - 派生数据

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
    /// 走现有的 `selectedTab` binding，**不新建导航栈**：根视图是条件渲染的 5 个页面 + 自绘 Tab 栏，
    /// 再塞一个 `NavigationStack` 会让 Tab 栏与页面层级打架（也会把当前页面重新包一层容器）。
    private func openRock() {
        withAnimation(Motion.tab) {
            selectedTab = .rock
        }
    }

    /// 简报轨迹卡点击 → 切到简报 Tab
    private func openBrief() {
        withAnimation(Motion.tab) {
            selectedTab = .brief
        }
    }
}
