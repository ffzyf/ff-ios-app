import SwiftUI

/// 今日简报卡（PRD §3.4 第 4 条）。
///
/// **权威字段是扁平字段**（`lunar` / `uvText` / `sunrise` / `windText` / `rain` / `yi[]` / `ji[]` /
/// `horoscope` / `body` / `birthday`），`sections[]` 只是服务端拼好的便捷视图 —— 这里不读它，
/// 否则同一份数据会出现「以谁为准」的第二次判断。
///
/// 铁律：**空字段整行不渲染**。不显示「--」，不显示 `null`，也不留空白占位行。
///
/// ## 3.11.0：默认态压到 3 条（用户："今日简报里面的内容太多了！app 就简洁一些"）
///
/// 默认只露三组：
/// ```
/// 今日简报                            10月30日   ← 页头（日期保留）
/// ─────────────────────────────────────────────
/// ☾ 农历九月十二 · 冲煞：鼠(北)              ← ① 农历行
/// ☂ 有阵雨，记得带伞                         ← ② 一条天气（优先级见 `BriefText.weatherLines`）
/// 宜 晒被 散步 …                            ← ③ 宜忌 chips
///                                     展开全文 ⌄
/// ```
/// 其余（紫外线 / 日出日落 / 风力 / 生日 / 彭祖百忌 / 星座 / 黄历正文）全部进「展开全文」。
/// 分组规则住在 `BriefText`（`compactLines` / `detailLines`），本文件只负责"长什么样"。
///
/// **本卡不挂任何外链**（3.11.0 复核：`Features/Brief` 与 `BriefView` 里都不存在「原文」入口）。
/// 用户点名"下面挂一个原文太占地方"，所以这里连一个 11pt 的小字入口都不留 ——
/// 简报本身就是成品，没有"更原文的原文"可点。要加外部链接请先确认真有那个地址。
///
/// `available == false`（当天快照还没生成）是正常业务状态，走口语化占位，**不是错误样式**。
///
/// 文案翻译全部在 `BriefText`，所以本文件只负责「长什么样」。
struct TodayBriefCard: View {
    let snapshot: BriefSnapshot?

    @State private var expanded: Bool = false

    var body: some View {
        GlassCard {
            if isAvailable {
                VStack(alignment: .leading, spacing: 10) {
                    headerRow
                    divider
                    // ① ②：默认态的两行（农历 → 一条天气）
                    if !compactLines.isEmpty {
                        lineViews(compactLines)
                    }
                    // ③：宜忌 chips（横向可滑，永远只占一行高）
                    if showsLuck {
                        BriefLuckChips(yi: yiTags, ji: jiTags)
                    }
                    if expanded {
                        expandedContent
                    }
                    if canExpand {
                        toggleRow
                    }
                }
                .padding(Spacing.cardPadding)
            } else {
                emptyBlock
            }
        }
        .animation(Motion.expand, value: expanded)
    }

    // MARK: - 头部 / 空态 / 折叠

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("今日简报")
                .font(Typography.titleS)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 6)
            Text(dateText)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
    }

    /// 口语化空态：不吓人、不说「错误」，也不承诺立刻就有
    private var emptyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今天还没有简报复本")
                .font(Typography.titleS)
                .foregroundStyle(Theme.textPrimary)
            Text("通常早上七点半就有了。这里只读现成的快照，不会为了你现场生成一份。")
                .font(Typography.footnote)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toggleRow: some View {
        Button(action: {
            Haptics.light()
            expanded.toggle()
        }) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Text(expanded ? "收起" : "展开全文")
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.limeInk)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.limeInk)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 展开后的内容

    @ViewBuilder
    private var expandedContent: some View {
        if let title = horoscopeTitle {
            BriefHoroscopeSection(
                title: title,
                lucky: horoscopeLuckyText,
                overview: horoscopeOverview
            )
        }
        if !detailLines.isEmpty {
            lineViews(detailLines)
        }
        if let text = bodyParagraph {
            BriefAlmanacBox(text: text)
        }
    }

    // MARK: - 通用行

    private func lineViews(_ lines: [BriefLine]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: line.icon)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 16, alignment: .center)
                    Text(line.text)
                        .font(Typography.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(Typography.lineSpacing(fontSize: 15, multiple: 1.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 派生数据

    private var isAvailable: Bool {
        return snapshot?.available ?? false
    }

    private var dateText: String {
        return BriefText.dateText(snapshot?.date)
    }

    /// 默认态的两行（农历 + 一条天气）
    private var compactLines: [BriefLine] {
        return BriefText.compactLines(snapshot)
    }

    /// 展开态的行（其余天气字段 + 生日 + 彭祖百忌）
    private var detailLines: [BriefLine] {
        return BriefText.detailLines(snapshot)
    }

    private var yiTags: [String] {
        return BriefText.yiTags(snapshot)
    }

    private var jiTags: [String] {
        return BriefText.jiTags(snapshot)
    }

    private var showsLuck: Bool {
        return !yiTags.isEmpty || !jiTags.isEmpty
    }

    private var horoscopeTitle: String? {
        return BriefText.horoscopeTitle(snapshot?.horoscope)
    }

    private var horoscopeLuckyText: String? {
        return BriefText.horoscopeLuckyText(snapshot?.horoscope)
    }

    private var horoscopeOverview: String? {
        return BriefText.horoscopeOverview(snapshot?.horoscope)
    }

    private var bodyParagraph: String? {
        return BriefText.bodyText(snapshot)
    }

    /// 有「多出来的内容」才给展开按钮；否则按钮点了也不会有变化，不如不出现
    private var canExpand: Bool {
        return horoscopeTitle != nil || horoscopeLuckyText != nil || horoscopeOverview != nil
            || !detailLines.isEmpty || bodyParagraph != nil
    }
}
