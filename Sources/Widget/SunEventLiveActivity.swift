import ActivityKit
import SwiftUI
import WidgetKit

/// 红石实时活动的锁屏 / 灵动岛界面（任务 1「太阳轨迹」重制版）。
///
/// 这里只管画，什么时候出现、什么时候消失全在 `LiveActivityCoordinator`（主 App）。
///
/// 锁屏视图（轨迹卡风格，设计文档 §5.1.3 实时活动行）：
/// 背景按状态渐变（即将=dawn / 进行中=active / 已结束=night）；
/// 弧线代表「红石 72 分钟窗口」进度（progress = (now-windowStart)/(windowEnd-windowStart)，钳到 [0,1]），
/// 节点 lime 发光；顶部 地图·倍率·落地时刻；中部 状态文案；底部 极细进度条。
///
/// 灵动岛：compact = 图标 + 倒计时；expanded = 地图 + 进度；minimal = 图标。
///
/// 技术选择（沿用旧版两条）：
/// 1. 进度条用 `ProgressView(timerInterval:countsDown:)` —— 系统按时间自己走，零推送成本；
/// 2. 状态文案按 `Date()` 现算而不是靠 `phase` 字段：锁屏放着不动时按日期现算才不会"落地半小时还写还有 12 分钟"。
struct SunEventLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SunEventActivityAttributes.self) { context in
            let key = TrackGradient.forLiveActivity(phase: context.state.phase)
            SunEventLockScreenView(state: context.state, attributes: context.attributes)
                // 锁屏卡片底：用轨迹卡配方（颜色即信息），不再用旧的纯色 bgRaise
                .activityBackgroundTint(TrackGradient.solid(for: key))
                .activitySystemActionForegroundColor(Theme.textPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.stars")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.limeInk)
                        Text(context.state.map)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        if let rate = context.state.rate {
                            Text(String(format: "%.1f×", rate))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.onLime)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Theme.lime)
                                }
                        }
                        Text(context.attributes.startTime)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(SunEventText.status(state: context.state))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        SunEventProgress(state: context.state, height: 3)
                    }
                }
            } compactLeading: {
                Image(systemName: "moon.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.limeInk)
            } compactTrailing: {
                SunEventCompactCountdown(state: context.state)
            } minimal: {
                Image(systemName: "moon.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.limeInk)
            }
        }
    }
}

// MARK: - 锁屏视图（轨迹卡风格）

/// 锁屏卡片：渐变背景 + 弧线（72 分钟窗口）+ 发光节点 + 文字内容。
struct SunEventLockScreenView: View {

    let state: SunEventActivityAttributes.ContentState
    let attributes: SunEventActivityAttributes

    @Environment(\.colorScheme) private var colorScheme

    /// 状态 → 配方（即将=dawn / 进行中=active / 兜底=night）
    private var key: TrackGradient.Key { TrackGradient.forLiveActivity(phase: state.phase) }
    private var gradient: [Color] { TrackGradient.gradient(for: key, scheme: colorScheme) }
    private var tint: Color { TrackGradient.arcTint(for: key, scheme: colorScheme) }

    /// 弧线 progress：红石 72 分钟窗口内的位置（钳到 [0,1]）
    private var windowProgress: CGFloat {
        let start = state.windowStart
        let end = state.windowEnd
        guard end > start else { return 0 }
        let p = Date().timeIntervalSince(start) / end.timeIntervalSince(start)
        return CGFloat(min(max(p, 0), 1))
    }

    var body: some View {
        GeometryReader { geo in
            let g = ArcGeometry(width: geo.size.width, height: geo.size.height)
            ZStack(alignment: .topLeading) {
                // 弧线 + 发光节点（透明底，叠在渐变之上）
                TrackCardBackdrop(geometry: g, progress: windowProgress, tint: tint)
                VStack(alignment: .leading, spacing: 8) {
                    headerRow
                    HStack(spacing: 6) {
                        Text(SunEventText.status(state: state))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        if state.needsCheck {
                            Text("待核对")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.statusWarn)
                        }
                        Spacer(minLength: 0)
                    }
                    SunEventProgress(state: state, height: 2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 整卡渐变背景（取代旧的纯色 Theme.bgRaise）
        .background(
            LinearGradient(colors: gradient, startPoint: TrackGradient.startPoint, endPoint: TrackGradient.endPoint)
        )
    }

    // MARK: - 顶部一行：地图 · 倍率 · 落地时刻

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "moon.stars")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)

            Text(state.map)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            if let rate = state.rate {
                Text(String(format: "%.1f×", rate))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.onLime)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.lime)
                    }
            }

            Spacer(minLength: 4)

            Text(attributes.startTime)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

// MARK: - 进度条

/// 覆盖「落地前 20 分钟 + 落地后 52 分钟 = 72 分钟」全程的细进度条。
///
/// 用 `ProgressView(timerInterval:)` 让系统按时间推进：主 App 退出前台之后它照样在走，
/// 这正是"锁屏看起来是活的"却零推送成本的来源。
struct SunEventProgress: View {

    let state: SunEventActivityAttributes.ContentState
    let height: CGFloat

    var body: some View {
        Group {
            if state.windowEnd > state.windowStart {
                ProgressView(timerInterval: state.windowStart...state.windowEnd, countsDown: false) {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(Theme.lime)
                .frame(height: height)
            } else {
                // 时间区间非法（脏数据）时画一条静态轨道，绝不构造非法 Range
                Capsule()
                    .fill(Theme.surfaceTint3)
                    .frame(height: height)
            }
        }
    }
}

// MARK: - 紧凑态倒计时

/// 灵动岛紧凑态的右侧数字。
///
/// 落地前显示到落地的倒计时 `12:04`；已经落地就退回剩余分钟 —— 不给一个"越数越大"的假倒计时。
struct SunEventCompactCountdown: View {

    let state: SunEventActivityAttributes.ContentState

    var body: some View {
        let now = Date()
        if state.startAt > now {
            Text(timerInterval: now...state.startAt, countsDown: true)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        } else {
            Text(state.isOngoing(now: now) ? remainingText(now: now) : "已结束")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
    }

    private func remainingText(now: Date) -> String {
        return "\(state.minutesLeft(now: now))分"
    }
}

// MARK: - 文案

/// 实时活动的两句话（PRD §5.4：「还有 12 分钟」/「进行中 · 剩 23 分钟」）。
///
/// 单独抽出来是为了让锁屏与灵动岛用同一套口径。
enum SunEventText {

    /// 状态文案。按当前时刻现算，不依赖 `phase` 字段。
    static func status(state: SunEventActivityAttributes.ContentState, now: Date = Date()) -> String {
        if state.isOngoing(now: now) {
            return "进行中 · 剩 \(state.minutesLeft(now: now)) 分钟"
        }
        if now >= state.endAt {
            return "已结束"
        }
        return "还有 \(state.minutesLeft(now: now)) 分钟"
    }
}
