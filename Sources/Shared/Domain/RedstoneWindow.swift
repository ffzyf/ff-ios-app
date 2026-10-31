import Foundation

// MARK: - 本月窗口状态

/// 「本月红石过完了没有」的三态。
///
/// 为什么需要第三个状态：`RockPhase` 只知道「有没有下一场」，于是两种情况被它合并成了
/// `notGenerated` ——
///   1. 排期还没拉到（初次加载 / 服务端这个月没数据）；
///   2. 本月有场次，但**全部已经过完了**（月末最后一晚 23:08 之后）。
/// 用户对这两种情况的期待完全不同：前者该说「排期还没生成」，后者该说
/// 「本月红石已收官 · 静候下个月」。混成一句话，用户会以为数据挂了。
///
/// 三种状态：
/// - `pending`：一条排期都没拿到 → 沿用现有「排期还没生成 / 暂无排期」文案；
/// - `closed(month:next:)`：本月有场次、且没有任何还在落地或未来的场次 → 「本月红石已收官」；
/// - `live`：还有正在落地或未来的场次 → 走现有倒计时逻辑（一行都不改）。
enum RedstoneWindowState: Equatable {
    /// 排期数据还没拉到（初次加载 / 服务端没数据）
    case pending
    /// 本月已收官。`month` 是刚过完的这个月，`next` 是下一个月（都从日期算，不写死）
    case closed(month: Int, next: Int)
    /// 还有场次可等（进行中 / 今天晚些 / 明天 / 下周都算）
    case live
}

extension RedstoneWindowState {

    /// 是不是「本月已收官」
    var isClosed: Bool {
        if case .closed = self { return true }
        return false
    }

    /// 是不是「排期还没拉到」
    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }

    /// 是不是「正常倒计时」
    var isLive: Bool {
        if case .live = self { return true }
        return false
    }

    /// 收官态的大字。非收官态返回 nil（那两个状态的文案由各自页面负责，不要在这里替换）
    var closedTitle: String? {
        guard isClosed else { return nil }
        return "本月红石已收官"
    }

    /// 收官态的副文案：`10 月的场次都过完了，静候 11 月的排期`。
    ///
    /// 月份**从日期算**：写死「10 月 / 11 月」在 12 月 31 日会变成
    /// 「12 月的场次都过完了，静候 12 月的排期」—— 跨年那一格必须由 `nextMonthNumber` 兜住。
    var closedNote: String? {
        guard case .closed(let month, let next) = self else { return nil }
        return String(month) + " 月的场次都过完了，静候 " + String(next) + " 月的排期"
    }
}

// MARK: - 判定

/// **本月窗口判定的唯一实现**：App 首页红石卡与桌面小组件共用这一份。
///
/// 为什么必须共用：同一个结论要出现在两个进程里（App 与 Widget），各写一遍必然漂移 ——
/// 「App 说本月已收官、桌面说还有 39 分钟」这种分歧比文案不好看严重得多。
/// 放在 `Sources/Shared/Domain/` 是因为 Widget target 只编译 `Sources/Widget` + `Sources/Shared`，
/// 而 `Features` / `DesignSystem` / `Services` 它一律引用不到。
///
/// 全部是纯函数：给定「排期 + 现在」，任何进程都得到同一个答案。
enum RedstoneWindow {

    // MARK: - 月份（一律从日期算，不写死）

    /// 某时刻所在月份（1…12，北京时区，与 `RedstoneClock` 同一个日历）
    static func monthNumber(of date: Date) -> Int {
        let month = RedstoneClock.calendar.component(.month, from: date)
        return (1...12).contains(month) ? month : 1
    }

    /// 下一个月（12 月 +1 = 次年 1 月，所以必须绕回来，不能 `month + 1` 了事）
    static func nextMonthNumber(after date: Date) -> Int {
        let month = monthNumber(of: date)
        return month >= 12 ? 1 : month + 1
    }

    // MARK: - 取数

    /// 本月（`now` 所在月）的全部场次，升序。
    ///
    /// 只比到「月」这一级：服务端的 `date` 是 `"2026-10-03"`，前 7 个字符就是月份键，
    /// 与 `RedstoneClock.monthKey` 同构 —— 不用再解析一次日 / 时，也不会被时区挪走一天。
    static func monthOccurrences(days: [RedstoneDay], now: Date) -> [Occurrence] {
        let key = RedstoneClock.monthKey(now)
        return RedstoneTimeline.occurrences(in: days).filter { occurrence in
            monthKey(ofDayKey: occurrence.date) == key
        }
    }

    // MARK: - 三态（App 用：手上有整月的排期）

    /// App 侧入口：手上有 `[RedstoneDay]`（可能跨两个月），自己算得清「本月场次」。
    ///
    /// 判定顺序：
    /// 1. 一条场次都没有 → `.pending`（「排期还没生成」，绝不编造）；
    /// 2. 本月一条场次都没有 → `.pending`（月初还没拉到本月的排期，说"收官"是胡说）；
    /// 3. 还有正在落地 / 未来的场次 → `.live`；
    /// 4. 其余 → `.closed`。
    ///
    /// 第 3 步用 `endAt`（而不是 `startAt`）判「还有」：一场落地要 52 分钟，
    /// 23:08 那一场在 23:30 正处于进行中，此刻说「本月已收官」是错的。
    /// 这也与 `RedstoneTimeline.phase` 把「进行中」排在最前面的口径完全一致。
    static func state(days: [RedstoneDay], now: Date) -> RedstoneWindowState {
        let all = RedstoneTimeline.occurrences(in: days)
        guard !all.isEmpty else { return .pending }

        let month = monthOccurrences(days: days, now: now)
        guard !month.isEmpty else { return .pending }

        if all.contains(where: { $0.endAt > now }) { return .live }

        return .closed(month: monthNumber(of: now),
                       next: nextMonthNumber(after: now))
    }

    // MARK: - 三态（Widget 用：entry 里只有两个布尔）

    /// Widget 侧入口：`RedstoneEntry` 里没有整月场次，只有
    /// 「有没有任何排期数据」与「有没有当前 / 未来的场次」两个结论
    /// （`WidgetProvider.swift` 不在本次可改范围内，所以判定必须能从这两项推出来）。
    ///
    /// 与 `state(days:now:)` 的关系：数据拿全时两者等价 ——
    /// 有数据且**没有任何**进行中 / 未来场次，就只可能是「本月的场次全过完了」。
    /// 唯一的分歧点是「本月还没数据、但更早的月份有数据」，那在 Widget 侧不可区分，
    /// 按「有数据就算收官」处理（这是月末那一格的真实情况，也是用户报的那个 bug）。
    static func state(hasData: Bool, hasFutureOccurrence: Bool, now: Date) -> RedstoneWindowState {
        guard hasData else { return .pending }
        if hasFutureOccurrence { return .live }
        return .closed(month: monthNumber(of: now),
                       next: nextMonthNumber(after: now))
    }

    // MARK: - 内部

    /// `"2026-10-03"` → `"2026-10"`
    private static func monthKey(ofDayKey day: String) -> String {
        guard day.count >= 7 else { return day }
        return String(day.prefix(7))
    }
}
