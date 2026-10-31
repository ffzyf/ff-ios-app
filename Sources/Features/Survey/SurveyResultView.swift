import Charts
import SwiftUI

/// 结果看板（PRD P11）。
///
/// 结构：页头（右上「答卷明细」）→ 顶部「共 N 份 + 时间范围」→ 类型分布（若有）→
/// 每题一张卡 → 页脚说明。
///
/// 两条容易做错的细节：
/// 1. **`typeDistribution == nil` 时整块不渲染**（不是显示"暂无数据"）：
///    null 的语义是"这个问卷类型 V3 不做"（维度型 MBTI），不是"没人填"；
///    在这种问卷的页脚补一句「维度报告请在网页端查看」，避免用户以为功能坏了；
/// 2. 统计与明细来自**同一个响应**（服务端刻意合并），所以顶部「共 48 份」与
///    浮层里的条数永远一致 —— 页面不需要自己再对齐一次。
struct SurveyResultView: View {
    let surveyId: String

    @ObservedObject private var store = SurveyStore.shared
    @State private var showsResponses: Bool = false

    private let onBack: () -> Void

    init(surveyId: String, onBack: @escaping () -> Void) {
        self.surveyId = surveyId
        self.onBack = onBack
    }

    private var data: SurveyResultResponse? {
        guard store.resultId == surveyId else { return nil }
        return store.result?.value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                SurveyPageHeader(
                    title: "结果看板",
                    subtitle: headerSubtitle,
                    trailingTitle: "答卷明细",
                    trailingIcon: "list.bullet.rectangle",
                    onTrailing: trailingAction,
                    onBack: onBack
                )
                bodyContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 6)
            .padding(.bottom, Spacing.pageBottomInset)
            // 结果看板列宽 720（§3.9）：理由同详情页 —— 条形图的可比性依赖行宽一致。
            .pageColumn(Layout.contentMaxWidth)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await store.loadResult(id: surveyId, force: true)
        }
        .sheet(isPresented: $showsResponses) {
            if let data = data {
                SurveyResponsesSheet(responses: data.responses, questions: data.stats.perQuestion)
            }
        }
        .task {
            await store.loadResult(id: surveyId)
        }
    }

    // MARK: - 状态分发

    private var headerSubtitle: String? {
        guard let data = data else { return nil }
        let trimmed = data.survey.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var canOpenResponses: Bool {
        guard let data = data else { return false }
        return !data.responses.isEmpty
    }

    /// 没有明细时按钮不出现（不画一个点了没反应的灰按钮）
    private var trailingAction: (() -> Void)? {
        guard canOpenResponses else { return nil }
        return { openResponses() }
    }

    private func openResponses() {
        Haptics.light()
        showsResponses = true
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let data = data {
            windowCard(data)
            if let distribution = data.typeDistribution {
                distributionCard(distribution)
            }
            if data.stats.total == 0 {
                emptyCard
            } else if data.stats.perQuestion.isEmpty {
                emptyCard
            } else {
                VStack(spacing: Spacing.cardGap) {
                    ForEach(Array(data.stats.perQuestion.enumerated()), id: \.element.id) { pair in
                        QuestionStatView(stat: pair.element, index: pair.offset)
                    }
                }
            }
            footerNote(data)
        } else if let error = store.resultFailure, !store.isLoadingResult {
            ErrorStateView(
                icon: error.icon,
                title: error.title,
                message: error.hint,
                retryTitle: "重新加载",
                onRetry: {
                    Task { await store.loadResult(id: surveyId, force: true) }
                }
            )
        } else {
            resultSkeleton
        }
    }

    // MARK: - 顶部概况

    private func windowCard(_ data: SurveyResultResponse) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(data.window.total)")
                        .font(Typography.display)
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Text("份答卷")
                        .font(Typography.callout)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                    if data.survey.isTest {
                        BadgePill(kind: .pinned, text: "测评型")
                    }
                }

                Text(rangeText(data.window))
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            .padding(Spacing.cardPadding)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("共 \(data.window.total) 份答卷，\(rangeText(data.window))")
    }

    /// 时间范围：`firstAt`/`lastAt` 都没有时给"还没有答卷"，绝不画 `—` 占位
    private func rangeText(_ window: ResultWindow) -> String {
        guard let first = window.firstAt, let last = window.lastAt else {
            return "还没有收到答卷"
        }
        let firstText = Formatters.relativeDay(first)
        let lastText = Formatters.relativeDay(last)
        if firstText == lastText {
            return "提交时间 " + firstText
        }
        return "从 " + firstText + " 到 " + lastText
    }

    // MARK: - 类型分布

    private func distributionCard(_ distribution: TypeDistribution) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(distribution.kindLabel)
                        .font(Typography.titleS)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    Text("\(distribution.buckets.count) 个结果")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                }

                if distribution.buckets.isEmpty {
                    Text("还没有可以归类的答卷。")
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    Chart(distribution.buckets) { bucket in
                        BarMark(
                            x: .value("类型", bucket.label),
                            y: .value("人数", bucket.count)
                        )
                        .foregroundStyle(Theme.chartBar)
                        .cornerRadius(4)
                    }
                    .frame(height: 160)
                    .accessibilityLabel("类型分布图")

                    VStack(spacing: 6) {
                        ForEach(distribution.buckets) { bucket in
                            HStack(spacing: 8) {
                                Text(bucket.label)
                                    .font(Typography.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(bucket.count) 人")
                                    .font(Typography.footnote)
                                    .foregroundStyle(Theme.textPrimary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .padding(Spacing.cardPadding)
        }
    }

    // MARK: - 空态与页脚

    private var emptyCard: some View {
        EmptyStateView(
            icon: "tray",
            title: "还没有人填写。",
            message: "把填答链接发给朋友，收到第一份答卷就能看到每题分布。"
        )
    }

    @ViewBuilder
    private func footerNote(_ data: SurveyResultResponse) -> some View {
        if data.typeDistribution == nil {
            if data.survey.isTest {
                // 维度型测评（MBTI 等）：V3 的服务端明确返回 null（设计文档 §9 D-1），
                // 这里只解释"去哪儿看"，不假装 App 算不出来是 bug
                Text("维度报告请在网页端查看；App 只给每题分布。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                    .padding(.horizontal, 4)
            } else {
                Text("逐份答卷可以在右上「答卷明细」里展开看。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                    .padding(.horizontal, 4)
            }
        } else {
            Text("统计口径与网页端一致；明细最多显示最近 200 份。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)
        }
    }

    // MARK: - 骨架

    private var resultSkeleton: some View {
        VStack(spacing: Spacing.cardGap) {
            SkeletonBlock(height: 96, cornerRadius: Radius.card)
            ForEach(0..<2, id: \.self) { _ in
                SkeletonBlock(height: 260, cornerRadius: Radius.card)
            }
        }
    }
}
