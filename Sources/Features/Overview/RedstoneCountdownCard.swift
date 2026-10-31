import SwiftUI

/// 概览页置顶的红石卡（P01 / P0-4 升 Hero）。
///
/// 版式（设计报告 §4.1 hero 线框图）：
/// ```
/// ┌──────────────────────────────────────┐
/// │ 红石 · 今日                    [2.5×] │  ← Eyebrow + 倍率
/// │                                      │
/// │ 23:08                                │  ← 40pt `metricL`（今天最大的那个东西）
/// │ ↘ 还有 39:27                          │  ← 13pt
/// │ ↗ 下一场 23:08 · 霞谷 · 圆梦村         │  ← 13pt
/// │ ──────────────●──────────             │  ← 4pt 进度轨（今日第 2/3 场）
/// │ 11:08      17:08      23:08           │  ← 13pt 三场并列
/// │ 圆梦村      霞谷       霞谷            │  ← 11pt
/// └──────────────────────────────────────┘
/// ```
///
/// 三处刻意的改动：
/// 1. **纵向单栏**取代原来的"左栏 + 126pt 右栏"。右栏那张三行小表把卡压成 223pt 却只有
///    12pt 字，是"底盘大内容小"的典型；搬到底部做三场并列之后，同一份数据只用一种长相；
/// 2. **进度轨**回答"今天第几场"这个原来没说的话 —— 只有数字没有刻度，读者记不住自己在哪；
/// 3. 大数字走 `Typography.metricL`（原 inline 36pt 已删除），与收益页总额同一个 token。
///
/// 刷新粒度 1 秒：`39:27` 是 mm:ss，按分钟刷会僵住。只重建内容子树，
/// 卡片底盘（渐变 / 云海 / 描边）在 `TimelineView` 之外常驻。
struct RedstoneCountdownCard: View {
    @EnvironmentObject private var rock: RockStore

    /// 卡片高度档：首页传 `.hero`（240），其它场景想复用可以降级
    private let tier: CardTier
    /// 点击整卡 → 切到红石 Tab（由 `OverviewView` 通过现有 tab binding 完成，不新建导航栈）
    private let onOpenRock: () -> Void

    init(tier: CardTier = .hero, onOpenRock: @escaping () -> Void) {
        self.tier = tier
        self.onOpenRock = onOpenRock
    }

    var body: some View {
        TrackCard(
            progress: ArcGeometry.dayProgress(),
            peak: 0.70,
            minHeight: tier.height,
            backdrop: .skyGame
        ) {
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
        let today = RedstoneTimeline.occurrences(in: days)
            .filter { $0.isOn(dayKey: RedstoneClock.dayKey(now)) }

        return VStack(alignment: .leading, spacing: 0) {
            eyebrowRow(phase: phase)

            // Spacer 的 minLength 是"内容自然高度"的组成部分：底部高度由 TrackCard 的
            // `minHeight`（hero 240）兜住，这里只负责让几块内容撑到接近那个高度，
            // 免得整块内容被居中后上下各空出一大截。
            Spacer(minLength: 12)

            bigValue(phase: phase, now: now)

            Spacer(minLength: 10)

            detailLines(phase: phase, now: now)

            Spacer(minLength: 18)

            // 今日没有场次时整块不画：一条 0/0 的空轨比没有轨更让人困惑
            if today.isEmpty == false {
                RedstoneProgressTrack(
                    total: today.count,
                    index: trackIndex(today: today, now: now)
                )
                .padding(.bottom, 12)

                sessionRow(today: today, now: now)
            }
        }
    }

    /// 眉题行：左边"这是什么栏目"，右边倍率 / 待核对（都是服务端给的，取不到就不画）
    private func eyebrowRow(phase: RockPhase) -> some View {
        HStack(spacing: 6) {
            Eyebrow(text: "红石 · 今日", color: Theme.trackTextDim)
            Spacer(minLength: 6)
            if let rate = phase.occurrence?.rate {
                RateBadge(rate: rate)
            }
            if phase.occurrence?.needsCheck == true {
                NeedsCheckBadge()
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
                    .font(Typography.metricL)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// 大字下面两行：横向是"还有多久"，斜向是"下一场在哪"
    private func detailLines(phase: RockPhase, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            switch phase {
            case .notGenerated:
                // 大字已经说了"排期还没生成"，这里只补一句接下来会怎样
                Text("等官方更新这月的排期。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.trackTextDim)
            default:
                if let detail = countdownLine(phase: phase, now: now) {
                    arrowLine(icon: "arrow.down.right", text: detail, emphasized: true)
                }
                if let occurrence = phase.occurrence {
                    arrowLine(icon: "arrow.up.right", text: placeText(phase: phase, occurrence: occurrence), emphasized: false)
                }
            }
        }
    }

    /// "下一场 23:08 · 霞谷 · 圆梦村" —— 三样东西拼一行，缺哪个都不编（`map` 服务端一定有，可能是"待确认"）
    private func placeText(phase: RockPhase, occurrence: Occurrence) -> String {
        if phase.isOngoing {
            return "正在 " + occurrence.time + " · " + occurrence.map
        }
        return "下一场 " + occurrence.time + " · " + occurrence.map
    }

    /// ↘ 行：进行中给剩余分钟，否则给"还有 mm:ss"（超过一天用"还有 N 天"）
    private func countdownLine(phase: RockPhase, now: Date) -> String? {
        switch phase {
        case .ongoing(_, let minutesLeft):
            return "进行中 · 剩 " + String(minutesLeft) + " 分"
        case .upcoming(_, let seconds):
            return "还有 " + Formatters.countdown(seconds: seconds)
        case .endedToday(_, let seconds):
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
                .font(emphasized ? Typography.footnoteMedium : Typography.footnote)
                .foregroundStyle(emphasized ? Theme.textPrimary : Theme.trackTextDim)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }

    /// 底部"三场并列"：时刻（13pt）+ 地图（11pt）。
    ///
    /// 已过场次不靠 `.opacity()` 变淡，而是换成更淡的**文字 token** ——
    /// 透明度只能加在 `Theme.*` 上（PRD §3.4），换 token 同样达到"退到后面"的效果。
    private func sessionRow(today: [Occurrence], now: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(today.prefix(3))) { occurrence in
                VStack(alignment: .leading, spacing: 2) {
                    Text(occurrence.time)
                        .font(Typography.footnoteMedium)
                        .foregroundStyle(occurrence.endAt <= now ? Theme.trackTextDim : Theme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(occurrence.map)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.trackTextDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 进度轨节点落在第几场（1 起）：已结束的场次数 + 1；全部结束则停在最后一场。
    ///
    /// 用 `endAt` 而不是 `startAt` 判定"过了"：落地持续 52 分钟，
    /// 用开始时刻判会让正在落地的那一场被算成"已过"，节点就提前跳到下一场。
    private func trackIndex(today: [Occurrence], now: Date) -> Int {
        let finished = today.filter { $0.endAt <= now }.count
        return min(max(1, finished + 1), max(1, today.count))
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

// MARK: - 今日场次进度轨

/// 4pt 细轨 + 当前节点（设计报告 §4.1 hero 卡）。
///
/// 轨用 `Theme.trackArc`（这张卡自己的光轨色），节点用 `Theme.lime`（品牌色 = 当前位置），
/// 两者都是 token：深浅两套外观各自解析，View 层不判 `colorScheme`。
private struct RedstoneProgressTrack: View {
    /// 今日总场次
    let total: Int
    /// 当前是第几场（1 起）
    let index: Int

    /// 节点横向位置。
    ///
    /// 预留 9pt（节点直径）再乘比例：否则走到第 3/3 场时圆点会有一半溢出卡片右侧内边距。
    private func nodeX(width: CGFloat, ratio: CGFloat) -> CGFloat {
        let clamped = min(max(ratio, 0), 1)
        return clamped * max(width - 9, 0)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let ratio = total > 0 ? CGFloat(index) / CGFloat(total) : 0
            let x = nodeX(width: width, ratio: ratio)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.trackArc.opacity(0.28))
                    .frame(height: Layout.trackHeight)
                Capsule()
                    .fill(Theme.lime)
                    .frame(width: x + Layout.trackHeight, height: Layout.trackHeight)
                Circle()
                    .fill(Theme.lime)
                    .frame(width: 9, height: 9)
                    .offset(x: x)
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("今日第 " + String(index) + "/" + String(total) + " 场")
    }
}
