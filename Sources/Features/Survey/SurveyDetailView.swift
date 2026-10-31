import SwiftUI

/// 问卷详情（PRD P09）。
///
/// 页面只做"展示 + 三个动作"：
/// · 「填写」→ 公开填答页（无需登录）；
/// · 「看结果」→ 结果看板；
/// · 「发布 / 截止」→ 二次确认后调 `actions`。
///
/// 能不能填 / 能不能看结果**一律以服务端下发的 `canFill` / `canSeeResult` 为准**，
/// 不自己按 `status + endAt` 推状态机 —— 状态机只有一处权威（服务端），
/// 否则哪天加了"定向发布"规则，App 就会显示错误的按钮状态。
struct SurveyDetailView: View {
    let surveyId: String

    @ObservedObject private var store = SurveyStore.shared

    @State private var showsPublishConfirm: Bool = false
    @State private var showsCloseConfirm: Bool = false

    private let onBack: () -> Void
    private let onFill: (String) -> Void
    private let onSeeResult: (String) -> Void

    init(
        surveyId: String,
        onBack: @escaping () -> Void,
        onFill: @escaping (String) -> Void,
        onSeeResult: @escaping (String) -> Void
    ) {
        self.surveyId = surveyId
        self.onBack = onBack
        self.onFill = onFill
        self.onSeeResult = onSeeResult
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                SurveyPageHeader(
                    title: "问卷详情",
                    subtitle: subtitle,
                    trailingIcon: "arrow.clockwise",
                    onTrailing: refresh,
                    onBack: onBack
                )
                bodyContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 6)
            .padding(.bottom, Spacing.pageBottomInset)
            // 问卷详情列宽 720（§3.9）：统计是逐行条，横向并排会让每条变短、比较失真。
            .pageColumn(Layout.contentMaxWidth)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            PageToast(message: store.toast)
        }
        .task(id: store.toast) {
            guard store.toast != nil else { return }
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(Motion.glassOut) {
                store.clearToast()
            }
        }
        .task {
            await store.loadDetail(id: surveyId)
        }
        // 发布 / 截止都要二次确认：这两个动作会立刻改变"外部能不能填"，
        // 误触的代价是让不该收到的答卷进来（或让正在填的人被挡在外面）。
        .confirmationDialog(
            Text("发布这份问卷？"),
            isPresented: $showsPublishConfirm,
            titleVisibility: .visible
        ) {
            Button("发布") {
                runAction(publish: true)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("发布后填答链接立刻可用，谁拿到链接都能提交。")
        }
        .confirmationDialog(
            Text("截止这份问卷？"),
            isPresented: $showsCloseConfirm,
            titleVisibility: .visible
        ) {
            Button("截止", role: .destructive) {
                runAction(publish: false)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("截止后填答入口会关闭，已经收到的答卷不受影响。")
        }
    }

    // MARK: - 状态分发

    private var currentDetail: SurveyDetail? {
        guard store.detailId == surveyId else { return nil }
        return store.detail?.value
    }

    private var subtitle: String? {
        guard let detail = currentDetail else { return nil }
        return detail.isTest ? "测评型问卷" : "普通问卷"
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let detail = currentDetail {
            infoCard(detail)
            actionRow(detail)
            stateHint(detail)
            actionRowForStatus(detail)
            FillLinkCard(fillUrl: detail.fillUrl)
            Text("App 只读：创建、编辑题目、导出 CSV 都留在网页端。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)
        } else if let error = store.detailFailure, !store.isLoadingDetail {
            ErrorStateView(
                icon: error.icon,
                title: error.title,
                message: error.hint,
                retryTitle: "重新加载",
                onRetry: refresh
            )
        } else {
            loadingSkeleton
        }
    }

    // MARK: - 信息卡

    private func infoCard(_ detail: SurveyDetail) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(detail.title.isEmpty ? "未命名问卷" : detail.title)
                    .font(Typography.titleXL)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    BadgePill(
                        kind: detail.canFill ? .newVersion : .neutral,
                        text: detail.statusLabel()
                    )
                    if detail.isTest {
                        BadgePill(kind: .pinned, text: "测评型")
                    }
                }

                if !detail.description.isEmpty {
                    Text(detail.description)
                        .font(Typography.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(Typography.lineSpacing(fontSize: 15, multiple: 1.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)

                HStack(spacing: 0) {
                    metricColumn(value: "\(detail.questionCount)", title: "题目")
                    metricDivider
                    metricColumn(value: "\(detail.responseCount)", title: "答卷")
                    metricDivider
                    metricColumn(value: deadlineText(detail), title: "截止")
                }

                Text("更新于 " + Formatters.relative(detail.updatedAt))
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            .padding(Spacing.cardPadding)
        }
    }

    private func metricColumn(value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Typography.titleM)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: 1, height: 30)
    }

    /// 截止时间用日期而不是相对时间：这里问的是"哪天关"，不是"多久以前"
    private func deadlineText(_ detail: SurveyDetail) -> String {
        guard let endAt = detail.endAt else { return "不限时" }
        return Formatters.isoDate(endAt)
    }

    // MARK: - 两个主按钮

    private func actionRow(_ detail: SurveyDetail) -> some View {
        HStack(spacing: 12) {
            Button(action: {
                guard detail.canFill else { return }
                Haptics.light()
                onFill(detail.id)
            }) {
                Text("填写")
            }
            .buttonStyle(PrimaryCTAStyle())
            .disabled(!detail.canFill)
            .opacity(detail.canFill ? 1 : 0.45)
            .accessibilityHint(detail.canFill ? "" : "草稿或已截止的问卷不能填写")

            Button(action: {
                guard detail.canSeeResult else { return }
                Haptics.light()
                onSeeResult(detail.id)
            }) {
                Text("看结果")
            }
            .buttonStyle(SecondaryCTAStyle())
            .disabled(!detail.canSeeResult)
            .opacity(detail.canSeeResult ? 1 : 0.45)
            .accessibilityHint(detail.canSeeResult ? "" : "还没有答卷可看")

            Spacer(minLength: 0)
        }
    }

    /// 一句话解释"为什么按钮是灰的"（PRD P09：草稿态要提示「先发布」）
    @ViewBuilder
    private func stateHint(_ detail: SurveyDetail) -> some View {
        if let hint = hintText(detail) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: hintIcon(detail))
                    .font(.system(size: 11, weight: .semibold))
                Text(hint)
                    .font(Typography.captionXS)
                    .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(detail.canFill ? Theme.textTertiary : Theme.statusWarn)
            .padding(.horizontal, 4)
        }
    }

    private func hintText(_ detail: SurveyDetail) -> String? {
        if detail.status == "draft" {
            return "这份问卷还是草稿：先发布，填答链接才会生效，也才有答卷可看。"
        }
        if !detail.canFill {
            return "已经截止了：填写入口关闭，已有的答卷仍然可以看。"
        }
        if !detail.canSeeResult {
            return "还没有人填写，等第一份答卷进来就能看结果。"
        }
        return nil
    }

    private func hintIcon(_ detail: SurveyDetail) -> String {
        return detail.canFill ? "info.circle" : "clock.badge.exclamationmark"
    }

    // MARK: - 发布 / 截止

    @ViewBuilder
    private func actionRowForStatus(_ detail: SurveyDetail) -> some View {
        if detail.status == "draft" {
            GlassListRow(icon: "paperplane", title: "发布问卷", detail: "发布后才能填") {
                showsPublishConfirm = true
            }
        } else if detail.status == "published" {
            GlassListRow(icon: "lock", title: "截止这份问卷", detail: "关闭填答入口") {
                showsCloseConfirm = true
            }
        }
    }

    private func runAction(publish: Bool) {
        // 发布 / 截止都是"状态变化"，用 warning 档触觉（PRD §4 #7 的分层约定）
        Haptics.selection()
        Task {
            if publish {
                _ = await store.publish(id: surveyId)
            } else {
                _ = await store.close(id: surveyId)
            }
        }
    }

    // MARK: - 骨架与刷新

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock(width: 240, height: 26)
                SkeletonBlock(width: 90, height: 18)
                SkeletonBlock(height: 14)
                SkeletonBlock(width: 200, height: 14)
            }
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

            HStack(spacing: 12) {
                SkeletonBlock(width: 110, height: 44, cornerRadius: 22)
                SkeletonBlock(width: 110, height: 44, cornerRadius: 22)
            }
        }
    }

    private func refresh() {
        Task {
            await store.loadDetail(id: surveyId, force: true)
        }
    }
}
