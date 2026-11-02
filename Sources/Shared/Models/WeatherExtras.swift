import Foundation

/// 空气质量（`/api/app/weather` 的 `air` 字段，和风 `/v7/air/now`）。
///
/// 为什么挂在天气响应里而不是单独开接口：AQI 的官方更新频率是小时级，
/// 与天气的 30 分钟缓存同寿，单独开一个端点只会多一个 RTT、多一份缓存要维护。
struct AirQuality: Codable, Equatable, Sendable {

    /// 空气质量指数（0…500+）
    let aqi: Int

    /// 等级文字（"优""良""轻度污染"…）
    let category: String?

    /// 首要污染物（"PM2.5"…）。和风在没有污染时给 "NA"，服务端已过滤。
    let primary: String?

    /// PM2.5 浓度（μg/m³）
    let pm25: Double?

    /// AQI 的分档颜色键 —— **只给语义，不给颜色值**。
    ///
    /// View 层拿它去 `Theme.aqiColor(_:)` 取色，模型里不出现任何 `Color`：
    /// 颜色是设计系统的职责，模型只负责表达"这是第几档"。
    var level: Level {
        switch aqi {
        case ..<51: return .good
        case 51..<101: return .moderate
        case 101..<151: return .unhealthySensitive
        case 151..<201: return .unhealthy
        case 201..<301: return .veryUnhealthy
        default: return .hazardous
        }
    }

    enum Level: String, Sendable {
        case good, moderate, unhealthySensitive, unhealthy, veryUnhealthy, hazardous
    }
}

/// 生活指数（和风 `/v7/indices/1d`，如"穿衣指数：较冷，建议着厚外套"）。
struct WeatherIndex: Codable, Equatable, Sendable, Identifiable {

    let name: String
    let category: String?
    let text: String?

    /// 指数名在同一份响应里天然唯一，直接拿来当 id
    var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name
        case category
        case text
    }
}

/// 一条天气预警（和风 `/v7/warning/now`，经服务端精简）。
///
/// 字段全部是"显示用"的：`title` 直接上横幅，`text` 是防御指南，
/// `colorHex` 交给 `Theme.alertColor(_:)` 转色 —— **模型里不 import SwiftUI**，
/// 这样它能被 Widget target 直接复用（Widget 不编译 DesignSystem 的那部分）。
struct WeatherAlert: Decodable, Equatable, Sendable, Identifiable {

    /// 预警唯一 ID（和风给的是长串；缺省时服务端用「标题 + 发布时间」兜底）
    let id: String

    /// 标题，如「上海市气象台发布暴雨黄色预警」
    let title: String

    /// 类型名，如「暴雨」「大风」
    let typeName: String?

    /// 严重程度（minor / moderate / severe / extreme / unknown）
    let severity: String?

    /// 严重程度中文（轻微 / 中等 / 严重 / 特别严重 / 未知）
    let severityText: String?

    /// 颜色（`#RRGGBB`）。服务端已把和风的 severityColor 映射成色值。
    let colorHex: String?

    /// 详细描述（几百字，横幅上只取第一句）
    let text: String?

    /// 发布时间（ISO8601 带时区）
    let pubTime: String?

    /// 失效时间（ISO8601 带时区）。可能为空 —— 有些预警不给结束时间。
    let endTime: String?

    /// 是否属于需要"顶格对待"的级别（严重 / 特别严重）。
    /// 横幅用它决定要不要常驻 + 是否用更重的视觉。
    var isSevere: Bool {
        return severity == "severe" || severity == "extreme"
    }

    /// 横幅上的一句话：取 `text` 的第一句（按中文句号/分号切）。
    ///
    /// 为什么不用完整 `text`：一条预警正文常有 200～400 字，放进横幅会把整页撑开，
    /// 用户反而看不到下面的天气。完整内容留在详情里。
    var shortText: String {
        guard let text, !text.isEmpty else { return title }
        let separators: Set<Character> = ["。", "；", "！", "\n"]
        var buffer = ""
        for ch in text {
            if separators.contains(ch) { break }
            buffer.append(ch)
            if buffer.count >= 60 { break }
        }
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title : trimmed
    }

    /// 发布时间的 `Date`。解析失败给 nil（不拿 `Date()` 兜底 —— 那会把"不知道"伪装成"刚刚"）。
    var pubDate: Date? {
        return Self.isoDate(pubTime)
    }

    /// 共用一份 ISO8601 解析器。
    ///
    /// 和风的时间串带 `+08:00`，且**可能带**小数秒（不同接口不一致），
    /// 所以两个 formatter 都要试。`ISO8601DateFormatter` 本身不是线程安全的，
    /// 但这里只在主线程的 SwiftUI 视图里读，且创建成本低 —— 每次新建比加锁简单。
    static func isoDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: raw) { return d }
        plain.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: raw)
    }
}

/// `/api/app/alerts` 的响应包。
struct AlertsResponse: Decodable, Sendable {

    /// **语义关键**：只有 `true` 才能拿 `warnings` 当"确定的现状"。
    /// `false` 表示拿不到（没配 key / 上游挂了），此时 App 应保留上一次的横幅而不是清空。
    let ok: Bool

    /// 预警列表。`ok == true` 时缺失等价于空数组（= 确实没有预警）。
    let warnings: [WeatherAlert]?

    let updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case ok
        case warnings
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        warnings = try? c.decode([WeatherAlert].self, forKey: .warnings)
        updatedAt = try? c.decode(Date.self, forKey: .updatedAt)
    }
}

/// 分钟级降水（`/api/app/minutely`，和风 `/v7/minutely/5m`）。
struct MinutelyRain: Decodable, Equatable, Sendable {

    let ok: Bool

    /// 一句话结论，如「23 分钟后雨停」「未来两小时无降水」
    let summary: String?

    /// 逐 5 分钟降水点（最多 24 个，覆盖 2 小时）
    let points: [Point]?

    /// 峰值降水强度（mm / 5min）
    let peak: Double?

    /// 服务端算好的「到底下不下」。
    ///
    /// 为什么不让 App 自己按 `points` 判：服务端已经用同一套阈值校验过 `summary`
    /// 的自洽性（见后端 `mapMinutely`），这里再判一次就是两份阈值、两种结论。
    /// 缺省时（老版本后端）才回落到本地判据。
    let wet: Bool?

    /// 最后一个有降水的时刻（ISO8601）。用来回答"还要下多久"。
    let lastWetAt: String?

    struct Point: Decodable, Equatable, Sendable {
        /// 预报时刻（ISO8601）
        let t: String
        /// 该 5 分钟的累计降水量（毫米）
        let p: Double
        /// rain / snow
        let type: String?
    }

    /// 有没有在下（或即将下）。
    ///
    /// 优先用服务端的 `wet`（它和 `summary` 是同一个判据算出来的，两者不会互相矛盾）。
    /// 没有时按柱子自己判 —— **阈值必须和后端一致（0.05mm/5min）**：
    /// 后端用 0.05 判定「不下雨」并改写 summary 为「未来两小时无降水」，
    /// 而这里若用 0.01，就会出现「文字说无降水、柱状图却一片柱子」的自相矛盾。
    var isWet: Bool {
        if let wet { return wet }
        guard let points else { return false }
        return points.contains { $0.p >= 0.05 }
    }

    /// 柱状图归一化用的最大值（至少 0.5，避免全是毛毛雨时柱子被拉到满格）。
    var scaleMax: Double {
        let peak = points?.map(\.p).max() ?? 0
        return max(0.5, peak)
    }
}
