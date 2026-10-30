import SwiftUI

/// 问卷列表卡（PRD P08）：标题 + 状态徽标 + 题目数 / 答卷数 / 更新时间。
///
/// 纯展示组件：卡片本身不接点击（列表页把它包在 `Button` 里），
/// 这样"卡片能点"这件事只有一个地方决定，将来改成 swipe 操作也不用改这里。
struct SurveyRowCard: View {
    let summary: SurveySummary
    /// 传入"现在"而不是在 body 里现取：列表里的所有卡必须用同一个时间基准
    /// （否则 23:59:59 渲染的卡片与 00:00:00 渲染的会显示不同状态）
    var now: Date = Date()

    init(summary: SurveySummary, now: Date = Date()) {
        self.summary = summary
        self.now = now
    }

    /// 「收集中」用青柠实心徽标，草稿 / 已截止用中性灰 ——
    /// 绿色只代表"现在能动"，全绿等于没有信号（与状态卡的配色铁律一致）。
    private var isCollecting: Bool { summary.isCollecting(now: now) }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Text(displayTitle)
                        .font(Typography.titleS)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    BadgePill(
                        kind: isCollecting ? .newVersion : .neutral,
                        text: summary.statusLabel(now: now)
                    )
                }

                HStack(spacing: 12) {
                    metaLabel(icon: "list.number", text: "\(summary.questionCount) 题")
                    metaLabel(icon: "tray.full", text: "\(summary.responseCount) 份")

                    Spacer(minLength: 8)

                    Text(updatedText)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .padding(Spacing.cardPadding)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayTitle)，\(summary.statusLabel(now: now))，\(summary.questionCount) 题，\(summary.responseCount) 份答卷")
    }

    // MARK: - 文案

    /// 标题为空时给"未命名问卷"而不是空行：卡片塌成一条线比占位文案更让人困惑
    private var displayTitle: String {
        let trimmed = summary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名问卷" : trimmed
    }

    private var updatedText: String {
        let relative = Formatters.relative(summary.updatedAt, now: now)
        return relative == "—" ? "更新时间未记录" : "更新于 " + relative
    }

    private func metaLabel(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(text)
                .font(Typography.captionXS)
                .monospacedDigit()
        }
        .foregroundStyle(Theme.textSecondary)
    }
}
