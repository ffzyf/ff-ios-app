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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await model.loadBrief()
        }
        // 全站共享的轻提示：刷新失败只弹这一条，不遮内容
        .overlay(alignment: .bottom) {
            PageToast(message: model.toastMessage)
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
        VStack(alignment: .leading, spacing: Spacing.sectionGap) {
            SkyVersionPanel(status: model.skyStatus)
            TodayBriefCard(snapshot: model.todayBrief)
            VersionRecordCard(status: model.skyStatus)
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
