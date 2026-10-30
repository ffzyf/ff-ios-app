import Foundation
import SwiftUI
import WidgetKit

// MARK: - JSON 解码器（Widget 自己一份）

/// Widget 进程用的解码器。
///
/// 为什么不复用 `APIJSON.decoder`：那个在 Services 层的网络客户端里，
/// **不属于 Shared，也不该属于**（Widget 不需要整个网络客户端）。
/// 这里只复制「ISO8601 带毫秒」这一条策略 —— 它与服务端 `new Date().toISOString()` 对齐，
/// 少这条会导致简报的 `savedAt` / `pushedAt` 全部解不出来。
enum WidgetJSON {

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()

        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        withFractional.timeZone = TimeZone(secondsFromGMT: 0)

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        plain.timeZone = TimeZone(secondsFromGMT: 0)

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = withFractional.date(from: raw) { return date }
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "无法解析的时间字符串: \(raw)"
                )
            )
        }
        return decoder
    }()

    /// 快照编解码用的编码器/解码器：**不含**自定义日期策略。
    /// 快照是本进程写、本进程读，编解码必须严格对称（用自定义策略反而会读不回自己的 Date）。
    static let cacheEncoder = JSONEncoder()
    static let cacheDecoder = JSONDecoder()
}

// MARK: - 本地快照

/// Widget 的本地快照（`UserDefaults`，**不用 App Group**）。
///
/// 设计文档 §1.2.3 的决策：`/api/app/*` 已豁免为匿名可读，Widget 自己请求即可，
/// 不需要主 App 与扩展共享容器。所以快照只服务一个目的 ——
/// **本次刷新失败时，还能画出上一次成功的内容**（PRD §5.3：失败不显示错误，保留旧 entry）。
enum WidgetSnapshot {

    /// 红石快照
    static let redstoneKey = "widget.redstone.snapshot.v1"
    /// 简报快照
    static let briefKey = "widget.brief.snapshot.v1"

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? WidgetJSON.cacheEncoder.encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? WidgetJSON.cacheDecoder.decode(type, from: data)
    }
}

/// 红石快照的内容（只存需要的，不存整份响应：模型改了也不会让快照整体失效）
struct RedstoneCachePayload: Codable {
    let days: [RedstoneDay]
    /// 服务端 `updated`（毫秒）
    let updated: Int
    let savedAt: Date
}

/// 简报快照的内容
struct BriefCachePayload: Codable {
    /// `"2026-10-30"`
    let date: String
    /// 已切好的前 2 段正文
    let paragraphs: [String]
    let pushedToday: Bool
    let pushedAt: Date?
    let savedAt: Date
}

// MARK: - 请求

/// Widget 侧的极简请求层（零依赖、零状态）。
enum WidgetFetch {

    /// 单个 GET + 解码。失败一律返回 nil（Widget 不做错误展示，失败就退回快照）
    static func get<T: Decodable>(_ type: T.Type, url: URL) async -> T? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try WidgetJSON.decoder.decode(type, from: data)
        } catch {
            return nil
        }
    }

    /// 需要拉哪几个月。
    ///
    /// 只拉「今天所在月」；如果今天已经接近月末（最后 3 天），连下个月一起拉 ——
    /// 否则 10 月 31 日 23:08 那一场结束后，小组件会以为"今天没场次了"，
    /// 而实际上明天 07:08 就有一场（PRD 验收第 8 条：结束后 1 分钟内要变成下一场）。
    static func monthKeys(around now: Date) -> [String] {
        let current = RedstoneClock.monthKey(now)
        let day = RedstoneClock.calendar.component(.day, from: now)
        let total = RedstoneClock.dayCount(in: current)
        guard day >= total - 2 else { return [current] }
        return [current, RedstoneClock.month(adding: 1, to: current)]
    }

    /// 拉红石排期（成功则写快照；失败则读快照）
    static func redstone(now: Date = Date()) async -> RedstoneCachePayload? {
        let keys = monthKeys(around: now)
        var days: [RedstoneDay] = []
        var updated: Int = 0
        var succeeded = false

        for key in keys {
            guard let url = API.redstone(month: key) else { continue }
            guard let response = await get(RedstoneResponse.self, url: url), response.ok else { continue }
            days.append(contentsOf: response.items)
            updated = max(updated, response.updated)
            succeeded = true
        }

        if succeeded {
            let payload = RedstoneCachePayload(days: dedupe(days), updated: updated, savedAt: now)
            WidgetSnapshot.save(payload, key: WidgetSnapshot.redstoneKey)
            return payload
        }

        // 失败：用上次成功的快照（PRD §5.3：容许旧 1 场，不显示错误）
        return WidgetSnapshot.load(RedstoneCachePayload.self, key: WidgetSnapshot.redstoneKey)
    }

    /// 拉简报（成功则写快照；失败则读快照）
    static func brief(now: Date = Date()) async -> BriefCachePayload? {
        guard let url = Endpoint.url(base: Endpoint.briefBase, path: Endpoint.briefPath) else {
            return WidgetSnapshot.load(BriefCachePayload.self, key: WidgetSnapshot.briefKey)
        }

        guard let response = await get(BriefResponse.self, url: url), response.ok else {
            return WidgetSnapshot.load(BriefCachePayload.self, key: WidgetSnapshot.briefKey)
        }

        let brief = response.brief
        let payload = BriefCachePayload(
            date: response.date,
            paragraphs: paragraphs(from: brief?.body),
            // `pushedToday` 是服务端明确给出的，缺省按「未推送」处理（PRD 的两种文案都基于它）
            pushedToday: brief?.pushedToday ?? false,
            pushedAt: brief?.pushedAt,
            savedAt: now
        )
        WidgetSnapshot.save(payload, key: WidgetSnapshot.briefKey)
        return payload
    }

    /// 同一天可能同时出现在两个月的数据里（月末跨月请求），按 `date` 去重
    static func dedupe(_ days: [RedstoneDay]) -> [RedstoneDay] {
        var seen = Set<String>()
        var result: [RedstoneDay] = []
        for day in days where !seen.contains(day.date) {
            seen.insert(day.date)
            result.append(day)
        }
        return result.sorted { $0.date < $1.date }
    }

    /// 从简报正文里切出前 2 段。
    ///
    /// 服务端的 `body` 是**一整段纯文本**，段落之间空行分隔，中间还夹着 `——————————` 这种分隔线。
    /// 这里做三件事：按空行切段 → 丢掉纯分隔线 → 取前 2 段。
    /// 取不到（`available == false` 的早上）就返回空数组，小组件显示「今天还没有简报」。
    static func paragraphs(from body: String?) -> [String] {
        guard let body = body else { return [] }
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n")
        var result: [String] = []
        for chunk in normalized.components(separatedBy: "\n\n") {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // 纯分隔线段（整段只有破折号/横线/空格）不算正文
            let isSeparator = trimmed.allSatisfy { character in
                character == "—" || character == "-" || character == "·" || character.isWhitespace
            }
            guard !isSeparator else { continue }
            result.append(trimmed)
            if result.count >= 2 { break }
        }
        return result
    }
}

// MARK: - 红石 entry

/// 红石小组件的一条 Timeline entry。
///
/// 为什么把 `phase` / `todayOccurrences` 在**生成 entry 时**就算好、而不是在 View 里算：
/// entry 的 `date` 就是"这一条被渲染的时刻"，而 View 里拿不到时间机器 ——
/// 直接把结论带进去，View 只负责画，不会出现「View 用 `Date()` 现算」导致
/// 预渲染与真实显示不一致的经典小组件 bug。
struct RedstoneEntry: TimelineEntry {
    let date: Date
    /// 有没有排期数据（false = 显示「暂无排期」，绝不显示 00:00 或假地图）
    let hasData: Bool
    /// 数据最后生成时间（过期提示用；nil 时不提示）
    let updatedAt: Date?
    let phase: RockPhase
    /// 今日全部场次（含已过），中号右半用它画列表
    let todayOccurrences: [Occurrence]
    /// 今日场次数
    let todayCount: Int
    /// 今日是否有待核对场次
    let needsCheck: Bool

    /// 下一场 / 进行中的那一场（没有就 nil）
    var focus: Occurrence? { phase.occurrence }
}

extension RedstoneEntry {

    /// 用一份排期数据 + 指定时刻造一条 entry
    static func make(date: Date, days: [RedstoneDay], updated: Int) -> RedstoneEntry {
        let occurrences = RedstoneTimeline.occurrences(in: days)
        let todayKey = RedstoneClock.dayKey(date)
        let today = occurrences.filter { $0.date == todayKey }
        let phase = RedstoneTimeline.phase(in: days, now: date)
        let updatedAt: Date? = updated > 0
            ? Date(timeIntervalSince1970: TimeInterval(updated) / 1000)
            : nil

        return RedstoneEntry(
            date: date,
            hasData: !occurrences.isEmpty,
            updatedAt: updatedAt,
            phase: phase,
            todayOccurrences: today,
            todayCount: today.count,
            needsCheck: today.contains { $0.needsCheck }
        )
    }

    /// 空态 entry（没数据 / 首次安装）
    static func empty(date: Date) -> RedstoneEntry {
        return RedstoneEntry(
            date: date,
            hasData: false,
            updatedAt: nil,
            phase: .notGenerated,
            todayOccurrences: [],
            todayCount: 0,
            needsCheck: false
        )
    }
}

// MARK: - 简报 entry

struct BriefEntry: TimelineEntry {
    let date: Date
    let hasData: Bool
    /// `"10月30日"`
    let dateText: String
    /// `"周四"`
    let weekdayText: String
    /// 前 2 段
    let paragraphs: [String]
    let pushedToday: Bool
    let pushedAt: Date?

    /// 页脚文案：「今日已推送 07:02」/「今日未推送」。没有简报数据时整条页脚不画
    var footerText: String? {
        guard hasData else { return nil }
        if pushedToday {
            guard let pushedAt = pushedAt else { return "今日已推送" }
            return "今日已推送 " + Formatters.timeHHmm(pushedAt)
        }
        return "今日未推送"
    }

    static func make(date: Date, payload: BriefCachePayload?) -> BriefEntry {
        guard let payload = payload else {
            return BriefEntry(
                date: date,
                hasData: false,
                dateText: Formatters.dayTitle(RedstoneClock.dayKey(date)),
                weekdayText: Formatters.weekdayCN(date),
                paragraphs: [],
                pushedToday: false,
                pushedAt: nil
            )
        }
        return BriefEntry(
            date: date,
            hasData: !payload.paragraphs.isEmpty,
            dateText: Formatters.dayTitle(payload.date),
            weekdayText: Formatters.weekdayLabel(dayKey: payload.date),
            paragraphs: payload.paragraphs,
            pushedToday: payload.pushedToday,
            pushedAt: payload.pushedAt
        )
    }
}

// MARK: - 红石 Provider

/// 红石 / 简共用的刷新预算（PRD §5.3：iOS 每天 40–70 次，必须省着用）。
///
/// 生成规则：**每小时 1 条**（24 条）+ **每场落地 1 条 + 每场结束 1 条**（3 场 = 6 条）≈ 30 条/天。
/// 倒计时本身不靠刷新 —— View 里用 `Text(timerInterval:)` 让系统自绘走时，秒级在动但零刷新成本。
struct RedstoneProvider: TimelineProvider {

    /// 预览占位（Xcode 里点开 Widget 时先看到的东西）
    func placeholder(in context: Context) -> RedstoneEntry {
        return RedstoneEntry.empty(date: Date())
    }

    /// 组件库里的快照：不发请求，直接用空态，避免用户在库里翻组件时打一堆请求
    func getSnapshot(in context: Context, completion: @escaping (RedstoneEntry) -> Void) {
        completion(RedstoneEntry.empty(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RedstoneEntry>) -> Void) {
        Task {
            let now = Date()
            let payload = await WidgetFetch.redstone(now: now)
            let days = payload?.days ?? []
            let updated = payload?.updated ?? 0

            guard !days.isEmpty else {
                // 彻底没有数据：一条空态 entry，1 小时后再试（不刷屏、也不假装有排期）
                let entry = RedstoneEntry.empty(date: now)
                completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(3600))))
                return
            }

            let entries = RedstoneProvider.entries(days: days, updated: updated, now: now)
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    /// 生成 entry 序列（导出成 static 便于自检与将来写单测）
    ///
    /// 时间点集合 = 「现在」+ 未来 24 小时里的每个整点 + 未来 26 小时里每场落地/结束时刻。
    /// 去重后升序，最多 34 条（24 + 6 + 边界余量），在系统预算内。
    static func entries(days: [RedstoneDay], updated: Int, now: Date) -> [RedstoneEntry] {
        var stamps: Set<Date> = [now]

        // ① 每小时 1 条
        var hourCursor = now.addingTimeInterval(3600)
        let hourLimit = now.addingTimeInterval(24 * 3600)
        while hourCursor < hourLimit {
            stamps.insert(hourCursor)
            hourCursor = hourCursor.addingTimeInterval(3600)
        }

        // ② 每场「落地」「结束」各 1 条
        let occurrences = RedstoneTimeline.occurrences(in: days)
        let occurrenceLimit = now.addingTimeInterval(26 * 3600)
        for occurrence in occurrences {
            if occurrence.startAt > now, occurrence.startAt < occurrenceLimit {
                stamps.insert(occurrence.startAt)
            }
            if occurrence.endAt > now, occurrence.endAt < occurrenceLimit {
                stamps.insert(occurrence.endAt)
            }
        }

        let ordered = stamps.sorted()
        return ordered.map { stamp in
            RedstoneEntry.make(date: stamp, days: days, updated: updated)
        }
    }
}

// MARK: - 简报 Provider

/// 简报小组件（中号）。
///
/// 刷新策略与红石不同：简报一天只变一次（早上生成、推送后 `pushedToday` 变一次），
/// 所以「每小时 1 条」纯属浪费预算 —— 这里改成 **下次整点 + 每 2 小时**，一天 12 条左右。
struct BriefProvider: TimelineProvider {

    func placeholder(in context: Context) -> BriefEntry {
        return BriefEntry.make(date: Date(), payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BriefEntry) -> Void) {
        completion(BriefEntry.make(date: Date(), payload: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BriefEntry>) -> Void) {
        Task {
            let now = Date()
            let payload = await WidgetFetch.brief(now: now)

            // 每 2 小时一条，覆盖未来 12 小时（够到下一次 App 打开 / 系统刷新）
            var entries: [BriefEntry] = []
            for step in 0..<6 {
                let stamp = now.addingTimeInterval(TimeInterval(step) * 2 * 3600)
                entries.append(BriefEntry.make(date: stamp, payload: payload))
            }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }
}
