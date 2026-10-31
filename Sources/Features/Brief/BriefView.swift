import SwiftUI

/// 简报页（Tab 3，PRD §3.4 / 设计文档 T08）。
///
/// 区块顺序（不可重排）：
/// ① 两服版本对比（`SkyVersionPanel`，比首页那张状态卡详细）→ ② 今日简报（`TodayBriefCard`）
/// → ③ 版本记录（`VersionRecordCard`）。
///
/// 三条数据纪律：
/// · 下拉刷新只调 `loadBrief()`，**绝不触发** daily-brief 生成 / Bark 推送（PRD F6）；
/// · `brief.available == false` 是正常业务状态（早上 7:30 前），走口语化占位，不是错误样式；
/// · 错误态只在「一条数据都没有」时出现；有旧数据就只弹 toast，不清空。
struct BriefView: View {
    @EnvironmentObject private var model: AppModel
    /// 推送状态那一行要读监控接口（PRD P07 明确「与 P12 同源」）。
    /// 用单例观察而不是再注入一个环境对象：简报页只需要它的两个字段（最近推送 / 时段），
    /// 多一层注入就多一处「模态没继承环境对象」的运行期风险。
    @ObservedObject private var monitor = MonitorStore.shared
    /// 尺寸模型（设计文档 §4.3）：rail 档把「两服版本 + 版本与推送」搬到右侧 368，
    /// 正文留在 680 —— 正文行宽一个字都不变（R9：行宽由字形决定，不由屏幕决定）。
    @Environment(\.layoutMetrics) private var metrics
    /// 主列实测高度（副列靠它撑高，`Spacer` 才吸得到差额；理由见 `View.measureHeight(into:)`）
    @State private var mainColumnHeight: CGFloat = 0
    /// 滚动偏移保活（B3）：由 RootView 持有字典并作为 Binding 注入。
    let scrollPosition: Binding<ScrollPosition>

    init(scrollPosition: Binding<ScrollPosition>) {
        self.scrollPosition = scrollPosition
    }

    var body: some View {
        ScrollView {
            // 组间 32：改版前 4 个块统一 24 且没有分区标题，一页读下来是"一列卡"（设计报告 §3.3）
            VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
            // 列宽：rail 档 = 画布 1080 + 页边距（主 680 / 32 / 副 368），否则 720（= 今天）。
            //
            // 这一页仍然**不做"正文分两栏"**：正文 680 折成两列只剩 340 ≈ 19 汉字/行，
            // 低于 30 字的下限（R9）。宽档只是把与正文不同性质的两组（两服版本 / 版本与推送）
            // 挪到右侧 —— 行宽没变，右侧那 474 的永久空白变成了 368 的对照信息。
            .pageColumn(metrics.railPageWidth)
        }
        .scrollPosition(scrollPosition)
        .pageScrollLight()
        .scrollIndicators(.hidden)
        .refreshable {
            await model.loadBrief()
            // 推送状态与简报同源但不同接口：下拉刷新时一起刷，避免「简报是新的一行是旧的」
            await monitor.load(force: true)
        }
        // ⌘R：与下拉刷新走同两条（简报 + 监控），否则键盘用户会看到"简报新了、推送还是旧的"
        .refreshShortcut {
            Task { await model.loadBrief() }
            Task { await monitor.load(force: true) }
        }
        // 首屏只补一次监控状态：它在简报页是"附加信息"，失败也不影响简报本体
        .task {
            await monitor.load()
        }
        // 全站共享的轻提示（B2 后来源是 ToastStore，这里不传文案即读全局）：
        // 刷新失败只弹这一条，不遮内容
        .overlay(alignment: .bottom) {
            PageToast()
        }
    }

    // MARK: - 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("简报")
                .font(Typography.display)
                .tracking(Typography.trackingLarge)
                .foregroundStyle(Theme.textPrimary)
            Text(updatedText)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 状态分发

    @ViewBuilder
    private var content: some View {
        if model.briefState.hasContent {
            loadedBlocks
        } else if let error = model.briefState.error {
            ErrorStateView(
                icon: error.icon,
                title: error.title,
                message: error.hint,
                onRetry: {
                    Task { await model.loadBrief() }
                }
            )
        } else {
            SkeletonBrief()
        }
    }

    /// 已加载时的分组排布：**窄档单列 / rail 档"正文 + 副列"**。
    ///
    /// 三个分组各自是一个属性（`versionSection` / `briefSection` / `recordSection`），
    /// 定义只有一份 —— 宽档改的是"谁在谁旁边"，不是"再写一套简报页"。
    /// 窄档分支的顺序与 3.7.0 一字不差：两服版本 → 今日详情 → 版本与推送。
    @ViewBuilder
    private var loadedBlocks: some View {
        if metrics.usesRail {
            HStack(alignment: .top, spacing: Layout.columnGap) {
                briefSection
                    .frame(maxWidth: metrics.railMainWidth, alignment: .topLeading)
                    .measureHeight(into: $mainColumnHeight)
                sideColumn
                    .frame(width: Layout.sideColumnWidth)
                    // `minHeight` 而不是 `height`：副列内容比主列高时不溢出卡片，
                    // 内容矮时仍然撑到主列高度 —— `Spacer` 吃差额，最后一块压到底边（齐平保留）。
                    .frame(minHeight: sideColumnHeight, alignment: .top)
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
                versionSection
                briefSection
                recordSection
            }
        }
    }

    /// rail 档副列：两服版本 → 版本与推送 → `Spacer(minLength: 32)`（设计文档 §4.3）。
    ///
    /// 两块的高度都由内容决定（三个组件都没有固定高度），所以这里不设任何阈值：
    /// 副列短时 `Spacer` 把「推送状态行」压到底边、副列长时主列底部留白（规则见 §4.0）。
    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
            versionSection
            recordSection
            Spacer(minLength: Layout.columnGap)
        }
    }

    /// 副列高度：量到主列才给值，首帧（0）给 `nil` = 按内容自然高。
    private var sideColumnHeight: CGFloat? {
        return mainColumnHeight > 0 ? mainColumnHeight : nil
    }

    // MARK: - 三个分组（定义只有一份，两个档共用）

    private var versionSection: some View {
        section("两服版本") {
            SkyVersionPanel(status: model.skyStatus)
        }
    }

    private var briefSection: some View {
        section("今日详情") {
            TodayBriefCard(snapshot: model.todayBrief)
        }
    }

    private var recordSection: some View {
        section("版本与推送") {
            // `VersionRecordCard` 卡内自带「版本记录」这行 17pt 标题，
            // 所以分区标题不同名（同一句话上下重复会被读成 bug）；
            // 顺带把「推送状态」这一行收进同一个组 —— 改版前它是 11pt 单行收尾，页面止于最轻元素
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                VersionRecordCard(status: model.skyStatus)
                // 批次 4：推送状态只读行。取不到时组件自己渲染 EmptyView（整行隐藏，不写"未知"）
                PushStatusRow(snapshot: model.todayBrief, monitor: monitor.response)
            }
        }
    }

    /// 「分区标题 + 内容」的统一拼法。
    ///
    /// 用 `spacing: 0` 的 `VStack` 而不是再叠一层间距：`SectionHeader` 已经自带 12pt 下距，
    /// 外层再加 12 就变成 24 —— 标题与它自己的内容会被读成两组（报告 §2 R3）。
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title)
            content()
        }
    }

    // MARK: - 派生文案

    /// 「更新于 今天 07:30」：优先快照时间，退回响应生成时间；都没有就说下拉可刷新
    private var updatedText: String {
        guard let response = model.briefState.value else { return "下拉可以刷新" }
        guard let stamp = response.brief?.savedAt ?? response.generatedAt else {
            return "下拉可以刷新"
        }
        return "更新于 " + Formatters.relativeDay(stamp)
    }
}
