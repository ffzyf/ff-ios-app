import AppIntents
import Foundation
import SwiftUI

/// 「今日简报」——**日常**简报：天气 / 黄历宜忌 / 紫外线 / 风 / 日出日落 / 生日 / 星座。
///
/// 注意别和光遇搞混：这里的「简报」是生活简报，光遇版本走 `SkyVersionIntent`。
/// 两句文案的措辞刻意不同（"今天的简报还没生成" vs "版本信息暂时查不到"），
/// 就是为了让用户在 Siri 里一听就知道自己刚才问的是哪一份。
///
/// 数据源 `GET /api/app/brief`（`API.brief()`）：**只读快照**，绝不触发生成 ——
/// 语音问一句就顺手让服务端跑一次 daily-brief，是这份接口最不该被做的事。
struct TodayBriefIntent: AppIntent {

    /// 快捷指令 App 里显示的名字，同时也是 Siri 的意图名词，所以用「今日简报」这个用户说法
    static var title: LocalizedStringResource = "今日简报"
    static var description = IntentDescription("查询今天的日常简报：天气、黄历宜忌、日出日落")

    /// 纯查询：Siri 念完 + 出卡片就结束，不把用户从当前场景拽进 App。
    /// （iOS 26 SDK 起这个属性有 `supportedModes` 的替代写法，这里沿用 iOS 18 的形态。）
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let outcome = await load()
        // 只有一个 return 点：`dialog` 与 `snippet` 都来自同一个 `Outcome`，
        // 不存在"Siri 说的"和"卡片写的"来自两次不同判定的可能。
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialog)) {
            TodayBriefSnippet(model: outcome.snippet)
        }
    }

    // MARK: - 取数 + 文案

    private struct Outcome: Sendable {
        let dialog: String
        let snippet: TodayBriefSnippetModel
    }

    /// 所有失败都在这里翻译成人话。
    ///
    /// `perform()` 本身**不抛**：AppIntents 在 `perform()` 抛错时会把 `localizedDescription`
    /// 交给 Siri 念，而 `IntentAPIError` 的描述是英文技术词 —— 用户听到的会是
    /// "The operation couldn't be completed"。所以错误在这一层就消化干净。
    private func load() async -> Outcome {
        do {
            let response = try await IntentAPI.get(API.brief(), as: BriefResponse.self)
            // `ok == false` 与网络不通给同一句话：对用户来说都是"现在问不到"，区分没有意义
            guard response.ok else { return unreachable() }
            // `brief == nil` 与 `available == false` 同义（当天快照还没生成，HTTP 仍 200）
            guard let snapshot = response.brief, snapshot.available else {
                return notReady(dayText: dayText(of: response, snapshot: response.brief))
            }
            return ready(dayText: dayText(of: response, snapshot: snapshot), snapshot: snapshot)
        } catch is CancellationError {
            // 用户说完就划走了：这是用户的动作，不是站点故障。
            // `IntentAPI` 特意把取消与传输错误分开抛，就是为了不让这里说成「连不上」。
            return cancelled()
        } catch {
            return unreachable()
        }
    }

    /// 日期文案统一在这里算：服务端 `date` 是 `"2026-11-17"`（北京自然日，**不是**时间戳），
    /// 走 `BriefText.dateText`（内部用 `Formatters.versionDateText`，不转 `Date`）——
    /// 一转 `Date` 再格式化，跨时区用户就会看到 16 号。
    private func dayText(of response: BriefResponse, snapshot: BriefSnapshot?) -> String {
        let raw = BriefText.clean(snapshot?.date) ?? BriefText.clean(response.date)
        return BriefText.dateText(raw)
    }

    private func ready(dayText: String, snapshot: BriefSnapshot) -> Outcome {
        let lunar = lunarClause(snapshot.lunar)
        let yi = Array(BriefText.yiTags(snapshot).prefix(3))
        let ji = Array(BriefText.jiTags(snapshot).prefix(3))

        let uv = BriefText.clean(snapshot.uvText)
        let wind = BriefText.clean(snapshot.windText)
        let rain = firstParagraph(snapshot.rain)

        // ① 日期 + 农历。服务端 `date` 缺失时 `BriefText.dateText` 给的是「今天」，
        //    那时句子里不能再套一个「今天是」（"今天是今天"），所以分成四种组合拼。
        //    `lunar` 同理：可能已带"农历"两字，也可能只有"十月初八" ——
        //    判一次前缀，避免念成"农历农历十月初八"这种典型的拼串事故。
        let datePart = dayText == "今天" ? "" : dayText
        let dateSentence: String
        if datePart.isEmpty {
            dateSentence = lunar.map { "今天，\($0)。" } ?? "今天。"
        } else if let lunar = lunar {
            dateSentence = "今天是\(datePart)，\(lunar)。"
        } else {
            dateSentence = "今天是\(datePart)。"
        }

        // ② 天气：只拼服务端给的 `uvText` / `windText` 原文。
        //    简报响应里**没有温度字段**（温度只在 `/api/app/weather`），所以这里不编一个。
        var weatherParts: [String] = []
        if let uv = uv { weatherParts.append(uv) }
        if let wind = wind { weatherParts.append(wind) }
        let weatherSentence: String? = weatherParts.isEmpty
            ? nil
            : "天气" + weatherParts.joined(separator: "，") + "。"

        // ③ 降雨单起一句：它是唯一"会改变今天安排"的信息，塞在天气句中间会被 TTS 连读带过
        let rainSentence = rain.map { $0.hasSuffix("。") ? $0 : $0 + "。" }

        // ④ 宜忌各最多 3 条：再多就成了念黄历，不是"简报"
        let luckSentence = luckClause(yi: yi, ji: ji)

        // 80 字预算与降级顺序（丢降雨 → 丢天气 → 丢宜忌）见 `IntentCopy.fit`
        let dialog = IntentCopy.fit([
            [dateSentence, weatherSentence, rainSentence, luckSentence],
            [dateSentence, weatherSentence, luckSentence],
            [dateSentence, luckSentence],
            [dateSentence]
        ])

        // 卡片上的天气行比朗读多给降雨：屏幕没有 80 字限制，念白省掉的信息在这里补回来
        var cardWeather = weatherParts
        if let rain = rain { cardWeather.append(rain) }

        let snippet = TodayBriefSnippetModel(
            title: titleText(dayText: dayText),
            available: true,
            yi: yi,
            ji: ji,
            weatherParts: cardWeather,
            note: nil,
            cancelled: false
        )
        return Outcome(dialog: dialog, snippet: snippet)
    }

    private func notReady(dayText: String) -> Outcome {
        Outcome(
            dialog: "今天的简报还没生成，晚一点再问我。",
            snippet: TodayBriefSnippetModel(
                title: titleText(dayText: dayText),
                available: false,
                yi: [],
                ji: [],
                weatherParts: [],
                note: "今天还没有简报副本，晚一点再看。",
                cancelled: false
            )
        )
    }

    private func unreachable() -> Outcome {
        Outcome(
            dialog: "简报站暂时连不上，稍后再试。",
            snippet: TodayBriefSnippetModel(
                title: "今日简报",
                available: false,
                yi: [],
                ji: [],
                weatherParts: [],
                note: "暂时连不上简报站，稍后再试。",
                cancelled: false
            )
        )
    }

    private func cancelled() -> Outcome {
        Outcome(
            dialog: "好，不查了。",
            snippet: TodayBriefSnippetModel(
                title: "今日简报",
                available: false,
                yi: [],
                ji: [],
                weatherParts: [],
                note: nil,
                cancelled: true
            )
        )
    }

    // MARK: - 文案零件

    /// 卡片标题：`今日简报 · 11月17日`。
    /// 日期缺失时退回 `今日简报` —— 不写"· 今天"这种半截标题。
    private func titleText(dayText: String) -> String {
        guard dayText != "今天", !dayText.isEmpty else { return "今日简报" }
        return "今日简报 · " + dayText
    }

    /// `lunar` → 「农历十月初八」；空返回 nil（整句不提农历，不写"农历—"）
    private func lunarClause(_ raw: String?) -> String? {
        guard let lunar = BriefText.clean(raw) else { return nil }
        return lunar.hasPrefix("农历") ? lunar : "农历" + lunar
    }

    /// 「宜：会友、出行；忌：动土、开仓。」—— 只有一边有值时只说那一边
    private func luckClause(yi: [String], ji: [String]) -> String? {
        var parts: [String] = []
        if !yi.isEmpty { parts.append("宜：" + yi.joined(separator: "、")) }
        if !ji.isEmpty { parts.append("忌：" + ji.joined(separator: "、")) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "；") + "。"
    }

    /// `rain` 可能是一整段（"有阵雨，记得带伞。傍晚转多云……"），只取第一段。
    ///
    /// 为什么按句号切而不是按字数截：截字数会切在半句上（"记得带"），
    /// 那比不说还难听；按句号切至少每段是完整的话。
    private func firstParagraph(_ raw: String?) -> String? {
        guard let text = BriefText.clean(raw) else { return nil }
        let head = text.split(whereSeparator: { $0 == "\n" || $0 == "。" }).first.map { String($0) } ?? text
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - 卡片

/// 卡片数据。**纯值类型**：Siri 的 snippet 由系统在另一个进程里渲染，
/// 拿不到 App 的环境对象，所以这里不能引用任何 Store / `@Environment` / 设计系统视图。
struct TodayBriefSnippetModel: Sendable {
    /// 成品标题（`今日简报 · 11月17日`），视图层不再判空
    let title: String
    let available: Bool
    let yi: [String]
    let ji: [String]
    /// 天气行：UV / 风 / 降雨的服务端原文，按这个顺序
    let weatherParts: [String]
    /// `available == false` 时的一句话
    let note: String?
    /// 用户取消时为 true：走极简占位，不显示任何错误措辞
    let cancelled: Bool
}

/// 简报卡片：标题 + 宜 / 忌两行 + 天气行。只用系统 `Text` / `Label`，
/// 不引 `DesignSystem`（`Theme` 的颜色要靠 `ThemeScope` 环境值，snippet 里没有那层环境）。
struct TodayBriefSnippet: View {
    let model: TodayBriefSnippetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.cancelled {
                IntentCancelledSnippet()
            } else {
                Text(model.title)
                    .font(.headline)

                if model.available {
                    if !model.yi.isEmpty {
                        luckRow(label: "宜", text: model.yi.joined(separator: "、"))
                    }
                    if !model.ji.isEmpty {
                        luckRow(label: "忌", text: model.ji.joined(separator: "、"))
                    }
                    if !model.weatherParts.isEmpty {
                        Label(model.weatherParts.joined(separator: " · "), systemImage: "sun.max")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let note = model.note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    /// 「宜」「忌」两个标签各自一行；用固定宽度的 label 列让两行文字左边缘对齐
    private func luckRow(label: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
