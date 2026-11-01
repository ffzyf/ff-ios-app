import Foundation

// MARK: - 天气三卡（日弧 / 月相 / 风）共用的数据层（3.10.0）

/// 三个天气类小组件共用的载荷（Wind / SunArc 直接显示它，Moon 只用日弧相关的两个时刻）。
///
/// 为什么不直接在 entry 里塞 `WeatherNow`：这三个卡要**失败回退缓存**（风速 / 日落是
/// 卡的主内容，不像天光的天气只是叠加层 —— `SkyLightWeatherFeed` 那边"失败就不叠"
/// 是对的，这里"失败就空白"是错的）。所以先转成 `Codable` 载荷再落盘
/// `UserDefaults.standard`（无 App Group，Widget 进程自己的标准库，工程先例见 `WidgetSnapshot`）。
struct WeatherCardPayload: Codable {
    /// `"2026-11-01"`（北京时间）：跨天后旧缓存作废的判据 ——
    /// 昨天的日落标成今天，比空白更糟（看起来正常，其实是错的）。
    let dayKey: String
    /// 当前气温（℃）
    let temp: Double?
    /// 今日高 / 低温（℃）
    let tMax: Double?
    let tMin: Double?
    /// 天气现象中文（"小雨"）；缺省 nil
    let text: String?
    /// 风速（Open-Meteo 默认单位 **km/h**，后端未指定 `windspeed_unit`，参考图也是 KM/H）
    let wind: Double?
    /// 风向 16 方位中文（服务端已换算，见 weather.js `windDirTextOf`）
    let windDirText: String?
    /// 今日日出（ISO 本地时刻串，解析见 `Formatters.weatherLocalTime`）
    let sunrise: String?
    /// 今日日落（同上）
    let sunset: String?
    /// 上游观测时间（服务端 `updatedAt`）。风卡底行显示"观测时刻"用它，
    /// 不用 `savedAt` —— "数据是什么时候测的"与"我们什么时候拉的"是两件事
    let updatedAt: Date?
    /// 落盘时刻（诊断用）
    let savedAt: Date

    /// 从一份天气响应构造；业务失败（`ok == false`）返回 nil。
    init?(from response: WeatherNow, at date: Date) {
        guard response.ok else { return nil }
        dayKey = RedstoneClock.dayKey(date)
        temp = response.temp
        tMax = response.tMax
        tMin = response.tMin
        text = response.text
        wind = response.wind
        windDirText = response.windDirText
        sunrise = response.sunrise
        sunset = response.sunset
        updatedAt = response.updatedAt
        savedAt = date
    }

    /// 这天的实际日出（解析失败 / 缺省 = nil）
    var sunriseDate: Date? {
        return Formatters.weatherLocalTime(sunrise)
    }

    /// 这天的实际日落（同上）
    var sunsetDate: Date? {
        return Formatters.weatherLocalTime(sunset)
    }
}

/// 三个天气卡的请求策略（与 `WidgetFetch.brief` / `redstone` 同一套）：
/// 成功写快照、失败读快照 —— 失败时宁可显示上一次成功的数据，也不显示空白或错误。
///
/// 为什么不复用 `WidgetFetch.weather()` 的"不落盘"策略：那边注释写明"天气是装饰，
/// 落盘会给用户一张昨天的晴"；这三个卡不一样 —— **风速和日落就是卡的内容**，
/// 风速半小时内的漂移对"今天风多大"没有意义，日落更是全天不变。
/// `dayKey` 挡住了"跨天用旧值"唯一的真坑（日出日落 / 高低温都是 per-day 的量）。
enum WeatherCardFeed {

    /// 拉一次（网络优先，失败回退当天的缓存；彻底没有就 nil —— 卡面自己走缺省形态）
    static func fetch() async -> WeatherCardPayload? {
        if let response = await WidgetFetch.weather(),
           let payload = WeatherCardPayload(from: response, at: Date()) {
            WidgetSnapshot.save(payload, key: WidgetSnapshot.weatherCardKey)
            return payload
        }
        return WidgetSnapshot.load(WeatherCardPayload.self, key: WidgetSnapshot.weatherCardKey)
    }
}
