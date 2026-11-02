import CoreGraphics
import Foundation

/// 天空时段 —— 简报卡「天际线」用它决定配色，也决定卡片上那句话说什么。
enum SkyPhase: String, CaseIterable {
    /// 深夜（日落后 30 分钟 ~ 日出前 24 分钟）
    case night
    /// 晨间蓝调（日出前 24 分钟 ~ 日出）
    case blueDawn
    /// 日出（日出 ~ 日出后 24 分钟）
    case sunrise
    /// 黄金时刻（日出后 24 ~ 70 分钟）
    case golden
    /// 白天
    case day
    /// 日落（日落前 70 分钟 ~ 日落）
    case sunset
    /// 暮间蓝调（日落 ~ 日落后 30 分钟）
    case blueDusk
}

/// 日出日落与天空时段。
///
/// 为什么自己算而不是写死 `06:05 / 18:13`：这两个时刻**每天都在变**（北京一年里日出
/// 从 04:46 到 07:32 跨了近 3 小时），写死的话入冬就全错。用赤纬 + 时角的简化式，
/// 误差在 ±3 分钟内 —— 对"背景色该是橙还是紫"这个精度需求绰绰有余。
///
/// 默认坐标取北京（用户在用的时区）：经度参与"太阳正午"修正，
/// 所以西边城市会自然晚一些，不需要每处都传参。
enum SunClock {

    /// 北京（朝阳）坐标
    static let latitude: Double = 39.9042
    static let longitude: Double = 116.4074

    /// 某天的日出 / 日落（北京时间）。极昼极夜返回 nil —— 中国境内不会发生，但不做假设。
    static func times(on date: Date,
                      latitude lat: Double = latitude,
                      longitude lon: Double = longitude) -> (sunrise: Date, sunset: Date)? {
        var calendar = RedstoneClock.calendar
        calendar.timeZone = RedstoneClock.beijing

        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }
        guard let dayStart = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) else { return nil }

        // 赤纬 δ（Cooper 近似）：一年里在 ±23.44° 之间摆动
        let declination = 23.44 * sin(2 * .pi * (Double(dayOfYear) - 81) / 365.0) * .pi / 180
        let latRad = lat * .pi / 180

        // 日出时角：cos H = -tan φ · tan δ
        let cosH = -tan(latRad) * tan(declination)
        guard abs(cosH) <= 1 else { return nil }
        let halfDayHours = (acos(cosH) * 180 / .pi) / 15.0

        // 太阳正午的时钟时刻：东八区中央经线 120°E，经度每偏 1° 差 4 分钟
        let solarNoon = 12.0 - (lon - 120.0) / 15.0

        let sunrise = dayStart.addingTimeInterval((solarNoon - halfDayHours) * 3600)
        let sunset = dayStart.addingTimeInterval((solarNoon + halfDayHours) * 3600)
        return (sunrise, sunset)
    }

    /// 此刻属于哪个时段
    static func phase(at now: Date) -> SkyPhase {
        guard let today = times(on: now) else { return .day }

        let dawnStart = today.sunrise.addingTimeInterval(-24 * 60)
        let sunriseEnd = today.sunrise.addingTimeInterval(24 * 60)
        let goldenEnd = today.sunrise.addingTimeInterval(70 * 60)
        let sunsetStart = today.sunset.addingTimeInterval(-70 * 60)
        let duskEnd = today.sunset.addingTimeInterval(30 * 60)

        if now < dawnStart { return .night }
        if now < today.sunrise { return .blueDawn }
        if now < sunriseEnd { return .sunrise }
        if now < goldenEnd { return .golden }
        if now < sunsetStart { return .day }
        if now < today.sunset { return .sunset }
        if now < duskEnd { return .blueDusk }
        return .night
    }

    /// 这个时段对应的「几点到几点」（设置 / 调试用；也用来给卡片画时间轴）
    static func window(of phase: SkyPhase, on date: Date) -> (start: Date, end: Date)? {
        guard let today = times(on: date) else { return nil }
        switch phase {
        case .night:
            return (today.sunset.addingTimeInterval(30 * 60), today.sunrise.addingTimeInterval(-24 * 60 + 86400))
        case .blueDawn:
            return (today.sunrise.addingTimeInterval(-24 * 60), today.sunrise)
        case .sunrise:
            return (today.sunrise, today.sunrise.addingTimeInterval(24 * 60))
        case .golden:
            return (today.sunrise.addingTimeInterval(24 * 60), today.sunrise.addingTimeInterval(70 * 60))
        case .day:
            return (today.sunrise.addingTimeInterval(70 * 60), today.sunset.addingTimeInterval(-70 * 60))
        case .sunset:
            return (today.sunset.addingTimeInterval(-70 * 60), today.sunset)
        case .blueDusk:
            return (today.sunset, today.sunset.addingTimeInterval(30 * 60))
        }
    }
}

// MARK: - 太阳在天上的位置（V3.4：桌面小组件的「实时太阳」）
//
// 用户要的不是一个装饰性的太阳图标，而是**「太阳现在在哪儿」**：日出贴左、正午最高、
// 日落贴右，走一条拱形轨迹。所以这里只做纯数学 —— 不给颜色、不碰 SwiftUI 视图，
// 位置一律用**归一化坐标**（0…1，左上角为原点）返回，由调用方乘上画布尺寸。
// 纯函数意味着它可以被单测、被预览、被 App 内那张卡复用，零副作用。

extension SunClock {

    /// 太阳轨迹的几何常量（归一化，0 = 画布顶 / 左）。
    ///
    /// `crestY` 直接取共享常量 `HorizonSky.crestY`（0.62）：太阳落在"弧顶高度"上，
    /// 正好压在那条地平线亮边上。以前这里另写一个 0.62 再靠注释说"必须与小组件一致"，
    /// 3.11.0 起读同一份定义 —— 两边不可能再漂。
    /// 两侧各留 0.10 的边，是给卡片圆角让位 ——
    /// 太阳贴在 0 / 1 的角上会被裁掉半个，看起来像画错了。
    enum SunTrack {
        /// 日出时太阳的水平位置
        static let leftX: CGFloat = 0.10
        /// 日落时太阳的水平位置
        static let rightX: CGFloat = 0.90
        /// 拱顶高度（天空区上方）
        static let peakY: CGFloat = 0.10
        /// 地平线弧顶高度（= 共享常量 `HorizonSky.crestY`）
        static let crestY: CGFloat = HorizonSky.crestY
        /// 太阳落下后余晖衰减的时长（分钟）：超过它天空里不再有任何太阳的痕迹
        static let glowFadeMinutes: Double = 45
    }

    /// 太阳此刻在天空里的「印记」：位置、是否露出地平线、光晕强度。
    ///
    /// 为什么不只返回一个 `CGPoint`：夜里夕阳已经落到弧线以下，视图需要知道
    /// **「这次不画本体，只留一点余晖」**，而余晖还要按"落下多久"衰减。
    /// 三件事一起返回，调用方就不必再算一遍日出日落。
    struct SunMark {
        /// 归一化位置：x 从左到右 0…1，y 从上到下 0…1
        let point: CGPoint
        /// 太阳本体是否在地平线以上（false = 夜里，只画余晖不画圆盘）
        let isUp: Bool
        /// 光晕强度 0…1（在地平线上恒为 1，落下后按 `glowFadeMinutes` 线性衰减到 0）
        let intensity: CGFloat
    }

    /// 太阳此刻的印记。算不出日出日落（极昼极夜）时返回 nil。
    ///
    /// 轨迹是一条**正弦拱**，不是直线也不是抛物线：
    /// - 归一化进度 `p = (now − sunrise) / (sunset − sunrise)`，夹到 0…1；
    /// - `x = leftX + (rightX − leftX) · p` —— 水平匀速，用户读得出"过了一半的时间"；
    /// - `y = crestY − (crestY − peakY) · sin(π · p)` —— `sin(π·p)` 在 0 / 1 处为 0、
    ///   在 0.5 处为 1，所以**日出日落两端自动落在弧顶高度（0.62）、正午升到 0.10**，
    ///   不用写任何分段判断。正弦比抛物线好在两端"起飞/落地"更缓，接近真实日轨。
    static func sunMark(at now: Date,
                        on date: Date,
                        crestY: CGFloat = SunTrack.crestY,
                        peakY: CGFloat = SunTrack.peakY) -> SunMark? {
        guard let today = times(on: date) else { return nil }
        let span = today.sunset.timeIntervalSince(today.sunrise)
        // 极昼 / 极夜被 times(on:) 拦掉后 span 仍然可能是 0，这里再兜一层
        guard span > 0 else { return nil }

        let raw = now.timeIntervalSince(today.sunrise) / span
        let isUp = raw >= 0 && raw <= 1
        let progress = CGFloat(min(max(raw, 0), 1))

        let x = SunTrack.leftX + (SunTrack.rightX - SunTrack.leftX) * progress
        let arch = CGFloat(sin(Double.pi * Double(progress)))
        let y = crestY - (crestY - peakY) * arch

        var intensity: CGFloat = 1
        if !isUp {
            // 落下多久了 / 还有多久升起 —— 取离地平线最近的那一头
            let gap: TimeInterval = raw < 0
                ? today.sunrise.timeIntervalSince(now)
                : now.timeIntervalSince(today.sunset)
            let minutes = max(0, gap) / 60
            intensity = max(0, 1 - CGFloat(minutes / SunTrack.glowFadeMinutes))
        }

        return SunMark(point: CGPoint(x: x, y: y), isUp: isUp, intensity: intensity)
    }

    /// 太阳在天空中的归一化位置。nil = 太阳在地平线以下（夜里）。
    ///
    /// 这是对外的主入口（视图只关心"画在哪儿"）：夜里的余晖由 `sunMark` 负责，
    /// 这里刻意返回 nil，避免调用方写出"夜里天上还挂个球"。
    /// `progress = 0.5` 时返回接近拱顶的值（y ≈ 0.10）。
    static func sunPosition(at now: Date, on date: Date) -> CGPoint? {
        guard let mark = sunMark(at: now, on: date), mark.isUp else { return nil }
        return mark.point
    }
}

// MARK: - 卡片文案

extension SkyPhase {

    // 3.23.0 起这里**没有** `var label` 了。
    //
    // 那七个词（夜间 / 日出 / 黄金时刻 / 距离日落 / 日落剩余 / 入夜剩余 / 蓝调剩余）
    // 全都搬进了 `SkyPhase.label(viewing:)`（见 `Shared/Domain/SkyViewing.swift`）：
    // 其中三档承诺的是**颜色**，阴天/雨雾里就是假话，所以"说什么"必须与天气一起判。
    //
    // 删掉无参版本不是洁癖：留着它，任何一处新写的 `.label`（不带 viewing）都能编过 ——
    // 于是"悄悄说一句假话"只需要一次手滑，而且编译器和 lint 都不会出声。
    // 现在漏传 `viewing` 是**编译错误**，这就是这条门禁的全部意义。

    /// 右上角倒计时要数到的时刻；nil = 当前时段不给倒数（例如刚日出的那一刻）
    func deadline(at now: Date) -> Date? {
        guard let today = SunClock.times(on: now) else { return nil }
        switch self {
        case .night:
            // 夜里数到「下一次日出」。
            //
            // 不能一律取 `now + 24h` 的日出：`.night` 这一段横跨午夜，
            // 凌晨 2 点仍属于 night，但那时"下一次日出"就是**今天** 06:05（4 小时后），
            // 取明天会显示成 28 小时 —— 用户在「天光」组件上会看到"距日出 28 小时"，明显是错的。
            // 判据：今天日出还没到 → 就是今天；已经过了（前半夜）→ 才跨到明天。
            if now < today.sunrise { return today.sunrise }
            let tomorrow = now.addingTimeInterval(86_400)
            return SunClock.times(on: tomorrow)?.sunrise
        case .blueDawn:
            return today.sunrise
        case .sunrise:
            return today.sunrise.addingTimeInterval(24 * 60)
        case .golden:
            return today.sunrise.addingTimeInterval(70 * 60)
        case .day:
            return today.sunset.addingTimeInterval(-70 * 60)
        case .sunset:
            return today.sunset
        case .blueDusk:
            return today.sunset.addingTimeInterval(30 * 60)
        }
    }

    /// 倒计时到期（或只剩不到 1 秒）时给的文案。
    ///
    /// 为什么不显示 0：`0分钟0秒` 是"已经结束"的读数，而这一刻离切换只差最后一抖 ——
    /// 用户读到的是"倒计时坏了"，不是"马上要换天色了"。
    static let imminentText = "即将切换"

    /// 倒计时文案：`2分钟4秒` / `7小时34分钟` / `49分钟30秒`（与参考图一致，不补零）。
    ///
    /// ## 为什么必须先判 `date > now`（3.11.0 QA nit）
    ///
    /// 取整是**截断**（`Int(_:)`），所以"还剩 0.4 秒"会被算成 0 秒 →
    /// 下一秒刷新时读到 `0分钟0秒`。而 `phase(at:)` 要到 `deadline` 当刻才翻档：
    /// 屏幕上的相位还是旧的、deadline 还是旧的，于是这最后不到 1 秒必然画出 `0分钟0秒`
    /// （桌面小组件更明显：时间线帧是静态的，过期后可以一直停在 `0分钟0秒`）。
    ///
    /// 所以：`remaining < 1`（含已过期，即 `deadline <= now`）一律返回「即将切换」，
    /// **绝不回 0**。这是所有调用点（天光页 / 天光卡 / 小组件）共用的唯一派生处，
    /// 在这里补上就不会有哪个入口漏掉。
    static func countdownText(to date: Date, now: Date) -> String {
        let remaining = date.timeIntervalSince(now)
        guard remaining >= 1 else { return imminentText }
        let seconds = Int(remaining)
        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "\(hours)小时\(minutes)分钟"
        }
        let minutes = seconds / 60
        let rest = seconds % 60
        return "\(minutes)分钟\(rest)秒"
    }
}
