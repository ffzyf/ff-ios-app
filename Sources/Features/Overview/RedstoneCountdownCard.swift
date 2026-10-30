import SwiftUI

/// 概览页置顶的红石倒计时卡（P01，PRD §5.1 的五种情况）。
///
/// **刷新粒度 1 分钟**：`TimelineView(.periodic(from: .now, by: 60))`。
/// 不用 `Timer` 逐秒刷 —— 红石的精度是分钟，逐秒刷新只会每秒重排一次数字（耗电且闪），
/// PRD §4 #1 明确把粒度定为分钟。
///
/// 五态映射（一张卡读完全部情况）：
/// | 情况 | 标题 | 大字 |
/// |---|---|---|
/// | 距下一场 > 0 | 下一场 · 今日 19:08 | 倒计时 `02:14` |
/// | 进行中 | 进行中 · 19:08 场 | `23 分钟` |
/// | 今日已结束 | 今日已结束 · 明日 07:08 | 倒计时 / `N 天后` |
/// | 排期未生成 | 排期未生成 | **不显示任何数字** |
/// | `needsCheck` | 照常 | 地图旁挂「待确认」 |
///
/// **任何情况都不显示 `00:00`、也不编造地图**：没有数据时走 `unavailableBlock`，
/// 有数据但没未来场次时走 `.notGenerated`（无数字 + 一句人话）。
struct RedstoneCountdownCard: View {
    @EnvironmentObject private var rock: RockStore

    /// 点击整卡 → 切到红石 Tab（由 `OverviewView` 通过现有 tab binding 完成，不新建导航栈）
    private let onOpenRock: () -> Void

    init(onOpenRock: @escaping () -> Void) {
        self.onOpenRock = onOpenRock
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            GlassCard(level: .card) {
                VStack(alignment: .leading, spacing: 10) {
                    if rock.hasLoadedAnyMonth {
                        phaseBlock(now: context.date)
                    } else {
                        unavailableBlock
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.cardPadding)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .onTapGesture {
                Haptics.light()
                onOpenRock()
            }
        }
    }

    // MARK: - 有数据

    private func phaseBlock(now: Date) -> some View {
        let phase = RedstoneTimeline.phase(in: rock.allLoadedDays, now: now)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.limeInk)
                Text(RockPhaseText.headline(phase, now: now))
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if rock.isDataOld {
                    Text("待更新")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.statusWarn)
                }
            }

            // 大字：没有可展示的数字时整块消失（未生成 = 不显示倒计时）
            if let big = RockPhaseText.big(phase, now: now) {
                bigValue(big)
            } else {
                notGeneratedLine
            }

            if let occurrence = phase.occurrence {
                HStack(spacing: 6) {
                    Text(occurrence.map)
                        .font(Typography.titleS)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    RateBadge(rate: occurrence.rate)
                    if occurrence.needsCheck {
                        NeedsCheckBadge()
                    }
                    Spacer(minLength: 0)
                }
            }

            if let detail = RockPhaseText.detail(phase, now: now) {
                Text(detail)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    /// 大号倒计时 / 剩余分钟 —— 唯一的 `.contentTransition(.numericText(countsDown: true))` 用法点
    private func bigValue(_ big: (value: String, unit: String)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(big.value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            if !big.unit.isEmpty {
                Text(big.unit)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .animation(Motion.tab, value: big.value)
    }

    /// 「排期未生成」：没有数字，给一个能往下走的按钮（落到红石 Tab 的规律入口）
    private var notGeneratedLine: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("排期还没生成，先看规律说明。")
                .font(Typography.footnote)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Text("查看规律")
                .font(Typography.footnoteMedium)
                .foregroundStyle(Theme.onLime)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background { Capsule().fill(Theme.lime) }
        }
    }

    // MARK: - 完全没有数据

    @ViewBuilder
    private var unavailableBlock: some View {
        if rock.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在看排期…")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
        } else if let error = rock.lastError {
            VStack(alignment: .leading, spacing: 8) {
                Text(error.userMessage)
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    Button {
                        Haptics.light()
                        Task { await rock.loadSchedule(force: true) }
                    } label: {
                        Text("重试")
                    }
                    .buttonStyle(PrimaryCTAStyle())

                    Text("暂时取不到排期")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        } else {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("暂无排期")
                        .font(Typography.titleS)
                        .foregroundStyle(Theme.textPrimary)
                    Text("去红石页看看这个月的场次。")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}
