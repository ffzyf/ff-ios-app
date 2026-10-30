import SwiftUI

/// 简报页底部的「推送状态」只读行（PRD P07 / P12 同源）。
///
/// 三个字段：今日是否已推送（含时间）、最近一次推送、推送时段说明。
/// 数据来自两处，优先级明确：
///   · 「今日是否已推」以**简报快照**为准（`pushedToday` / `pushedAt`，和简报是同一份服务端快照）；
///   · 「最近推送 / 时段说明」以**监控接口**为准（`lastPushAt` / `pushWindow`）。
///
/// 一条硬约束（PRD 明确写在验收里）：**取不到时整行隐藏**。
/// 所以这里没有「未知」「—」这两种文案 —— 没有数据就渲染 `EmptyView`，
/// 用户看到的是一页干净的简报，而不是一行写着"未知"的噪点。
struct PushStatusRow: View {

    /// 简报快照（可能为 nil：首屏还没回来）
    private let snapshot: BriefSnapshot?
    /// 监控响应（可能为 nil：简报页不强制等监控接口）
    private let monitor: MonitorResponse?
    private let now: Date

    init(snapshot: BriefSnapshot?, monitor: MonitorResponse?, now: Date = Date()) {
        self.snapshot = snapshot
        self.monitor = monitor
        self.now = now
    }

    var body: some View {
        Group {
            if hasAnyFact {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        headlineRow
                        if let detail = detailText {
                            Text(detail)
                                .font(Typography.captionXS)
                                .foregroundStyle(Theme.textTertiary)
                                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                        }
                    }
                    .padding(.horizontal, Spacing.cardPadding)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - 行

    private var headlineRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "paperplane")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.limeInk)
                .frame(width: 20, alignment: .center)

            Text("推送状态")
                .font(Typography.footnote)
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 8)

            Text(headlineText)
                .font(Typography.footnote)
                .foregroundStyle(headlineTint)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    // MARK: - 派生

    /// 有没有任何一件确定的事实可以展示。没有就整行隐藏。
    ///
    /// 判据取「拿到过简报快照」而不是「今日已推送」：`pushedToday == false` 本身就是一条
    /// 确定的信息（服务端明确说今天还没推），把它也当成"没有数据"会让这一行在早上永远不出现。
    private var hasAnyFact: Bool {
        if snapshot != nil { return true }
        return monitor?.lastPushAt != nil
    }

    /// 主文案：优先「今日已推送 07:02」/「今日未推送」，其次退回「最近推送 X 前」
    private var headlineText: String {
        if let snapshot = snapshot {
            if snapshot.pushedToday {
                if let pushedAt = snapshot.pushedAt {
                    return "今日已推送 " + Formatters.timeHHmm(pushedAt)
                }
                return "今日已推送"
            }
            if let pushedAt = snapshot.pushedAt {
                return "最近推送 " + Formatters.relativeDay(pushedAt, now: now)
            }
            return "今日未推送"
        }
        if let lastPush = monitor?.lastPushAt {
            return "最近推送 " + Formatters.relativeDay(lastPush, now: now)
        }
        return ""
    }

    private var headlineTint: Color {
        guard let snapshot = snapshot else { return Theme.textSecondary }
        return snapshot.pushedToday ? Theme.limeInk : Theme.textSecondary
    }

    /// 副文案：时段说明优先（服务端原话），没有就用「最近一次推送」
    private var detailText: String? {
        let window = (monitor?.pushWindow?.displayText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !window.isEmpty {
            return "推送时段：" + window
        }
        guard let lastPush = monitor?.lastPushAt else { return nil }
        return "最近一次推送 " + Formatters.relativeDay(lastPush, now: now)
    }
}
