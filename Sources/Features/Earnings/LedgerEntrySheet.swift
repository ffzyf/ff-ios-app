import SwiftUI

/// 表单要打开的形态（新建 / 改一笔）。
///
/// 用一个 `Identifiable` 枚举而不是两个 `Bool`：`.sheet(item:)` 天然保证
/// 「同一时刻只有一张表单」，也保证改一笔时把那一笔的对象一起带进去。
///
/// `.create` 带一个 `defaultDate`：翻到 7 月点「记一笔」时，日期默认落在 7 月最后一天。
/// 否则表单默认今天、列表却停在 7 月，用户会以为"刚记的那笔没存上"。
enum LedgerSheetMode: Identifiable {
    case create(defaultDate: Date)
    case edit(LedgerEntry)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let entry): return entry.id.uuidString
        }
    }

    var entry: LedgerEntry? {
        switch self {
        case .create: return nil
        case .edit(let entry): return entry
        }
    }

    /// 新建时的默认日期
    var defaultDate: Date {
        switch self {
        case .create(let date): return date
        case .edit(let entry): return entry.date
        }
    }
}

/// 记一笔 / 改一笔的表单。
///
/// 金额输入的两个硬要求：
/// 1. `keyboardType(.decimalPad)` —— 只弹数字与小数点，iPhone 上省一次切键盘；
/// 2. **不用 `Double` 解析**：`LedgerMoney.parseAmount` 按「元」「分」两段逐位取数，
///    `"12.5"` 稳定变成 `1250` 分。表单里显示的就是解析结果（"记作 ¥12.50"），
///    用户能在按保存之前发现小数点错位。
struct LedgerEntrySheet: View {

    let mode: LedgerSheetMode
    /// 保存成功后回传这一笔（外层据此把月份切到它所在的那个月）
    let onSaved: (LedgerEntry) -> Void

    @ObservedObject private var store = LedgerStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var kind: LedgerEntry.Kind
    @State private var category: String
    @State private var date: Date
    @State private var note: String
    @FocusState private var isAmountFocused: Bool

    init(mode: LedgerSheetMode, onSaved: @escaping (LedgerEntry) -> Void = { _ in }) {
        self.mode = mode
        self.onSaved = onSaved
        let entry = mode.entry
        let initialKind = entry?.kind ?? .income
        _amountText = State(initialValue: entry.map { LedgerMoney.plainAmount(cents: $0.amountCents) } ?? "")
        _kind = State(initialValue: initialKind)
        _category = State(initialValue: entry?.category ?? LedgerStore.defaultCategory(for: initialKind))
        _date = State(initialValue: mode.defaultDate)
        _note = State(initialValue: entry?.note ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleRow
                kindPicker
                amountBlock
                categoryBlock
                dateBlock
                noteBlock
                saveButton
                disclaimer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // 新建时直接把光标放到金额上：记一笔的第一步永远是输金额
            if mode.entry == nil {
                isAmountFocused = true
            }
        }
        .onChange(of: kind) { _, newKind in
            // 切到收入/支出后，如果原分类不属于新方向，落到新方向的第一个分类
            let options = LedgerStore.categories(for: newKind)
            if options.contains(category) == false {
                category = options.first ?? ""
            }
        }
    }

    // MARK: - 标题

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isEditing ? "改一笔" : "记一笔")
                    .font(Typography.titleL)
                    .foregroundStyle(Theme.textPrimary)
                Text("只记在这台手机上，不进平台统计。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background { Circle().fill(Theme.surfaceTint2) }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("关闭")
        }
    }

    // MARK: - 收入 / 支出

    /// 自绘分段控件：系统的 `.segmented` 选中态用的是 accent 色 + 系统决定的字色，
    /// 而本工程要求「面上字」成对出现（`lime` 面 + `onLime` 字），所以这里自己画一组胶囊。
    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(LedgerEntry.Kind.allCases) { item in
                let selected = item == kind
                Button {
                    guard item != kind else { return }
                    Haptics.selection()
                    withAnimation(Motion.press) { kind = item }
                } label: {
                    Text(item.title)
                        .font(Typography.footnoteMedium)
                        .foregroundStyle(selected ? Theme.onLime : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background { Capsule().fill(selected ? Theme.lime : Theme.surfaceTint2) }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: - 金额

    private var amountBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("金额")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .font(LedgerType.amountInput)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .focused($isAmountFocused)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                    .fill(Theme.surfaceTint1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                    .strokeBorder(amountBroken ? Theme.statusError : Theme.divider, lineWidth: 1)
            }

            amountHint
        }
    }

    @ViewBuilder
    private var amountHint: some View {
        if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("小数最多两位，例如 12.5 会记成 12.50 元。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
        } else if let cents = parsedCents, cents > 0 {
            Text("记作 " + LedgerMoney.format(cents: cents))
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        } else if parsedCents == nil {
            Text("这个金额还读不出来，检查一下小数点。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.statusError)
        } else {
            Text("金额要大于 0 才能保存。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.statusWarn)
        }
    }

    // MARK: - 分类

    private var categoryBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("分类")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
                if category.isEmpty {
                    Text("选一个分类")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.statusWarn)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { name in
                        categoryChip(name)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func categoryChip(_ name: String) -> some View {
        let selected = name == category
        return Button {
            Haptics.selection()
            category = name
        } label: {
            Text(name)
                .font(Typography.footnoteMedium)
                .foregroundStyle(selected ? Theme.onLime : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background { Capsule().fill(selected ? Theme.lime : Theme.surfaceTint2) }
                .overlay {
                    Capsule().strokeBorder(selected ? Theme.glassStrokeTop : Theme.divider, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 当前方向下的分类；编辑老数据时把不在常量表里的分类也带出来（否则会显示成"没选"）
    private var categories: [String] {
        let base = LedgerStore.categories(for: kind)
        if category.isEmpty || base.contains(category) {
            return base
        }
        return base + [category]
    }

    // MARK: - 日期 / 备注

    private var dateBlock: some View {
        HStack(spacing: 10) {
            Text("日期")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
            DatePicker(
                "日期",
                selection: $date,
                in: ...Date(),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .tint(Theme.lime)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                .fill(Theme.surfaceTint1)
        }
    }

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            TextField("一句话说明（可选）", text: $note)
                .font(Typography.callout)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                        .fill(Theme.surfaceTint1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: 1)
                }
        }
    }

    // MARK: - 保存

    private var saveButton: some View {
        VStack(spacing: 8) {
            Button {
                save()
            } label: {
                Text(isEditing ? "保存修改" : "记下这笔")
            }
            .buttonStyle(PrimaryCTAStyle())
            .opacity(canSave ? 1 : 0.55)
            .disabled(canSave == false)

            if canSave == false {
                Text("金额大于 0 且选了分类才能保存。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disclaimer: some View {
        Text("账本 = 你自己记的流水；页面上的平台统计来自服务端，两者互不相加。")
            .font(Typography.captionXS)
            .foregroundStyle(Theme.textTertiary)
            .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
    }

    // MARK: - 计算 / 动作

    private var isEditing: Bool { mode.entry != nil }

    /// 输入框文字的解析结果；`nil` = 完全解析不出来（`0` = 解析出来但金额是 0）
    private var parsedCents: Int? {
        return LedgerMoney.parseAmount(amountText)
    }

    /// 边框标红：非空但解析不出来
    private var amountBroken: Bool {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false && parsedCents == nil
    }

    private var canSave: Bool {
        guard let cents = parsedCents else { return false }
        return cents > 0 && category.isEmpty == false
    }

    private func save() {
        guard let cents = parsedCents, cents > 0, category.isEmpty == false else {
            Haptics.error()
            return
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = LedgerEntry(
            id: mode.entry?.id ?? UUID(),
            date: date,
            amountCents: cents,
            kind: kind,
            category: category,
            note: trimmedNote
        )
        if isEditing {
            store.update(entry)
        } else {
            store.add(entry)
        }
        onSaved(entry)
        Haptics.success()
        dismiss()
    }
}
