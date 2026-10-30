import Foundation

/// 简报的一行展示数据（图标 + 一句文案）。
///
/// `id` 用字段名而不是下标：服务端字段集合稳定，用语义 id 更利于 diff，
/// 也不会因为某字段为空导致整列 id 位移、动画错位。
struct BriefLine: Identifiable {
    let id: String
    let icon: String
    let text: String
}

/// 把简报的**扁平字段**翻译成展示文案的纯函数集合。
///
/// 放在单独文件里的两个理由：
/// 1. 这些规则（哪些字段拼一行、空值如何整行消失）是本次验收的核心，集中在一处才好逐条核对；
/// 2. 它们不依赖 SwiftUI，纯输入输出，将来要做单元测试可以直接调。
///
/// 铁律：任何函数都不返回「--」「null」这类占位；没有内容就返回 nil / 空数组。
enum BriefText {

    /// 空白一律视为「没有这个字段」：服务端清洗过一遍，这里再兜一层
    static func clean(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 日期：服务端给 `2026-10-30`（北京今日）。复用 `Formatters.versionDateText` 的 date-only 解析，
    /// 不转 `Date` —— 时区会把 30 号漂成 29 号。
    static func dateText(_ raw: String?) -> String {
        guard let raw = clean(raw) else { return "今天" }
        let text = Formatters.versionDateText(raw)
        return text == "—" ? "今天" : text
    }

    /// 折叠状态下的前 5 行：农历/冲煞 → 紫外线 → 日出日落 → 风力 → 降雨
    static func baselineLines(_ snapshot: BriefSnapshot?) -> [BriefLine] {
        guard let snapshot = snapshot else { return [] }
        var lines: [BriefLine] = []

        var lunarParts: [String] = []
        if let lunar = clean(snapshot.lunar) {
            lunarParts.append(lunar)
        }
        if let chong = clean(snapshot.chong) {
            lunarParts.append("冲煞：" + chong)
        }
        if !lunarParts.isEmpty {
            lines.append(BriefLine(id: "lunar", icon: "moon.stars", text: lunarParts.joined(separator: " · ")))
        }

        if let uv = clean(snapshot.uvText) {
            lines.append(BriefLine(id: "uv", icon: "sun.max", text: uv))
        }

        var sunParts: [String] = []
        if let sunrise = clean(snapshot.sunrise) {
            sunParts.append("日出 " + sunrise)
        }
        if let sunset = clean(snapshot.sunset) {
            sunParts.append("日落 " + sunset)
        }
        if !sunParts.isEmpty {
            lines.append(BriefLine(id: "sun", icon: "sunset", text: sunParts.joined(separator: " · ")))
        }

        if let wind = clean(snapshot.windText) {
            lines.append(BriefLine(id: "wind", icon: "wind", text: wind))
        }
        if let rain = clean(snapshot.rain) {
            lines.append(BriefLine(id: "rain", icon: "cloud.rain", text: rain))
        }
        return lines
    }

    /// 展开后才出现的两行：生日倒计时、彭祖百忌
    static func extraLines(_ snapshot: BriefSnapshot?) -> [BriefLine] {
        var lines: [BriefLine] = []
        if let birthday = clean(snapshot?.birthday) {
            lines.append(BriefLine(id: "birthday", icon: "gift", text: birthday))
        }
        if let pengzu = clean(snapshot?.pengzu) {
            lines.append(BriefLine(id: "pengzu", icon: "text.book.closed", text: "彭祖百忌：" + pengzu))
        }
        return lines
    }

    static func yiTags(_ snapshot: BriefSnapshot?) -> [String] {
        return (snapshot?.yi ?? []).compactMap { clean($0) }
    }

    static func jiTags(_ snapshot: BriefSnapshot?) -> [String] {
        return (snapshot?.ji ?? []).compactMap { clean($0) }
    }

    /// 「白羊座 · 综合 78 分」
    static func horoscopeTitle(_ horoscope: Horoscope?) -> String? {
        guard let horoscope = horoscope else { return nil }
        var parts: [String] = []
        if let sign = clean(horoscope.sign) {
            parts.append(sign)
        }
        if let score = horoscope.score {
            parts.append("综合 \(score) 分")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 「幸运色 青柠绿 · 幸运数字 7 · 贵人 双子」
    static func horoscopeLuckyText(_ horoscope: Horoscope?) -> String? {
        guard let horoscope = horoscope else { return nil }
        var parts: [String] = []
        if let color = clean(horoscope.luckyColor) {
            parts.append("幸运色 " + color)
        }
        if let number = horoscope.luckyNumber {
            parts.append("幸运数字 \(number)")
        }
        if let noble = clean(horoscope.noble) {
            parts.append("贵人 " + noble)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func horoscopeOverview(_ horoscope: Horoscope?) -> String? {
        return clean(horoscope?.overview)
    }

    static func bodyText(_ snapshot: BriefSnapshot?) -> String? {
        return clean(snapshot?.body)
    }
}
