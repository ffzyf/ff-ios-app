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
            // 单列 720 居中（设计文档 §3.4）。这一页**刻意不做两列**：
            // 主体是文字，680 的正文折成两列只剩 340 ≈ 19 汉字/行，低于 30 字的下限；
            // 而且"版本对比"与"今日详情"并排会让读者以为它们是同一层级的两件事。
            .pageColumn(Layout.contentMaxWidth)
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

    private var loadedBlocks: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
            // 三个分组各给一个 22pt 分区标题：版本 / 简报详情 / 版本记录是这页的三件事，
            // 改版前它们都是"同宽同圆角的玻璃卡"，只能靠读内容猜边界（报告 §3.3）
            section("两服版本") {
                SkyVersionPanel(status: model.skyStatus)
            }
            section("今日详情") {
                TodayBriefCard(snapshot: model.todayBrief)
            }
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
