import SwiftUI
import TipKit

// MARK: - 文案口径

/// 「下一场」相关的文案口径 —— 顶部条与概览卡**共用这一份**。
///
/// 为什么抽出来：这两个地方显示的是同一个"下一场"，只是在两个页面上。
/// 如果各写一套，迟早会出现"条上说还有 2 小时、卡上说今日已结束"这种最伤口碑的矛盾。
///
/// 硬规则（PRD §5.1 / §5.2）：
///   · 永不返回 `00:00`（`Formatters.countdown` 保证最小 `00:01`）
///   · 没有数据时返回 nil，由调用方隐藏，**绝不编一个时间或地图**
///   · 超过 24 小时按「日历天数」表达（周一看到的下一场是周五，"98:12"没人看得懂）
enum RockPhaseText {

    /// 标题行：「下一场 · 今日 11:08」/「进行中 · 11:08 场」/「今日已结束 · 明日 07:08」/「排期未生成」
    static func headline(_ phase: RockPhase, now: Date) -> String {
        switch phase {
        case .upcoming(let occurrence, _):
            return "下一场 · " + dayLabel(occurrence, now: now) + " " + occurrence.time
        case .ongoing(let occurrence, _):
            return "进行中 · " + occurrence.time + " 场"
        case .endedToday(let occurrence, _):
            return "今日已结束 · " + dayLabel(occurrence, now: now) + " " + occurrence.time
        case .notGenerated:
            return "排期未生成"
        }
    }

    /// 大字与单位。`nil` = 这一段不渲染（未生成时不给任何数字）
    static func big(_ phase: RockPhase, now: Date) -> (value: String, unit: String)? {
        switch phase {
        case .ongoing(_, let minutesLeft):
            // 已向上取整且 >= 1，所以不会出现「剩余 0 分钟」
            return (String(minutesLeft), "分钟")
        case .upcoming(_, let seconds), .endedToday(_, let seconds):
            if seconds < 86_400 {
                return (Formatters.countdown(seconds: seconds), "")
            }
            let occurrence = phase.occurrence
            return (String(daysUntil(occurrence, now: now)), "天后")
        case .notGenerated:
            return nil
        }
    }

    /// 副文案（不重复大字里的信息）
    static func detail(_ phase: RockPhase, now: Date) -> String? {
        switch phase {
        case .upcoming(_, let seconds):
            return seconds < 86_400 ? "开始倒计时" : "最近一场在后面"
        case .ongoing(_, let minutesLeft):
            return "剩余 " + String(minutesLeft) + " 分钟"
        case .endedToday(let occurrence, let seconds):
            if seconds < 86_400 { return "明天还有" }
            return "下一次在 " + dayLabel(occurrence, now: now)
        case .notGenerated:
            return "等排期出来，倒计时会自己出现。"
        }
    }

    /// 场次所属日：今日 / 明日 / 周五 / 11月6日
    static func dayLabel(_ occurrence: Occurrence?, now: Date) -> String {
        guard let occurrence = occurrence else { return "" }
        let today = RedstoneClock.dayKey(now)
        if occurrence.date == today { return "今日" }
        if occurrence.date == RedstoneClock.nextDayKey(today) { return "明日" }
        let weekday = Formatters.weekdayLabel(dayKey: occurrence.date)
        if !weekday.isEmpty && daysUntil(occurrence, now: now) < 7 {
            return weekday
        }
        return Formatters.dayTitle(occurrence.date)
    }

    /// 距该场还有几个**日历日**（今天 = 0，明天 = 1）
    static func daysUntil(_ occurrence: Occurrence?, now: Date) -> Int {
        guard let occurrence = occurrence,
              let from = RedstoneClock.startOfDay(dayKey: RedstoneClock.dayKey(now)),
              let to = RedstoneClock.startOfDay(dayKey: occurrence.date) else {
            return 1
        }
        let days = RedstoneClock.calendar.dateComponents([.day], from: from, to: to).day ?? 1
        return max(1, days)
    }
}

// MARK: - 小徽标

/// 倍率徽标（`2.5×`）。`nil` 不渲染 —— 绝不显示「—」
struct RateBadge: View {
    let rate: Double?

    var body: some View {
        if let text = RedstoneRules.rateText(rate) {
            Text(text)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.limeInk)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background { Capsule().fill(Theme.lime.opacity(0.14)) }
                .overlay { Capsule().strokeBorder(Theme.limeInk.opacity(0.30), lineWidth: 1) }
                .accessibilityLabel("倍率 " + text)
        }
    }
}

/// 「待确认」黄徽标（PRD §5.1 第 5 条）：只降可信度，不隐藏数据。
///
/// 配色刻意走「淡底 + 警示字 + 警示描边」而不是实心黄底：
/// `#FFC24B` 作底还能看，作字在白底只有 1.6:1（PRD §3.2 明令只能当底色）。
struct NeedsCheckBadge: View {
    var body: some View {
        Text("待确认")
            .font(Typography.captionXS)
            .foregroundStyle(Theme.statusWarn)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background { Capsule().fill(Theme.statusWarnFill.opacity(0.18)) }
            .overlay { Capsule().strokeBorder(Theme.statusWarn.opacity(0.45), lineWidth: 1) }
    }
}

// MARK: - 顶部「下一场」条

/// 红石日历页顶部的「下一场」条（P04）。
///
/// 刷新粒度 1 分钟（`TimelineView(.periodic(from: .now, by: 60))`）：
/// 红石的精度就是分钟，逐秒刷新只会让整条每帧重排，耗电还看不出差别（PRD §4 #1）。
struct NextEventBar: View {
    /// 已加载的全部场次（跨月合并，避免 31 号翻到 11 月后显示"未生成"）
    let days: [RedstoneDay]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let phase = RedstoneTimeline.phase(in: days, now: context.date)
            // 只有「进行中」才值得动：下一场在几小时后，图标不该一直呼吸——
            // 一直动的东西等于没有动（常驻动效会退化成背景噪音）。
            let ongoing: Bool = {
                if case .ongoing = phase { return true }
                return false
            }()
            GlassCard(level: .card) {
                HStack(alignment: .center, spacing: 12) {
                    icon(active: ongoing)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(RockPhaseText.headline(phase, now: context.date))
                            .font(Typography.footnoteMedium)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        occurrenceLine(phase)
                    }
                    Spacer(minLength: 8)
                    valueBlock(phase, now: context.date)
                }
                .padding(.horizontal, Spacing.cardPadding)
                .padding(.vertical, 14)
            }
            // 场次从「下一场」翻成「进行中」的瞬间给一次触觉——
            // 这是这条 bar 上唯一真正发生"事件"的时刻，其余都只是数字变化。
            // 用 `sensoryFeedback` 而不是手写 `Haptics`：它会跟随系统的「减弱动效/触觉」开关，
            // 而手写的 UIImpactFeedbackGenerator 不会。
            .sensoryFeedback(.success, trigger: ongoing)
            // Tip 只在「进行中」时挂：静止状态下这条 bar 没什么可解释的，
            // 让 Tip 在不该出现的时机出现，等于教会用户忽略 Tip。
            .popoverTip(tipForOngoing(ongoing))
        }
    }

    /// 把「什么时候该有 Tip」这件事显式写成一个函数，而不是就地写三元表达式。
    ///
    /// 原因很具体：`popoverTip` 的形参类型是 `(any Tip)?`，
    /// 而 `ongoing ? RockOngoingTip() : nil` 会被推断成 `RockOngoingTip?`，
    /// 两者之间的隐式转换在泛型上下文里不一定成立。给返回值写上 `(any Tip)?`
    /// 就没有推断空间了 —— 这类"本地无编译器"时最容易翻车的点。
    private func tipForOngoing(_ ongoing: Bool) -> (any Tip)? {
        ongoing ? RockOngoingTip() : nil
    }

    /// 图标：进行中时外圈呼吸 + 符号脉冲。
    ///
    /// 呼吸用 `phaseAnimator` 而不是 `withAnimation` 循环：
    /// 前者是声明式的"永远在两个相位之间往返"，不需要自己管 Timer 的启停，
    /// 视图消失时也自动停——用 Timer 的话每次进出页面都要留一份取消逻辑。
    private func icon(active: Bool) -> some View {
        ZStack {
            Circle().fill(Theme.surfaceTint2)

            if active {
                Circle()
                    .strokeBorder(Theme.limeInk.opacity(0.35), lineWidth: 1)
                    .phaseAnimator([1.0, 1.3]) { view, scale in
                        view
                            .scaleEffect(scale)
                            .opacity(1.6 - scale)
                    } animation: { _ in
                        .easeInOut(duration: 1.4)
                    }
            }

            Image(systemName: "moon.stars")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.limeInk)
                .symbolEffect(.pulse, options: .repeating, isActive: active)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    /// 地图 + 倍率 + 待确认徽标。没有场次时给一句人话，不留空行。
    @ViewBuilder
    private func occurrenceLine(_ phase: RockPhase) -> some View {
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
            }
        } else {
            Text("先看规律说明，弄清哪天有场次。")
                .font(Typography.footnote)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
    }

    /// 右侧倒计时 / 剩余分钟。未生成时整块消失（不留 `--:--` 这种假数字）。
    @ViewBuilder
    private func valueBlock(_ phase: RockPhase, now: Date) -> some View {
        if let big = RockPhaseText.big(phase, now: now) {
            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(big.value)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    if !big.unit.isEmpty {
                        Text(big.unit)
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                if let detail = RockPhaseText.detail(phase, now: now) {
                    Text(detail)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .animation(Motion.tab, value: big.value)
        }
    }
}
