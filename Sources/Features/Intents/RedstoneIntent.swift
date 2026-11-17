import AppIntents
import Foundation
import SwiftUI

/// 「最近红石」——接下来三场（每个时刻算一场）红石的时间、地点与倍率。
///
/// 三条硬规则，每一条都对应一个曾经真实出过错的场景：
/// 1. **起点是"北京时间的此刻"**，用 `RedstoneClock` 的日历算，不用设备时区 ——
///    服务端给的 `date` / `times` 都是北京钟面值，混用设备时区会让跨时区用户的场次整体漂一天；
/// 2. `map == "待确认"` 的场次直接跳过 —— 引擎没数据时 `rate` 也是 nil，
///    念出去等于给用户编一个地点；
/// 3. **只念红石**：`type` 可能是"黑石"，而这句朗读说的就是「红石」，
///    把黑石算进来就是说错话（用户按语音跑过去只会扑空）。
struct RedstoneIntent: AppIntent {

    static var title: LocalizedStringResource = "最近红石"
    static var description = IntentDescription("查询接下来三场红石的日期、时间、地点和倍率")
    static var openAppWhenRun: Bool = false

    /// 取几场。`同一天有多个 times` 时每个时刻各算一场（需求原文），
    /// 所以这个数字是**场次**上限，不是天数上限 —— 一天的三个场次可能就把它占满。
    private static let limit = 3

    /// 补下个月那一发的预算。
    ///
    /// 为什么单独给 3 秒：两发是**串行**的，若都吃满 `IntentAPI.timeout`（8 秒），
    /// 最坏情况下用户要对着 Siri 等 16 秒 —— 那条链路在 5 秒时就已经像卡死了。
    /// 第二发只是"补一刀"，它慢就该立刻放弃、把本月已取到的结果先念出来。
    private static let fallbackTimeout: TimeInterval = 3

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let outcome = await load()
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialog)) {
            RedstoneSnippet(model: outcome.snippet)
        }
    }

    // MARK: - 取数

    private struct Session: Sendable {
        /// `"2026-11-19"`（北京自然日）
        let day: String
        /// `"10:08"`
        let time: String
        let map: String
        let rate: Double?
    }

    /// 同一天的多场次合并成一句/一行
    private struct DayGroup: Sendable {
        let day: String
        let times: [String]
        let map: String
        let rate: Double?
    }

    /// 一个月的取数结果：场次 + 服务端"还有没有下个月"的标记
    private struct MonthPage: Sendable {
        let sessions: [Session]
        let hasNextMonth: Bool
    }

    private struct Outcome: Sendable {
        let dialog: String
        let snippet: RedstoneSnippetModel
    }

    private func load() async -> Outcome {
        // 「此刻」只取一次，两个月的请求共用同一个基准：
        // 若每发各取一次 `Date()`，跨零点那一两秒会把同一个场次判成"未来"又判成"过去"。
        let now = Date()
        let today = RedstoneClock.dayKey(now)
        let month = RedstoneClock.monthKey(now)

        var page: MonthPage
        do {
            page = try await fetchSessions(month: month, today: today, now: now, timeout: IntentAPI.timeout)
        } catch is CancellationError {
            // 用户说完就划走了：这是用户的动作，不是站点故障（`IntentAPI` 特意把取消
            // 与传输错误分开抛，就是为了不让这里把两者混成「连不上」）
            return cancelled()
        } catch {
            // 第一发就失败：说"连不上"而不是"还没有排期"——后者是假话，会让用户以为这个月没活动
            return unreachable()
        }
        var sessions = page.sessions

        // 本月剩余不足三场（或本月已经过完）就补下个月。
        //
        // 三个刻意的取舍：
        // 1. 先看 `hasNextMonth`：服务端明说没有下个月就不发这一枪（纯浪费，还要多等最多 3 秒）；
        // 2. 第二发只给 `fallbackTimeout`（3 秒），理由见那个常量的注释；
        // 3. 失败一律 `try?` 吞掉 —— **连取消也一起吞**。这是有意的：
        //    走到这里说明本月已经有部分结果，卡片先给已取到的场次，比回一句"不查了"有用。
        if sessions.count < Self.limit, page.hasNextMonth {
            let nextMonth = RedstoneClock.month(adding: 1, to: month)
            if let more = try? await fetchSessions(month: nextMonth,
                                                   today: today,
                                                   now: now,
                                                   timeout: Self.fallbackTimeout) {
                sessions.append(contentsOf: more.sessions)
            }
        }

        let picked = Array(sessions.prefix(Self.limit))
        guard !picked.isEmpty else { return empty() }
        return ready(picked)
    }

    /// 拉一个月：摊平成按时间升序的场次 + 服务端"还有没有下个月"的标记。
    ///
    /// 把 `hasNextMonth` 一起带出来，是因为调用方要靠它决定"要不要补下个月"——
    /// 服务端明说没有时的那一枪是纯浪费（多花最多 `fallbackTimeout` 秒，结果一定是空数组）。
    private func fetchSessions(month: String,
                               today: String,
                               now: Date,
                               timeout: TimeInterval) async throws -> MonthPage {
        let response = try await IntentAPI.get(API.redstone(month: month),
                                               as: RedstoneResponse.self,
                                               timeout: timeout)
        guard response.ok else { throw IntentAPIError.business }

        var result: [Session] = []
        for item in response.items {
            // 占位数据：地点没确认，倍率也是 nil，念出来是纯粹的噪音
            guard item.map != "待确认" else { continue }
            guard item.isRedstone else { continue }
            // 便宜的预筛：不必把过去日期的每一个 `times` 都丢进日历里解析
            // （`date` 是定长零填充的 `"YYYY-MM-DD"`，字符串比较即日期比较）
            guard item.date >= today else { continue }
            for time in item.times {
                // 真正决定"算不算接下来"的是**绝对时刻**：晚上 23 点问 Siri，
                // 当天 10:08 / 17:08 已经过去了，只比日期会把它们当成「接下来三场」念出来。
                guard let start = RedstoneClock.date(day: item.date, time: time), start > now else {
                    continue
                }
                result.append(Session(day: item.date, time: time, map: item.map, rate: item.rate))
            }
        }

        // 同一天内按 `HH:mm` 升序（同样靠定长零填充的字符串比较）；
        // 服务端本来就给的是升序，这里排一次是为了跨月拼接后顺序仍然对
        result.sort { lhs, rhs in
            lhs.day == rhs.day ? lhs.time < rhs.time : lhs.day < rhs.day
        }
        return MonthPage(sessions: result, hasNextMonth: response.hasNextMonth)
    }

    // MARK: - 文案

    private func ready(_ sessions: [Session]) -> Outcome {
        let groups = dayGroups(from: sessions)

        // 同一批场次拼三档说法，从"信息最全"到"只说得出时间"：
        var withRate: [String] = []
        var withoutRate: [String] = []
        var firstTimeOnly: [String] = []
        var rows: [RedstoneRowModel] = []

        for group in groups {
            let dayText = Formatters.dayTitle(group.day)                 // "11月19日"
            let weekday = Formatters.weekdayLabel(dayKey: group.day)     // "周四"（北京时区算）
            let map = spokenMap(group.map)

            var clause = "\(dayText)\(weekday) \(group.times.joined(separator: "、"))，\(map)"
            withoutRate.append(clause)
            if let rate = group.rate {
                clause += "，倍率" + rateText(rate)
            }
            withRate.append(clause)

            if let first = group.times.first {
                firstTimeOnly.append("\(dayText)\(weekday) \(first)")
            }

            // 卡片每行：`11月19日 周四 · 10:08 / 17:08 / 23:08 · 霞谷圆梦村`
            let head = weekday.isEmpty ? dayText : dayText + " " + weekday
            rows.append(
                RedstoneRowModel(
                    id: group.day,
                    line: head + " · " + group.times.joined(separator: " / ") + " · " + map
                )
            )
        }

        // 标题按**实际场次数**说：本月快过完时可能只有 1–2 场，
        // 还硬说"最近三场"就是数错了。
        // 单场用中文数字「一场」——"接下来1场红石"读起来像机器播报。
        let spokenTitle: String
        if sessions.count >= Self.limit {
            spokenTitle = "最近三场红石"
        } else if sessions.count == 1 {
            spokenTitle = "接下来一场红石"
        } else {
            spokenTitle = "接下来\(sessions.count)场红石"
        }

        // 三天三场连念约 150 字，必须降级：先丢倍率，再退到"日期 + 第一个时刻"。
        // 顺序即优先级，长度判定交给 `IntentCopy.fit`（与今日简报共用同一套预算）。
        let dialog = IntentCopy.fit([
            [spokenTitle + "：" + withRate.joined(separator: "；") + "。"],
            [spokenTitle + "：" + withoutRate.joined(separator: "；") + "。"],
            [spokenTitle + "：" + firstTimeOnly.joined(separator: "；") + "。"]
        ])

        return Outcome(
            dialog: dialog,
            snippet: RedstoneSnippetModel(title: spokenTitle, rows: rows, note: nil, cancelled: false)
        )
    }

    private func empty() -> Outcome {
        Outcome(
            dialog: "最近还没有红石排期。",
            snippet: RedstoneSnippetModel(title: "最近红石", rows: [], note: "最近还没有红石排期。", cancelled: false)
        )
    }

    private func unreachable() -> Outcome {
        Outcome(
            dialog: "红石站暂时连不上，稍后再试。",
            snippet: RedstoneSnippetModel(title: "最近红石", rows: [], note: "暂时连不上红石站，稍后再试。", cancelled: false)
        )
    }

    private func cancelled() -> Outcome {
        Outcome(
            dialog: "好，不查了。",
            snippet: RedstoneSnippetModel(title: "最近红石", rows: [], note: nil, cancelled: true)
        )
    }

    /// 场次 → 按天分组的连续数组（`sessions` 已按时间升序，所以"相邻同一天"就是同一组）
    private func dayGroups(from sessions: [Session]) -> [DayGroup] {
        var groups: [DayGroup] = []
        for session in sessions {
            if let last = groups.last, last.day == session.day {
                groups[groups.count - 1] = DayGroup(
                    day: last.day,
                    times: last.times + [session.time],
                    map: last.map,
                    // 同一天只有一个 `rate`；万一服务端给得参差，取第一个非空的（后面不再覆盖）
                    rate: last.rate ?? session.rate
                )
                continue
            }
            groups.append(
                DayGroup(day: session.day, times: [session.time], map: session.map, rate: session.rate)
            )
        }
        return groups
    }

    /// `map` 原文是 `"霞谷·圆梦村"`：卡片保留间隔点当分隔符太密，念白更不能留 ——
    /// TTS 会在「·」处停顿，听起来像两个地点。
    private func spokenMap(_ raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "·", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 清完变空（服务端给了个纯符号）时原样退回：宁可念一个怪符号，也不编一个地点名
        return trimmed.isEmpty ? raw : trimmed
    }

    /// 倍率 → 念白文本。
    ///
    /// 四个用例（`RedstoneDay.rate` 的文档取值是 2 / 2.5 / 3.5）：
    /// · `2.0`   → `"2"`     —— `Int(exactly: 2.0)` 有值
    /// · `2.5`   → `"2.5"`   —— `Int(exactly: 2.5)` 为 nil，落到 `%.1f`
    /// · `3.5`   → `"3.5"`   —— 同上（**绝不能**先 `rounded()`：那会得到 4）
    /// · `+∞ / NaN` → `"—"`  —— 外部 JSON 的脏数据，不让它进格式化
    ///
    /// 两个坑都在这一行里：
    /// 1. 不能用 `String(rate)`：`String(2.0)` 是 "2.0"，TTS 会念成"二点零倍"；
    /// 2. 不能先 `rate.rounded()` 再取整：`rounded()` 是四舍五入到最近的整数，
    ///    `Int(exactly:)` 于是**恒成立**，2.5 会被念成"倍率3"、3.5 变成"倍率4"。
    private func rateText(_ rate: Double) -> String {
        guard rate.isFinite else { return "—" }
        if let integer = Int(exactly: rate) {
            return String(integer)
        }
        return String(format: "%.1f", rate)
    }
}

// MARK: - 卡片

struct RedstoneRowModel: Identifiable, Sendable {
    let id: String
    /// 整行成品：`11月19日 周四 · 10:08 / 17:08 / 23:08 · 霞谷圆梦村`
    let line: String
}

struct RedstoneSnippetModel: Sendable {
    /// 卡片标题（`最近三场红石` / `接下来2场红石`），与朗读标题同源
    let title: String
    let rows: [RedstoneRowModel]
    /// `rows` 为空时的一句话
    let note: String?
    /// 用户取消时为 true：走极简占位，不显示任何错误措辞
    let cancelled: Bool
}

/// 最近几场：每行一天。纯系统视图（理由同 `TodayBriefSnippet`）。
struct RedstoneSnippet: View {
    let model: RedstoneSnippetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.cancelled {
                IntentCancelledSnippet()
            } else {
                Text(model.title)
                    .font(.headline)

                if model.rows.isEmpty {
                    if let note = model.note {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(model.rows) { row in
                        Text(row.line)
                            .font(.callout)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
