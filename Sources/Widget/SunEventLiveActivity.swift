import ActivityKit
import SwiftUI
import WidgetKit

/// 红石实时活动的锁屏 / 灵动岛界面（PRD §5.4）。
///
/// 分工：**这里只管画**，什么时候出现、什么时候消失全在 `LiveActivityCoordinator`（主 App）。
///
/// 字段（锁屏）：地图名 · 倍率徽标 · 落地时刻 `19:08` · 状态文案（「还有 12 分钟」/「进行中 · 剩 23 分钟」）
/// · 一条极细进度条（覆盖 72 分钟全程）。
/// 灵动岛：紧凑态 `moon.stars` + 剩余倒计时；展开态 地图 + 倍率 + 时刻 + 剩余；最小态仅图标。
///
/// 两个技术选择：
/// 1. 进度条用 `ProgressView(timerInterval:countsDown:)` —— 系统按时间自己走，
///    不需要主 App 每秒推一次（一次都不推）；
/// 2. 状态文案按 `Date()` 现算而不是靠 `phase` 字段：`phase` 只在主 App 前台时才会更新，
///    用户锁屏放着不动时，按日期现算才不会出现"落地半小时了还写着还有 12 分钟"。
struct SunEventLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SunEventActivityAttributes.self) { context in
            SunEventLockScreenView(state: context.state, attributes: context.attributes)
                // 锁屏卡片底：与桌面小组件同一套 token，深浅跟随系统
                .activityBackgroundTint(Theme.bgRaise)
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
                // 紧凑态左：仅图标（PRD：`moon.stars`）
                Image(systemName: "moon.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.limeInk)
            } compactTrailing: {
                SunEventCompactCountdown(state: context.state)
            } minimal: {
                // 最小态：仅图标
                Image(systemName: "moon.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.limeInk)
            }
        }
    }
}

// MARK: - 锁屏视图

/// 锁屏卡片（PRD 字段逐条：地图 · 倍率 · 落地时刻 · 状态文案 · 极细进度条）
struct SunEventLockScreenView: View {

    let state: SunEventActivityAttributes.ContentState
    let attributes: SunEventActivityAttributes

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.limeInk)

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
/// 落地前显示到落地的倒计时 `12:04`（PRD 的例子就是这个形态）；
/// 已经落地就退回落地时刻本身 —— 不给一个"越数越大"的假倒计时。
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

/// 实时活动的两句话（PRD §5.4 明确给了形态：「还有 12 分钟」/「进行中 · 剩 23 分钟」）。
///
/// 单独抽出来是为了让锁屏与灵动岛用同一套口径 —— 两处各写一遍，迟早会出现
/// 一个说 12 分钟、一个说 11 分钟。
enum SunEventText {

    /// 状态文案。按当前时刻现算，不依赖 `phase` 字段（见 `SunEventLiveActivity` 的注释）
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
