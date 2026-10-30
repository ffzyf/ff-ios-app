import SwiftUI

/// 答卷明细浮层（PRD P11「右上答卷明细」）。
///
/// 三条约定：
/// 1. **倒序**：服务端 `listResponses` 已按 `created_at DESC` 返回，这里不再排 ——
///    再排一次只会在"同一秒提交"时把顺序弄乱；
/// 2. **点一行展开逐题答案**：默认只显示时间与地点，答案折叠（一份问卷 20 题，
///    全部展开等于一屏 20 段文字，谁也不想滚）；
/// 3. **不显示 ip / ua**：服务端刻意没有下发（`projectResponses` 只给 id / 时间 / 地点 / 答案），
///    App 也不去猜。
struct SurveyResponsesSheet: View {
    let responses: [SurveyResponseRow]
    let questions: [QuestionStat]

    @Environment(\.dismiss) private var dismiss
    /// 当前展开的那一份（nil = 全部折叠）
    @State private var expandedId: String?

    init(responses: [SurveyResponseRow], questions: [QuestionStat]) {
        self.responses = responses
        self.questions = questions
    }

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground(glow: false)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.cardGap) {
                    header
                    if responses.isEmpty {
                        EmptyStateView(
                            icon: "tray",
                            title: "还没有答卷。",
                            message: "有人提交后，这里会按时间倒序排出来。"
                        )
                    } else {
                        ForEach(Array(responses.enumerated()), id: \.element.id) { pair in
                            row(pair.element, number: pair.offset + 1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.page)
                .padding(.top, 12)
                .padding(.bottom, Spacing.page)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("答卷明细")
                    .font(Typography.titleL)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            IconGlassButton(icon: "xmark", size: 36) {
                dismiss()
            }
            .accessibilityLabel("关闭")
        }
    }

    private var subtitle: String {
        if responses.isEmpty { return "空空如也" }
        return "共 \(responses.count) 份 · 新的在上面"
    }

    // MARK: - 一行

    private func row(_ item: SurveyResponseRow, number: Int) -> some View {
        let isExpanded = (expandedId == item.id)
        return Button(action: {
            Haptics.light()
            withAnimation(Motion.expand) {
                expandedId = isExpanded ? nil : item.id
            }
        }) {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        Text("#\(number)")
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                            .frame(minWidth: 28, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Formatters.relativeDay(item.createdAt))
                                .font(Typography.footnoteMedium)
                                .foregroundStyle(Theme.textPrimary)
                                .monospacedDigit()
                            if !item.locationText.isEmpty {
                                Text(item.locationText)
                                    .font(Typography.captionXS)
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 8)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    if isExpanded {
                        VStack(alignment: .leading, spacing: 10) {
                            Rectangle()
                                .fill(Theme.divider)
                                .frame(height: 1)

                            if answers(of: item).isEmpty {
                                Text("这份答卷没有留下任何答案。")
                                    .font(Typography.footnote)
                                    .foregroundStyle(Theme.textTertiary)
                            } else {
                                ForEach(answers(of: item)) { answer in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(title(for: answer.id))
                                            .font(Typography.captionXS)
                                            .foregroundStyle(Theme.textTertiary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(answer.text)
                                            .font(Typography.callout)
                                            .foregroundStyle(Theme.textBody)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.cardPadding)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint(isExpanded ? "收起逐题答案" : "展开逐题答案")
    }

    // MARK: - 数据

    private var questionOrder: [String] {
        return questions.map { $0.id }
    }

    private func answers(of item: SurveyResponseRow) -> [SurveyAnswerItem] {
        return item.orderedAnswers(questionOrder)
    }

    private func title(for questionId: String) -> String {
        guard let stat = questions.first(where: { $0.id == questionId }) else {
            return "题目"
        }
        let trimmed = stat.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名题目" : trimmed
    }
}
