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
    /// 尺寸模型（设计文档 §3.3）：红石是三个会做两列的页面之一 ——
    /// 月历是 7 列网格，拉宽只让格子变胖；右侧 368 恰好放"下一场／分布／规律"。
    @Environment(\.layoutMetrics) private var metrics

    /// 当前弹层。用**一个** sheet 装两种内容（某天场次 / 规律说明）：
    /// 同一个视图上挂两个 `.sheet` 在 iOS 上容易互相顶掉，改成一个 `item` 派发最稳。
    @State private var activeSheet: RockSheet?
    @State private var showsGuide: Bool = false
    /// 主列实测高度。副列要撑到同一高度，里面的 `Spacer(minLength: 32)` 才吸得到差额
    /// （理由见 `View.measureHeight(into:)` 的注释）。首帧为 0 = 按内容自然高。
    @State private var mainColumnHeight: CGFloat = 0

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
                pageGroups
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
            // 列宽：rail 档 = 画布 1080 + 页边距 40（主列 680 / 栏距 32 / 副列 368），
            // 否则 = 720（= 今天，834 竖屏 / 1024 竖屏 / 所有 compact 尺寸都走这条）。
            // `railPageWidth` 已经含页边距，页面里不再加 `+ Spacing.page * 2`（加了主列会宽 40、
            // 月历 7 格每格多 5pt，副列被挤出画布）。
            .pageColumn(metrics.railPageWidth)
        }
        .scrollPosition(scrollPosition)
        .pageScrollLight()
        .scrollIndicators(.hidden)
        // 顶部细条占自己的高度，不压标题、不遮内容（与概览页同一手法）
        .safeAreaInset(edge: .top, spacing: 0) {
            bannerArea
        }
        .refreshable {
            await rock.refresh()
        }
        // ⌘R：与下拉刷新同一个方法，不另开请求路径
        .refreshShortcut {
            Task { await rock.refresh() }
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

    // MARK: - 分组排布（单列 / rail）

    /// rail 档的写法：**同一个 body 里分支**，不复制两份布局。
    ///
    /// 四个分组各自只是一个属性，定义只有一份；这里分叉的只有"谁在谁上面"这件事 ——
    /// 而这正是宽屏真正要改的东西（宽屏把「下一场／今日场次／分布／规律」从月历**下面**
    /// 搬到**右边**，并补一组今天还没有过场次的场内清单）。
    ///
    /// 窄屏分支的视图顺序、间距与 3.7.0 完全一致：下一场 → 月历 → 分布 → 规律。
    /// 顺序写反（比如把 `nextEventBar` 放到 `monthGroup` 之后）是这一页最隐蔽的回归 ——
    /// 因为它依然"看起来正常"，只是信息层级被悄悄换了。
    @ViewBuilder
    private var pageGroups: some View {
        if metrics.usesRail {
            HStack(alignment: .top, spacing: Layout.columnGap) {
                monthGroup
                    // 主列宽 = 画布 − 栏距 − 副列 = 680（从画布算，不写死：
                    // Stage Manager 拖到 1100 时主列自动变窄，副列才不会被挤出画布）。
                    // 用 `maxWidth` 而不是 `width`：不足时也不会横向溢出被裁。
                    .frame(maxWidth: metrics.railMainWidth)
                    .measureHeight(into: $mainColumnHeight)
                sideColumn
                    .frame(width: Layout.sideColumnWidth)
                    // 高度跟主列走，`Spacer` 才吸得到差额（见 `sideColumnHeight` 的注释）。
                    // 用 `minHeight` 而不是 `height`：副列内容比主列高时（红石今天 4 场，
                    // 副列 500 > 主列 481）固定高度会把最后一组顶出卡片；`minHeight` 让它在
                    // 内容更高时自然长高、更矮时仍然撑到主列高度（`Spacer` 吃差额、底边齐平）。
                    .frame(minHeight: sideColumnHeight, alignment: .top)
            }
        } else {
            nextEventBar
            monthGroup
            distributionGroup
            rulesGroup
        }
    }

    /// 副列高度：量到主列才给值，首帧（0）给 `nil` = 按内容自然高。
    ///
    /// 为什么不写死 481（设计文档给的"主列 481"）：月历行数随月份变（10 月是 5 行、11 月是 6 行），
    /// 写死会让 5 行的月份右下角空出 64pt、6 行的月份把「规律」压出画布。
    private var sideColumnHeight: CGFloat? {
        return mainColumnHeight > 0 ? mainColumnHeight : nil
    }

    /// 宽档副列：`NextEventBar` → 「今日场次」→ 分布 → `Spacer` → 规律（设计文档 §4.2）。
    ///
    /// `Spacer(minLength: 32)` 放在"会变长的内容"之后、最后一组之前：副列比主列短时它吃掉差额、
    /// 把「规律」压到与月历同底；副列更长时它只吸不放（不生效），此时主列底部留白。
    /// 这就是"右下角漏一块"被修掉的地方 —— 不塞东西，只把最后一组压到底边。
    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
            nextEventBar
            RockTodayColumn(day: todayRow)
            distributionGroup
            Spacer(minLength: Layout.columnGap)
            rulesGroup
        }
    }

    /// 侧栏「今日场次」的数据：**今天那一条**（`visibleDays` 里通常只有今天一天是"当天"）。
    /// 取不到（那个月还没加载 / 今天没排期）→ 组件整块不渲染，副列由 `Spacer` 把规律压到底。
    private var todayRow: RedstoneDay? {
        let todayKey = RedstoneClock.dayKey(Date())
        return rock.visibleDays.first { $0.date == todayKey }
    }

    /// 单独提出来是为了让"窄屏 / 宽屏两条路径引用同一个定义"，
    /// 而不是在 `pageGroups` 里各写一遍 `NextEventBar(days: rock.allLoadedDays)`。
    private var nextEventBar: some View {
        NextEventBar(days: rock.allLoadedDays)
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
        // ⌘← / ⌘→ 翻月（设计文档 §7.1）。挂在既有 Button 上、不新增视图 ——
        // 翻月本来就是"左右"这件事，方向键是最不需要记的映射。
        // 用 `offset` 决定方向而不是再传一个参数：两处（左/右）各调一次，
        // 多一个参数就多一处可以让"图标向左、快捷键向右"的错配活下来的地方。
        // `.disabled(!enabled)` 对快捷键同样生效：到头了按 ⌘→ 不会有任何反应。
        .keyboardShortcut(offset < 0 ? .leftArrow : .rightArrow, modifiers: .command)
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
                    todayKey: RedstoneClock.dayKey(Date()),
                    // 宽档格子 64 高（7 格各 88.3×64，1.38:1）：560→680 带来的是格宽 +17，
                    // 只加宽不加高会让格子从 1.27:1 变成 1.38:1 的"扁片"，
                    // 高度跟着 +8 才是"同一块格子变大了"（设计文档 §4.2）。
                    cellHeight: metrics.usesRail ? 64 : 56
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

    /// 顶部细条要与主体同列宽：主体在 `pageColumn` 里限到画布（rail 档 1120 / 单列 720），
    /// 而细条是 `.frame(maxWidth: .infinity)` 的胶囊、挂在 `safeAreaInset` 上拿的是满宽 ——
    /// 不吃列宽的话 iPad 上它会比内容列宽一大截、左右各探出一块。
    /// 直接引用 `metrics.railPageWidth`（它就是 body 里那个实参），不再手写一遍表达式：
    /// 手写的那一份在这次改版里已经和 body 漂过一次（960 vs 1080）。
    /// 窄屏两个值都 > 393，`maxWidth` 不生效 → 零影响。
    private var bannerColumnWidth: CGFloat {
        metrics.railPageWidth
    }

    @ViewBuilder
    private var bannerArea: some View {
        if rock.isOffline {
            OfflineBanner(kind: .offline)
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, 6)
                .pageColumn(bannerColumnWidth)
        } else if rock.isDataOld {
            OfflineBanner(kind: .staleData, text: "排期已有些天数没更新，先按现在的看。")
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, 6)
                .pageColumn(bannerColumnWidth)
        } else if let warning = rock.warningText {
            OfflineBanner(kind: .staleData, text: warning)
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, 6)
                .pageColumn(bannerColumnWidth)
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
