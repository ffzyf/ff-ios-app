import SwiftUI
import Foundation

/// 红石日历（Tab 2 主页面，P04）。
///
/// 结构：标题 + 攻略入口 → 「下一场」条 → 翻月器 → 月历网格 → 「本月分布」折叠图 → 规律入口。
/// 数据全部来自 `RockStore`（页面不发请求，§7.3 唯一入口）。`gridBody` 的状态优先级是
/// **有响应 > 空月 > 加载/失败**：弱网下翻月不会把已经在看的月份闪成骨架屏（PRD §7）。
struct RockCalendarView: View {
    @EnvironmentObject private var rock: RockStore
    @EnvironmentObject private var guide: RockGuideStore

    /// 当前弹层。用**一个** sheet 装两种内容（某天场次 / 规律说明）：
    /// 同一个视图上挂两个 `.sheet` 在 iOS 上容易互相顶掉，改成一个 `item` 派发最稳。
    @State private var activeSheet: RockSheet?
    @State private var showsGuide: Bool = false

    /// 显式空 init：`@State` / `@EnvironmentObject` 是 private 存储属性，会把自动生成的
    /// memberwise init 降级成 private，跨文件 `RockCalendarView(scrollPosition:)` 就编译不过（同 `RootView`）。
    let scrollPosition: Binding<ScrollPosition>

    init(scrollPosition: Binding<ScrollPosition>) {
        self.scrollPosition = scrollPosition
    }

    var body: some View {
        ScrollView {
            // 组间 32 / 组内 12：改版前 6 个块全部 `cardGap 12` 等距平铺，
            // 月历（336pt）与 32pt 高的翻月器被同样对待，重块被轻块夹住（设计报告 §3.2）
            VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
                header
                NextEventBar(days: rock.allLoadedDays)
                monthGroup
                distributionGroup
                rulesGroup
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
        }
        .scrollPosition(scrollPosition)
        .scrollIndicators(.hidden)
        // 顶部细条占自己的高度，不压标题、不遮内容（与概览页同一手法）
        .safeAreaInset(edge: .top, spacing: 0) {
            bannerArea
        }
        .refreshable {
            await rock.refresh()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .day(let day):
                RedstoneDaySheet(day: day)
            case .rules:
                RockRulesView(rules: rock.rules, usesFallback: rock.rulesFallback)
            }
        }
        .fullScreenCover(isPresented: $showsGuide) {
            // 显式再注入一次环境对象：不依赖模态呈现是否继承（与文章详情同一约定）
            RockGuideView()
                .environmentObject(guide)
        }
        .task {
            await rock.loadSchedule()
            await rock.loadRules()
        }
    }

    // MARK: - 标题

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("红石")
                    .font(Typography.display)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.light()
                showsGuide = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("攻略")
                        .font(Typography.footnoteMedium)
                }
                .foregroundStyle(Theme.limeInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassSurface(.floating, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("打开攻略")
        }
    }

    private var subtitle: String {
        if let ranges = rock.visibleResponse?.coveredRanges {
            let trimmed = ranges.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return "已生成 " + trimmed }
        }
        return "月历 · 场次 · 规律"
    }

    // MARK: - 分组

    /// 「本月」组：分区标题 + 翻月器（塞进标题右侧插槽）+ 月历。
    ///
    /// 翻月器原来独立占一行 40pt、前后各 12pt，白白吃掉一屏的 64pt；
    /// 塞进插槽之后，它和"本月"这个标题说的是同一件事，也就该在同一行（报告 §4.2）。
    private var monthGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            // `SectionHeader` 自带 12pt 下距，所以只用 spacing 0 的 VStack 就是"标题 + 12 + 内容"
            SectionHeader(title: "本月") {
                monthSwitcher
            }

            if showsMonthEmptyNote {
                Text("本月排期尚未生成")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.bottom, Spacing.gridUnit)
            }

            gridCard
        }
    }

    /// 「本月分布」组：折叠图从"和月历同级的一张卡"降级成月历之后的第二层信息。
    ///
    /// 分区标题写「场次分布」而不是「本月分布」：卡内那一行本身就是展开开关（写的是「本月分布」），
    /// 分区标题若与它同名，同一句话上下相距 30pt 出现两次会被读成 bug。
    /// 「场次」这个词来自本页副标题（月历 · 场次 · 规律），不是新造的区块名。
    private var distributionGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "场次分布")
            MonthDistributionCard(days: rock.visibleDays)
        }
    }

    /// 「规律」组：原来是一行没有归属的 `GlassListRow`，现在给它一个 22pt 的分区标题。
    /// 同样不同名重复：行内写的是「为什么是这天？」，分区说清"这是一组规律说明"就够。
    private var rulesGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "规律")
            rulesRow
        }
    }

    // MARK: - 翻月

    /// 翻月器（现在住在「本月」的右侧插槽里，所以去掉了两端 `Spacer` 与整行高度）
    private var monthSwitcher: some View {
        HStack(spacing: 8) {
            monthArrow(icon: "chevron.left", enabled: rock.canShiftBackward, offset: -1, label: "上个月")
            Text(Formatters.monthTitle(rock.visibleMonth))
                // 17pt：它紧挨着 22pt 的分区标题，再大就变成"两个标题"
                .font(Typography.titleS)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
            monthArrow(icon: "chevron.right", enabled: rock.canShiftForward, offset: 1, label: "下个月")
        }
    }

    /// 只有"明确拿到了这个月但一条都没有"时才提示；加载中不提示（否则会闪一下）
    private var showsMonthEmptyNote: Bool {
        guard let response = rock.visibleResponse else { return false }
        return response.items.isEmpty
    }

    private func monthArrow(icon: String, enabled: Bool, offset: Int, label: String) -> some View {
        Button {
            Haptics.selection()
            withAnimation(Motion.tab) {
                rock.shiftMonth(by: offset)
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                // 不可用时只靠颜色区分：`.opacity()` 只允许作用在 `Theme.*` token 上
                // （PRD §3.4：透明度只能出现在 Theme 的 dyn/dyna 里），所以这里不再叠一层透明度
                .foregroundStyle(enabled ? Theme.textSecondary : Theme.textTertiary)
                .frame(width: 32, height: 32)
                .background { Circle().fill(Theme.surfaceTint2) }
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: - 月历

    private var gridCard: some View {
        GlassCard(level: .card) {
            gridBody
                .padding(Spacing.cardPadding)
        }
    }

    @ViewBuilder
    private var gridBody: some View {
        if let response = rock.visibleResponse {
            if response.items.isEmpty {
                RockMonthStateView(
                    mode: .empty,
                    onShowRules: { activeSheet = .rules },
                    onReturnCurrent: returnCurrentAction
                )
            } else {
                RedstoneMonthGrid(
                    monthKey: rock.visibleMonth,
                    days: response.items,
                    todayKey: RedstoneClock.dayKey(Date())
                ) { day in
                    activeSheet = .day(day)
                }
            }
        } else if let error = rock.lastError, !rock.isLoading {
            RockMonthStateView(
                mode: .failed(error),
                onRetry: { Task { await rock.loadSchedule(month: rock.visibleMonth, force: true) } }
            )
        } else {
            RockMonthStateView(mode: .loading)
        }
    }

    /// 「回到本月」的动作；当前就在本月时返回 nil（按钮不渲染）。
    /// 不用三元表达式内联一个闭包：`cond ? nil : { … }` 在上下文里推断 `(() -> Void)?` 容易失败。
    private var returnCurrentAction: (() -> Void)? {
        guard rock.visibleMonth != rock.currentMonthKey else { return nil }
        return { rock.returnToCurrentMonth() }
    }

    // MARK: - 规律入口

    private var rulesRow: some View {
        GlassListRow(
            icon: "questionmark.circle",
            title: "为什么是这天？",
            detail: rulesDetail
        ) {
            activeSheet = .rules
        }
    }

    private var rulesDetail: String? {
        guard let version = rock.rules?.version else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : "v" + trimmed
    }

    // MARK: - 顶部细条

    @ViewBuilder
    private var bannerArea: some View {
        if rock.isOffline {
            OfflineBanner(kind: .offline)
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, 6)
        } else if rock.isDataOld {
            OfflineBanner(kind: .staleData, text: "排期已有些天数没更新，先按现在的看。")
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, 6)
        } else if let warning = rock.warningText {
            OfflineBanner(kind: .staleData, text: warning)
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, 6)
        }
    }
}

/// 红石页的两种弹层。`Identifiable` 的 id 必须是稳定的字符串：
/// 用 `item:` 驱动的 sheet 会在 id 变化时重建内容，用日期/常量拼最直观。
enum RockSheet: Identifiable {
    case day(RedstoneDay)
    case rules

    var id: String {
        switch self {
        case .day(let day): return "day-" + day.date
        case .rules: return "rules"
        }
    }
}
