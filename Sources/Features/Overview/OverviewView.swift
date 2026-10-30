import SwiftUI
import Foundation

/// 概览首页（Tab 1，PRD §3.1 / 设计文档 T05）。
///
/// 职责边界（这里比 PRD 少一样东西，写清楚免得被当成漏做）：
/// · 本页负责「日期头 + 光遇状态卡 + 最近写的 + 快捷入口」四段；
/// · PRD §3.1 第 5 条「今日简报摘要卡」的数据域归简报页（T08）。做一张假占位卡比不做更糟
///   （用户会以为数据坏了），所以本批不画，等 T08 的 `BriefView` 落地后由主理人决定放哪。
///
/// 数据只从 `AppModel` 读（页面绝不自己发请求），Tab 状态由 RootView 通过 `selectedTab` 注入。
struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @Binding private var selectedTab: AppTab
    private let onOpenArticle: (ArticleSummary) -> Void

    @State private var showsSettings: Bool = false
    /// 「最近写的」快照：只认 feed 第 1 页。列表页翻页后 `feedState.articles.page` 会涨到 N，
    /// 首页不该跟着换成第 N 页的内容（否则会出现很早的文章），所以这里按页码守住快照。
    @State private var latest: [ArticleSummary] = []

    init(selectedTab: Binding<AppTab>, onOpenArticle: @escaping (ArticleSummary) -> Void) {
        self._selectedTab = selectedTab
        self.onOpenArticle = onOpenArticle
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
        // 全站共享的轻提示：刷新失败不清空内容，只弹这一条（1.8s 自动消失）
        .overlay(alignment: .bottom) {
            PageToast(message: model.toastMessage)
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        .onChange(of: articleIDs) { _, _ in
            syncLatest()
        }
        .onAppear {
            syncLatest()
        }
    }

    // MARK: - 状态分发

    /// 有内容就渲染内容；第一次就失败才整页错误态（PRD §7：错误态不清空已有内容）
    @ViewBuilder
    private var bodyContent: some View {
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
            SkeletonHome()
        }
    }

    private var loadedBlocks: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionGap) {
            SkyStatusCard(status: model.skyStatus) {
                withAnimation(Motion.tab) {
                    selectedTab = .brief
                }
            }
            LatestArticlesSection(
                articles: latest,
                onSelect: onOpenArticle,
                onOpenAll: {
                    withAnimation(Motion.tab) {
                        selectedTab = .articles
                    }
                }
            )
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

    /// 用于 `onChange` 判定的轻量指纹：只比 id，不比整个模型（`LoadState` 不是 `Equatable`）
    private var articleIDs: [String] {
        return model.articles.map { $0.id }
    }

    private var feedPage: Int {
        guard let feed = model.feedState.value else { return 1 }
        return feed.articles.page
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

    private func syncLatest() {
        // 只在第 1 页时认账；翻页造成的第 N 页结果一律忽略
        guard feedPage <= 1 else { return }
        latest = Array(model.articles.prefix(2))
    }
}
