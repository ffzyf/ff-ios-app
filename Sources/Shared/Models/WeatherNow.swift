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

    /// 上游观测时间（服务端给 ISO 字符串）。与"我们何时拉取"是两件事，
    /// 卡片要显示"几分钟前"应当用它，而不是 `Date()`。
    let updatedAt: Date?

    /// WMO 代码 → 8 组视觉类型。代码缺失或未知一律 nil（理由见 `WeatherKind.from(code:)`）
    var kind: WeatherKind? {
        return WeatherKind.from(code: code)
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
        case updatedAt
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
        updatedAt = try? container.decode(Date.self, forKey: .updatedAt)
    }
}
