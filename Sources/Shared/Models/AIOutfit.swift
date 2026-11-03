import Foundation

/// `POST /api/ai/outfit` 返回的一条穿搭建议。
///
/// 服务端按「坐标 + 日期」缓存 6 小时（`ai:outfit:<lat>,<lon>:<yyyyMMdd>`），
/// 所以同一天同一地点几乎总是免费命中 —— 客户端也按 6 小时落一份盘，
/// 让冷启动能先上屏（理由与 `WeatherStore` 的 `diskMaxAge` 一致：
/// 每次打开都盯着"AI 还没说话"比看到半小时前的建议更糟）。
struct AIOutfitAdvice: Codable, Equatable, Sendable {

    /// 建议正文（聊天口吻的一两段中文），直接上屏
    let text: String

    /// 出这段文字的模型 id
    let model: String

    /// 服务端生成时刻
    let generatedAt: Date

    /// 是不是"旧的"：读盘 / 请求失败时仍显示的那份，界面据此加一句「稍早的建议」。
    ///
    /// 不是服务端字段（服务端只回 text/model/generatedAt），由 `AIOutfitStore` 自己维护 ——
    /// 所以解码时缺省为 false。
    var stale: Bool

    init(text: String, model: String, generatedAt: Date, stale: Bool = false) {
        self.text = text
        self.model = model
        self.generatedAt = generatedAt
        self.stale = stale
    }

    /// 手写 `init(from:)` 后编译器不再自动合成 `CodingKeys`，必须显式声明
    enum CodingKeys: String, CodingKey {
        case text
        case model
        case generatedAt
        case stale
    }
}

extension AIOutfitAdvice {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 全 `try?`：字段缺一个只是"这个字段没有"，不该让整段建议消失
        text = (try? container.decode(String.self, forKey: .text)) ?? ""
        model = (try? container.decode(String.self, forKey: .model)) ?? ""
        // 缺 generatedAt 只能按"刚拿到"算：它的唯一用途是显示"多久前更新的"，
        // 缺了就退化成"不显示那句话"，比让整段建议消失好
        generatedAt = (try? container.decode(Date.self, forKey: .generatedAt)) ?? Date()
        stale = (try? container.decode(Bool.self, forKey: .stale)) ?? false
    }
}

// MARK: - 请求体

/// `POST /api/ai/outfit` 的请求体。
///
/// 服务端拿这些数算"今天该穿什么"：气温区间 + 体感 + 天气文字 + 降水时段。
/// 缺一个不致命（`tMin` / `tMax` / `feelsLike` / `text` 都是可选，编码时 nil 不占位），
/// 但**坐标必填**：建议必须绑到一个地方，服务端没有"默认城市"这一说。
struct AIOutfitRequest: Encodable, Sendable {

    /// 纬度（已按两位小数取整，见 `AIOutfitStore`）
    let lat: Double

    /// 经度（同上）
    let lon: Double

    let tMin: Double?
    let tMax: Double?
    let feelsLike: Double?

    /// 天气文字（"小雨"、"晴间多云"），服务端原话直接带过去
    let text: String?

    /// 分钟级降水时段。契约里只写了 `[{from,to,level}]`，`from` / `to` 的形状
    /// （ISO 时刻？"HH:mm"？）**没有定死**，所以这里用不透明字符串透传，不做类型假设 ——
    /// 猜成 `Date` 会在某天上游改成 `"HH:mm"` 时整条请求 400。
    let precip: [AIOutfitPrecipSlot]?

    init(lat: Double,
         lon: Double,
         tMin: Double? = nil,
         tMax: Double? = nil,
         feelsLike: Double? = nil,
         text: String? = nil,
         precip: [AIOutfitPrecipSlot]? = nil) {
        self.lat = lat
        self.lon = lon
        self.tMin = tMin
        self.tMax = tMax
        self.feelsLike = feelsLike
        self.text = text
        self.precip = precip
    }
}

/// 一个降水时段（原样透传，理由见 `AIOutfitRequest.precip`）
struct AIOutfitPrecipSlot: Encodable, Sendable, Equatable {

    let from: String
    let to: String

    /// 强度档位（服务端自己定义的名字，客户端不解释）
    let level: String

    init(from: String, to: String, level: String) {
        self.from = from
        self.to = to
        self.level = level
    }
}

// MARK: - 响应

/// 服务端的错误信封（`{code, message}`）。
///
/// 为什么不复用 `APIErrorEnvelope`：那个在 `Services/` 里，而本文件在 `Shared/`
/// （会被编进小组件 target），**不许**跨目录引用。就两个字段，抄一份比拆依赖便宜。
struct AIOutfitErrorPayload: Codable, Sendable, Equatable {

    let code: String?
    let message: String?

    init(code: String? = nil, message: String? = nil) {
        self.code = code
        self.message = message
    }

    /// 可直接上屏的原话（空白 → nil）
    var cleanMessage: String? {
        guard let message = message else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// `POST /api/ai/outfit` 的完整响应：`{ok, advice:{text,model,generatedAt}, cached}`
struct AIOutfitResponse: Codable, Sendable {

    let ok: Bool
    let advice: AIOutfitAdvice?

    /// 这次是不是命中服务端缓存（`true` 说明没花上游的钱）
    let cached: Bool?

    /// 业务失败时的原因（HTTP 200 也可能 `ok == false`，比如上游挂了）
    let error: AIOutfitErrorPayload?

    init(ok: Bool = false,
         advice: AIOutfitAdvice? = nil,
         cached: Bool? = nil,
         error: AIOutfitErrorPayload? = nil) {
        self.ok = ok
        self.advice = advice
        self.cached = cached
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case advice
        case cached
        case error
    }
}

extension AIOutfitResponse {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        advice = try? container.decodeIfPresent(AIOutfitAdvice.self, forKey: .advice)
        cached = try? container.decodeIfPresent(Bool.self, forKey: .cached)
        error = try? container.decodeIfPresent(AIOutfitErrorPayload.self, forKey: .error)
    }
}
