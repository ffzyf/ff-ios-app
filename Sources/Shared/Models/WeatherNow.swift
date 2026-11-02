import Foundation

/// `GET /api/app/weather`（简报站）的天气实况 —— 匿名可读，无需鉴权。
///
/// 字段契约：**除 `ok` 外全部可能缺省**。服务端严格"空值不占位"（没有值就不给这个键，
/// 不给 `null`、不给空字符串），所以这里每个字段都是可选，缺省不是错误。
///
/// 由此推出两条不能破的规矩：
/// 1. `kind` 是可选 —— 缺 `code` 就是"不知道什么天"。渲染层必须自己表达"天气未知"，
///    不许拿 `.clear` 兜底（那样后端出问题时卡片会阳光明媚地骗人）；
/// 2. 业务失败（`ok == false`，HTTP 仍是 200）只表示这次没拿到数据，
///    **不代表天气变坏了** —— 调用方应保留上一次的值，而不是清空。
///
/// 解码必须用 `APIJSON.decoder`：`updatedAt` 是 `new Date(ms).toISOString()` 那种
/// **带毫秒**的 ISO 字符串，裸 `JSONDecoder()` 的 `.iso8601` 策略解不开（见 `APIClient` 顶部注释）。
struct WeatherNow: Decodable, Equatable, Sendable {

    /// 业务成功标志。**唯一非可选字段**：没有它就无法区分"天气是空的"和"接口报错了"
    let ok: Bool

    /// WMO 4677 天气代码（0,1,2,3,45,48,51,53,55,56,57,61,63,65,66,67,71,73,75,77,
    /// 80,81,82,85,86,95,96,99）
    let code: Int?

    /// 服务端给的中文描述（"小雨"、"雷阵雨"），比 `kind.title` 细一档，优先用它上屏
    let text: String?

    /// 当前气温（摄氏度）
    let temp: Double?

    /// 今日最高气温
    let tMax: Double?

    /// 今日最低气温
    let tMin: Double?

    /// 云量百分比 0…100。
    ///
    /// 注意它与 `kind.cloudiness`（0…1 的语义档）**不是一回事**：
    /// 这个字段可能缺省，而云量语义是画云所必需的，所以视觉层用 `kind.cloudiness`，
    /// 这个百分比只用来显示数字（"云量 85%"）。
    let cloud: Double?

    /// 白天 / 夜间。缺省时按"不知道"处理，**不要**用本地时间猜：
    /// 服务端算的是观测点，设备可能在别的时区。
    let isDay: Bool?

    /// 风速（m/s）
    let wind: Double?

    /// 风向的 16 方位中文（"东北"、"北西北"…）。
    ///
    /// 3.10.0 新增：**服务端已经把度数换算成中文**（见后端 weather.js 的 `windDirTextOf`），
    /// 这里只透传显示，不再在 Swift 侧换算一遍 —— 三端各换算一份迟早出现「App 说东北、
    /// 小组件说东东北」的分叉。需要角度（画箭头）时用 `windDirectionDegrees` 反查。
    let windDirText: String?

    /// 今日日出：ISO **本地时刻串**（如 `"2026-11-01T06:58"`，无时区后缀）。
    /// 上游请求钉了 `timezone=Asia/Shanghai`，解析必须用 `Formatters.weatherLocalTime`
    ///（把时区钉成 UTC+8）—— 用系统默认策略会把钟面值当成 GMT，日落漂 8 小时。
    let sunrise: String?

    /// 今日日落：同上
    let sunset: String?

    /// 上游观测时间（服务端给 ISO 字符串）。与"我们何时拉取"是两件事，
    /// 卡片要显示"几分钟前"应当用它，而不是 `Date()`。
    let updatedAt: Date?

    // MARK: - 3.19.0 新增（和风为主源后带回来的字段）

    /// 体感温度（摄氏度）。和风给的，与气温的区别是算进了湿度与风。
    /// 缺省 = 不知道，不要拿 `temp` 顶替 —— 「28 度但体感 34」正是用户最需要看到的那句话。
    let feelsLike: Double?

    /// 相对湿度（0…100，整数百分比）
    let humidity: Double?

    /// 海平面气压（hPa）
    let pressure: Double?

    /// 能见度（**米**）。
    ///
    /// 服务端做了一次单位换算：和风 v7 给的是公里，这里统一成米，
    /// 与 `SkyHaze.level(visibilityMeters:)` 的口径一致。
    ///
    /// 它的存在让 `VisibilityProbe`（直连 Open-Meteo 的那一发）变成了兜底 ——
    /// 天气接口自己带了，就不用再多打一次第三方。
    let visibilityMeters: Double?

    /// 过去一小时降水量（毫米）
    let precip: Double?

    /// 紫外线指数（0…15）
    let uvIndex: Int?

    /// 空气质量（和风 `/v7/air/now`）
    let air: AirQuality?

    /// 生活指数（穿衣 / 洗车 / 运动…，最多 8 条）
    let indices: [WeatherIndex]?

    /// 最终是哪些源拼出来的（`qweather` / `qweather+open-meteo`…）。
    ///
    /// 3.20.0 起它**上屏**了：天光页卡片区底部那行「和风天气 + Open-Meteo · 14:20 更新」
    /// 就是它 —— 四个源在同一坐标上常年差 2~3℃，用户需要一个能自证出处的凭据。
    /// 翻译成人话在 `SkyRoomSourceFooter.sourceLabel(_:)`，那边遇到未知名字会原样显示，
    /// 所以这里新增源时不必同步改两处（但改了翻译表才能看到中文）。
    let provider: String?

    /// WMO 代码 → 8 组视觉类型。代码缺失或未知一律 nil（理由见 `WeatherKind.from(code:)`）
    var kind: WeatherKind? {
        return WeatherKind.from(code: code)
    }

    /// 16 方位表（与后端 weather.js 的 `COMPASS_16_CN` 逐字一致，索引 0 = 正北）。
    /// 为什么在 Swift 侧再留一份：后端只给中文不给度数，画风向箭头需要反查角度；
    /// 改任何一边都必须两边同步，否则文案对不上。
    static let compassNames: [String] = [
        "北", "北东北", "东北", "东东北",
        "东", "东东南", "东南", "南东南",
        "南", "南西南", "西南", "西西南",
        "西", "西西北", "西北", "北西北"
    ]

    /// 风向来向的角度（0 = 正北、顺时针，meteorological：风**从**这个方向来）。
    ///
    /// 由 `windDirText` 反查（后端换算时的取整不可逆，±11.25° 对"画个箭头"足够）。
    /// 需要表示"风吹向哪"时再加 180°。
    var windDirectionDegrees: Double? {
        guard let text = windDirText?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.isEmpty == false,
              let index = Self.compassNames.firstIndex(of: text) else { return nil }
        return Double(index) * 22.5
    }

    /// 今日日出的 `Date`。解析失败 / 字段缺省返回 nil —— 绝不拿 `Date()` 兜底
    ///（那会把"不知道日出几点"伪装成"现在"，是比缺字段更糟的错）。
    var sunriseDate: Date? {
        return Formatters.weatherLocalTime(sunrise)
    }

    /// 今日日落的 `Date`。同上
    var sunsetDate: Date? {
        return Formatters.weatherLocalTime(sunset)
    }

    /// 手写 `init(from:)` 后编译器不再自动合成 `CodingKeys`，必须显式声明。
    /// 服务端键名与属性名逐字一致（camelCase），故无需写 rawValue。
    private enum CodingKeys: String, CodingKey {
        case ok
        case code
        case text
        case temp
        case tMax
        case tMin
        case cloud
        case isDay
        case wind
        case windDirText
        case sunrise
        case sunset
        case updatedAt
        case feelsLike
        case humidity
        case pressure
        case visibilityMeters
        case precip
        case uvIndex
        case air
        case indices
        case provider
    }

    /// 逐个 `try?`：任何一个字段解不开都只是"这个字段没有"，不影响整份响应。
    /// 这是全工程对"空值不占位"接口的统一写法（见 `BriefResponse`），本文件照抄同一套。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `ok` 缺失按失败算：拿不准成功就不当成有天气，避免把脏数据上屏
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        code = try? container.decode(Int.self, forKey: .code)
        text = try? container.decode(String.self, forKey: .text)
        temp = try? container.decode(Double.self, forKey: .temp)
        tMax = try? container.decode(Double.self, forKey: .tMax)
        tMin = try? container.decode(Double.self, forKey: .tMin)
        cloud = try? container.decode(Double.self, forKey: .cloud)
        isDay = try? container.decode(Bool.self, forKey: .isDay)
        wind = try? container.decode(Double.self, forKey: .wind)
        windDirText = try? container.decode(String.self, forKey: .windDirText)
        sunrise = try? container.decode(String.self, forKey: .sunrise)
        sunset = try? container.decode(String.self, forKey: .sunset)
        updatedAt = try? container.decode(Date.self, forKey: .updatedAt)
        feelsLike = try? container.decode(Double.self, forKey: .feelsLike)
        humidity = try? container.decode(Double.self, forKey: .humidity)
        pressure = try? container.decode(Double.self, forKey: .pressure)
        visibilityMeters = try? container.decode(Double.self, forKey: .visibilityMeters)
        precip = try? container.decode(Double.self, forKey: .precip)
        uvIndex = try? container.decode(Int.self, forKey: .uvIndex)
        air = try? container.decode(AirQuality.self, forKey: .air)
        indices = try? container.decode([WeatherIndex].self, forKey: .indices)
        provider = try? container.decode(String.self, forKey: .provider)
    }
}
