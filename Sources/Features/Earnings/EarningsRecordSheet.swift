import SwiftUI

// MARK: - 表单的会话级默认值

/// 记账表单的会话级默认值（**不落盘**）。
///
/// 只留一个「上次选的日期」：一个活动常有多笔奖励，连着补记时日期往往相同，
/// 记完第一笔后下一笔默认还用这一天（网站版也是这个手感）。
///
/// 为什么不写 `UserDefaults`：这不是业务数据，只是"下次打开更省事"的一个默认值；
/// 存进磁盘就多一份可能与服务端不一致的状态，重启 App 回到今天没有任何损失。
enum EarningsRecordDraft {

    /// 上次用过的日期（nil = 还没记过）
    private static var lastDate: Date?
    /// `lastDate` 是哪一天写进去的（用来判断"还算不算最近"）
    private static var lastDateSavedAt: Date?

    /// 打开表单时默认选哪一天。
    ///
    /// 规则：**同一自然日内的下一笔沿用上次日期；隔天就回到今天**。
    /// 为什么不永久沿用：补记完一批旧账、关掉页面，过几天再来记账时如果默认还停在旧日期，
    /// 一不小心就把今天到账的钱记到上个月 —— 金额和月份归属会一起错。
    static func initialDate(now: Date = Date()) -> Date {
        guard let last = lastDate, let savedAt = lastDateSavedAt else { return now }
        return beijingCalendar.isDate(savedAt, inSameDayAs: now) ? last : now
    }

    /// 记下这次用的日期（保存成功后调用），供当天的下一笔沿用
    static func remember(_ date: Date, now: Date = Date()) {
        lastDate = date
        lastDateSavedAt = now
    }

    /// 北京时间日历：日期归属与 `Formatters` 一致（跨时区用户看到的"今天"必须是同一个今天）
    private static var beijingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Formatters.beijing
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    /// 把日期钉在**北京时间当天中午 12 点**再转毫秒。
    ///
    /// 为什么不直接用 `date.timeIntervalSince1970`：`DatePicker` 给的是本地时区那一天的 00:00，
    /// 换算成毫秒后服务端按自己的时区解释，跨时区时可能把「8 月 3 日」记成 8 月 2 日。
    /// 钉在中午，任何 ±12 小时内的时区偏移都不会漂日期。
    static func millis(for date: Date) -> Int {
        let parts = beijingCalendar.dateComponents([.year, .month, .day], from: date)
        var noon = DateComponents()
        noon.year = parts.year
        noon.month = parts.month
        noon.day = parts.day
        noon.hour = 12
        noon.minute = 0
        noon.second = 0
        let anchored = beijingCalendar.date(from: noon) ?? date
        return Int(anchored.timeIntervalSince1970 * 1000)
    }
}

// MARK: - 记账表单

/// 「记一笔」表单 —— 对齐**网站版**的记账模型，不是记账 App 的通用模型。
///
/// 与网站版的四条一致性（这就是"把网站版的记账功能拿过来"的字面意思）：
/// 1. **两层结构**：先选活动（`activity`），再往里挂 entry。没有活动就记不了账；
/// 2. **只记收入**：没有"收入 / 支出"开关 —— 网站文档明确「本产品只记收入」；
/// 3. **待发 / 已发是服务端字段**：新记的恒为待发，这里只做展示说明，不伪造可写字段；
/// 4. **写服务端**：`POST /api/app/earnings/entry`，App 本地不存账本。
///    存本地就成了第二个真相源，网页端与 App 必然对不上账。
///
/// 汇总也不在这里算：顶部与 `EarningsView.heroCard` 用的是同一份服务端 `EarningsSummary`。
struct EarningsRecordSheet: View {

    @ObservedObject private var store = EarningsStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var activityId: String?
    @State private var amountText: String = ""
    @State private var typeText: String = ""
    @State private var date: Date = EarningsRecordDraft.initialDate()
    @State private var note: String = ""
    @State private var isSaving: Bool = false
    /// 刚记成功 → 显示「再记一笔」提示
    @State private var didJustSave: Bool = false
    /// 可直接上屏的错误（409 / 401 / 离线）
    @State private var errorText: String?

    @FocusState private var isAmountFocused: Bool

    /// 显式 init：本 View 的存储属性全是私有 `@State` / `@ObservedObject`，
    /// 走 memberwise init 会被降级成 `private`（跨文件 `EarningsRecordSheet()` 就编不过）。
    /// 所有属性都自带默认值，空 init 即可。
    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleRow

                if store.activities.isEmpty {
                    // 没有活动 = 没有记账入口（entry 必须挂在活动下）
                    EarningsRecordNoActivityHint()
                    footerNote
                } else {
                    EarningsRecordActivityPicker(activities: store.activities, selectedId: $activityId)
                    EarningsRecordAmountField(text: $amountText, isFocused: $isAmountFocused, cents: amountCents)
                    EarningsRecordTypeField(text: $typeText, recent: recentTypes)
                    EarningsRecordPaidRow()
                    EarningsRecordDateRow(date: $date)
                    EarningsRecordNoteField(text: $note)
                    saveBlock
                    footerNote
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: prepare)
        .onChange(of: amountText) { _, newValue in
            // 用户开始输下一笔 → 收起「再记一笔」那行（清空自身不会触发，因为清成空串）
            if newValue.isEmpty == false {
                didJustSave = false
            }
        }
    }

    // MARK: - 头部

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("记一笔")
                    .font(Typography.titleL)
                    .foregroundStyle(Theme.textPrimary)
                Text("写进服务端，网页端立刻是同一笔。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background { Circle().fill(Theme.surfaceTint2) }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("关闭")
        }
    }

    // MARK: - 保存

    private var saveBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                save()
            } label: {
                if isSaving {
                    ProgressView().controlSize(.small).tint(Theme.onLime)
                } else {
                    Text("记下这笔")
                }
            }
            .buttonStyle(PrimaryCTAStyle())
            .opacity(canSave ? 1 : 0.55)
            .disabled(canSave == false || isSaving)

            if let errorText {
                Text(errorText)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.statusError)
            } else if didJustSave {
                Text("记上了。再记一笔 —— 金额已清空，类型和活动还留着。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.limeInk)
            } else if canSave == false {
                Text("金额大于 0、填了类型才能保存。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 页脚（只展示服务端给的数）

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary = store.summary {
                Text("服务端当前：待发 " + EarningsMoney.formatCents(summary.pending)
                     + " · 本月新增 " + EarningsMoney.formatCents(summary.monthAdded))
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            Text("只记收入：金额、类型、日期写进服务端后，汇总由服务端算，App 与网页端读的是同一份账。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 计算

    /// 金额（整数分）；`nil` = 空 / 中间态（`"."`），`0` = 还没输到钱
    private var amountCents: Int? {
        return EarningsRecordAmount.cents(from: amountText)
    }

    /// 金额 ≤ 0 或 类型为空 → 不能保存（另加：必须选了活动）
    private var canSave: Bool {
        guard activityId != nil else { return false }
        guard let cents = amountCents, cents > 0 else { return false }
        return typeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// 最近用过的类型（置顶，最多 6 个）：按 entry 时间倒序取，去重，截到 12 字。
    ///
    /// 不做本地存储 —— 服务端数据本身就是「最近用过」的唯一来源，
    /// 这样在网页端记的类型，手机上也能一点即填。
    private var recentTypes: [String] {
        var seen = Set<String>()
        var result: [String] = []
        let entries = store.activities
            .flatMap { $0.liveEntries }
            .sorted { $0.time > $1.time }
        for entry in entries {
            let name = String(entry.type
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(EarningsRecordTypeField.maxLength))
            guard name.isEmpty == false, seen.contains(name) == false else { continue }
            seen.insert(name)
            result.append(name)
            if result.count >= 6 { break }
        }
        return result
    }

    // MARK: - 动作

    private func prepare() {
        if activityId == nil {
            activityId = store.activities.first?.id
        }
        if typeText.isEmpty, let first = recentTypes.first {
            // 预填最近用过的类型：连续录入同一活动的同类奖励时，少打一次字
            typeText = first
        }
        if store.activities.isEmpty == false {
            // 记一笔的第一步永远是输金额
            isAmountFocused = true
        }
    }

    private func save() {
        let trimmedType = typeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let activityId, let cents = amountCents, cents > 0, trimmedType.isEmpty == false, isSaving == false else {
            Haptics.error()
            return
        }

        isSaving = true
        errorText = nil
        let pickedDate = date
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let input = EarningsEntryInput(
            activityId: activityId,
            type: trimmedType,
            // 契约要求的兼容字段（元）。**全工程唯一的 Double 金额**，整数分才是真值。
            amount: Double(cents) / 100,
            amountCents: cents,
            currency: "CNY",
            date: Formatters.isoDate(pickedDate),
            time: EarningsRecordDraft.millis(for: pickedDate),
            note: trimmedNote
        )

        Task {
            do {
                try await store.addEntry(input)
                Haptics.success()
                didJustSave = true
                // 连续录入是主场景：清金额、焦点留在金额框、类型与活动都留着
                amountText = ""
                EarningsRecordDraft.remember(pickedDate)
                isAmountFocused = true
            } catch let error as APIError {
                Haptics.error()
                errorText = error.userMessage
            } catch {
                Haptics.error()
                errorText = "没记上，稍后再试。"
            }
            isSaving = false
        }
    }
}
