import SwiftUI
import Foundation

/// 概览页的「每日简报」轨迹卡 —— 与桌面简报小组件同一套视觉（V3.1 返工）。
///
/// 版式（照参考图重排，每个元素都有固定位置，不再"飘"在弧线上）：
/// ```
/// ┌─────────────────────────────────────┐
/// │ 10月30日 周五                 简报  │  ← 顶部一行（日期 · 星期 · 标签）
/// │                                     │
/// │ 🗓 每日简报                          │  ← 标题行（SF Symbol，不用 emoji）
/// │ 🎁 距离生日还有 253 天               │  ← 副标题（取不到生日改农历）
/// │                                     │
/// │ ↘ 今日已推送 07:03                   │  ← 底部两行
/// │ ↗ 光遇简报                          │
/// └─────────────────────────────────────┘
/// ```
///
/// 两条口径（与简报页保持一致，PRD §5.1）：
/// · 早上简报还没生成时**不编造内容**，副标题退回农历；
/// · 没推送过就不写"已推送"，按 `pushedToday` 分「已推送 / 今日未推送」两版文案。
struct TodayBriefTrackCard: View {

    let snapshot: BriefSnapshot?
    private let onOpenBrief: () -> Void

    init(snapshot: BriefSnapshot?, onOpenBrief: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onOpenBrief = onOpenBrief
    }

    var body: some View {
        TrackCard(progress: ArcGeometry.dayProgress(), bandTop: 0.46, bandBottom: 0.98, peak: 0.64) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                Spacer(minLength: 14)
                titleRow
                Spacer(minLength: 4)
                subtitleRow
                Spacer(minLength: 12)
                footerRows
            }
            .padding(Spacing.cardPadding)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture {
            Haptics.light()
            onOpenBrief()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开今日简报")
    }

    // MARK: - 顶部一行：日期 · 星期 · 简报

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Formatters.dayTitle(dayKey))
                .font(Typography.caption)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(Formatters.weekdayLabel(dayKey: dayKey))
                .font(Typography.captionXS)
                .foregroundStyle(Theme.trackTextDim)
            Spacer(minLength: 0)
            Text("简报")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.trackArc.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background {
                    Capsule()
                        .fill(Theme.trackArc.opacity(0.14))
                }
        }
    }

    // MARK: - 标题 / 副标题

    private var titleRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "calendar")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.trackArc)
            Text("每日简报")
                .font(Typography.titleM)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var subtitleRow: some View {
        if let text = subtitleText {
            HStack(spacing: 7) {
                Image(systemName: "gift")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.trackArc.opacity(0.85))
                Text(text)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
        } else {
            EmptyView()
        }
    }

    /// 副标题优先级：生日倒计时 → 农历 → 简报首句（都取不到才整行不渲染，不写"暂无"）
    private var subtitleText: String? {
        guard let snapshot else { return nil }
        if let days = Self.daysUntilBirthday(snapshot.birthday) {
            return days == 0 ? "今天生日，生日快乐" : "距离生日还有 " + String(days) + " 天"
        }
        if let lunar = snapshot.lunar, !lunar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lunar
        }
        if let body = snapshot.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return body
        }
        return nil
    }

    // MARK: - 底部两行

    private var footerRows: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: (snapshot?.pushedToday ?? false) ? "paperplane.fill" : "paperplane")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle((snapshot?.pushedToday ?? false) ? Theme.trackArc : Theme.trackTextDim)
                Text(pushText)
                    .font(Typography.captionXS)
                    .foregroundStyle((snapshot?.pushedToday ?? false) ? Theme.textPrimary : Theme.trackTextDim)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.trackArc.opacity(0.8))
                Text("光遇简报")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.trackTextDim)
                Spacer(minLength: 0)
            }
        }
    }

    /// 推送文案：推送过给时刻，没推送过明确说没推送（不写"未知"）
    private var pushText: String {
        guard let snapshot else { return "还没有简报" }
        if snapshot.pushedToday {
            if let pushedAt = snapshot.pushedAt {
                return "今日已推送 " + Formatters.timeHHmm(pushedAt)
            }
            return "今日已推送"
        }
        return "今日未推送"
    }

    // MARK: - 工具

    /// 简报的日期键：服务端给的优先，缺省用「今天（北京）」
    private var dayKey: String {
        if let date = snapshot?.date, !date.isEmpty {
            return date
        }
        return RedstoneClock.dayKey(Date())
    }

    /// 解析生日文案 → 距下一次生日还有几天（今天 = 0；解析不出返回 nil）
    ///
    /// 服务端给的是自由文本（见过 `07-17` / `1995-07-17` / `7月17日` 三种），
    /// 所以统一"按非数字切分、取数字分组"，只认最后两个数字作为月/日 —— 年份对倒计时没有意义。
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
        let parts = calendar.dateComponents([.year, .month, .day], from: now)

        func occurrence(year: Int) -> Date? {
            var components = DateComponents()
            components.timeZone = RedstoneClock.beijing
            components.year = year
            components.month = month
            components.day = day
            components.hour = 0
            components.minute = 0
            components.second = 0
            return calendar.date(from: components)
        }
        guard let year = parts.year, let todayStart = calendar.date(from: parts) else { return nil }
        guard var next = occurrence(year: year) else { return nil }
        if next < todayStart {
            guard let following = occurrence(year: year + 1) else { return nil }
            next = following
        }
        let days = calendar.dateComponents([.day], from: todayStart, to: next).day ?? 0
        return max(0, days)
    }
}
