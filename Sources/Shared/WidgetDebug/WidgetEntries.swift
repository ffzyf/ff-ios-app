import Foundation
import WidgetKit

// MARK: - Widget Timeline Entry 值类型（App / Widget 双 target 共用）

/// 5.1.2 · T03：把 6 个 `*Entry` 的**值类型定义**从 `Sources/Widget/` 抽到 `Sources/Shared`。
///
/// ## 为什么必须抽（首批一致性疑点 ③ 的正式解决）
/// `project.yml` 用 `- path: Sources / excludes: ["Widget"]` 把整个 `Sources/Widget`
/// 排除在主 App target 之外，另以独立 `path:` 条目显式引入 `*Face` 渲染层（R5 调试面板
/// 要「App 进程内复用渲染层」）。而 Face 的 `init(entry: XxxEntry)` 需要具体 entry 类型，
/// 这些类型原本散落在 `WidgetProvider.swift` / `SkyLightProvider.swift` / 三个 `*Widget.swift`
/// —— 全是**不进主 App target** 的 Provider 文件。不抽，主 App 编译必然报
/// `cannot find 'XxxEntry' in scope`。
///
/// 抽到 Shared 后：主 App target 与 Widget target 都编译本文件，Face 与 Provider 引用
/// **同一份**类型（单一真相源），调试面板可以直接构造模拟 entry 交给 `*Face`。
///
/// ## 抽取纪律（最小改动）
/// 1. 这里只放**字段 + 只读计算属性**，且它们只依赖 `Sources/Shared` 里的类型
///    （`SkyPhase` / `SunClock` / `RockPhase` / `Occurrence` / `WeatherNow` /
///    `MinutelyRain` / `WeatherKind` / `SkyViewing` / `Formatters` / `RedstoneClock`）。
/// 2. 依赖 Widget-only 类型（`WeatherCardPayload` / `BriefCachePayload` /
///    `WidgetTheme` / `SunTimesOverride` / `SkyLightWeatherFeed`）的 `static func make`
///    / `empty` / `preview` / `weekRows` **一律留在原文件**，改为 `extension XxxEntry`，
///    继续只被 Widget target 编译。主 App 不需要造真实 entry（调试面板用预设 + 自定义
///    JSON 注入），因此不缺这些工厂方法。
/// 3. `RedstoneWeekRow`（`RedstoneEntry.weekRows` 的字段类型）与 `MoonPhaseMath`
///    （Face 与 `MoonPhaseEntry` 共用的纯天文计算）同样只依赖 Foundation，一并抽到本文件。
/// 4. 字段、计算属性、注释口径与原文一致；**不改任何展示语义**。
///
/// 「调试看到的 = 桌面看到的」的前提就是这里：预览构造的 entry 与 Provider 产出的
/// entry 是同一个类型，交给同一份 `*Face` 渲染。

// MARK: - 本周排期行（原 WidgetProvider.swift:549）

/// 红石大号卡「本周排期」的一行：一天一条。
///
/// 只带**展示需要的三个字符串**（不塞 `[Occurrence]`）：entry 会进 Timeline 缓存，
/// 让每行背着整天的场次对象既没必要，也让「哪天开始多带一个字段」变得难以察觉。
struct RedstoneWeekRow: Identifiable, Equatable {
    /// `"2026-11-01"`
    let dayKey: String
    /// `"今天"` / `"明天"` / `"周三"`
    let dayLabel: String
    /// `"11:08 · 17:08 · 23:08"`
    let timesLabel: String
    /// `"霞谷·圆梦村"`；空串 = 待确认（渲染层照样不编地名）
    let map: String

    var id: String { dayKey }
}

// MARK: - 月相计算（原 MoonPhaseWidget.swift:20，纯本地、零网络）

/// 月龄 / 照明度 / 月名 —— **纯天文计算，零网络**。
///
/// 以 2000-01-06 18:14 UTC 的新月（朔）为纪元，朔望月周期取 29.53059 天（平均朔望月）。
/// 固定周期模型长期误差约 ±0.5 天，对「今晚月亮多圆」这个展示粒度足够。
/// 5.1.2 从 `MoonPhaseWidget.swift` 抽到 Shared：`MoonPhaseFace` / `MoonDisc`（主 App
/// 编译）与 `MoonPhaseEntry.make`（Widget 编译）都要用它，同一份实现，零第二真值源。
enum MoonPhaseMath {

    /// 纪元：2000-01-06 18:14:00 UTC（那刻是朔）的 Unix 秒
    private static let epochSeconds: Double = 947_182_440
    /// 平均朔望月（天）
    static let synodicMonth: Double = 29.53059

    /// 月龄（天，0…29.53）。0 = 朔、14.77 = 望
    static func age(on date: Date) -> Double {
        let elapsed = date.timeIntervalSince1970 - epochSeconds
        let days = elapsed / 86_400
        let raw = days.truncatingRemainder(dividingBy: synodicMonth)
        return raw < 0 ? raw + synodicMonth : raw
    }

    /// 照明度（0…1）。朔 0、望 1：`illumination = (1 − cos(2π·age/周期)) / 2`
    static func illumination(_ age: Double) -> Double {
        return (1 - cos(2 * .pi * age / synodicMonth)) / 2
    }

    /// 八段月名（与后端无契约、纯展示；顺序按月龄均分 8 段，每段 ≈ 3.69 天）
    static func name(_ age: Double) -> String {
        let names = ["朔", "娥眉", "上弦", "盈凸", "望", "亏凸", "下弦", "残月"]
        let segment = synodicMonth / 8
        let index = Int((age / segment).rounded()) % names.count
        return names[max(0, index)]
    }

    /// 是否盈月（月龄 < 半周期，亮面在西边 / 视觉右侧）
    static func isWaxing(_ age: Double) -> Bool {
        return age < synodicMonth / 2
    }

    /// 距下一次满月还有几天。满月在月龄 14.765 天（半周期）；取整用 `rounded()`
    /// 而不是 `ceil()`：差 0.4 天时说「还有 0 天」（今晚就圆）才对。
    static func daysToFullMoon(_ age: Double) -> Int {
        let half = synodicMonth / 2
        let remaining = age <= half ? half - age : (synodicMonth - age) + half
        return max(0, Int(remaining.rounded()))
    }

    /// 阴影圆的偏移量（相对月盘半径的比例，0…2）。
    /// 由等圆透镜面积公式反解（二分 32 次，纯函数、确定性 —— Widget 每帧重绘，
    /// 绝不能有随机或近似抖动），保证「图上的亮面比例」与文字照明度百分比严格一致。
    static func shadowOffset(for illumination: Double, radius: Double) -> Double {
        let clamped = min(max(illumination, 0), 1)
        let area = Double.pi * radius * radius
        func lensArea(_ d: Double) -> Double {
            let half = d / 2
            let term = 4 * radius * radius - d * d
            return 2 * radius * radius * acos(min(max(half / radius, 0), 1))
                - half * (term > 0 ? term.squareRoot() : 0)
        }
        var low = 0.0
        var high = 2 * radius
        // 边界快速返回：全暗 / 全亮不需要迭代
        if clamped <= 0.001 { return 0 }
        if clamped >= 0.999 { return 2 * radius }
        for _ in 0..<32 {
            let mid = (low + high) / 2
            let bright = 1 - lensArea(mid) / area
            if bright < clamped { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }
}

// MARK: - WindEntry（原 WindWidget.swift:7）

/// 风卡的 Timeline entry：当前风速 / 风向（来自 `/api/app/weather`，失败回退缓存）。
/// `static func make(date:payload:)` 依赖 Widget-only 的 `WeatherCardPayload`，
/// 留在 `WindWidget.swift` 的 `extension WindEntry`（仅 Widget target 编译）。
struct WindEntry: TimelineEntry {
    let date: Date
    /// 风速（km/h，Open-Meteo 默认单位）；nil = 没拿到（卡面走缺省形态）
    let wind: Double?
    /// 风向 16 方位中文（"东北"…）；nil = 同上
    let windDirText: String?
    /// 风向来向角度（0 = 正北、顺时针，meteorological：风**从**这个方向来）
    let windDirectionDegrees: Double?
    /// 上游观测时刻（底行"数据时间"；nil = 整段不画）
    let updatedAt: Date?
}

// MARK: - SunArcEntry（原 SunArcWidget.swift:11）

/// 日弧卡的一条 Timeline entry。
///
/// 为什么日出 / 日落 / 阶段在 entry 里备好、而不是 View 里现算：与 `SkyLightEntry`
/// 同一条纪律 —— entry 是预渲染帧，View 里现取 `Date()` 会让「卡片显示的时刻」与
/// 「太阳在弧上的位置」错位。
/// `static func make(date:payload:)` 依赖 Widget-only 的 `WeatherCardPayload`，
/// 留在 `SunArcWidget.swift` 的 `extension SunArcEntry`。
struct SunArcEntry: TimelineEntry {
    let date: Date
    /// 这一帧属于哪一档天色（七档，决定整卡渐变的配色）
    let phase: SkyPhase
    /// 当天实际日出（来自天气接口；接口没给就回退 `SunClock` 计算值，见 `make`）
    let sunrise: Date?
    /// 当天实际日落（同上）
    let sunset: Date?
    /// 当前气温（℃）；nil = 没拿到 → 那一句整段不画（绝不写 "—°"）
    let temp: Double?
    /// 天气现象中文（"小雨"），nil = 没拿到
    let weatherText: String?
    /// 今日高 / 低温
    let tMax: Double?
    let tMin: Double?

    /// 太阳在弧上的进度（0 = 日出、1 = 日落）；夜里 / 算不出时为 nil（不画太阳点）
    var dayProgress: Double? {
        guard let sunrise = sunrise, let sunset = sunset else { return nil }
        let span = sunset.timeIntervalSince(sunrise)
        guard span > 0 else { return nil }
        let raw = date.timeIntervalSince(sunrise) / span
        guard raw >= 0, raw <= 1 else { return nil }   // 夜里：太阳在弧线以下，不画
        return raw
    }

    /// 下一站（倒计时目标）：白天数到日落，日落后数到下一次日出。
    ///
    /// 为什么不复用 `SkyLightEntry.deadline`：那张卡数的是「下一阶段起点」（换色用），
    /// 这张卡数的是「距离日落 / 日出」—— 两个口径在 `sunset` 附近会差出 70 分钟，
    /// 不能混用。
    var nextEvent: Date? {
        if let sunset = sunset, date < sunset { return sunset }
        guard let tomorrow = SunClock.times(on: date.addingTimeInterval(86_400)) else { return nil }
        return tomorrow.sunrise
    }

    /// 大号底部那一句「晴 21° 12°/24°」。三头（现象 / 温度 / 高低温）全缺就返回 nil。
    /// 为什么允许「只有一部分」：这句是**辅助信息**，缺一项就少写一项，比整句消失更有用。
    var weatherSummary: String? {
        var parts: [String] = []
        if let text = weatherText, text.isEmpty == false { parts.append(text) }
        if let temp = temp { parts.append("\(Int(temp))°") }
        if let tMax = tMax, let tMin = tMin { parts.append("\(Int(tMin))°/\(Int(tMax))°") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

// MARK: - MoonPhaseEntry（原 MoonPhaseWidget.swift:107）

/// 月相卡的 Timeline entry（纯本地计算，无网络）。
/// `static func make(date:)` 留在 `MoonPhaseWidget.swift` 的 `extension MoonPhaseEntry`。
struct MoonPhaseEntry: TimelineEntry {
    let date: Date
    /// 月龄（天）
    let age: Double
    /// 照明度 0…1
    let illumination: Double
    /// 月名（朔 / 娥眉 / 上弦 / 盈凸 / 望 / 亏凸 / 下弦 / 残月）
    let name: String

    /// 距下一次满月还有几天。不是 Optional：纯天文函数永远算得出，没有「缺数据」这一说。
    var daysToFullMoon: Int {
        return MoonPhaseMath.daysToFullMoon(age)
    }

    /// 大号卡底部那行文案：`下次满月还有 3 天` / `今晚满月`
    var fullMoonText: String {
        return daysToFullMoon == 0 ? "今晚满月" : "下次满月还有 \(daysToFullMoon) 天"
    }
}

// MARK: - SkyLightEntry（原 SkyLightProvider.swift:19）

/// 天光小组件的一帧。
///
/// 为什么把「阶段 / 倒计时目标 / 日出日落」全部在 entry 里算好，而不是留给 View：
/// entry 是 Timeline **预渲染**的时刻，`date` 就是「这一帧代表哪一刻」。如果 View 里
/// 现取 `Date()`，系统展示一条旧帧时文字会和真实时间错位。
///
/// 存「观测」而不存「词」：渲染层说的话是 `phase.label(viewing:)` 这个纯函数的结果，
/// 若改存 `phaseLabel: String`，同一句话就有了两个真值来源，会写出「黄金时刻」却配着
/// 白天的蓝且没有编译错误提醒。
/// `static func make / sunTimes` 等工厂方法依赖 Widget-only 的 `SunTimesOverride` /
/// `SkyLightWeatherFeed`，留在 `SkyLightProvider.swift` 的 `extension SkyLightEntry`；
/// 只依赖 Shared 的 `deadline(for:phase:)` / `upcomingSunrise(after:)` 已在本文件下沉
/// （见下方 `extension SkyLightEntry`）。
struct SkyLightEntry: TimelineEntry {

    /// 这一帧对应的时刻（= 上一个阶段边界，或 15 分钟网格点）
    let date: Date
    /// 这一帧属于哪一档天色（七档，见 `SunClock` 文件头的时段定义）
    let phase: SkyPhase
    /// 这一帧的**天气判定**（三档，见 `SkyViewing`）。nil = 没拿到数据。
    let viewing: SkyViewing.Verdict?
    /// 倒计时要数到的时刻：**下一阶段的起点**。夜里是下一次日出
    let deadline: Date?
    /// 这一帧所在"一天"的日出（北京时间）；极昼极夜为 nil，地面区整块不画
    let sunrise: Date?
    /// 同上的日落
    let sunset: Date?
    /// 这一帧要叠加的天气实况。**可空，且 nil 是正常状态**（拉失败就完全不画叠加层，
    /// 绝不兜底成晴天）。
    let weather: WeatherNow?
    /// 这一帧的能见度（米）。nil = 没数据（不是"很好"）。
    let visibilityMeters: Double?

    /// 天气类型（8 组视觉类型）。nil = 不知道什么天 → 叠加层整层不画
    var weatherKind: WeatherKind? {
        return weather?.kind
    }

    /// 距 `deadline` 还有多少秒（已经过点 / 算不出时返回 0）
    var remaining: TimeInterval {
        guard let deadline else { return 0 }
        return max(0, deadline.timeIntervalSince(date))
    }

    /// 倒计时是否需要「秒级走时」。< 1 小时才需要，交给 `Text(timerInterval:)` 由系统
    /// 自绘（Widget 里**不能**起 Timer，进程随时会被挂起）。
    var needsSecondTicker: Bool {
        return remaining > 0 && remaining < 3600
    }

    /// ≥ 1 小时用的静态文案：`12小时32分钟` / `49分钟30秒`（规则见 `SkyPhase.countdownText`）
    var countdownText: String? {
        guard let deadline else { return nil }
        return SkyPhase.countdownText(to: deadline, now: date)
    }
}

// MARK: - SkyLightEntry 倒计时目标（5.1.2 从 SkyLightProvider.swift 纯平移）

/// 5.1.2 · T03：`deadline(for:phase:)` / `upcomingSunrise(after:)` 从
/// `Sources/Widget/SkyLightProvider.swift` **纯平移**到这里。
///
/// ## 为什么必须下沉
/// `DaylightLiveActivity.swift` 已显式接入主 App target（R5 调试面板），它要现造一帧
/// `SkyLightEntry`，倒计时目标就写 `SkyLightEntry.deadline(for:phase:)`。原实现只在
/// Widget target 的 Provider 文件里 —— 主 App 看不到那个 static 方法，于是把
/// `SkyLightEntry.deadline` 解析成**实例属性** `let deadline: Date?`，报
/// `cannot call value of non-function type 'Date?'`。
///
/// ## 为什么可以下沉
/// 这两个方法只依赖 Shared 里的 `SunClock` / `RedstoneClock` 与 `SkyPhase.deadline(at:)`，
/// 不碰 `SunTimesOverride` / `SkyLightWeatherFeed` 这些 Widget-only 类型
/// （那些仍留在 `SkyLightProvider.swift` 的 `extension SkyLightEntry`）。
///
/// ## 抽取纪律
/// 实现与注释逐字未改：同一套 `SunClock` 算法，夜间仍走「下一次日出」而不是
/// `SkyPhase.deadline(at:)`（后者过了子夜会指向明天，凌晨 1 点会显示 29 小时）。
extension SkyLightEntry {

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
}

// MARK: - BriefEntry（原 WidgetProvider.swift:722）

/// 简报小组件的一帧。
/// `static func make(date:payload:weather:minutely:)` 依赖 Widget-only 的
/// `BriefCachePayload`，留在 `WidgetProvider.swift` 的 `extension BriefEntry`。
struct BriefEntry: TimelineEntry {
    let date: Date
    let hasData: Bool
    /// `"10月30日"`
    let dateText: String
    /// `"周四"`
    let weekdayText: String
    /// 前 2 段
    let paragraphs: [String]
    let pushedToday: Bool
    let pushedAt: Date?
    /// 生日文案（`07-17` / `1995-07-17` / `7月17日` 三种都见过），`nil` = 服务端没给
    let birthday: String?
    /// 宜（服务端 `brief.yi[]`，已按服务端顺序排好）
    let yi: [String]
    /// 忌
    let ji: [String]
    /// 服务端给的日出文案；nil 时渲染层退回 `SunClock` 现算（**不编造**）
    let sunrise: String?
    /// 服务端给的日落文案
    let sunset: String?
    /// 今天的天气实况（`GET /api/app/weather`）。**拉失败就是 nil** —— 卡片退回无天气
    /// 形态，绝不猜一个晴天出来。
    let weather: WeatherNow?
    /// 未来两小时的分钟级降水。nil 的三种来源（超时 / `ok == false` / 没给 `points`）
    /// 语义都是「没拿到」，不是「无降水」，底部柱状图整块不画。
    let minutely: MinutelyRain?

    /// 页脚文案：「今日已推送 07:02」/「今日未推送」。没有简报数据时整条页脚不画
    var footerText: String? {
        guard hasData else { return nil }
        if pushedToday {
            guard let pushedAt = pushedAt else { return "今日已推送" }
            return "今日已推送 " + Formatters.timeHHmm(pushedAt)
        }
        return "今日未推送"
    }

    /// 地平线**以下**那行注脚：`宜 打猎、散步 · 忌 店铺开业`。
    /// 空则返回 nil —— 调用方整行不画。**取不到就空着，绝不编一条"今日宜出行"出来**。
    var ritualText: String? {
        var parts: [String] = []
        if !yi.isEmpty {
            parts.append("宜 " + yi.prefix(2).joined(separator: "、"))
        }
        if !ji.isEmpty {
            parts.append("忌 " + ji.prefix(1).joined(separator: "、"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 日出 / 日落文案：优先服务端值（它按当地算过，比 App 自己算的准），
    /// 缺了才回落到 `SunClock`（天文计算，误差 ±3 分钟，不是编造内容）。
    /// 两头都拿不到就返回 nil，地面区那一侧整个不画。
    func sunTexts() -> (rise: String?, set: String?) {
        if let rise = nonEmpty(sunrise), let set = nonEmpty(sunset) {
            return (rise, set)
        }
        guard let times = SunClock.times(on: date) else {
            return (nonEmpty(sunrise), nonEmpty(sunset))
        }
        return (nonEmpty(sunrise) ?? Formatters.timeHHmm(times.sunrise),
                nonEmpty(sunset) ?? Formatters.timeHHmm(times.sunset))
    }

    private func nonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - RedstoneEntry（原 WidgetProvider.swift:485）

/// 红石小组件的一条 Timeline entry。
///
/// 为什么把 `phase` / `todayOccurrences` 在**生成 entry 时**就算好、而不是在 View 里算：
/// entry 的 `date` 就是「这一条被渲染的时刻」，而 View 里拿不到时间机器 ——
/// 直接把结论带进去，View 只负责画，不会出现「View 用 `Date()` 现算」导致
/// 预渲染与真实显示不一致的经典小组件 bug。
/// `static func make / empty / preview / weekRows` 依赖 Widget-only 的
/// `RedstoneDay` / `WidgetTheme` / `SkyLightEntry.make`，留在 `WidgetProvider.swift`
/// 的 `extension RedstoneEntry`。
struct RedstoneEntry: TimelineEntry {
    let date: Date
    /// 有没有排期数据（false = 显示「暂无排期」，绝不显示 00:00 或假地图）
    let hasData: Bool
    /// 数据最后生成时间（过期提示用；nil 时不提示）
    let updatedAt: Date?
    let phase: RockPhase
    /// 今日全部场次（含已过），中号右半用它画列表
    let todayOccurrences: [Occurrence]
    /// 今日场次数
    let todayCount: Int
    /// 今日是否有待核对场次
    let needsCheck: Bool
    /// 空窗期（`focus == nil`）时整卡切换的天光帧（由 Provider 在造 entry 时顺带算好，
    /// 视图里再起一个 `SkyLightProvider` 会破坏「一张卡一个 Provider」的契约）。
    let daylight: SkyLightEntry?

    /// 一份天气观测最多往后认多久（秒）：3 小时。超限的帧退回 `nil`，
    /// 词变成「晨光剩余」/「入夜剩余」，天气摘要与云层整块不画。
    static let weatherFreshness: TimeInterval = 3 * 3600

    /// 「本周排期」（大号卡下半部那 3–4 行）。空数组 = 没有未来场次，大号卡下半部
    /// 整块不渲染。
    let weekRows: [RedstoneWeekRow]

    /// 下一场 / 进行中的那一场（没有就 nil）
    var focus: Occurrence? { phase.occurrence }
}
