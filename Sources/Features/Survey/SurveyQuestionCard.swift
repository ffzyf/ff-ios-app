import SwiftUI

/// 单题渲染（PRD P10：7 种题型）。
///
/// 设计成"受控组件"（`answer` 进、`onChange` 出）而不是 `@Binding`：
/// 父页面持有整份答案字典（提交、进度、校验都要用），单题只负责把一次交互翻译成
/// `SurveyAnswerValue` 回调出去 —— 值的形状（字符串 / 数组 / 数字）由这里决定，
/// 别的文件不需要知道 `__other__:` 这类后端约定。
///
/// 7 种题型的答案形状（与网页端 `renderer.js` 的 `collect()` 逐一对应）：
/// · radio / dropdown → `.text(选项)`，其他 → `.text("__other__:文字")`
/// · checkbox         → `.list([.text(选项), …])`
/// · rating / scale   → `.number(分值)`
/// · date             → `.text("2026-10-30")`
/// · text             → `.text(正文)`
struct SurveyQuestionCard: View {
    let question: SurveyQuestion
    /// 从 0 开始的题号（显示时 +1）
    let index: Int
    let answer: SurveyAnswerValue?
    let onChange: (SurveyAnswerValue) -> Void

    init(
        question: SurveyQuestion,
        index: Int,
        answer: SurveyAnswerValue?,
        onChange: @escaping (SurveyAnswerValue) -> Void
    ) {
        self.question = question
        self.index = index
        self.answer = answer
        self.onChange = onChange
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                titleBlock
                questionBody
            }
            .padding(Spacing.cardPadding)
        }
    }

    // MARK: - 题干

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1).")
                .font(Typography.titleS)
                .foregroundStyle(Theme.limeInk)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(question.questionType?.label ?? "网页端题型")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background { Capsule().fill(Theme.surfaceTint3) }

                    if question.isRequired {
                        Text("必答")
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.statusWarn)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var displayTitle: String {
        let trimmed = question.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名题目" : trimmed
    }

    // MARK: - 按题型分发

    @ViewBuilder
    private var questionBody: some View {
        switch question.questionType {
        case .radio:
            choiceList(multiple: false)
        case .checkbox:
            choiceList(multiple: true)
        case .dropdown:
            dropdownControl
        case .rating:
            ratingControl
        case .scale:
            scaleControl
        case .date:
            dateControl
        case .text:
            textControl
        case .none:
            Text("这一题的题型 App 还不认识，请在网页端填写。")
                .font(Typography.footnote)
                .foregroundStyle(Theme.statusWarn)
        }
    }

    // MARK: - 单选 / 多选

    private func choiceList(multiple: Bool) -> some View {
        VStack(spacing: 8) {
            ForEach(question.optionList, id: \.self) { option in
                optionRow(
                    title: option,
                    selected: multiple ? selectedTexts.contains(option) : singleText == option
                ) {
                    if multiple {
                        toggleOption(option)
                    } else {
                        onChange(.text(option))
                    }
                }
            }

            if question.allowsOther {
                otherRow(
                    selected: isOtherSelected,
                    onToggle: {
                        if multiple {
                            toggleOther()
                        } else if isOtherSelected {
                            onChange(.text(""))
                        } else {
                            onChange(.text("__other__"))
                        }
                    },
                    text: multiple ? listOtherBinding : singleOtherBinding
                )
            }
        }
    }

    private func optionRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? Theme.limeInk : Theme.textTertiary)

                Text(title)
                    .font(Typography.callout)
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                    .fill(selected ? Theme.lime.opacity(0.10) : Theme.surfaceTint1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                    .strokeBorder(selected ? Theme.limeInk.opacity(0.35) : Theme.divider, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    /// 「其他」行：左边是勾选圈，右边是可输入的文本框
    private func otherRow(selected: Bool, onToggle: @escaping () -> Void, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Button(action: {
                Haptics.selection()
                onToggle()
            }) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? Theme.limeInk : Theme.textTertiary)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("其他")

            Text("其他")
                .font(Typography.callout)
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)

            TextField("请填写", text: text)
                .font(Typography.callout)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .disabled(!selected)
                .opacity(selected ? 1 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                .fill(selected ? Theme.lime.opacity(0.10) : Theme.surfaceTint1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                .strokeBorder(selected ? Theme.limeInk.opacity(0.35) : Theme.divider, lineWidth: 1)
        }
    }

    // MARK: - 下拉

    private var dropdownControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                Button("请选择") {
                    onChange(.text(""))
                }
                ForEach(question.optionList, id: \.self) { option in
                    Button(option) {
                        onChange(.text(option))
                    }
                }
                if question.allowsOther {
                    Button("其他（在下方填写）") {
                        onChange(.text("__other__"))
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(dropdownText)
                        .font(Typography.callout)
                        .foregroundStyle(singleText.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                        .fill(Theme.surfaceTint1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: 1)
                }
            }
            .accessibilityLabel("下拉选择")

            if question.allowsOther && isOtherSelected {
                TextField("若选「其他」，在这里填写", text: singleOtherBinding)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                            .fill(Theme.surfaceTint1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                            .strokeBorder(Theme.divider, lineWidth: 1)
                    }
            }
        }
    }

    private var dropdownText: String {
        if singleText.isEmpty { return "请选择" }
        return SurveyAnswerValue.prettyOther(singleText)
    }

    // MARK: - 评分

    private var ratingControl: some View {
        HStack(spacing: 6) {
            ForEach(1...question.ratingMax, id: \.self) { value in
                Button(action: {
                    Haptics.selection()
                    onChange(.number(Double(value)))
                }) {
                    Text("\(value)")
                        .font(Typography.footnoteMedium)
                        .foregroundStyle(isRatingOn(value) ? Theme.onLime : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                                .fill(isRatingOn(value) ? Theme.lime : Theme.surfaceTint2)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                                .strokeBorder(isRatingOn(value) ? Theme.glassStrokeTop : Theme.divider, lineWidth: 1)
                        }
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(value) 分")
                .accessibilityAddTraits(isRatingOn(value) ? AccessibilityTraits.isSelected : AccessibilityTraits())
            }
        }
    }

    private func isRatingOn(_ value: Int) -> Bool {
        guard case .number(let current)? = answer else { return false }
        return Int(current.rounded()) >= value
    }

    // MARK: - 量表

    private var scaleControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(question.minAnchor)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 8)
                Text(question.maxAnchor)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(spacing: 6) {
                ForEach(question.scaleValues, id: \.self) { value in
                    Button(action: {
                        Haptics.selection()
                        onChange(.number(Double(value)))
                    }) {
                        Text("\(value)")
                            .font(Typography.footnoteMedium)
                            .foregroundStyle(isScaleOn(value) ? Theme.onLime : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background {
                                RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                                    .fill(isScaleOn(value) ? Theme.lime : Theme.surfaceTint2)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                                    .strokeBorder(isScaleOn(value) ? Theme.glassStrokeTop : Theme.divider, lineWidth: 1)
                            }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("\(value) 分")
                    .accessibilityAddTraits(isScaleOn(value) ? AccessibilityTraits.isSelected : AccessibilityTraits())
                }
            }
        }
    }

    private func isScaleOn(_ value: Int) -> Bool {
        guard case .number(let current)? = answer else { return false }
        return Int(current.rounded()) == value
    }

    // MARK: - 日期

    private var dateControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            DatePicker(
                "日期",
                selection: dateBinding,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .accessibilityLabel("选择日期")

            if singleText.isEmpty {
                Text("选好日期后才会记入答案。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// 答案存的是 `"2026-10-30"` 字符串（北京时间），不是 `Date` —— 转 Date 再序列化
    /// 会在时区边界把 30 号漂成 29 号（与红石日程同一类坑）。
    private var dateBinding: Binding<Date> {
        Binding(get: {
            return QuestionDateFormatter.parse(singleText) ?? Date()
        }, set: { newValue in
            onChange(.text(QuestionDateFormatter.string(from: newValue)))
        })
    }

    // MARK: - 文本

    private var textControl: some View {
        TextField(textPlaceholder, text: plainTextBinding, axis: .vertical)
            .lineLimit(3...6)
            .font(Typography.body)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                    .fill(Theme.surfaceTint1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.insideCard, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            }
            .accessibilityLabel("填空")
    }

    private var textPlaceholder: String {
        let trimmed = (question.placeholder ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "请输入" : trimmed
    }

    // MARK: - 值读写

    /// 单选 / 下拉 / 日期 / 文本共用的字符串值
    private var singleText: String {
        guard case .text(let value)? = answer else { return "" }
        // `__other__` 这类占位值不当正文用
        return value.hasPrefix("__other__") ? "" : value
    }

    private var selectedTexts: [String] {
        guard case .list(let values)? = answer else { return [] }
        return values.compactMap { value in
            guard case .text(let text) = value else { return nil }
            return text
        }
    }

    private var isOtherSelected: Bool {
        if case .text(let value)? = answer {
            return value.hasPrefix("__other__")
        }
        return selectedTexts.contains { $0.hasPrefix("__other__") }
    }

    /// 文本题：直接写正文。
    ///
    /// 刻意不复用 `singleOtherBinding`：那个绑定会写成 `__other__:文字`
    /// （单选 / 下拉的"其他"约定），用在填空上会把用户的正文加前缀，提交后统计里
    /// 变成一条"其他：……"，是数据污染级别的错。
    private var plainTextBinding: Binding<String> {
        Binding(get: {
            guard case .text(let value)? = answer else { return "" }
            return value
        }, set: { text in
            onChange(.text(text))
        })
    }

    /// 单选 / 下拉的「其他」文本（读回 `__other__:文字` 里的文字）
    private var singleOtherBinding: Binding<String> {        Binding(get: {
            guard case .text(let value)? = answer, value.hasPrefix("__other__:") else { return "" }
            return String(value.dropFirst("__other__:".count))
        }, set: { text in
            onChange(.text(text.isEmpty ? "__other__" : "__other__:" + text))
        })
    }

    /// 多选的「其他」文本
    private var listOtherBinding: Binding<String> {
        Binding(get: {
            guard let raw = selectedTexts.first(where: { $0.hasPrefix("__other__:") }) else { return "" }
            return String(raw.dropFirst("__other__:".count))
        }, set: { text in
            var current = selectedTexts.filter { !$0.hasPrefix("__other__") }
            current.append(text.isEmpty ? "__other__" : "__other__:" + text)
            onChange(.list(current.map { .text($0) }))
        })
    }

    private func toggleOption(_ option: String) {
        var current = selectedTexts
        if let index = current.firstIndex(of: option) {
            current.remove(at: index)
        } else {
            current.append(option)
        }
        onChange(.list(current.map { .text($0) }))
    }

    private func toggleOther() {
        var current = selectedTexts
        if current.contains(where: { $0.hasPrefix("__other__") }) {
            current.removeAll { $0.hasPrefix("__other__") }
        } else {
            current.append("__other__")
        }
        onChange(.list(current.map { .text($0) }))
    }
}

// MARK: - 日期格式

/// `"2026-10-30"` ↔ `Date`，固定按北京时间，
/// 与 `Formatters.isoDate` 用同一套规则（否则会差一天）。
enum QuestionDateFormatter {
    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Formatters.beijing
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: trimmed)
    }

    static func string(from date: Date) -> String {
        return Formatters.isoDate(date)
    }
}
