import Foundation
import WidgetKit

// MARK: - 天光 entry

/// 天光小组件的一帧。
///
/// 为什么把「阶段 / 倒计时目标 / 日出日落」全部在 entry 里算好，而不是留给 View：
/// entry 是 Timeline **预渲染**的时刻，`date` 就是"这一帧代表哪一刻"。
/// 如果 View 里现取 `Date()`，系统展示一条旧帧时文字会和真实时间错位
/// （典型症状：太阳已经偏西，倒计时还停在正午）。
///
/// 这个 entry **不带任何业务数据**：天光只描述"此刻的光"，
/// 全部信息都能从 `SunClock` 纯函数推出来，所以没有网络请求、没有快照、
/// 也没有"加载失败"这种状态 —— 时钟算不出来（极昼极夜）时整块不画。
struct SkyLightEntry: TimelineEntry {

    /// 这一帧对应的时刻（= 上一个阶段边界，或 15 分钟网格点）
    let date: Date
    /// 这一帧属于哪一档天色（七档，见 `SunClock` 文件头的时段定义）
    let phase: SkyPhase
    /// 倒计时要数到的时刻：**下一阶段的起点**。夜里是下一次日出
    let deadline: Date?
    /// 这一帧所在"一天"的日出（北京时间）；极昼极夜为 nil，地面区整块不画
    let sunrise: Date?
    /// 同上的日落
    let sunset: Date?

    /// 距 `deadline` 还有多少秒（已经过点 / 算不出时返回 0）
    var remaining: TimeInterval {
        guard let deadline else { return 0 }
        return max(0, deadline.timeIntervalSince(date))
    }

    /// 倒计时是否需要"秒级走时"。
    ///
    /// < 1 小时才需要：这一档里秒是唯一的变量，交给 `Text(timerInterval:countsDown:)`
    /// 由系统自绘（Widget 里**不能**起 Timer，进程随时会被挂起）。
    /// ≥ 1 小时用静态文案（`12小时32分钟`），分钟位由"每 15 分钟一帧"的网格推进 ——
    /// 在小时量级上，这个精度足够，而且省掉一整块系统计时器。
    var needsSecondTicker: Bool {
        return remaining > 0 && remaining < 3600
    }

    /// ≥ 1 小时用的静态文案：`12小时32分钟` / `49分钟30秒`（规则见 `SkyPhase.countdownText`）
    var countdownText: String? {
        guard let deadline else { return nil }
        return SkyPhase.countdownText(to: deadline, now: date)
    }

    /// 由时刻造一帧（唯一入口，纯函数 —— 可被预览、可被自检复用）
    static func make(date: Date) -> SkyLightEntry {
        let phase = SunClock.phase(at: date)
        let times = sunTimes(for: date, phase: phase)
        return SkyLightEntry(
            date: date,
            phase: phase,
            deadline: deadline(for: date, phase: phase),
            sunrise: times?.sunrise,
            sunset: times?.sunset
        )
    }

    // MARK: - 倒计时目标

    /// 这一档的倒计时目标。夜里特殊处理，其余直接复用 `SkyPhase.deadline(at:)`。
    ///
    /// 为什么夜里不能直接用 `SkyPhase.deadline(at:)`：那个实现在 `.night` 分支里
    /// 固定取"now + 24 小时那天的日出"，过了子夜就会指向**明天**的日出
    /// （凌晨 1 点看到"29 小时"，明显不对）。天光的夜间倒计时是这张卡的主信息，
    /// 所以这里自己算"下一次日出"：今天的还没到就用今天的，已经过了才顺延到明天。
    static func deadline(for date: Date, phase: SkyPhase) -> Date? {
        if phase == .night {
            return upcomingSunrise(after: date)
        }
        return phase.deadline(at: date)
    }

    /// 严格晚于 `date` 的下一次日出
    static func upcomingSunrise(after date: Date) -> Date? {
        guard let today = SunClock.times(on: date) else { return nil }
        if today.sunrise > date { return today.sunrise }
        let tomorrow = date.addingTimeInterval(86_400)
        return SunClock.times(on: tomorrow)?.sunrise
    }

    /// 地面区要显示的日出 / 日落。
    ///
    /// 日落之后（已经是 `.night`）显示**明天**那一对：那时卡片上数的是"距日出 12 小时"，
    /// 左下角就该写那个数要对齐的时刻，写今天早上已经过去的那次会让人以为时间错了。
    static func sunTimes(for date: Date, phase: SkyPhase) -> (sunrise: Date, sunset: Date)? {
        guard let today = SunClock.times(on: date) else { return nil }
        guard phase == .night, date >= today.sunset else { return today }
        let tomorrow = date.addingTimeInterval(86_400)
        return SunClock.times(on: tomorrow) ?? today
    }
}

// MARK: - 阶段边界（纯函数）

extension SkyLightEntry {

    /// 严格晚于 `date` 的**下一个阶段起始时刻**。
    ///
    /// 七档的边界一共七个（一天），全部由日出日落偏移出来，与 `SunClock.phase(at:)`
    /// 里的判定阈值**逐条一一对应**（同一组常数，改一处必须改两处，否则会"跳档但边界没到"）：
    ///
    /// | 边界 | 时刻 | 跨过它 |
    /// |---|---|---|
    /// | 晨蓝开始 | 日出 − 24min | night → blueDawn |
    /// | 日出 | 日出 | blueDawn → sunrise |
    /// | 日出后 24min | 日出 + 24min | sunrise → golden |
    /// | 黄金结束 | 日出 + 70min | golden → day |
    /// | 日落前 70min | 日落 − 70min | day → sunset |
    /// | 日落 | 日落 | sunset → blueDusk |
    /// | 暮蓝结束 | 日落 + 30min | blueDusk → night |
    ///
    /// 取 `day` 前后各一天共三天的边界再筛 `> date`：这样跨子夜、跨年、
    /// 以及 23:59 那一刻都能拿到正确的"下一档"，不需要任何特殊分支。
    ///
    /// - Parameters:
    ///   - date: 起点（严格大于它才返回值）
    ///   - day: 参照日（用它的日出日落生成边界；边界扫描会覆盖它前 / 后各一天）
    static func nextPhaseBoundary(after date: Date, on day: Date) -> Date? {
        var candidates: [Date] = []

        for offset in [-1, 0, 1] {
            guard let shifted = RedstoneClock.calendar.date(byAdding: .day, value: offset, to: day) else {
                continue
            }
            guard let times = SunClock.times(on: shifted) else { continue }
            candidates.append(times.sunrise.addingTimeInterval(-24 * 60))
            candidates.append(times.sunrise)
            candidates.append(times.sunrise.addingTimeInterval(24 * 60))
            candidates.append(times.sunrise.addingTimeInterval(70 * 60))
            candidates.append(times.sunset.addingTimeInterval(-70 * 60))
            candidates.append(times.sunset)
            candidates.append(times.sunset.addingTimeInterval(30 * 60))
        }

        return candidates.filter { $0 > date }.min()
    }
}

// MARK: - Provider

/// 天光的 Timeline 刷新策略：**按阶段边界精确插帧**。
///
/// WidgetKit 不会自己醒来看天色 —— 它只认两件事：timeline 里排好的 entry 到点就换，
/// 以及 `policy` 到期时回调 `getTimeline` 重新排。所以"太阳落了自己轮换"这件事
/// 完全取决于 entry 有没有排到日落那一刻：
///
/// - 只铺 15 分钟网格：最坏情况晚 15 分钟才换色，日出的第一缕光会被错过；
/// - **边界帧 + 15 分钟网格**（本实现）：换档那一刻正好有一帧落在边界上，一秒不差；
///   网格帧负责中间那些"太阳要往上爬"的时段（太阳位置由时间算，帧越密轨迹越顺）。
///
/// 视野 24 小时（一天跑一遍，够覆盖到下一次同类阶段），帧数约 96 + 7，
/// 但这些都是**预渲染帧**，不消耗刷新预算（预算只算 `getTimeline`）。
/// `policy: .after(下一个边界 + 1 秒)`：边界后立刻重排一轮，
/// 保证卡片永远握着"至少 23 小时"的未来帧，且跨日后日出日落自动更新。
struct SkyLightProvider: TimelineProvider {

    /// 视野：24 小时（覆盖完整一天，跨过一次日出与日落）
    static let horizon: TimeInterval = 24 * 3600
    /// 网格：15 分钟。比简报卡的 30 分钟更细 —— 这张卡的天上有一个**真的在移动**的太阳，
    /// 30 分钟的间隔在日出后会看出"跳一格"。
    static let gridStep: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> SkyLightEntry {
        return SkyLightEntry.make(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SkyLightEntry) -> Void) {
        completion(SkyLightEntry.make(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SkyLightEntry>) -> Void) {
        let now = Date()
        let entries = SkyLightProvider.entries(now: now)

        // 下一个边界 + 1 秒再回来重排：+1 秒是为了让 `SunClock.phase(at:)` 真的跨过阈值，
        // 否则在边界那一瞬重算，新阶段的第一帧会因为"还差 0.4 秒"被判回上一档。
        let nextBoundary = SkyLightEntry.nextPhaseBoundary(after: now, on: now)
            ?? now.addingTimeInterval(3600)
        let refreshAt = nextBoundary.addingTimeInterval(1)

        completion(Timeline(entries: entries, policy: .after(refreshAt)))
    }

    /// 生成这一轮的 entry 序列：**第一帧是当前时刻** + 15 分钟网格 + 所有阶段边界。
    ///
    /// 去重（边界常常落在整刻点上）后升序，并过滤掉过去的帧 —— WidgetKit 不接受
    /// 时间早于现在的 entry，出现过去的帧会让系统判定这条 timeline 失效。
    ///
    /// 网格复用 `WidgetTimeline.stamps`（Widget target 里已有的等距铺点工具，
    /// 自带防死循环），边界帧由 `boundaryStamps` 单独补。
    static func entries(now: Date) -> [SkyLightEntry] {
        var stamps = WidgetTimeline.stamps(now: now, horizon: horizon, step: gridStep)
        stamps.append(contentsOf: boundaryStamps(now: now, horizon: horizon))

        let ordered = Array(Set(stamps.filter { $0 >= now })).sorted()
        return ordered.map { SkyLightEntry.make(date: $0) }
    }

    /// 未来 `horizon` 里所有阶段边界时刻（严格晚于 `now`）。
    ///
    /// 游标每轮强制前进（边界 + 1 秒），循环次数有硬上限：24 小时最多跨 7 档，
    /// 16 次给足余量，任何异常数据都不会把 `getTimeline` 拖死。
    static func boundaryStamps(now: Date, horizon: TimeInterval) -> [Date] {
        let limit = now.addingTimeInterval(horizon)
        var result: [Date] = []
        var cursor = now

        for _ in 0..<16 {
            guard let boundary = SkyLightEntry.nextPhaseBoundary(after: cursor, on: cursor) else {
                break
            }
            if boundary >= limit { break }
            result.append(boundary)
            cursor = boundary.addingTimeInterval(1)
        }
        return result
    }
}
