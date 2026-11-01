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
/// 天光只描述"此刻的光与此刻的天"：天色来自 `SunClock` 的纯函数，
/// 天气来自一次 `/api/app/weather`。
///
/// 两者在 entry 里**汇合而不是互相依赖**：天气拉失败就填 nil，天色照样算得出来 ——
/// 天光卡的主视觉是"天空 + 地平线 + 太阳"，天气只是叠在它上面的一层，
/// 所以网络失败绝不会让这张卡变成空白或错误态。
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
    /// 这一帧要叠加的天气实况。**可空，且 nil 是正常状态**。
    ///
    /// 为什么整条 timeline 只拉一次、然后逐帧共用同一个值：
    /// 天光一轮排 24 小时、约 103 帧（15 分钟网格 96 帧 + 7 个阶段边界），
    /// 每帧各拉一次就是 103 次请求 —— 刷新预算（每天 40–70 次）会被一轮打穿。
    /// 而"今天到底有没有云"半小时内不会变，共用一份完全够用。
    ///
    /// nil 的三种来源：接口超时 / `ok == false` / 后端没给 `code`。
    /// 三种都走同一条路：**完全不画叠加层**，天空保持原样。
    /// 绝不兜底成晴天：把缺数据画成晴天，是这个项目已经踩过一次的坑
    /// （见 `WeatherKind.from(code:)` 的注释）。
    let weather: WeatherNow?

    /// 天气类型（8 组视觉类型）。nil = 不知道什么天 → 叠加层整层不画
    var weatherKind: WeatherKind? {
        return weather?.kind
    }

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
    ///
    /// - Parameters:
    ///   - date: 这一帧代表的时刻
    ///   - weather: 这一轮拉到的天气。默认 nil：`placeholder` / `getSnapshot` 不发请求，
    ///     所以它们在组件库里露出的就是"纯天光"那一版（也正是无数据时的退化形态）。
    ///   - sunTimes: 当天**实际**日出日落（3.10.0，来自天气接口，见 `SunTimesOverride`）。
    ///     nil = 回退 `SunClock` 计算值（±3 分钟）—— 兜底语义写在 `SunTimesOverride.resolve`。
    static func make(date: Date,
                     weather: WeatherNow? = nil,
                     sunTimes: SunTimesOverride? = nil) -> SkyLightEntry {
        let phase = SunClock.phase(at: date)
        // 显式写类型名：参数 sunTimes 与同名静态方法重名，局部名会遮蔽方法名。
        var times = SkyLightEntry.sunTimes(for: date, phase: phase)
        // 实际值只驱动**同一天**的帧：这一轮 timeline 铺 24 小时，明天的帧拿不到
        // 天气接口的值（上游只给今天），让它们继续用 SunClock —— 跨天时刻略偏 ±3 分钟，
        // 但绝不会出现"用今天的日落顶替明天的"这种张冠李戴。
        if let sunTimes = sunTimes, RedstoneClock.dayKey(date) == sunTimes.dayKey {
            times = (sunTimes.sunrise, sunTimes.sunset)
        }
        return SkyLightEntry(
            date: date,
            phase: phase,
            deadline: deadline(for: date, phase: phase),
            sunrise: times?.sunrise,
            sunset: times?.sunset,
            weather: weather
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

// MARK: - 实际日出日落（3.10.0）

/// 当天**实际**日出日落（来自 `/api/app/weather` 的 `sunrise` / `sunset` 字段）。
///
/// 用户原话："每天的日落时间都不一样，天光小组件应该显示当天实际的日落时间……直接读（天气接口）"。
/// `SunClock` 是天文近似（±3 分钟，驱动**颜色与阶段**绰绰有余），但把 "06:58" 写在
/// 卡片左下角给用户看时，3 分钟就是"和我手机天气 App 对不上"。
/// 所以显示值优先取接口，`SunClock` 只做兜底。
///
/// 只覆盖 `dayKey` 那一天的帧（上游 `forecast_days=1` 只有今天），
/// 其余帧继续用 `SunClock` —— 见 `SkyLightEntry.make` 的注释。
struct SunTimesOverride: Equatable {
    /// `"2026-11-01"`（北京时间）
    let dayKey: String
    let sunrise: Date
    let sunset: Date

    /// 从一轮天气响应里解析实际日出日落，并维护缓存。
    ///
    /// 兜底链（逐级降级，每一级都诚实）：
    /// 1. **网络值**：接口给了合法的 sunrise/sunset 串（`Formatters.weatherLocalTime`
    ///    按 UTC+8 解析无时区后缀的本地时刻串）→ 采用并写缓存；
    /// 2. **缓存值**：这轮没拿到（失败 / 字段缺省）→ 读上次成功的缓存，
    ///    但仅当缓存就是**今天**的（跨天后旧值作废，回退 SunClock ——
    ///    把昨天的日落标成今天，比退回 ±3 分钟的计算值糟得多）；
    /// 3. **都拿不到** → nil：`SkyLightEntry.make` 里整条走 `SunClock` 计算值，
    ///    与 3.9.0 及之前的行为逐点一致。
    static func resolve(from weather: WeatherNow?, now: Date) -> SunTimesOverride? {
        let dayKey = RedstoneClock.dayKey(now)

        if let sunrise = weather?.sunriseDate, let sunset = weather?.sunsetDate {
            let override = SunTimesOverride(dayKey: dayKey, sunrise: sunrise, sunset: sunset)
            WidgetSnapshot.save(
                SunTimesCachePayload(dayKey: dayKey, sunrise: sunrise, sunset: sunset, savedAt: now),
                key: WidgetSnapshot.skylightSunTimesKey
            )
            return override
        }

        if let cached = WidgetSnapshot.load(SunTimesCachePayload.self, key: WidgetSnapshot.skylightSunTimesKey),
           cached.dayKey == dayKey {
            return SunTimesOverride(dayKey: cached.dayKey, sunrise: cached.sunrise, sunset: cached.sunset)
        }

        return nil
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
///
/// 天气是**叠加**进来的，不改变上面这套插帧策略：一轮只发 1 次 `/api/app/weather`
/// （与插帧并发，最多等 8 秒），拿到的同一个 `WeatherNow` 发给这一轮所有 103 帧。
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
        Task {
            let now = Date()

            // 天气与插帧**并发**：`async let` 在声明那一刻就把子任务踢出去跑了，
            // 所以下面算时间戳（纯 CPU）与等天气（最多 8 秒网络）是重叠的，
            // 而不是"先等 8 秒网络，再算帧" —— 天光卡的刷新不能被天气拖长。
            async let pendingWeather = SkyLightWeatherFeed.fetch()
            let stamps = SkyLightProvider.stamps(now: now)
            let weather = await pendingWeather

            // 实际日出日落（3.10.0）：与天气同一次响应，**零额外请求**；
            // 失败时内部走缓存、再失败走 SunClock —— 见 `SunTimesOverride.resolve`。
            let sunTimes = SunTimesOverride.resolve(from: weather, now: now)

            // 每一帧带**同一个**天气（理由见 `SkyLightEntry.weather` 的注释）。
            // 天气为 nil 时这里什么都不特殊处理：entry 带着 nil 下去，渲染层不画叠加层。
            let entries = stamps.map { SkyLightEntry.make(date: $0, weather: weather, sunTimes: sunTimes) }

            // 下一个边界 + 1 秒再回来重排：+1 秒是为了让 `SunClock.phase(at:)` 真的跨过阈值，
            // 否则在边界那一瞬重算，新阶段的第一帧会因为"还差 0.4 秒"被判回上一档。
            let nextBoundary = SkyLightEntry.nextPhaseBoundary(after: now, on: now)
                ?? now.addingTimeInterval(3600)
            let refreshAt = nextBoundary.addingTimeInterval(1)

            completion(Timeline(entries: entries, policy: .after(refreshAt)))
        }
    }

    /// 这一轮 entry 的时间戳集合：**第一帧是当前时刻** + 15 分钟网格 + 所有阶段边界。
    ///
    /// 去重（边界常常落在整刻点上）后升序，并过滤掉过去的帧 —— WidgetKit 不接受
    /// 时间早于现在的 entry，出现过去的帧会让系统判定这条 timeline 失效。
    ///
    /// 单独抽出来是为了配合天气的并发拉取：时间戳是纯计算，可以先把它们排好，
    /// 等天气回来再套同一份 stamps 上 —— 插帧策略一个字没改。
    static func stamps(now: Date) -> [Date] {
        var stamps = WidgetTimeline.stamps(now: now, horizon: horizon, step: gridStep)
        stamps.append(contentsOf: boundaryStamps(now: now, horizon: horizon))
        return Array(Set(stamps.filter { $0 >= now })).sorted()
    }

    /// 生成这一轮的 entry 序列（不需要天气时的直通入口）。
    ///
    /// 网格复用 `WidgetTimeline.stamps`（Widget target 里已有的等距铺点工具，
    /// 自带防死循环），边界帧由 `boundaryStamps` 单独补。
    static func entries(now: Date) -> [SkyLightEntry] {
        return stamps(now: now).map { SkyLightEntry.make(date: $0) }
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

// MARK: - 天气（叠加层的数据源）

/// 天光卡自己的天气请求。
///
/// 为什么不复用 `WidgetFetch.get(_:url:)`：那个超时是 12 秒，是给"简报 / 红石"这种
/// **整张卡的内容都来自网络**的组件定的。天光的天气是叠加层 —— 它迟到 8 秒还好，
/// 但拖到 12 秒就会把这条 timeline 的交付一起往后拖，系统等不到就可能直接渲染占位帧。
/// 这里宁可 8 秒就放弃，超时后返回 nil，天空照旧。
///
/// 为什么失败只返回 nil、不读本地快照：天光卡的语义是"此刻的天"。
/// 拿半小时前（甚至昨天）的天气往今天的天空上叠，比不叠更糟 ——
/// 一个不动的假云会让人以为天气没变，而实物在窗外下着雨。
enum SkyLightWeatherFeed {

    /// 单次请求的超时（秒）。见类型注释：8 秒是"能给就给、给不到就拉倒"的分界。
    static let timeout: TimeInterval = 8

    /// 拉一次天气实况。**任何失败都返回 nil**，绝不 throw、绝不兜底成晴天。
    ///
    /// 三条失败分支都走同一个出口：
    /// - 拼不出 URL（配置坏了）/ 网络错误 / 超时；
    /// - HTTP 非 2xx；
    /// - 业务失败（HTTP 200 + `ok == false`）—— 它只代表"这次没拿到"，
    ///   不代表"天气变好了"，所以同样不下任何结论。
    static func fetch() async -> WeatherNow? {
        guard let url = API.weather() else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }
            // 解码器复用 `WidgetJSON.decoder`：`updatedAt` 是带毫秒的 ISO 字符串，
            // 裸 `JSONDecoder()` 解不开（会把整个响应判成坏数据）。
            let now = try WidgetJSON.decoder.decode(WeatherNow.self, from: data)
            guard now.ok else { return nil }
            return now
        } catch {
            return nil
        }
    }
}

