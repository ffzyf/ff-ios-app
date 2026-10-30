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
