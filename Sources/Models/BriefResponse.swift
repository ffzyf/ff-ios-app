import Foundation

/// `GET /api/app/brief`（简报站）的响应 —— 只读快照，**绝不触发生成**。
///
/// 真实字段以已部署实现为准（`appsite/functions/_lib/app-brief-core.js`）：
/// 扁平字段才是权威契约，`brief.sections[]` 只是同一批数据的便捷视图（由扁平字段拼出来的）。
///
/// 空值字段服务端**直接缺省**（不给空字符串 / null 占位），所以模型里全部是可选类型，
/// 渲染层「空字段整行不渲染」，不猜、不显示 undefined。
struct BriefResponse: Decodable {
    let ok: Bool
    let apiVersion: Int?
    let serverTime: Date?
    let generatedAt: Date?
    /// 北京今日（YYYY-MM-DD），服务端按 UTC+8 算好，不跟随设备时区
    let date: String
    let sky: SkyStatus?
    let brief: BriefSnapshot?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        apiVersion = try? container.decode(Int.self, forKey: .apiVersion)
        serverTime = try? container.decode(Date.self, forKey: .serverTime)
        generatedAt = try? container.decode(Date.self, forKey: .generatedAt)
        date = (try? container.decode(String.self, forKey: .date)) ?? ""
        sky = try? container.decode(SkyStatus.self, forKey: .sky)
        brief = try? container.decode(BriefSnapshot.self, forKey: .brief)
    }
}

/// 今日简报快照。`available == false` 时只有 `date` / `yi` / `ji` / `pushedToday` 四个字段，
/// 属正常业务状态（HTTP 仍 200），不是错误。
struct BriefSnapshot: Decodable {
    let date: String
    let available: Bool
    let lunar: String?
    let chong: String?
    let pengzu: String?
    let yi: [String]
    let ji: [String]
    let uv: Double?
    let uvText: String?
    let sunrise: String?
    let sunset: String?
    let windText: String?
    let rain: String?
    let birthday: String?
    let body: String?
    let horoscope: Horoscope?
    /// 便捷视图（由扁平字段拼好），渲染可直接用；但扁平字段才是权威
    let sections: [BriefSection]
    let savedAt: Date?
    let pushedToday: Bool
    let pushedAt: Date?
    let weatherError: String?
    let horoscopeError: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? container.decode(String.self, forKey: .date)) ?? ""
        available = (try? container.decode(Bool.self, forKey: .available)) ?? false
        lunar = try? container.decode(String.self, forKey: .lunar)
        chong = try? container.decode(String.self, forKey: .chong)
        pengzu = try? container.decode(String.self, forKey: .pengzu)
        yi = (try? container.decode([String].self, forKey: .yi)) ?? []
        ji = (try? container.decode([String].self, forKey: .ji)) ?? []
        uv = try? container.decode(Double.self, forKey: .uv)
        uvText = try? container.decode(String.self, forKey: .uvText)
        sunrise = try? container.decode(String.self, forKey: .sunrise)
        sunset = try? container.decode(String.self, forKey: .sunset)
        windText = try? container.decode(String.self, forKey: .windText)
        rain = try? container.decode(String.self, forKey: .rain)
        birthday = try? container.decode(String.self, forKey: .birthday)
        body = try? container.decode(String.self, forKey: .body)
        horoscope = try? container.decode(Horoscope.self, forKey: .horoscope)
        sections = (try? container.decode([BriefSection].self, forKey: .sections)) ?? []
        savedAt = try? container.decode(Date.self, forKey: .savedAt)
        pushedToday = (try? container.decode(Bool.self, forKey: .pushedToday)) ?? false
        pushedAt = try? container.decode(Date.self, forKey: .pushedAt)
        weatherError = try? container.decode(String.self, forKey: .weatherError)
        horoscopeError = try? container.decode(String.self, forKey: .horoscopeError)
    }
}

/// 简报展示行：`{ key, label, text }`（`lunar` / `uv` / `sun` / `wind` / `rain` / `yi` / `ji` /
/// `horoscope` / `body` / `birthday`，服务端已按 PRD 顺序排好且滤掉空值）
struct BriefSection: Decodable, Identifiable {
    let key: String
    let label: String
    let text: String

    var id: String { key }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decode(String.self, forKey: .key)) ?? ""
        label = (try? container.decode(String.self, forKey: .label)) ?? ""
        text = (try? container.decode(String.self, forKey: .text)) ?? ""
    }
}

/// 星座段（只保留非空子字段；整体无非空字段时服务端给 null）
struct Horoscope: Decodable {
    let sign: String?
    let signEn: String?
    let score: Int?
    let luckyColor: String?
    let luckyNumber: Int?
    let noble: String?
    let overview: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sign = try? container.decode(String.self, forKey: .sign)
        signEn = try? container.decode(String.self, forKey: .signEn)
        score = try? container.decode(Int.self, forKey: .score)
        luckyColor = try? container.decode(String.self, forKey: .luckyColor)
        luckyNumber = try? container.decode(Int.self, forKey: .luckyNumber)
        noble = try? container.decode(String.self, forKey: .noble)
        overview = try? container.decode(String.self, forKey: .overview)
    }
}
