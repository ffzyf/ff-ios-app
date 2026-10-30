import SwiftUI
import WidgetKit

/// 简报桌面小组件（PRD §5.3：中号）。
///
/// 三段结构，自上而下：
/// ① 日期 + 星期（服务端给的北京日期，不跟随设备时区）；
/// ② 简报正文**前 2 段**（超出以「…」截断 —— 用 `lineLimit` + `.tail` 截断，系统自带省略号）；
/// ③ 「今日已推送 07:02」/「今日未推送」。
///
/// 没有正文（早上 7:30 前简报还没生成）时不说假话，也不留一片空白：
/// 明确写「今天还没有简报」，把"等待"这件事讲清楚。
struct BriefWidget: Widget {

    static let kind = "BriefWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: BriefWidget.kind, provider: BriefProvider()) { entry in
            BriefWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetTheme.containerBackground()
                }
        }
        .configurationDisplayName("今日简报")
        .description("每天一份：日期、正文前两段，以及今天推送了没有。")
        .supportedFamilies([.systemMedium])
    }
}

/// 简报小组件视图
struct BriefWidgetView: View {

    private let entry: BriefEntry

    init(entry: BriefEntry) {
        self.entry = entry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            if entry.hasData {
                bodyText
            } else {
                emptyText
            }
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(WidgetTheme.padding)
    }

    // MARK: - 顶部

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.dateText)
                .font(WidgetTheme.meta)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(entry.weekdayText)
                .font(WidgetTheme.meta)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
            Text("简报")
                .font(WidgetTheme.label)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - 正文

    /// 前 2 段。每段最多 2 行，整体最多 4 行 —— 中号画布放不下更多，
    /// 而"截断"比"缩小字号硬塞"更可读（PRD §5.3：超出以「…」截断）。
    private var bodyText: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(entry.paragraphs.prefix(2).enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(WidgetTheme.briefBody)
                    .foregroundStyle(Theme.textBody)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
    }

    private var emptyText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("今天还没有简报")
                .font(WidgetTheme.mapName)
                .foregroundStyle(Theme.textSecondary)
            Text("生成后会出现在这里")
                .font(WidgetTheme.meta)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - 底部

    /// 推送状态。没有简报数据时整条不画（不写「未知」）
    @ViewBuilder
    private var footer: some View {
        if let text = entry.footerText {
            HStack(spacing: 4) {
                Image(systemName: entry.pushedToday ? "paperplane.fill" : "paperplane")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(entry.pushedToday ? Theme.limeInk : Theme.textTertiary)
                Text(text)
                    .font(WidgetTheme.briefFooter)
                    .foregroundStyle(entry.pushedToday ? Theme.limeInk : Theme.textTertiary)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
        }
    }
}
