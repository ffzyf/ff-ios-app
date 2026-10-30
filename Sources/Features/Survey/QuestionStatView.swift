import Charts
import SwiftUI

/// 单题统计卡（PRD P11）：按题型分派图表。
///
/// 写 Chart 的手法刻意保持**最朴素**（`BarMark(x:y:)` + `String` × `Int`）：
/// 泛型组合、`Plottable` 自定义类型、坐标轴样式闭包在 CI 的无签名编译下最容易报
/// "无法推断泛型参数"（设计文档 R11 已点过名），而这里只需要一根柱子一个人数。
///
/// 题型对应的呈现（PRD P11 逐条）：
/// · 单选 / 多选 / 下拉 → 条形图 + 人数 + 百分比
/// · 评分 / 量表       → 均值 + 分布
/// · 日期             → 按月聚合的柱状图
/// · 文本             → 回答列表（默认折叠前 5 条）
struct QuestionStatView: View {
    let stat: QuestionStat
    /// 从 0 开始的题号
    let index: Int

    /// 文本题是否展开全部
    @State private var showsAllTexts: Bool = false

    init(stat: QuestionStat, index: Int) {
        self.stat = stat
        self.index = index
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                content
                footer
            }
            .padding(Spacing.cardPadding)
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(index + 1). \(displayTitle)")
                .font(Typography.titleS)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(typeLabel)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background { Capsule().fill(Theme.surfaceTint3) }

                Text("\(stat.answered) 人作答")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()

                if stat.skipped > 0 {
                    Text("\(stat.skipped) 人跳过")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var displayTitle: String {
        let trimmed = stat.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名题目" : trimmed
    }

    private var typeLabel: String {
        return stat.questionType?.label ?? "其他"
    }

    // MARK: - 按题型分发

    @ViewBuilder
    private var content: some View {
        switch stat.questionType {
        case .radio, .checkbox, .dropdown:
            choiceContent
        case .rating, .scale:
            scoreContent
        case .date:
            dateContent
        case .text, .none:
            textContent
        }
    }

    // MARK: - 选项类

    private var choiceContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stat.choiceSlices.isEmpty {
                emptyHint
            } else {
                barChart(stat.choiceSlices)
                VStack(spacing: 6) {
                    ForEach(stat.choiceSlices) { slice in
                        legendRow(label: slice.label, count: slice.count, rate: rate(of: slice.count))
                    }
                }
                if stat.questionType == .checkbox {
                    // 多选一个人的答案会命中多个选项，百分比加起来会超过 100%，必须说明
                    Text("多选题按「选了几次」计，百分比加起来会超过 100%。")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    // MARK: - 评分 / 量表

    private var scoreContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stat.bucketSlices.isEmpty {
                emptyHint
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(averageText)
                        .font(Typography.titleXL)
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Text("平均分 · 满分 \(maxValue)")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                }
                barChart(stat.bucketSlices)
                VStack(spacing: 6) {
                    ForEach(stat.bucketSlices) { slice in
                        // 分母用 answered：评分题的"跳过"不该算进分布
                        legendRow(label: slice.label + " 分", count: slice.count, rate: rate(of: slice.count))
                    }
                }
            }
        }
    }

    private var averageText: String {
        guard let average = stat.average else { return "—" }
        return String(format: "%.2f", average)
    }

    private var maxValue: Int {
        if let max = stat.max { return max }
        return stat.bucketSlices.compactMap { Int($0.id) }.max() ?? 5
    }

    // MARK: - 日期

    private var dateContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stat.dateSlices.isEmpty {
                emptyHint
            } else {
                barChart(stat.dateSlices)
                VStack(spacing: 6) {
                    ForEach(stat.dateSlices) { slice in
                        legendRow(label: slice.label, count: slice.count, rate: rate(of: slice.count))
                    }
                }
                Text("按月份聚合（服务端只保留到月）。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - 文本

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if displayTexts.isEmpty {
                emptyHint
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(displayTexts.enumerated()), id: \.offset) { pair in
                        HStack(alignment: .top, spacing: 8) {
                            Text("·")
                                .font(Typography.callout)
                                .foregroundStyle(Theme.textTertiary)
                            Text(pair.element)
                                .font(Typography.callout)
                                .foregroundStyle(Theme.textBody)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                    }
                }

                if allTexts.count > collapsedCount {
                    Button(action: {
                        Haptics.light()
                        withAnimation(Motion.expand) {
                            showsAllTexts.toggle()
                        }
                    }) {
                        Text(showsAllTexts ? "收起" : "展开全部 \(allTexts.count) 条")
                            .font(Typography.footnoteMedium)
                            .foregroundStyle(Theme.limeInk)
                    }
                    .buttonStyle(PressableStyle())
                }

                if stat.textTruncated == true {
                    Text("文本回答太多，服务端只保留前 50 条；完整内容去网页端看。")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    /// 默认折叠前 5 条（PRD P11）
    private var collapsedCount: Int { 5 }

    private var allTexts: [String] {
        let raw = stat.texts ?? []
        return raw.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var displayTexts: [String] {
        if showsAllTexts { return allTexts }
        return Array(allTexts.prefix(collapsedCount))
    }

    // MARK: - 复用块

    private func barChart(_ slices: [SurveyCountSlice]) -> some View {
        Chart(slices) { slice in
            BarMark(
                x: .value("选项", slice.label),
                y: .value("人数", slice.count)
            )
            .foregroundStyle(Theme.chartBar)
            .cornerRadius(4)
        }
        .frame(height: 150)
        .accessibilityLabel("\(displayTitle)的分布图")
    }

    private func legendRow(label: String, count: Int, rate: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Typography.footnote)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text("\(count)")
                .font(Typography.footnote)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(percentText(rate))
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }

    private var emptyHint: some View {
        Text("这一题还没有人作答。")
            .font(Typography.footnote)
            .foregroundStyle(Theme.textTertiary)
            .padding(.vertical, 8)
    }

    private var footer: some View {
        Group {
            // 「其他」选项的自定义文字：只在选项类题型出现（服务端 `otherTexts`）
            if !otherTextPreview.isEmpty {
                Text("「其他」里填的内容：" + otherTextPreview.joined(separator: "、"))
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 只预览前 3 条：完整内容在答卷明细里逐份看，卡片不该被长文本撑爆
    private var otherTextPreview: [String] {
        let raw = stat.otherTexts ?? []
        return raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - 百分比

    /// 分母用 `answered`（回答这一题的人数），不是总答卷数
    private func rate(of count: Int) -> Double {
        guard stat.answered > 0 else { return 0 }
        return Double(count) / Double(stat.answered)
    }

    private func percentText(_ rate: Double) -> String {
        return "\(Int((rate * 100).rounded()))%"
    }
}
