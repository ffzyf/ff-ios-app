import Foundation

/// 红石当前所处的阶段（设计文档 §3 类图 `RockPhase`）。
///
/// 为什么把「今日已结束」与「排期未生成」分成两个 case，而不是统一成"没有下一场"：
/// PRD §5.1 对这两种情况的文案完全不同 —— 前者要显示「今日已结束 · 明日 07:08」并继续倒计时，
/// 后者必须显示「排期未生成」并且**不显示任何倒计时**。合成一个 case 就一定会有人把
/// 「明日 07:08」在无数据时也渲染出来，那就是"编造地图/时间"。
enum RockPhase: Equatable {
    /// 距下一场还有 `seconds` 秒（> 0，永不为 0）
    case upcoming(Occurrence, seconds: Int)
    /// 正在落地中，`minutesLeft` 已向上取整且至少 1（所以永远不会显示「剩余 0 分钟」）
    case ongoing(Occurrence, minutesLeft: Int)
    /// 今天已全部结束，`next` 是后面最近的一场（一定非空，可能在明天，也可能在周五）
    case endedToday(Occurrence, seconds: Int)
    /// 一条未来场次都没有：未生成月份 / 本月全部过去且没有后续
    case notGenerated

    /// 该阶段对应的场次（`notGenerated` 为 nil）
    var occurrence: Occurrence? {
        switch self {
        case .upcoming(let occurrence, _), .endedToday(let occurrence, _):
            return occurrence
        case .ongoing(let occurrence, _):
            return occurrence
        case .notGenerated:
            return nil
        }
    }

    /// 是否处于进行中（用于实时活动 / 触觉等后续批次）
    var isOngoing: Bool {
        if case .ongoing = self { return true }
        return false
    }
}

// MARK: - 「还有几天」（App 与 Widget 共用）

/// 红石「下一场还有几天」的唯一实现。
///
/// 为什么放在这里而不是 `RockPhaseText`（`Features/Rock/NextEventBar.swift`）：
/// `RockPhaseText` 属于 App target 的 `Features`，Widget target 只编译 `Sources/Widget` +
/// `Sources/Shared`，引用不到它。而「几天后」这件事必须由**两个进程给出同一个答案** ——
/// 各写一份，迟早会出现「手机说 5 天后、桌面说 10:08」这种最伤口碑的分歧。
extension RockPhase {

    /// 「下一场还有几天」——从今天算起的**日历天差**（今天有场 = 0，明天 = 1，周六 = 5）。
    ///
    /// 为什么按日历天而不是 24 小时：用户问的是"几天后"，跨一个 0 点就该 +1。
    /// 用 86400 秒去除会出现"明天下午的场次显示 1 天后、明天早上的显示 0 天后"这种自相矛盾
    /// （明天 07:08 距此刻也许只有 5 小时，明天 23:08 有 17 小时，但不该一个叫「今天」一个叫「明天」）。
    ///
    /// 日历一律取 `RedstoneClock.calendar`（时区已钉死为 UTC+8）：**不要**用 `Calendar.current`，
    /// 那会让海外用户的桌面与手机差一天。
    ///
    /// - Parameters:
    ///   - occurrence: 目标场次；`nil` 直接返回 `nil`（`notGenerated` 时没有目标，不猜）
    ///   - now: 当前时刻（由调用方传入，Widget 里是 entry.date，保证预渲染与真显示一致）
    /// - Returns: 天数；`occurrence.date` 这个日期键解析不出来时也返回 `nil` —— 不猜。
    static func daysAhead(_ occurrence: Occurrence?, now: Date) -> Int? {
        guard let occurrence = occurrence,
              let from = RedstoneClock.startOfDay(dayKey: RedstoneClock.dayKey(now)),
              let to = RedstoneClock.startOfDay(dayKey: occurrence.date) else {
            return nil
        }
        return RedstoneClock.calendar.dateComponents([.day], from: from, to: to).day
    }

    /// 天差的人类可读短标签：`今天` / `明天` / `5 天后`。
    ///
    /// 10 天以上照样写数字（`12 天后`），**不写「下周」**：红石排期最多看到下月初，
    /// 一句"下周"反而让人算不出是哪一天。
    /// 负数按「今天」处理：只有设备时钟被拨到过去才会出现，显示「-1 天后」比不显示更糟。
    ///
    /// - Returns: 文案；天差拿不到时返回 `nil`（调用方退回时刻或整段不渲染）
    static func daysAheadLabel(_ occurrence: Occurrence?, now: Date) -> String? {
        guard let days = daysAhead(occurrence, now: now) else { return nil }
        switch days {
        case ..<1:
            return "今天"
        case 1:
            return "明天"
        default:
            return String(days) + " 天后"
        }
    }

    /// 今天**还有**没有可等的场次（进行中 / 今天晚些的 `.upcoming`）。
    ///
    /// 这是「大字该写时刻，还是该写『5 天后』」「眉题该写『今日』还是『下一次』」的唯一判据，
    /// App 概览卡与小组件三档都吃这一份，避免各自解读 `phase`：
    ///   · `.ongoing` → 有。正在落地，用户此刻要读的就是时刻（跨零点的场次也算）；
    ///   · `.upcoming` → 有。`phase(in:now:)` **只在** `next.date == 今天` 时才产出 `.upcoming`，
    ///     这里再比一次日期，是为了让"今天晚些"和"明天/周六"在代码上也彻底隔开 ——
    ///     否则将来有人改动 `phase` 的判定顺序，这里会静默把 `.upcoming` 误判成"今日已结束"；
    ///   · `.endedToday` → **没有**。这个 case 的语义就是「今天的都过完了，next 在明天或更远」；
    ///   · `.notGenerated` → 没有（既没有场次，也说不出几天后）。
    ///
    /// - Parameter now: 当前时刻（北京日的判定基准）
    func hasRemainingSessionToday(now: Date) -> Bool {
        switch self {
        case .ongoing:
            return true
        case .upcoming(let occurrence, _):
            return occurrence.date == RedstoneClock.dayKey(now)
        case .endedToday, .notGenerated:
            return false
        }
    }
}

/// **红石时间判定的唯一实现**：纯函数、无状态、无网络、无 UI。
///
/// 为什么必须是纯函数：这套判定要同时被 5 个地方用（月历顶部条、概览倒计时卡、当天浮层、
/// 批次 4 的小组件 Timeline、实时活动），其中两个在 Widget 进程里。纯函数意味着
/// 只要给定 `[RedstoneDay]` + `now`，任何进程都得到同一个结论 —— 不会出现
/// 「App 说还有 12 分钟、小组件说进行中」这种最伤口碑的分歧。
///
/// 判定顺序（这个顺序本身就是需求，改动前先看 PRD §5.1 的五种情况）：
///   1. 有进行中的场 → `.ongoing`（跨零点靠绝对时刻比较天然成立）
///   2. 有下一场且是今天 → `.upcoming`
///   3. 有下一场但不是今天 → `.endedToday`（今天真的结束了，明天/周五接棒）
///   4. 一场都没有 → `.notGenerated`
enum RedstoneTimeline {

    /// 单场落地时长（分钟）。PRD §5.1：单场约 52 分钟
    static let landingMinutes: Int = 52

    /// 单场时长（秒）
    static let landingSeconds: TimeInterval = TimeInterval(landingMinutes * 60)

    /// `updated` 超过这个时长就算"数据可能过期"（PRD §5.2 / 设计文档 §1.3.3：7 天）
    static let staleInterval: TimeInterval = 7 * 24 * 3600

    // MARK: - 摊平

    /// 把一整月的 `items` 摊成按时间升序的场次列表。
    ///
    /// 脏时刻（`"25:99"`、`""`）在这里被丢掉：让非法数据不参与判定，
    /// 比在判定里到处判空更不容易漏。`times` 未排序时也顺手排序（服务端已升序，这里不假设）。
    static func occurrences(in days: [RedstoneDay]) -> [Occurrence] {
        var result: [Occurrence] = []
        for day in days {
            result.append(contentsOf: occurrences(on: day))
        }
        result.sort { $0.startAt < $1.startAt }
        return result
    }

    /// 单日的场次（升序）
    static func occurrences(on day: RedstoneDay) -> [Occurrence] {
        var result: [Occurrence] = []
        for time in day.times.sorted() {
            guard let start = RedstoneClock.date(day: day.date, time: time) else { continue }
            result.append(
                Occurrence(
                    date: day.date,
                    startAt: start,
                    endAt: start.addingTimeInterval(landingSeconds),
                    time: time,
                    map: day.map,
                    rate: day.rate,
                    needsCheck: day.needsCheck,
                    type: day.type
                )
            )
        }
        result.sort { $0.startAt < $1.startAt }
        return result
    }

    // MARK: - 三个查询（都是纯函数）

    /// 进行中的那一场：`startAt <= now < endAt`。
    ///
    /// 用绝对时刻比较，所以「23:30 落地 → 次日 00:22 结束」在 00:05 依然算进行中，
    /// 不需要为跨零点写任何特例。
    static func currentEvent(in days: [RedstoneDay], now: Date) -> Occurrence? {
        return occurrences(in: days).first { $0.startAt <= now && now < $0.endAt }
    }

    /// 下一场：第一个 `startAt > now` 的场次。等于落地时刻的那一秒属于「进行中」，不算下一场。
    static func nextEvent(in days: [RedstoneDay], now: Date) -> Occurrence? {
        return occurrences(in: days).first { $0.startAt > now }
    }

    /// 今天还剩几场（北京日）。**不含**正在落地的那一场 —— 进行中由 `currentEvent` 单独表达，
    /// 混进来会让「今日剩余 2 场」与实际可等的场次数不符。
    static func remainingToday(in days: [RedstoneDay], now: Date) -> [Occurrence] {
        let today = RedstoneClock.dayKey(now)
        return occurrences(in: days).filter { $0.date == today && $0.startAt > now }
    }

    /// 数据是否可能过期（`updated` 是毫秒时间戳；0 = 从未生成，按过期处理）
    static func isStale(updatedMilliseconds: Int, now: Date) -> Bool {
        guard updatedMilliseconds > 0 else { return true }
        let updatedAt = Date(timeIntervalSince1970: TimeInterval(updatedMilliseconds) / 1000)
        return now.timeIntervalSince(updatedAt) > staleInterval
    }

    // MARK: - 阶段

    /// 当前阶段（PRD §5.1 的四种可展示状态；`needsCheck` 是叠在数据上的徽标，不是状态）。
    static func phase(in days: [RedstoneDay], now: Date) -> RockPhase {
        let all = occurrences(in: days)

        // 1) 进行中优先：落地后的 52 分钟里，"下一场"是 3 小时后，用户此刻关心的是"还剩多久"
        if let ongoing = all.first(where: { $0.startAt <= now && now < $0.endAt }) {
            let remainSeconds = ongoing.endAt.timeIntervalSince(now)
            let minutes = max(1, Int((remainSeconds / 60).rounded(.up)))
            return .ongoing(ongoing, minutesLeft: minutes)
        }

        // 2) 下一场
        if let next = all.first(where: { $0.startAt > now }) {
            let seconds = max(1, Int(next.startAt.timeIntervalSince(now).rounded(.up)))
            if next.date == RedstoneClock.dayKey(now) {
                return .upcoming(next, seconds: seconds)
            }
            // 3) 今天已经结束，最近一场在明天 / 周五
            return .endedToday(next, seconds: seconds)
        }

        // 4) 没有未来场次：未生成月份，或本月最后一场之后再无排期
        return .notGenerated
    }
}
