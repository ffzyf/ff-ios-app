import SwiftUI

/// 填答页（PRD P10）。
///
/// 五条硬要求，逐条对应实现：
/// 1. **逐题作答 + 进度条**：进度按"可见题目"算（`showIf` 隐藏的题不计入分母）；
/// 2. **提交失败保留已填内容**：答案只存在本视图的 `@State answers` 里，
///    提交失败只加一条错误行，绝不 `answers.removeAll()`；
/// 3. **未发布 / 已截止 → 整页提示「该问卷未开放」**：公开接口对这些情况返回 403，
///    服务端原话最准（可能是"已截止，感谢参与"），页面把它当整页状态而不是 toast；
/// 4. **断网禁止提交**：`store.isOnline` 由 `NWPathMonitor` 驱动，
///    离线时按钮禁用并给出顶部细条 —— 让用户点了才发现没网是最差的一种交互；
/// 5. **不需要登录**：走公开接口（`/public` + `/submit`），凭证完全不参与。
struct SurveyFillView: View {
    let surveyId: String

    @ObservedObject private var store = SurveyStore.shared

    /// 已填答案：题目 id → 值。这是**唯一**的答案来源，提交成功前不会被清空
    @State private var answers: [String: SurveyAnswerValue] = [:]
    @State private var errorText: String?
    /// 非 nil = 已提交成功，显示完成态（内容是服务端的 `submitTip`）
    @State private var successTip: String?

    private let onBack: () -> Void

    init(surveyId: String, onBack: @escaping () -> Void) {
        self.surveyId = surveyId
        self.onBack = onBack
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                SurveyPageHeader(
                    title: "填写问卷",
                    subtitle: surveyTitle,
                    onBack: onBack
                )
                bodyContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 6)
            .padding(.bottom, Spacing.pageBottomInset)
            // 填答列宽 640（§3.9 / §3.1）：输入型页面，行越宽越难对着题干读选项。
            .pageColumn(Layout.formMaxWidth)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !store.isOnline && successTip == nil {
                OfflineBanner(kind: .offline, text: "现在没网，先填着，联网后再提交。")
                    .padding(.horizontal, Spacing.page)
                    .padding(.bottom, 6)
                    // 与主体同一个列宽（640，见 body 里的 `pageColumn`）：填答页是表单列，
                    // 细条若按满宽画，iPad 上会比输入框宽出一大截，看着像两套栅格。
                    // 窄屏 393 < 640，`maxWidth` 不生效 → 零影响。
                    .pageColumn(Layout.formMaxWidth)
            }
        }
        .task {
            // 每次都强拉：题面可能刚被改过，按旧题作答提交会被服务端拒（403/400 都很难解释）
            await store.loadForm(id: surveyId, force: true)
        }
    }

    // MARK: - 状态分发

    private var currentForm: SurveyPublic? {
        guard store.formId == surveyId else { return nil }
        return store.publicForm
    }

    private var surveyTitle: String? {
        guard let form = currentForm else { return nil }
        let trimmed = form.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let tip = successTip {
            completionCard(tip)
        } else if let form = currentForm {
            introCard(form)
            progressCard
            questionsSection
            if let errorText = errorText {
                errorRow(errorText)
            }
            submitButton
            Text("答卷是匿名的：服务端只记录提交城市与时间，用来给你看分布。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)
        } else if let error = store.formFailure, !store.isLoadingForm {
            // 403（未发布 / 已截止）与 404（不存在）在这里被统一成"未开放"
            unavailableCard(error)
        } else {
            fillSkeleton
        }
    }

    // MARK: - 说明卡

    private func introCard(_ form: SurveyPublic) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(form.title.isEmpty ? "未命名问卷" : form.title)
                    .font(Typography.titleL)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !form.descriptionText.isEmpty {
                    Text(form.descriptionText)
                        .font(Typography.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(Typography.lineSpacing(fontSize: 15, multiple: 1.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("共 \(form.structure.count) 题 · 带「必答」的要填完才能提交")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Spacing.cardPadding)
        }
    }

    // MARK: - 进度

    private var progressCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("已答 \(answeredCount) / \(visibleQuestions.count)")
                        .font(Typography.footnoteMedium)
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    Text(progressText)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.lime)
            }
            .padding(Spacing.smallCardPadding)
        }
        .animation(Motion.press, value: answeredCount)
    }

    private var progressText: String {
        if visibleQuestions.isEmpty { return "没有题目" }
        if answeredCount >= visibleQuestions.count { return "可以提交了" }
        return "还差 \(visibleQuestions.count - answeredCount) 题"
    }

    private var progress: Double {
        guard !visibleQuestions.isEmpty else { return 0 }
        return Double(answeredCount) / Double(visibleQuestions.count)
    }

    // MARK: - 题目

    private var questionsSection: some View {
        VStack(spacing: Spacing.cardGap) {
            ForEach(Array(visibleQuestions.enumerated()), id: \.element.id) { pair in
                SurveyQuestionCard(
                    question: pair.element,
                    index: pair.offset,
                    answer: answers[pair.element.id],
                    onChange: { value in
                        // 空值不留在字典里：提交时不需要再筛一遍，进度也不会把空串算成已答
                        answers[pair.element.id] = value.isFilled ? value : nil
                        // 已经报过"第 N 题必答"，用户一改动就把错误行撤掉，别让它一直红着
                        if errorText != nil {
                            errorText = nil
                        }
                    }
                )
            }
        }
    }

    // MARK: - 提交

    private var submitButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: submit) {
                HStack(spacing: 6) {
                    if store.isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(store.isSubmitting ? "提交中" : "提交")
                }
            }
            .buttonStyle(PrimaryCTAStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.45)

            if !store.isOnline {
                Text("现在没网，提交不了。先填着，联网后再点提交 —— 内容不会丢。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.statusWarn)
            } else if visibleQuestions.isEmpty {
                Text("这份问卷还没有题目，暂时不能提交。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var canSubmit: Bool {
        return store.isOnline && !store.isSubmitting && !visibleQuestions.isEmpty && successTip == nil
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(Typography.footnote)
                .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.statusError)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isStaticText)
    }

    private func submit() {
        guard canSubmit else { return }

        // 必答校验：只校验"可见"的题 —— 被 showIf 隐藏的题不该拦住用户
        if let index = visibleQuestions.firstIndex(where: { $0.isRequired && !isAnswered($0) }) {
            Haptics.error()
            errorText = "第 \(index + 1) 题是必答题，填完再提交。"
            return
        }

        errorText = nil
        let payload = collectAnswers()

        Task {
            let outcome = await store.submit(id: surveyId, answers: payload)
            switch outcome {
            case .success(let tip):
                Haptics.success()
                // 成功后清空答案：这份问卷已经交出去了，留着只会让人以为还能改
                answers = [:]
                withAnimation(Motion.glassIn) {
                    successTip = tip
                }
            case .failure(let message):
                Haptics.error()
                // ⚠️ 这里**绝不**清空 `answers`（PRD P10「提交失败保留已填内容」）
                errorText = message
            }
        }
    }

    private func collectAnswers() -> [String: SurveyAnswerValue] {
        var payload: [String: SurveyAnswerValue] = [:]
        for question in visibleQuestions {
            guard let value = answers[question.id], value.isFilled else { continue }
            payload[question.id] = value
        }
        return payload
    }

    // MARK: - 完成态

    private func completionCard(_ tip: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Theme.lime.opacity(0.16))
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.limeInk)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("提交成功")
                            .font(Typography.titleS)
                            .foregroundStyle(Theme.textPrimary)
                        Text("这份答卷已经在服务端了。")
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                }

                Text(tip)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 15, multiple: 1.6))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: {
                    onBack()
                }) {
                    Text("返回")
                }
                .buttonStyle(SecondaryCTAStyle())
            }
            .padding(Spacing.cardPadding)
        }
    }

    // MARK: - 未开放

    private func unavailableCard(_ error: APIError) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.surfaceTint2)
                Circle().strokeBorder(Theme.divider, lineWidth: 1)
                Image(systemName: "lock")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 76, height: 76)

            VStack(spacing: 6) {
                Text("该问卷未开放")
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)
                Text(error.userMessage)
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.5))
            }

            HStack(spacing: 10) {
                Button(action: {
                    Task { await store.loadForm(id: surveyId, force: true) }
                }) {
                    Text("再试一次")
                }
                .buttonStyle(SecondaryCTAStyle())

                Button(action: {
                    onBack()
                }) {
                    Text("返回")
                }
                .buttonStyle(PrimaryCTAStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, Spacing.page)
    }

    // MARK: - 骨架

    private var fillSkeleton: some View {
        VStack(spacing: Spacing.cardGap) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonBlock(width: 220, height: 16)
                    SkeletonBlock(height: 40, cornerRadius: Radius.insideCard)
                    SkeletonBlock(height: 40, cornerRadius: Radius.insideCard)
                }
                .padding(Spacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        }
    }

    // MARK: - 可见题与作答判断

    /// 可见题目（`showIf` 条件不满足的题不渲染、不计入进度、不参与校验）
    private var visibleQuestions: [SurveyQuestion] {
        guard let form = currentForm else { return [] }
        return form.structure.filter { isVisible($0) }
    }

    private func isVisible(_ question: SurveyQuestion) -> Bool {
        guard let condition = question.showIf, !condition.qid.isEmpty else { return true }
        guard let parent = answers[condition.qid] else { return false }
        if case .list(let values) = parent {
            return values.contains { value in
                if case .text(let text) = value { return text == condition.value }
                return value.displayText == condition.value
            }
        }
        return parent.displayText == condition.value
    }

    private func isAnswered(_ question: SurveyQuestion) -> Bool {
        guard let value = answers[question.id], value.isFilled else { return false }
        // 只勾了「其他」却没写字：与网页端 validate 的 otherOk 一致，算未答
        if case .text(let text) = value, text == "__other__" { return false }
        if case .list(let values) = value {
            let onlyEmptyOther = values.allSatisfy { item in
                if case .text(let text) = item { return text == "__other__" }
                return false
            }
            if onlyEmptyOther { return false }
        }
        return true
    }

    private var answeredCount: Int {
        return visibleQuestions.filter { isAnswered($0) }.count
    }
}
