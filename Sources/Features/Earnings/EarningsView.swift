import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 收益工作站（V3.2 新增，替换原来的「文章」Tab 位）。
///
/// 网页端（`creator-earnings-tracker.pages.dev`）的收益统计搬到这里：总额 / 三态构成 /
/// 本月新增 / 平台占比 / 活动流水。
///
/// **能建活动、也能记一笔，但账不在本地**：App 通过 `POST /api/app/earnings/activity` 建活动、
/// 通过 `POST /api/app/earnings/entry` 往活动里追加条目（见 `EarningsRecordSheet`），
/// 与网页端读同一份 KV。改活动 / 勾「已发」仍在网页端 —— 那些要长表单，塞进手机反而更难用。
///
/// 未登录时给登录引导页（不是弹窗）：`EarningsAuth` 要管理密码，弹窗一关就得重来。
///
/// ## 版面（设计报告 §4.4 / P0-8）
///
/// 改版前的病是"一个大数字 + 一堆 12pt 小字表"：整页只有 hero 一处重量，往下全是同宽同圆角的
/// 卡片，眼睛扫不到"这是新的一组"。现在的区块顺序与重量：
///
/// 1. **hero 216pt**：眉题（总计 · 本月新增）+ 40pt `metricL` 总额 + 10pt 三态堆叠条 + 图例
///    + 右下「记一笔」入口 —— 一屏唯一的锚点；
/// 2. **「本月」+ 三张 96pt tile**：本月新增（28pt `metricM`，涨红跌绿）/ 待结算 / 活动 · 平台；
/// 3. **「平台」+ 两列小卡（A+B 混合方案）**：默认是两列概览（品牌色圆点 + 平台名 13pt +
///    金额 20pt + 3pt 占比细条），点任一卡弹出该平台的完整活动墙（`PlatformDetailSheet`）——
///    概览回答"谁占多少"，点进去才回答"这个平台具体是哪些活动"。
///    为什么不再是一条条横向占比条：平台一多，条形图变成七八条同宽的横线，眼睛扫不到"最大的是谁"；
///    两列卡片用面积 + 金额双重编码，一屏 4 张，谁最大一眼就看出来；
/// 4. **「最近活动」+ 全部**：行高 72，名称 15pt、金额 17pt；
/// 5. 页脚 11pt 说明。
///
/// 组间一律 `Spacing.sectionGapLoose` 32、组内 `Spacing.cardGap` 12；分区标题一律走
/// `SectionHeader`（22pt + 右侧动作 + 12pt 下距），不再有自造的 12pt「假分区标题」。
struct EarningsView: View {

    @ObservedObject private var auth = EarningsAuth.shared
    @ObservedObject private var store = EarningsStore.shared
    /// 尺寸模型（设计文档 §3.5）：收益是数据看板 —— hero（总）与平台占比（分）并置才能对照。
    @Environment(\.layoutMetrics) private var metrics

    @State private var password: String = ""
    @State private var loginError: String?
    @State private var isSubmitting: Bool = false
    /// 「记一笔」表单
    @State private var showsRecord: Bool = false
    /// 平台详情弹页的呈现开关（`PlatformDetailSheet`）。
    ///
    /// 与上一版的区别：以前这个开关控制"占比卡里内联展开一张平台明细表"，
    /// 现在平台区块改成了两列卡片墙 —— 内联展开会让区块高度随活动数暴涨，
    /// 所以同一个开关改成"弹出单平台弹页"，语义从"展开"变成"进入"，状态名沿用不改
    /// （改名不会让行为更对，只会让 diff 更大）。
    @State private var showsPlatformDetail: Bool = false
    /// 当前选中的平台名。与 `showsPlatformDetail` 成对：先写名字再置 true，
    /// 弹页读到的永远是刚点的那一张卡（而不是上一张留下的名字）。
    @State private var selectedPlatformName: String = ""
    /// 「最近活动」的本地分页页码（0 起，3.10.0 替换原「全部 / 收起」展开态）。
    /// 翻页纯切片、不发请求；数据变化（下拉刷新 / 记一笔）时回第 1 页。
    @State private var activityPage: Int = 0
    @FocusState private var isPasswordFocused: Bool

    /// hero 卡最小高度。
    ///
    /// 为什么不直接用 `CardTier.hero.height`：240 是首页红石倒计时那一档（它还有 4pt 进度轨
    /// 与"三场并列"行）；收益 hero 里只有一个数字 + 一条构成条 + 一行图例，216 才是它的内容高度。
    /// 用 `minHeight` 而不是固定 `height`：数字换行或大字号时卡可以长高，不会裁字。
    ///
    /// **宽档 264**（设计文档 §4.4）：主列从 560 长到 680（×1.21），高度跟着 ×1.22 ——
    /// 高宽比 2.59:1 → 2.58:1 不变，观感是"同一张卡变大了"；等比放大（×1.56）会把 216 撑到 337，
    /// 卡里只剩空气。这是全工程唯一一处"页面本地卡片高度"，保留它是因为它不属于 `CardTier`
    /// 的任何一档（红石 hero 有进度轨，收益 hero 没有）。
    private var heroMinHeight: CGFloat {
        metrics.usesRail ? 264 : 216
    }

    /// 主列实测高度（副列靠它撑高，`Spacer` 才吸得到差额；理由见 `View.measureHeight(into:)`）
    @State private var mainColumnHeight: CGFloat = 0

    /// 平台网格列定义。两列等宽、列间距 `Spacing.cardGap`（12）：
    ///
    /// 为什么不是 `.adaptive` —— 屏幕更宽时（iPad / 横屏）adaptive 会自己变成 3~4 列，
    /// 而收益页的金额字号是按"单卡约 150pt 宽"定的，列数一变就得再判宽度换字号。
    /// 固定两列让版式在所有设备上一致：平台再多，也只会往下排。
    /// 宽档副列仍是 368（`Layout.sideColumnWidth`），两列各 178 —— 所以这里不用改。
    private let platformGridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: Spacing.cardGap),
        GridItem(.flexible(), spacing: Spacing.cardGap)
    ]
    /// 活动行高度（报告 §4.4：72pt）。名称 15 + 元信息 12 两行文字需要的最小呼吸量。
    private let activityRowHeight: CGFloat = 72.0
    /// 每页条数（3.10.0 用户反馈：一次 12 条太长，翻页找某一天更快）。本地分页，翻页不发请求
    private let activityPageSize: Int = 5

    let scrollPosition: Binding<ScrollPosition>

    init(scrollPosition: Binding<ScrollPosition>) {
        self.scrollPosition = scrollPosition
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
                header

                if auth.isLoggedIn {
                    if let summary = store.summary {
                        loadedBlocks(summary: summary)
                    } else if store.isLoading {
                        loadingCard
                    } else {
                        emptyCard
                    }
                } else {
                    loginCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
            // 列宽：rail 档 = 画布 1080 + 页边距（主列 680 / 32 / 副列 368），否则 720（= 今天）。
            // `railPageWidth` 已含页边距，页面里不再 `+ Spacing.page * 2`。
            .pageColumn(metrics.railPageWidth)
        }
        .scrollPosition(scrollPosition)
        .pageScrollLight()
        .scrollIndicators(.hidden)
        .refreshable {
            await store.load(force: true)
        }
        // ⌘R：与下拉刷新同一个方法
        .refreshShortcut {
            Task { await store.load(force: true) }
        }
        .task {
            // 已登录才拉：没凭证时 load() 自己会清成空态，不发请求
            await store.load()
        }
        .sheet(isPresented: $showsRecord) {
            EarningsRecordSheet()
        }
    }

    // MARK: - 正文排布（单列 / 两列）

    /// 左主列的两个锚点：hero（总计）+ 本月三格。
    ///
    /// 抽成一段而不是在 body 里写两遍：宽屏它放左、窄屏它照旧纵向排，两种情况下
    /// 内部都是"组间 32"—— 所以抽出来**不改变窄屏的任何间距与顺序**。
    private func mainColumn(summary: EarningsSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
            heroCard(summary: summary)
            monthSection(summary: summary)
        }
    }

    /// 主列宽 = 画布 − 栏距 − 副列（rail 档 = 680）。
    /// 从画布算而不是写死：Stage Manager 拖窄时主列自动收，副列不会被挤出画布。
    private var mainColumnWidth: CGFloat {
        metrics.railMainWidth
    }

    /// 已登录且有数据时的正文（设计文档 §4.4）。
    ///
    /// 窄屏分支的顺序与 3.7.0 一致：hero → 本月 → 平台 → 活动流水 → 页脚。
    /// rail 档只是把「平台」从下方搬到右边、把页脚搬进副列底部 —— 四个分组各自只有一份定义。
    ///
    /// 为什么宽档条件里还要带上 `platformBreakdown.isEmpty == false`：
    /// 平台区块在没有平台数据时**整块不渲染**（`platformSection` 内部就是空分支），
    /// 但副列那个 `.frame(width: Layout.sideColumnWidth)` 是挂在调用处的 ——
    /// 于是 iPad 上会出现"左 680 有内容 + 32 间隔 + 右 368 全空"，右侧白掉一大条。
    /// 没有可放进副列的东西时就不该有副列：退回单列后主列自然吃满画布。
    /// （3.5.1 修过一次的同一个 bug，这次把条件原样带过来，没有退回去。）
    @ViewBuilder
    private func loadedBlocks(summary: EarningsSummary) -> some View {
        if usesRail(summary) {
            HStack(alignment: .top, spacing: Layout.columnGap) {
                mainColumn(summary: summary)
                    .frame(maxWidth: mainColumnWidth)
                    .measureHeight(into: $mainColumnHeight)
                // 副列 368：平台网格仍是两列（(368 − 12) / 2 = 178 一张），
                // 不改 `.adaptive` —— 金额字号是按 150pt 卡宽定的（文件上方已写明理由）。
                sideColumn(summary: summary)
                    .frame(width: Layout.sideColumnWidth)
                    // `minHeight` 而不是 `height`：副列内容比主列高时不溢出卡片，
                    // 内容矮时仍然撑到主列高度 —— `Spacer` 吃差额，页脚压到底边（齐平保留）。
                    .frame(minHeight: sideColumnHeight, alignment: .top)
            }
            // 活动流水**通栏**：它天然是"流水"，宽度越大越好读；放副列会让右列比左列高一倍。
            // 它必须在两列**之外**（通栏 1080），否则 680 里塞一张 12 列的表会把金额列挤成省略号。
            activitySection
        } else {
            mainColumn(summary: summary)
            platformSection(summary: summary)
            // 单列：活动流与页脚照旧跟在平台后面 —— 顺序与 3.7.0 一字不差
            activitySection
            footerNote
        }
    }

    /// 这一页要不要走"主列 + 副列"。**页面里唯一一处宽档判断**（设计文档 §4.0 规则 2）。
    ///
    /// 除了 rail 档成立，还要求平台数据非空：平台区块在没有数据时**整块不渲染**
    /// （`platformSection` 内部就是空分支），但副列那个 `.frame(width: 368)` 挂在调用处 ——
    /// 于是 iPad 上会出现"左 680 有内容 + 32 间隔 + 右 368 全空"，右侧白掉一大条。
    /// 没有可放进副列的东西时就不该有副列：退回单列后主列自然吃满画布。
    /// （3.5.1 修过同一个 bug，这次把条件原样带过来，没有退回去。）
    private func usesRail(_ summary: EarningsSummary) -> Bool {
        return metrics.usesRail && !summary.platformBreakdown.isEmpty
    }

    /// 副列高度：量到主列才给值，首帧（0）给 `nil` = 按内容自然高。
    private var sideColumnHeight: CGFloat? {
        return mainColumnHeight > 0 ? mainColumnHeight : nil
    }

    /// rail 档副列：平台卡墙 + `Spacer(minLength: 32)` + 页脚说明（设计文档 §4.4）。
    ///
    /// 页脚从"整页最底部"搬到这里，是为了让左右两列的**底边同高收尾**：
    /// 平台卡只有 292，主列有 456 —— `Spacer` 吃掉 164，页脚正好贴在主列的底边线上。
    /// 单列时页脚仍在页面最底部（`else` 分支），一个字都没动。
    private func sideColumn(summary: EarningsSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            platformSection(summary: summary)
            Spacer(minLength: Layout.columnGap)
            footerNote
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("收益")
                    .font(Typography.display)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if auth.isLoggedIn {
                    Button {
                        Haptics.light()
                        Task { await store.load(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background {
                                Circle().fill(Theme.glassFill)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("刷新收益")
                }
            }

            HStack(spacing: 6) {
                if let updated = store.updatedText {
                    Text(updated)
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textTertiary)
                    if store.isStale {
                        Text("· 离线数据")
                            .font(Typography.footnote)
                            .foregroundStyle(Theme.statusWarn)
                    }
                } else {
                    Text(auth.isLoggedIn ? "来自收益工作台" : "需要访问密码")
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    // MARK: - hero（一屏唯一锚点）

    private func heroCard(summary: EarningsSummary) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                // 眉题说"这是什么口径的数"：总计 + 本月新增。金额单独着色，
                // 因为 `Eyebrow` 只吃一个颜色 —— 让它整条变红，就把"总计"这个标签也染红了
                HStack(spacing: 5) {
                    Eyebrow(text: "总计 · 本月")
                    Text(monthAddedText(summary.monthAdded))
                        .font(Typography.eyebrow)
                        .tracking(Typography.trackingEyebrow)
                        .foregroundStyle(monthAddedColor(summary.monthAdded))
                        .monospacedDigit()
                        .lineLimit(1)
                    Image(systemName: summary.monthAdded >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(monthAddedColor(summary.monthAdded))
                    Spacer(minLength: 0)
                }

                Text(EarningsMoney.formatCents(summary.total))
                    // hero 在宽档是 680 宽的整块（264 高），40pt 在里面就是"放大的空卡"；
                    // 与概览 hero 同一判据 —— 宽档 56pt（`metricXL`），窄档仍是今天的 40pt（`metricL`）。
                    .font(metrics.usesRail ? Typography.metricXL : Typography.metricL)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                // 三态构成条：pending + receivedUnclosed + closed 就是这条条的全部，
                // "本月新增"是流量口径，刻意不参与（见 `StatCompositionBar` 注释）
                StatCompositionBar(
                    pending: summary.pending,
                    receivedUnclosed: summary.receivedUnclosed,
                    closed: summary.closed
                )

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if canRecord {
                        recordButton
                    }
                }
            }
            .padding(Spacing.cardPadding)
            .frame(minHeight: heroMinHeight, alignment: .topLeading)
        }
    }

    /// 本月新增的文案：正数带 `+`，负数交给 `EarningsMoney` 自己带 `-`（它已经带 `¥` 前缀）
    private func monthAddedText(_ cents: Int) -> String {
        let body = EarningsMoney.formatCents(abs(cents))
        return cents >= 0 ? "+" + body : "-" + body
    }

    /// 涨=红 / 跌=绿（中国习惯）。不能借 `statusError` / `statusNew`：
    /// 那是"出错了 / 有新版本"，用在金额上会被读成状态而不是趋势。
    private func monthAddedColor(_ cents: Int) -> Color {
        return cents >= 0 ? Theme.riseRed : Theme.fallGreen
    }

    /// 能不能记账：**只要登录了就给入口**。
    ///
    /// 早先这里的条件是「登录 + 至少一个活动」，因为那时建活动只能在网页端做，
    /// 没活动就等于没地方记账。现在弹页里可以建活动（`POST /api/app/earnings/activity`），
    /// 所以「一个活动都没有」恰恰是最该点进来的情况 —— 再挡住入口就等于把建活动的路也堵了。
    private var canRecord: Bool {
        return auth.isLoggedIn
    }

    /// 「记一笔」入口（hero 卡右下角）。
    private var recordButton: some View {
        Button {
            Haptics.light()
            showsRecord = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.onLime)
                Text("记一笔")
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.onLime)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background { Capsule().fill(Theme.lime) }
            .overlay { Capsule().strokeBorder(Theme.glassStrokeTop, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("记一笔收入")
    }

    // MARK: - 本月 · 三张 tile

    private func monthSection(summary: EarningsSummary) -> some View {
        // `SectionHeader` 自带 12pt 下距，所以这里用 spacing 0 而不是再加一层 cardGap
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "本月")
            HStack(spacing: Spacing.cardGap) {
                statTile(title: "本月新增") {
                    Text(monthAddedText(summary.monthAdded))
                        .font(Typography.metricM)
                        .foregroundStyle(monthAddedColor(summary.monthAdded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }

                statTile(title: "待结算") {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(summary.pendingActivityCount)")
                            .font(Typography.metricM)
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                        Text("个")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .lineLimit(1)
                }

                statTile(title: "活动 / 平台") {
                    Text("\(summary.activityCount) / \(summary.platformCount)")
                        .font(Typography.metricM)
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            }
        }
    }

    /// 96pt tile 的统一外壳：眉题在顶、数字在底（`Spacer` 把两边顶开，
    /// 三张卡的数字基线因此永远对齐，即便某张数字因缩放变窄）。
    ///
    /// 高度走 `cardHeight(.tile)`：窄档 96（今天）/ 宽档 120。三张 tile 在 680 的主列里
    /// 各 218.7 宽、120 高 = 1.82:1，与今天 178.7×96 的 1.86:1 同比例（设计文档 §4.4）。
    private func statTile<Value: View>(
        title: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: title)
                Spacer(minLength: 0)
                value()
                Spacer(minLength: 0)
            }
            .padding(Spacing.smallCardPadding)
            .frame(height: metrics.cardHeight(.tile), alignment: .leading)
        }
    }

    // MARK: - 平台（两列小卡墙 → 点卡进弹页）

    /// 平台区块：`SectionHeader("平台")` + 两列网格。
    ///
    /// 右侧动作**删掉了**（上一版是「明细 / 收起」）。理由：动作原来控制"在卡里内联展开一张
    /// 平台明细表"，现在每张卡自己就是入口 —— 卡可点、点开是完整弹页，
    /// 再留一个「明细」按钮就有两个入口通向同一件事，而且那个按钮点开的是`store.platforms`
    /// 全量列表，与"我想看这个平台"的意图并不一致。
    @ViewBuilder
    private func platformSection(summary: EarningsSummary) -> some View {
        if summary.platformBreakdown.isEmpty == false {
            // `SectionHeader` 自带 12pt 下距，所以这里 spacing 用 0（与「本月」同一写法）
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "平台")

                LazyVGrid(columns: platformGridColumns, spacing: Spacing.cardGap) {
                    ForEach(summary.platformBreakdown) { item in
                        PlatformCard(
                            item: item,
                            totalAmount: platformAmountTotal(summary.platformBreakdown),
                            activityCount: activityCounts[item.name] ?? 0
                        ) {
                            // 触觉不在这里发：`PressableGlassCard` 已经在按钮按下时给了一次
                            // `Haptics.light()`，再加一次就是双击感
                            openPlatformDetail(item.name)
                        }
                    }
                }
                // 弹页挂在平台区块自己身上，不挂在页面根视图：同一个视图上挂两个 `.sheet`
                // （「记一笔」+ 平台详情）在 SwiftUI 里会互相遮蔽，只有后挂的那个能弹出来。
                // 挂在子视图上两者各归各的宿主，谁点弹谁。
                .sheet(isPresented: $showsPlatformDetail) {
                    // 过滤用 `EarningsPlatformPreset.activities(_:in:)`（与服务端同序、不重排），
                    // 不在弹页里再写一遍 filter —— 平台名匹配的规则只留一处
                    PlatformDetailSheet(
                        platformName: selectedPlatformName,
                        aggregate: store.platforms.first { $0.name == selectedPlatformName },
                        activities: EarningsPlatformPreset.activities(store.activities, in: selectedPlatformName)
                    )
                }
            }
        }
    }

    /// 各平台金额之和 —— 细条的分母（只此一处，卡片按参数吃，不各自求和）
    private func platformAmountTotal(_ items: [EarningsPlatformBreakdown]) -> Int {
        return items.reduce(0) { $0 + $1.amount }
    }

    /// 平台名 → 该平台的活动数。
    ///
    /// 卡片要显示「N 个活动」，但 `EarningsActivity` 只在 `store.activities` 里；
    /// 每张卡各自 filter 一遍是 O(平台数 × 活动数)，活动多时会在滚动里反复扫同一个数组，
    /// 所以在这里一次数完，卡片只吃一个 `Int`。
    private var activityCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for activity in store.activities {
            counts[activity.platform, default: 0] += 1
        }
        return counts
    }

    /// 打开某个平台的详情弹页。
    ///
    /// 先写名字、再置 true：`.sheet(isPresented:)` 的内容闭包在呈现那一刻求值，
    /// 顺序反过来会让弹页有一帧读到上一个平台的名字（能看到标题闪一下）。
    private func openPlatformDetail(_ name: String) {
        selectedPlatformName = name
        showsPlatformDetail = true
    }

    // MARK: - 最近活动

    /// 活动总页数（≥ 1，由数据量决定；与切片共用一个分母，不会漂）
    private var activityPageCount: Int {
        return max(1, Int(ceil(Double(store.activities.count) / Double(max(activityPageSize, 1)))))
    }

    /// 当前页的活动切片。页码越界（数据变少）时夹到最后一页 ——
    /// 否则删数据后停在一个空页上，"下一页"灰着、"上一页"也没内容。
    private var visibleActivities: [EarningsActivity] {
        let page = min(max(activityPage, 0), activityPageCount - 1)
        let start = page * activityPageSize
        let end = min(start + activityPageSize, store.activities.count)
        guard start < end else { return [] }
        return Array(store.activities[start..<end])
    }

    @ViewBuilder
    private var activitySection: some View {
        if store.activities.isEmpty == false {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "最近活动")

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleActivities) { activity in
                            activityRow(activity)
                            if activity.id != visibleActivities.last?.id {
                                Rectangle()
                                    .fill(Theme.divider)
                                    .frame(height: 1)
                            }
                        }

                        // 多于一页才给翻页器：一页装得下时它只是噪音
                        if activityPageCount > 1 {
                            activityPager
                        }
                    }
                    .padding(.horizontal, Spacing.cardPadding)
                    .padding(.vertical, 4)
                }
                // 数据变化（下拉刷新 / 记一笔新增 / 切登录态）回第 1 页：
                // 页码是"当时那份数组的下标"，数组换了内容旧页码只会指向错误的位置。
                // 用条数当信号：条数不变但内容整体翻新的场景（换账号）极少，
                // 漏一次的代价只是"停在第 2 页"，不值得一提一个更重的 identity。
                .onChange(of: store.activities.count) { _, _ in
                    activityPage = 0
                }
            }
        }
    }

    /// 翻页器：「上一页 / 第 x / y 页 / 下一页」。首页禁上一页、末页禁下一页。
    ///
    /// 为什么是本地切片而不是接着拉接口：服务端一次就把全部活动给回来了
    /// （`store.activities`），翻页只是"看哪一段"，再发请求是纯浪费；
    /// 样式沿用工程里的玻璃胶囊按钮（`CapsuleGlassButton` 的形态），不新造一套。
    private var activityPager: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.light()
                withAnimation(Motion.press) {
                    activityPage = max(0, min(activityPage, activityPageCount - 1) - 1)
                }
            } label: {
                Text("上一页")
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassSurface(.floating, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(activityPage <= 0)
            .opacity(activityPage > 0 ? 1 : 0.4)

            Spacer(minLength: 0)

            Text("第 \(min(max(activityPage, 0), activityPageCount - 1) + 1) / \(activityPageCount) 页")
                .font(Typography.footnote)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()

            Spacer(minLength: 0)

            Button {
                Haptics.light()
                withAnimation(Motion.press) {
                    activityPage = min(activityPage + 1, activityPageCount - 1)
                }
            } label: {
                Text("下一页")
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassSurface(.floating, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(activityPage >= activityPageCount - 1)
            .opacity(activityPage < activityPageCount - 1 ? 1 : 0.4)
        }
        .padding(.vertical, 8)
    }

    private func activityRow(_ activity: EarningsActivity) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                // 15pt：活动名是这一行的主语
                Text(activity.name)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(activity.platform + " · " + EarningsClock.format(ms: activity.time))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                // 17pt：金额与平台占比卡保持同一档
                Text(EarningsMoney.formatCents(activity.totalCents))
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(activity.isClosed ? "已结" : "进行中")
                    .font(Typography.caption)
                    .foregroundStyle(activity.isClosed ? Theme.textTertiary : Theme.statusOk)
            }
        }
        .frame(minHeight: activityRowHeight)
        .contentShape(Rectangle())
        // 活动行的长按菜单（§7.3 第三处）：只放「复制金额」。
        // 为什么不做「编辑 / 标记已发」：那两个要长表单与状态回写，留在网页端（PRD 的边界）。
        // 复制的是 `formatCents` 的输出（与屏幕上看到的**同一个**字符串），不是原始分数 ——
        // 用户复制完贴到账本里，看到的和记的对得上。
        .contextMenu {
            Button {
                Haptics.light()
                #if canImport(UIKit)
                UIPasteboard.general.string = EarningsMoney.formatCents(activity.totalCents)
                Haptics.success()
                #endif
            } label: {
                Label("复制金额", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - 状态页

    private var loadingCard: some View {
        GlassCard {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(Theme.lime)
                Text("正在读取收益…")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(Spacing.cardPadding)
        }
    }

    private var emptyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.errorText ?? "还没有读到收益数据")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    Haptics.light()
                    Task { await store.load(force: true) }
                } label: {
                    Text("重新读取")
                }
                .buttonStyle(PrimaryCTAStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.cardPadding)
        }
    }

    // MARK: - 登录引导

    private var loginCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("连接收益工作台")
                        .font(Typography.titleM)
                        .foregroundStyle(Theme.textPrimary)
                    Text("用网页端的访问密码登录一次，之后就免密。")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textTertiary)
                }

                SecureField("访问密码", text: $password)
                    .textContentType(.password)
                    .focused($isPasswordFocused)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                            .fill(Theme.glassFill)
                    }
                    .submitLabel(.go)
                    .onSubmit { submit() }

                if let loginError {
                    Text(loginError)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.statusError)
                }

                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small).tint(Theme.onLime)
                    } else {
                        Text("登录")
                    }
                }
                .buttonStyle(PrimaryCTAStyle())
                .disabled(isSubmitting || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("密码就是网页端 `ACCESS_PASSWORD`。App 只存一个 30 天有效的会话 Cookie 在 Keychain，退出即删。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
            }
            .padding(Spacing.cardPadding)
        }
    }

    private func submit() {
        let value = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        loginError = nil
        Haptics.light()
        Task {
            do {
                try await auth.login(password: value)
                password = ""
                isPasswordFocused = false
                await store.load(force: true)
            } catch let error as EarningsAuthError {
                loginError = error.userMessage
            } catch {
                loginError = "登录没成功，稍后再试。"
            }
            isSubmitting = false
        }
    }

    // MARK: - 页脚

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("App 里能建活动、选平台、记一笔；改活动 / 勾「已发」仍在网页端。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            if store.activities.isEmpty {
                Text("还没有活动：点 hero 卡里的「记一笔」，在里面填名称 + 平台就能建一个。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.statusWarn)
            }
        }
        .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
        .padding(.horizontal, 4)
    }
}
