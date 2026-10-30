import SwiftUI
import Foundation

/// 规律说明页（P05）。
///
/// 三条设计要点：
/// 1. **取不到就兜底，不留白**：PRD P05 明确要求"取不到 → 显示内置的四条规律文案"，并注明
///    「内容可能不是最新」。所以 `rules == nil` 时页面照样完整可读，只是顶部多一条提示；
/// 2. 四条规律的**顺序不能改**：日期 → 时段 → 点位 → 倍率，这是"从哪天有 → 几点 → 在哪 → 几倍"的
///    认知顺序，也是用户理解这套引擎的最短路径；
/// 3. 数据全部来自 `rules`，本文档不写死任何"某天某图"—— 那种信息归日历，写在规律页会过期。
struct RockRulesView: View {
    /// 服务端规律摘要；nil 时用内置文案
    var rules: RedstoneRules? = nil
    /// 是否正在用兜底文案（由 Store 的 `rulesFallback` 传进来）
    var usesFallback: Bool = false

    @Environment(\.dismiss) private var dismiss

    /// 显式 init：`@Environment` 是 private 存储属性，memberwise init 会被降级成 private
    init(rules: RedstoneRules? = nil, usesFallback: Bool = false) {
        self.rules = rules
        self.usesFallback = usesFallback
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                header
                if showsFallbackNote {
                    fallbackNote
                }
                ForEach(ruleSections) { section in
                    ruleCard(section)
                }
                RuleWeekdayTable(rules: rules)
                RuleSeedsSection(rules: rules)
                footnote
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background { PageBackground(glow: false) }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("为什么是这天？")
                    .font(Typography.titleL)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                Text("红石排期的四条规律")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background { Circle().fill(Theme.surfaceTint2) }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("关闭")
        }
    }

    private var showsFallbackNote: Bool {
        return usesFallback || rules == nil
    }

    private var fallbackNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
            Text("现在用的是 App 内置的规律文案，内容可能不是最新。")
                .font(Typography.captionXS)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.statusWarn)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: Radius.badge + 2, style: .continuous).fill(Theme.statusWarnFill.opacity(0.14)) }
    }

    // MARK: - 四条规律

    private var ruleSections: [RuleSection] {
        let dateText = trimmed(rules?.date).isEmpty
            ? "每月 1—15 号排周六和周日；16 号到月末排周五和周日；周日每周都有。"
            : trimmed(rules?.date)

        let timesText = "落地时段与星期绑定：周五、周六、周日各有一套固定时刻。"
        let poolText = "点位分大池和小池：大池 5 个图轮流出，小池补位；同一天的三场用同一张图。"
        let rateText = "倍率由点位决定，与日期无关：同一张图永远是同一个倍率。"

        var poolChips: [String] = []
        if let rules = rules {
            poolChips = Array((rules.big5 + rules.smallPool).prefix(8))
        }
        var rateChips: [String] = []
        if let rules = rules {
            rateChips = rules.rateValues.map { value in
                RedstoneRules.rateText(value) ?? ""
            }.filter { !$0.isEmpty }
        }

        return [
            RuleSection(id: 0, title: "① 日期双轨", body: dateText, chips: []),
            RuleSection(id: 1, title: "② 时段绑定星期", body: timesText, chips: []),
            RuleSection(id: 2, title: "③ 点位双池", body: poolText, chips: poolChips),
            RuleSection(id: 3, title: "④ 倍率由点位决定", body: rateText, chips: rateChips)
        ]
    }

    private func ruleCard(_ section: RuleSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(Typography.titleS)
                .foregroundStyle(Theme.textPrimary)
            Text(section.body)
                .font(Typography.callout)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(Typography.lineSpacing(fontSize: 15, multiple: 1.6))
            if !section.chips.isEmpty {
                chips(section.chips)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
    }

    /// 点位 / 倍率的小胶囊。用 `Layout` 之外最稳的 `flexible` 网格：两列，自动换行
    private func chips(_ items: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { RoundedRectangle(cornerRadius: Radius.badge, style: .continuous).fill(Theme.surfaceTint2) }
            }
        }
    }

    // MARK: - 脚注

    private var footnote: some View {
        Text(footerText)
            .font(Typography.captionXS)
            .foregroundStyle(Theme.textTertiary)
            .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
    }

    private var footerText: String {
        var parts: [String] = []
        let version = trimmed(rules?.version)
        if !version.isEmpty { parts.append("规律版本 " + version) }
        if let anchorCount = rules?.anchorCount, anchorCount > 0 {
            parts.append("已验证 " + String(anchorCount) + " 个锚点")
        }
        if let equiv = rules?.monthEquiv.first, !equiv.isEmpty {
            parts.append("月份等价：" + equiv)
        }
        parts.append("排期由站点引擎推算，玩家校准后会更新。")
        return parts.joined(separator: " · ")
    }

    private func trimmed(_ raw: String?) -> String {
        return (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 一条规律的展示数据
private struct RuleSection: Identifiable {
    let id: Int
    let title: String
    let body: String
    let chips: [String]
}
