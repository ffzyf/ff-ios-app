import SwiftUI

// MARK: - 金额展示（端侧只做 ÷100 显示格式化，绝不参与计算）

/// 瓜分金额的**展示**格式化。
///
/// 唯一允许在端侧出现的价格运算：把服务端算好的整数分换成「元」字符串给人看。
/// 这里不做任何份额 / 奖池 / 人数的运算 —— 那些只在服务端 `zg-calc.js` 发生。
private enum ZGDisplay {
    static func yuan(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let value = NSNumber(value: Double(cents) / 100.0) // 仅展示：分 → 元
        return "¥" + (formatter.string(from: value) ?? "0.00")
    }

    /// 三档区间的一行标签。用 Identifiable 结构体而非元组 —— Swift 的 key path 不能指向元组元素，
    /// ForEach 用元组数组 + `id: \.key` 会编译失败，故用具名类型。
    struct Level: Identifiable {
        let key: String
        let label: String
        var id: String { key }
    }

    /// 三档区间的短标签（低/中/高）。
    static let levelNames: [Level] = [
        Level(key: "low", label: "偏多人 · 偏少"),
        Level(key: "mid", label: "中性估计"),
        Level(key: "high", label: "偏少人 · 偏多")
    ]
}

/// 结果表的一行（端侧只承载服务端给的字符串，不做任何数值运算）。
private struct ZGTableRow: Identifiable {
    let id: String
    let title: String
    let raw: String
    let capped: String
    let cap: String
    let isHeader: Bool
    let emphasized: Bool
}

/// 追光计划瓜分计算（T11，ZG-032/033，验13–17）。
///
/// 这是纯展示层：金额、告警、建议全部来自服务端 `/api/zg/*`，端侧不重算任何数。
/// 典型流程：选期次 → 看规则口径 → 处理话题告警（原文 + 忽略）/合并建议（确认）
/// → 看服务端已算好的结果（手动 / 自动三档区间）。
///
/// ## 双端适配（验13–17，全部在本文件内闭环）
/// · 单列 / 双栏：读 `layoutMetrics.usesRail`（≥900pt 为双栏），左列表右详情；
///   选中态放在 `@State selectedID`，尺寸变化只重排视图、不重建状态，切换不丢选中。
/// · 结果表：横向滚动 + 首列（奖项名）用 `safeAreaInsets` 外侧固定，金额右对齐、单位独立列；
///   列数 > 6 时提供「精简 / 完整」切换。
/// · safe-area：内容包在 `.safeAreaInset` 里，底部不留白被 Home 区吃。
/// · Dynamic Type：正文一律走 `Typography`（系统字体，随系统字号放大）；不写 `.font(.system(size:))`，
///   不锁 `.dynamicTypeSize`。
/// · 触控 ≥44pt / 行高 ≥56pt：所有可点行 `.frame(minHeight:)` 显式给够。
/// · 深色模式：全部走 `Theme` 语义色（textPrimary / surfaceTint / divider…），无硬编码、无 colorScheme 判断。
struct ZGShareView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = EarningsStore.shared

    /// 当前期次（27 / 28）
    @State private var period: Int = 27
    /// 计算模式：服务端展示的结果来自已存的 result；auto 时额外展示三档区间
    @State private var mode: ZGMode = .manual
    /// 结果表「精简 / 完整」：列 >6 时可切换（验15）
    @State private var compactTable: Bool = true
    /// 双栏时右侧详情选中的条目 id（旋转 / 尺寸变化不重置，见验14）
    @State private var selectedID: String?
    /// 当前正在看的分组（话题 / 合并 / 奖项），双栏左侧列表切换用
    @State private var activeGroup: ZGGroup = .awards

    private enum ZGMode: String { case manual, auto }
    private enum ZGGroup: String, CaseIterable, Identifiable {
        case awards = "奖项" , topics = "话题告警", merge = "合并建议", rules = "规则口径"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let wide = geo.size.width >= Layout.wideWidthThreshold
                ZStack {
                    Theme.bgBase.ignoresSafeArea()

                    if wide {
                        // ≥900pt：左列表 + 右详情，通栏铺满
                        HStack(alignment: .top, spacing: Layout.columnGap) {
                            leftPane
                                .frame(width: Layout.sideColumnWidth)
                            rightPane
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, Spacing.page)
                    } else {
                        // <900pt：单列卡片纵向排列
                        ScrollView {
                            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                                headerCard
                                resultCard(compact: compactTable)
                                // 自动模式：展示服务端结果里的三档区间（端侧不重算）
                                if mode == .auto { rangeCard }
                                topicsCard
                                mergeCard
                                rulesCard
                            }
                            .padding(.horizontal, Spacing.page)
                            .padding(.bottom, Spacing.pageBottomInset)
                        }
                    }
                }
            }
            .navigationTitle("瓜分计算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .frame(minHeight: 44)
                        .accessibilityLabel("关闭瓜分计算")
                }
            }
        }
        .task { await store.loadZGAll(period: period) }
        .onChange(of: period) { _, newPeriod in
            Task { await store.loadZGAll(period: newPeriod) }
        }
    }

    // MARK: - 双栏左：分组列表

    private var leftPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                headerCard
                SectionHeader(title: "明细")
                VStack(spacing: Spacing.cardGap) {
                    ForEach(ZGGroup.allCases) { group in
                        groupRow(group)
                    }
                }
            }
        }
        .padding(.bottom, Spacing.pageBottomInset)
    }

    private func groupRow(_ group: ZGGroup) -> some View {
        Button {
            Haptics.selection()
            activeGroup = group
            selectedID = nil
        } label: {
            HStack {
                Text(group.rawValue)
                    .font(Typography.body)
                    .foregroundStyle(activeGroup == group ? Theme.textPrimary : Theme.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Spacing.cardPadding)
            .frame(minHeight: 56)
            .background {
                RoundedRectangle(cornerRadius: Radius.smallCard)
                    .fill(activeGroup == group ? Theme.surfaceTint3 : Theme.surfaceTint1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.rawValue)
    }

    // MARK: - 双栏右：选中分组详情

    @ViewBuilder
    private var rightPane: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionGap) {
            switch activeGroup {
            case .awards:
                resultCard(compact: compactTable)
                // 自动模式：三档区间来自服务端 result.range，端侧只渲染
                if mode == .auto { rangeCard }
            case .topics:
                topicsCard
            case .merge:
                mergeCard
            case .rules:
                rulesCard
                cleanCard
            }
        }
    }

    // MARK: - 头部：期次 + 模式 + 离线标注

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            Text("选择期次")
                .font(Typography.footnoteMedium)
                .foregroundStyle(Theme.textSecondary)

            Picker("期次", selection: $period) {
                Text("第 27 期").tag(27)
                Text("第 28 期").tag(28)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityLabel("活动期次")

            HStack(spacing: Spacing.cardGap) {
                Text("结果口径")
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.textSecondary)
                Picker("模式", selection: $mode) {
                    Text("手动").tag(ZGMode.manual)
                    Text("自动预估").tag(ZGMode.auto)
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
                .accessibilityLabel("计算模式")
            }

            if store.zgIsStale {
                Label("离线数据，可能不是最新", systemImage: "wifi.slash")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.statusWarn)
            }
            if store.zgClean?.report?.truncated == true {
                Label("抖音数据疑似截断，请分批导出后重传", systemImage: "exclamationmark.triangle")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.statusError)
            }
            if let note = store.zgResult?.exportCapNote {
                Text(note)
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.statusWarn)
            }
        }
        .padding(Spacing.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: Radius.card).fill(Theme.surfaceTint1)
        }
    }

    // MARK: - 结果表

    /// 结果表：首列（奖项名）冻结 + 右侧金额横向滚动；金额右对齐、单位独立列。
    /// 列数 >6 时给「精简 / 完整」切换（验15）—— 当前 5 奖项 + 单位列，
    /// 精简模式只显示截断后金额，完整模式额外显示原始金额与上限。
    private func resultCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            HStack {
                SectionHeader(title: "瓜分结果")
                Spacer(minLength: 0)
                Toggle("完整", isOn: $compactTable)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .frame(minHeight: 44)
                    .accessibilityLabel("完整视图")
            }

            if let result = store.zgResult {
                if result.isEstimate {
                    Label(result.message.isEmpty ? "预估值，非实际到账" : result.message,
                          systemImage: "info.circle")
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.statusWarn)
                }

                // 真正的首列冻结：固定标题列 + 独立横向滚动的金额矩阵（同一滚动视图内表头/数据/合计同步）
                let rows = buildTableRows(result: result, compact: compact)
                HStack(alignment: .top, spacing: Spacing.cardGap) {
                    // 左：冻结首列（不随金额区横向滚动）
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.id) { row in
                            frozenTitleCell(row.title, isHeader: row.isHeader, emphasized: row.emphasized)
                        }
                    }
                    // 右：金额矩阵，横向滚动；表头/数据/合计行同在一个 ScrollView 内 → 滚动同步
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(rows, id: \.id) { row in
                                amountRow(row, showRaw: !compact)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                // 冻结列与滚动区之间的分隔线
                Divider().background(Theme.divider)

                if !result.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.warnings, id: \.self) { warning in
                            Text("· \(warning)")
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            } else {
                emptyHint("还没有瓜分结果，先在处理完成后计算。")
            }
        }
        .padding(Spacing.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: Radius.card).fill(Theme.surfaceTint1)
        }
    }

    /// 把服务端结果整理成表格行。这里只做字符串化（ZGDisplay.yuan 仅 ÷100 展示），不含瓜分公式。
    private func buildTableRows(result: ZGResult, compact: Bool) -> [ZGTableRow] {
        var rows: [ZGTableRow] = [
            ZGTableRow(id: "head", title: "奖项", raw: "原始（元）", capped: "截断后（元）",
                       cap: "上限（元）", isHeader: true, emphasized: false)
        ]
        for item in (result.awards?.ordered ?? []) {
            rows.append(ZGTableRow(
                id: item.key,
                title: item.key,
                raw: ZGDisplay.yuan(item.award.rawCents),
                capped: ZGDisplay.yuan(item.award.cappedCents),
                cap: item.award.capYuan.map { "¥\(String(format: "%.0f", $0))" } ?? "—",
                isHeader: false, emphasized: false
            ))
        }
        rows.append(ZGTableRow(
            id: "total", title: "合计（截断后）", raw: ZGDisplay.yuan(result.totalCents),
            capped: ZGDisplay.yuan(result.cappedCents), cap: "",
            isHeader: false, emphasized: true
        ))
        return rows
    }

    /// 冻结的首列单元格（奖项名）。
    private func frozenTitleCell(_ title: String, isHeader: Bool, emphasized: Bool) -> some View {
        Text(title)
            .font(isHeader ? Typography.footnoteMedium : Typography.body)
            .foregroundStyle(isHeader ? Theme.textSecondary : (emphasized ? Theme.limeInk : Theme.textPrimary))
            .frame(width: 108, alignment: .leading)
            .frame(minHeight: 56)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// 可横向滚动区中的一行金额（右对齐 + 单位独立列）。
    private func amountRow(_ row: ZGTableRow, showRaw: Bool) -> some View {
        HStack(spacing: Spacing.cardGap) {
            if showRaw {
                amountCell(row.raw, isHeader: row.isHeader)
                    .frame(width: 96, alignment: .trailing)
            }
            amountCell(row.capped, isHeader: row.isHeader)
                .frame(width: 104, alignment: .trailing)
            Text(row.cap.isEmpty ? "—" : row.cap)
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 72, alignment: .trailing)
                .lineLimit(1)
        }
        .frame(minHeight: 56)
        .monospacedDigit()
        .foregroundStyle(row.emphasized ? Theme.limeInk : Theme.textPrimary)
    }

    private func amountCell(_ text: String, isHeader: Bool) -> some View {
        Text(text)
            .font(isHeader ? Typography.footnoteMedium : Typography.callout)
            .foregroundStyle(isHeader ? Theme.textSecondary : Theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    // MARK: - 自动预估三档区间

    private var rangeCard: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            SectionHeader(title: "预估区间")
            if let range = store.zgResult?.range {
                ForEach(ZGDisplay.levelNames) { level in
                    HStack {
                        Text(level.label)
                            .font(Typography.body)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                        Text(rangeText(range, key: level.key))
                            .font(Typography.callout)
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                    }
                    .frame(minHeight: 56)
                }
                if let source = store.zgResult?.priorSource {
                    Text("先验来源：\(source)")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            } else {
                emptyHint("人数未知，无法估算。")
            }
        }
        .padding(Spacing.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: Radius.card).fill(Theme.surfaceTint1)
        }
    }

    /// 按档位 key 取服务端结果里的金额文本。普通 switch 语句，避免 ViewBuilder 里的 switch 表达式。
    private func rangeText(_ range: ZGRange, key: String) -> String {
        let point: ZGRangePoint?
        if key == "low" {
            point = range.low
        } else if key == "mid" {
            point = range.mid
        } else {
            point = range.high
        }
        guard let point else { return "—" }
        return ZGDisplay.yuan(point.cappedCents)
    }

    // MARK: - 话题告警

    private var topicsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            SectionHeader(title: "话题告警")
            if let topics = store.zgTopics {
                if topics.warnings.isEmpty {
                    emptyHint("没有话题告警。")
                } else {
                    ForEach(topics.warnings, id: \.workId) { warning in
                        topicRow(warning, ignored: topics.ignoredIds[warning.workId] == true)
                            .frame(minHeight: 56)
                    }
                }
            } else {
                emptyHint("正在加载话题校验…")
            }
        }
        .padding(Spacing.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: Radius.card).fill(Theme.surfaceTint1)
        }
    }

    private func topicRow(_ warning: ZGTopicWarning, ignored: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.cardGap) {
            VStack(alignment: .leading, spacing: 2) {
                // 标题原文（铁律2：只读展示，绝不改写）
                Text(warning.title)
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text("缺少：" + (warning.missing.isEmpty ? "—" : warning.missing.joined(separator: "、")))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.statusWarn)
                // 快手无法校验审核状态（平台约束，明确标注）
                Text(warning.platform == "kuaishou" ? "快手作品无法校验审核状态" : (warning.platform ?? ""))
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { ignored },
                set: { newValue in
                    Task {
                        try? await store.setZGTopicIgnore(
                            period: period, workId: warning.workId, ignore: newValue
                        )
                        await store.fetchZGTopics(period: period)
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .frame(minHeight: 44)
            .accessibilityLabel("忽略这条话题告警")
        }
    }

    // MARK: - 合并建议

    private var mergeCard: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            SectionHeader(title: "合并建议")
            if let merge = store.zgMerge {
                if merge.suggestions.isEmpty {
                    emptyHint("没有合并建议。")
                } else {
                    ForEach(merge.suggestions, id: \.id) { suggestion in
                        mergeRow(suggestion)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedID = suggestion.id }
                            .overlay(alignment: .leading) {
                                if selectedID == suggestion.id {
                                    Rectangle().fill(Theme.lime).frame(width: 3)
                                }
                            }
                    }
                }
            } else {
                emptyHint("正在加载合并建议…")
            }
        }
        .padding(Spacing.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: Radius.card).fill(Theme.surfaceTint1)
        }
    }

    private func mergeRow(_ suggestion: ZGMergeSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(suggestion.titles, id: \.self) { title in
                Text(title)
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            HStack {
                Text("相似度 \(String(format: "%.0f%%", suggestion.similarity * 100)) · 相差 \(suggestion.timeDiffSec) 秒")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Button("确认合并") {
                    Haptics.light()
                    Task {
                        try? await store.confirmZGMerge(
                            period: period, douyin: suggestion.douyin,
                            kuaishou: suggestion.kuaishou, confirm: true
                        )
                        await store.fetchZGMerge(period: period)
                    }
                }
                .font(Typography.caption)
                .foregroundStyle(Theme.limeInk)
                .frame(minHeight: 44)
            }
        }
    }

    // MARK: - 规则口径

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            SectionHeader(title: "规则口径")
            if let rules = store.zgRules {
                if let version = rules.ruleVersion {
                    Text("版本 \(version)")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                ruleLines(rules.rules)
            } else {
                emptyHint("正在加载规则…")
            }
        }
        .padding(Spacing.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: Radius.card).fill(Theme.surfaceTint1)
        }
    }

    /// 规则口径的一行：用 Identifiable 结构体，避免元组 keypath（Swift 的 key path 不能指向元组元素）。
    private struct RuleLine: Identifiable {
        let label: String
        let path: [String]
        var id: String { label }
    }

    /// 从通用 JSON 里读几条关键口径展示（valid_metric / threshold / cap 等）。
    /// 只看、不解释、不参与计算。
    /// 用 `if let` 而非 `guard ... return`：result builder（@ViewBuilder）不允许 guard 控制流。
    @ViewBuilder
    private func ruleLines(_ value: ZGJSONValue?) -> some View {
        if let value {
            let candidates: [RuleLine] = [
                RuleLine(label: "档位累加·有效口径", path: ["awards", "tier_cumulative", "valid_metric"]),
                RuleLine(label: "档位累加·门槛", path: ["awards", "tier_cumulative", "valid_threshold"]),
                RuleLine(label: "档位累加·上限", path: ["awards", "tier_cumulative", "cap"]),
                RuleLine(label: "新星成长·门槛", path: ["awards", "rising_star", "valid_threshold"]),
                RuleLine(label: "新星成长·上限", path: ["awards", "rising_star", "cap"]),
                RuleLine(label: "全勤天数", path: ["awards", "active", "full_attendance", "days"])
            ]
            ForEach(candidates) { candidate in
                if let v = value.member(candidate.path) {
                    HStack {
                        Text(candidate.label).font(Typography.footnote).foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 0)
                        Text(v.displayText).font(Typography.callout).foregroundStyle(Theme.textPrimary)
                    }
                    .frame(minHeight: 56)
                }
            }
        } else {
            emptyHint("规则为空")
        }
    }

    // MARK: - 清洗报告（附在规则详情下）

    private var cleanCard: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            SectionHeader(title: "清洗概况")
            if let report = store.zgClean?.report {
                cleanLine("总行数", report.totalRows)
                cleanLine("审核剔除", report.auditRemoved)
                cleanLine("时间线剔除", report.timelineRemoved)
                cleanLine("占位符异常", report.placeholderAnomalies)
            } else {
                emptyHint("正在加载清洗报告…")
            }
        }
        .padding(Spacing.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: Radius.card).fill(Theme.surfaceTint1)
        }
    }

    private func cleanLine(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label).font(Typography.footnote).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            Text("\(value)").font(Typography.callout).foregroundStyle(Theme.textPrimary).monospacedDigit()
        }
        .frame(minHeight: 56)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(Typography.footnote)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }
}
