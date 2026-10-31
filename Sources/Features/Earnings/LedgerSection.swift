import SwiftUI

/// 收益页里的「我的手记」区块：本月小结 + 记一笔入口 + 按天分组的流水。
///
/// **口径红线**（这个区块存在的全部意义）：上面的 `heroCard` / `breakdownCard` 是服务端
/// 从各平台后台抓来的收益，这里的账本是用户自己敲进去的流水。两者**绝不相加、绝不互相覆盖**，
/// 所以本区块有自己的标题与说明，且所有数字都只从 `LedgerStore` 读，一个 `EarningsSummary`
/// 的字段都不碰。
///
/// 布局三段（故意与上面的卡片区分开，一眼能看出"这是另一套数"）：
/// 1. 标题行 + 说明 + 青柠实心「记一笔」；
/// 2. 小结卡：月份步进 + 收入 / 支出 / 结余 三连大数字（rounded）；
/// 3. 流水：按天分组的玻璃卡，行内左滑删除、点按修改。
struct LedgerSection: View {

    @ObservedObject private var store = LedgerStore.shared

    /// 当前浏览的月份（默认本月，可往前翻）
    @State private var month: Date = Date()
    /// 正在打开的表单（新建 / 改一笔）
    @State private var sheetMode: LedgerSheetMode?
    /// 当前滑开的那一行（保证同时只有一行露出删除按钮）
    @State private var openEntryID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            header
            summaryCard
            listSection
            if store.saveFailed {
                saveWarning
            }
        }
        .sheet(item: $sheetMode) { mode in
            LedgerEntrySheet(mode: mode) { entry in
                // 存下的那一笔可能落在别的月份（翻到 7 月却把日期改成了 6 月）：
                // 列表跟过去，别让用户以为"记了但没出现"
                month = entry.date
                openEntryID = nil
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text("我的手记")
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Button {
                    Haptics.light()
                    openEntryID = nil
                    sheetMode = .create(defaultDate: defaultDate)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("记一笔")
                    }
                }
                .buttonStyle(PrimaryCTAStyle())
                .accessibilityLabel("记一笔")
            }

            Text("自己记的账，不参与上面的平台统计。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - 月度小结

    private var summary: LedgerMonthSummary {
        return store.monthSummary(of: month)
    }

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                monthStepper

                HStack(alignment: .top, spacing: 0) {
                    moneyCell(title: "收入", cents: summary.incomeCents, tint: LedgerInk.income)
                    statDivider
                    moneyCell(title: "支出", cents: summary.expenseCents, tint: LedgerInk.expense)
                    statDivider
                    moneyCell(
                        title: "结余",
                        cents: summary.balanceCents,
                        tint: LedgerInk.signed(summary.balanceCents)
                    )
                }
            }
            .padding(Spacing.cardPadding)
        }
    }

    private var monthStepper: some View {
        HStack(spacing: 8) {
            Text(LedgerLabel.month(month))
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
            if LedgerLabel.isCurrentMonth(month) {
                Text("本月")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.limeInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background { Capsule().fill(Theme.surfaceTint2) }
            }
            Spacer(minLength: 0)
            stepButton(systemName: "chevron.left", label: "上个月", disabled: false) {
                shiftMonth(by: -1)
            }
            stepButton(systemName: "chevron.right", label: "下个月", disabled: LedgerLabel.isCurrentMonth(month)) {
                shiftMonth(by: 1)
            }
        }
    }

    private func stepButton(
        systemName: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 26, height: 26)
                .background { Circle().fill(Theme.surfaceTint2) }
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private func moneyCell(title: String, cents: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            Text(LedgerMoney.format(cents: cents))
                .font(LedgerType.summaryValue)
                .foregroundStyle(tint)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: 1, height: 28)
            .padding(.horizontal, 4)
    }

    /// 新建时的默认日期：本月 → 今天；翻到历史月 → 那个月的最后一天
    private var defaultDate: Date {
        let calendar = LedgerStore.calendar
        let now = Date()
        if LedgerLabel.isCurrentMonth(month) {
            return now
        }
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return now }
        return calendar.date(byAdding: .day, value: -1, to: interval.end) ?? now
    }

    private func shiftMonth(by value: Int) {
        guard let next = LedgerStore.calendar.date(byAdding: .month, value: value, to: month) else { return }
        // 不往后翻到未来：未来的账还没发生，翻过去只会看到一张空表
        if value > 0, LedgerLabel.isCurrentMonth(next) == false {
            return
        }
        withAnimation(Motion.press) {
            month = next
            openEntryID = nil
        }
    }

    // MARK: - 流水

    private var groups: [LedgerDayGroup] {
        return store.dayGroups(in: month)
    }

    @ViewBuilder
    private var listSection: some View {
        if groups.isEmpty {
            emptyCard
        } else {
            VStack(spacing: Spacing.cardGap) {
                ForEach(groups) { group in
                    dayBlock(group)
                }
                Text("点一行可以改，左滑可以删。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func dayBlock(_ group: LedgerDayGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(LedgerLabel.day(group.day))
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
                Text(LedgerMoney.formatSigned(cents: group.totalCents))
                    .font(LedgerType.groupTotal)
                    .foregroundStyle(LedgerInk.signed(group.totalCents))
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)

            GlassCard {
                VStack(spacing: 0) {
                    ForEach(group.entries) { entry in
                        LedgerRow(
                            entry: entry,
                            isOpen: openBinding(for: entry),
                            onTap: {
                                Haptics.light()
                                openEntryID = nil
                                sheetMode = .edit(entry)
                            },
                            onDelete: {
                                remove(entry)
                            }
                        )
                        if entry.id != group.entries.last?.id {
                            Rectangle()
                                .fill(Theme.divider)
                                .frame(height: 1)
                                .padding(.leading, Spacing.cardPadding)
                        }
                    }
                }
                // 与卡片同形状裁切：左滑时内容不会溢到卡片圆角外面
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        }
    }

    private func openBinding(for entry: LedgerEntry) -> Binding<Bool> {
        return Binding(
            get: { openEntryID == entry.id },
            set: { isOpen in
                if isOpen {
                    openEntryID = entry.id
                } else if openEntryID == entry.id {
                    openEntryID = nil
                }
            }
        )
    }

    private func remove(_ entry: LedgerEntry) {
        withAnimation(Motion.press) {
            store.delete(id: entry.id)
            if openEntryID == entry.id {
                openEntryID = nil
            }
        }
    }

    // MARK: - 空态

    private var emptyCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.surfaceTint2)
                    Circle()
                        .strokeBorder(Theme.divider, lineWidth: 1)
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(width: 56, height: 56)

                VStack(spacing: 5) {
                    Text(emptyTitle)
                        .font(Typography.titleS)
                        .foregroundStyle(Theme.textPrimary)
                    Text("稿费、广告进来一笔就记一笔，月底不用对着平台流水一点点回想。")
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.5))
                }

                Button {
                    Haptics.light()
                    sheetMode = .create(defaultDate: defaultDate)
                } label: {
                    Text("记第一笔")
                }
                .buttonStyle(PrimaryCTAStyle())
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .padding(.horizontal, Spacing.cardPadding)
        }
    }

    private var emptyTitle: String {
        return LedgerLabel.isCurrentMonth(month) ? "这个月还没记过账。" : "这个月没有账目。"
    }

    // MARK: - 落盘失败提示

    private var saveWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.statusWarn)
            Text("刚记的账没能写进手机，重启 App 可能会丢，稍后再记一次。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.statusWarn)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}
