import SwiftUI

/// 概览页置顶的红石轨迹卡（P01）—— 与桌面红石小组件同一套视觉（V3.1 返工）。
///
/// 版式（照参考图重排，一句话说清"谁在哪"）：
/// ```
/// ┌───────────────────────────────┬──────────────┐
/// │ 霞谷 · 圆梦村  [2.5×]          │ 今日 3 场     │
/// │                               │ 11:08 … 2.5× │
/// │ 23:08                         │ 17:08 … 2.5× │
/// │ ↘ 还有 39:27                  │ 23:08 … 2.5× │
/// │ ↗ 霞谷 · 圆梦村               │              │
/// └───────────────────────────────┴──────────────┘
/// ```
/// 左栏 = 焦点场次（大字时刻 + 倒计时 + 去向），右栏 = 今日场次表，中间一条竖线。
/// 光轨只在卡片下沿扫过，**不穿过任何文字**（上一版就是穿在标题中间才难看）。
///
/// 刷新粒度 1 秒：参考图要的是"实时变动"的观感（`39:27` 是 mm:ss，按分钟刷会僵住）。
/// 只重建数字子树，卡片底盘（渐变 / 描边 / 阴影）在 `TimelineView` 之外常驻。
struct RedstoneCountdownCard: View {
    @EnvironmentObject private var rock: RockStore

    /// 点击整卡 → 切到红石 Tab（由 `OverviewView` 通过现有 tab binding 完成，不新建导航栈）
    private let onOpenRock: () -> Void

    init(onOpenRock: @escaping () -> Void) {
        self.onOpenRock = onOpenRock
    }

    var body: some View {
        TrackCard(progress: ArcGeometry.dayProgress(), bandTop: 0.52, bandBottom: 0.98, peak: 0.70) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if rock.hasLoadedAnyMonth {
                    cardContent(now: context.date)
                } else {
                    unavailableBlock
                }
            }
            .padding(Spacing.cardPadding)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture {
            Haptics.light()
            onOpenRock()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开红石日历")
    }

    // MARK: - 有数据

    private func cardContent(now: Date) -> some View {
        let days = rock.allLoadedDays
        let phase = RedstoneTimeline.phase(in: days, now: now)
        let today = RedstoneTimeline.occurrences(in: days).filter { $0.isOn(dayKey: RedstoneClock.dayKey(now)) }

        return HStack(alignment: .top, spacing: 14) {
            leftColumn(phase: phase, now: now)
                .frame(maxWidth: .infinity, alignment: .leading)

            if today.isEmpty == false {
                Rectangle()
                    .fill(Theme.trackDivider)
                    .frame(width: 1)
                    .padding(.vertical, 2)
                rightColumn(today: today, now: now)
                    .frame(width: 126, alignment: .leading)
            }
        }
    }

    /// 左栏：地图 + 倍率 / 大字时刻 / ↘ 倒计时 / ↗ 去向
    private func leftColumn(phase: RockPhase, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(phase.occurrence?.map ?? "暂无排期")
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let rate = phase.occurrence?.rate {
                    RateBadge(rate: rate)
                }
                if phase.occurrence?.needsCheck == true {
                    NeedsCheckBadge()
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 12)

            bigValue(phase: phase, now: now)

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 3) {
                if let detail = countdownLine(phase: phase, now: now) {
                    arrowLine(icon: "arrow.down.right", text: detail, emphasized: true)
                }
                if let occurrence = phase.occurrence {
                    arrowLine(icon: "arrow.up.right", text: occurrence.map, emphasized: false)
                }
            }
        }
    }

    /// 大字：焦点场次的时刻（`23:08`）。未生成时不给任何数字。
    @ViewBuilder
    private func bigValue(phase: RockPhase, now: Date) -> some View {
        switch phase {
        case .notGenerated:
            Text("排期还没生成")
                .font(Typography.titleM)
                .foregroundStyle(Theme.textPrimary)
        default:
            if let occurrence = phase.occurrence {
                Text(occurrence.time)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }

    /// ↘ 行：进行中给剩余分钟，否则给"还有 mm:ss"（超过一天用"还有 N 天"）
    private func countdownLine(phase: RockPhase, now: Date) -> String? {
        switch phase {
        case .ongoing(_, minutesLeft: let minutesLeft):
            return "进行中 · 剩 " + String(minutesLeft) + " 分"
        case .upcoming(_, seconds: let seconds):
            return "还有 " + Formatters.countdown(seconds: seconds)
        case .endedToday(_, seconds: let seconds):
            if seconds < 86_400 {
                return "明日场次 · 还有 " + Formatters.countdown(seconds: seconds)
            }
            return "下一次 · " + RockPhaseText.dayLabel(phase.occurrence, now: now)
        case .notGenerated:
            return nil
        }
    }

    private func arrowLine(icon: String, text: String, emphasized: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(emphasized ? Theme.trackArc : Theme.trackTextDim)
            Text(text)
                .font(.system(size: 12, weight: emphasized ? .semibold : .medium, design: .rounded))
                .foregroundStyle(emphasized ? Theme.textPrimary : Theme.trackTextDim)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }

    /// 右栏：今日场次表（已过场次压到 30%，与红石日历一致）
    private func rightColumn(today: [Occurrence], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日 " + String(today.count) + " 场")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.trackTextDim)
            ForEach(today.prefix(3)) { occurrence in
                HStack(spacing: 5) {
                    Text(occurrence.time)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                    Text(occurrence.map)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.trackTextDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if let rate = occurrence.rate {
                        Text(RedstoneRules.rateText(rate) ?? "")
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.trackTextDim)
                    }
                }
                .opacity(occurrence.endAt <= now ? 0.32 : 1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 完全没有数据

    @ViewBuilder
    private var unavailableBlock: some View {
        if rock.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.trackArc)
                Text("正在看排期…")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.trackTextDim)
                Spacer(minLength: 0)
            }
        } else if let error = rock.lastError {
            VStack(alignment: .leading, spacing: 8) {
                Text(error.userMessage)
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                Button {
                    Haptics.light()
                    Task { await rock.loadSchedule(force: true) }
                } label: {
                    Text("重试")
                }
                .buttonStyle(PrimaryCTAStyle())
            }
        } else {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("暂无排期")
                        .font(Typography.titleS)
                        .foregroundStyle(Theme.textPrimary)
                    Text("去红石页看看这个月的场次。")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.trackTextDim)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.trackTextDim)
            }
        }
    }
}
