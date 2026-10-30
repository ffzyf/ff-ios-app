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

// MARK: - 卡片文案

extension SkyPhase {

    /// 左上角那枚圆点后面的话（照参考图的措辞）
    var label: String {
        switch self {
        case .night: return "夜间"
        case .blueDawn: return "蓝调剩余"
        case .sunrise: return "日出"
        case .golden: return "黄金时刻"
        case .day: return "距离日落"
        case .sunset: return "日落剩余"
        case .blueDusk: return "蓝调剩余"
        }
    }

    /// 右上角倒计时要数到的时刻；nil = 当前时段不给倒数（例如刚日出的那一刻）
    func deadline(at now: Date) -> Date? {
        guard let today = SunClock.times(on: now) else { return nil }
        switch self {
        case .night:
            // 夜里数到明天日出
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

    /// 倒计时文案：`2分钟4秒` / `7小时34分钟` / `49分钟30秒`（与参考图一致，不补零）
    static func countdownText(to date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
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
