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
///
/// ## 3.11.0：分成「默认两行」和「展开才出」
///
/// 用户原话："今日简报里面的内容太多了！app 就简洁一些，把重要的挑出来"。
/// 所以文案层先按**信息密度**分成两组（而不是让卡片自己 `prefix(3)` 硬切）：
/// - `compactLines`：农历行 + **一条**天气行（优先级见 `weatherLines`）；
/// - `detailLines`：其余天气字段 + 生日 + 彭祖百忌。
/// 卡片默认只读前者，后者进「展开全文」—— 分组规则只有这一处，卡片不重复实现。
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

    // MARK: - 默认态（最多两行）

    /// 折叠状态下露出的 **2 行**：农历/冲煞 → 一条最值得看的天气。
    ///
    /// 为什么是 2 行而不是 3 行：页头一眼读到的第三组信息是宜忌 chips（占一整行），
    /// 加上这两行正好是「3 条高信息量行」—— 再多就得滚动，那就不是"简洁"了。
    static func compactLines(_ snapshot: BriefSnapshot?) -> [BriefLine] {
        guard let snapshot = snapshot else { return [] }
        var lines: [BriefLine] = []
        if let lunar = lunarLine(snapshot) {
            lines.append(lunar)
        }
        if let weather = weatherLines(snapshot).first {
            lines.append(weather)
        }
        return lines
    }

    // MARK: - 展开态

    /// 展开后才出现的行：**其余**天气字段 + 生日倒计时 + 彭祖百忌。
    ///
    /// 与 `compactLines` 严格互补（同一条字段不会上下各出现一次）：
    /// 默认态已经上屏的那一条由 `weatherLines` 的顺序决定，这里按 id 排掉它。
    static func detailLines(_ snapshot: BriefSnapshot?) -> [BriefLine] {
        guard let snapshot = snapshot else { return [] }
        // 只算一次 `weatherLines`：它内部有三次 `clean` + 一次拼接，展开态每次重绘都会走
        let weather = weatherLines(snapshot)
        let primary = weather.first?.id
        var lines = weather.filter { $0.id != primary }

        if let birthday = clean(snapshot.birthday) {
            lines.append(BriefLine(id: "birthday", icon: "gift", text: birthday))
        }
        if let pengzu = clean(snapshot.pengzu) {
            lines.append(BriefLine(id: "pengzu", icon: "text.book.closed", text: "彭祖百忌：" + pengzu))
        }
        return lines
    }

    // MARK: - 字段 → 行

    /// 农历 + 冲煞（服务端两个字段合成一行：分开写会占掉默认态一半的额度）
    private static func lunarLine(_ snapshot: BriefSnapshot) -> BriefLine? {
        var parts: [String] = []
        if let lunar = clean(snapshot.lunar) {
            parts.append(lunar)
        }
        if let chong = clean(snapshot.chong) {
            parts.append("冲煞：" + chong)
        }
        guard !parts.isEmpty else { return nil }
        return BriefLine(id: "lunar", icon: "moon.stars", text: parts.joined(separator: " · "))
    }

    /// 天气相关的四条，**按信息量排序**：降雨 → 紫外线 → 风力 → 日出日落。
    ///
    /// 排序理由（决定默认态那唯一一条天气显示什么）：
    /// 1. 降雨是唯一会改变当天行为的（要不要带伞），永远排第一；
    /// 2. 紫外线次之（要不要防晒），且它只在有值时才有；
    /// 3. 风力排第三（体感相关，但不改变计划）；
    /// 4. 日出日落最后 —— 天空页（`SkyRoomView`）底部已经常驻这一对了，
    ///    简报里再抢第一条位置等于重复。
    private static func weatherLines(_ snapshot: BriefSnapshot) -> [BriefLine] {
        var lines: [BriefLine] = []

        if let rain = clean(snapshot.rain) {
            lines.append(BriefLine(id: "rain", icon: "cloud.rain", text: rain))
        }
        if let uv = clean(snapshot.uvText) {
            lines.append(BriefLine(id: "uv", icon: "sun.max", text: uv))
        }
        if let wind = clean(snapshot.windText) {
            lines.append(BriefLine(id: "wind", icon: "wind", text: wind))
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
        return lines
    }

    // MARK: - 宜忌 / 星座 / 正文

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
