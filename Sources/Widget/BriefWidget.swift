import SwiftUI
import WidgetKit

/// 简报桌面小组件（V3.1 返工：与首页简报卡同一套版式）。
///
/// 版式（照参考图一重排，四个区块各就各位，不再有元素"飘"在弧线上）：
/// ```
/// ┌─────────────────────────────────────┐
/// │ 10月30日 周五                 简报  │  ← 顶部一行
/// │                                     │
/// │ 🗓 每日简报                          │  ← 标题
/// │ 🎁 距离生日还有 253 天               │  ← 副标题（无生日退回农历 / 首句）
/// │                                     │
/// │ ↘ 今日已推送 07:03                   │  ← 底部两行
/// │ ↗ 光遇简报                          │
/// └─────────────────────────────────────┘
/// ```
///
/// 两条口径（与简报页一致，PRD §5.1）：
/// · 早上简报还没生成 → 副标题退回农历，绝不编一段"今日运势"；
/// · 没推送过就写「今日未推送」，不写"未知"。
struct BriefWidget: Widget {

    static let kind = "BriefWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: BriefWidget.kind, provider: BriefProvider()) { entry in
            BriefWidgetView(entry: entry)
        }
        .configurationDisplayName("今日简报")
        .description("每天一份：日期、首句，以及今天推送了没有。")
        .supportedFamilies([.systemMedium])
    }
}

/// 简报小组件视图
struct BriefWidgetView: View {

    private let entry: BriefEntry

    @Environment(\.colorScheme) private var colorScheme

    init(entry: BriefEntry) {
        self.entry = entry
    }

    // 配方 / 进度：简报按当前时段选配方，弧线用当天时间轴（与红石同源）
    private var key: TrackGradient.Key { TrackGradient.forBrief() }
    private var gradient: [Color] { TrackGradient.gradient(for: key, scheme: colorScheme) }
    private var tint: Color { TrackGradient.arcTint(for: key, scheme: colorScheme) }
    private var progress: CGFloat { ArcGeometry.dayProgress() }

    /// 简报来源名（底部 ↗ 用的站点标签，属品牌标识，非捏造的指标数据）
    private let sourceName = "光遇简报"

    var body: some View {
        ZStack(alignment: .topLeading) {
            TrackArcBackdrop(
                progress: progress,
                tint: tint,
                lineWidth: 2,
                nodeRadius: 4.5,
                bandTop: 0.50,
                bandBottom: 0.97,
                peak: 0.64,
                scrimOpacity: 0.06
            )
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            WidgetTheme.containerBackground(gradient: gradient)
        }
    }

    // MARK: - 内容

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Spacer(minLength: 12)
            titleRow
            Spacer(minLength: 3)
            subtitleRow
            Spacer(minLength: 10)
            footerRows
        }
    }

    // MARK: - 顶部一行：日期 · 星期 · 简报

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.dateText)
                .font(WidgetTheme.meta)
                .foregroundStyle(TrackGradient.foreground(for: key))
                .monospacedDigit()
            Text(entry.weekdayText)
                .font(WidgetTheme.statusSecondary)
                .foregroundStyle(TrackGradient.foreground(for: key).opacity(0.7))
            Spacer(minLength: 0)
            Text("简报")
                .font(WidgetTheme.label)
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background {
                    Capsule().fill(tint.opacity(0.14))
                }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text("每日简报")
                .font(WidgetTheme.briefBig)
                .foregroundStyle(TrackGradient.foreground(for: key))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var subtitleRow: some View {
        if let text = subtitleText {
            HStack(spacing: 6) {
                Image(systemName: "gift")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.9))
                Text(text)
                    .font(WidgetTheme.briefBody)
                    .foregroundStyle(TrackGradient.foreground(for: key).opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
        } else {
            EmptyView()
        }
    }

    /// 副标题优先级：生日倒计时 → 农历 → 简报首句。都没有就整行不画。
    private var subtitleText: String? {
        guard entry.hasData else { return nil }
        if let days = Self.daysUntilBirthday(entry.birthday) {
            return days == 0 ? "今天生日，生日快乐" : "距离生日还有 " + String(days) + " 天"
        }
        if let first = entry.paragraphs.first, !first.isEmpty {
            return first
        }
        return nil
    }

    // MARK: - 底部两行

    private var footerRows: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: entry.pushedToday ? "paperplane.fill" : "paperplane")
                    .font(WidgetTheme.placeIcon)
                    .foregroundStyle(entry.pushedToday ? tint : TrackGradient.foreground(for: key).opacity(0.7))
                Text(entry.footerText ?? "还没有简报")
                    .font(WidgetTheme.briefFooter)
                    .foregroundStyle(entry.pushedToday ? TrackGradient.foreground(for: key) : TrackGradient.foreground(for: key).opacity(0.7))
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right")
                    .font(WidgetTheme.placeIcon)
                    .foregroundStyle(tint)
                Text(sourceName)
                    .font(WidgetTheme.statusSecondary)
                    .foregroundStyle(TrackGradient.foreground(for: key).opacity(0.7))
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 工具

    /// 生日文案 → 距下次生日天数（今天 = 0；解析不出返回 nil）。
    ///
    /// 服务端给的是自由文本，统一"按非数字切分、取最后两个数字作月 / 日"，年份对倒计时没意义。
    private static func daysUntilBirthday(_ raw: String?) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        let groups = raw.split(whereSeparator: { $0.isNumber == false }).compactMap { Int($0) }
        guard groups.count >= 2 else { return nil }
        let month = groups[groups.count - 2]
        let day = groups[groups.count - 1]
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }

        var calendar = RedstoneClock.calendar
        calendar.timeZone = RedstoneClock.beijing
        let now = Date()
        guard let year = calendar.dateComponents([.year], from: now).year,
              let todayStart = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: now)) else {
            return nil
        }

        func occurrence(_ year: Int) -> Date? {
            var components = DateComponents()
            components.timeZone = RedstoneClock.beijing
            components.year = year
            components.month = month
            components.day = day
            return calendar.date(from: components)
        }
        guard var next = occurrence(year) else { return nil }
        if next < todayStart {
            guard let following = occurrence(year + 1) else { return nil }
            next = following
        }
        return max(0, calendar.dateComponents([.day], from: todayStart, to: next).day ?? 0)
    }
}
