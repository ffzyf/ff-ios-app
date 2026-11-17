import AppIntents
import Foundation
import SwiftUI

/// 「光遇版本」——国服 / 国际服当前版本与更新状态。
///
/// 数据源与今日简报是**同一个** `GET /api/app/brief`（`sky.apps[]` 那一节）：
/// 版本信息本来就跟着每日快照一起下发，为 Siri 单开一个接口只会多出一份"谁是权威"的判断。
///
/// 判定规则**只 switch 服务端给的 `status` / `hasUpdate` / `lastError`**，绝不比较版本号字符串：
/// `previous` 在推送成功后即丢失（见 `SkyAppVersion` 的类型注释），
/// 自己比版本号迟早会把「有新版本」说成「已是最新」。
struct SkyVersionIntent: AppIntent {

    static var title: LocalizedStringResource = "光遇版本"
    static var description = IntentDescription("查询光遇国服与国际服的版本号和更新状态")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let outcome = await load()
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialog)) {
            SkyVersionSnippet(model: outcome.snippet)
        }
    }

    // MARK: - 取数 + 文案

    private struct Outcome: Sendable {
        let dialog: String
        let snippet: SkyVersionSnippetModel
    }

    /// 失败一律收敛成"版本信息暂时查不到，稍后再试。"——
    /// 用户问的是版本号，不该听到 HTTP 状态码或英文错误。
    private func load() async -> Outcome {
        do {
            let response = try await IntentAPI.get(API.brief(), as: BriefResponse.self)
            // `apps` 为空是服务端确认过的第五态（KV 里读不到监控历史），
            // 与"整段 sky 缺失"同义：这一刻确实没有版本可念
            guard response.ok, let sky = response.sky, !sky.apps.isEmpty else {
                return missing()
            }
            return ready(apps: sky.apps)
        } catch is CancellationError {
            // 用户说完就划走了：这是用户的动作，不是站点故障。
            // `IntentAPI` 特意把取消与传输错误分开抛，就是为了不让这里说成「查不到」。
            return cancelled()
        } catch {
            return missing()
        }
    }

    private func ready(apps: [SkyAppVersion]) -> Outcome {
        var clauses: [String] = []
        var rows: [SkyVersionRowModel] = []

        for (index, app) in apps.enumerated() {
            let fullName = BriefText.clean(app.name) ?? BriefText.clean(app.region) ?? "光遇"
            let region = BriefText.clean(app.region) ?? fullName
            // 第一句念全名（"光遇国服"），后面只念地区（"国际服"）：
            // 连着说两遍「光遇」在中文口语里很别扭，这也是需求里两条例子的写法。
            // **所有分支统一用这个 `subject`**，不要再退回 `region`。
            let subject = index == 0 ? fullName : region
            let state = Self.state(of: app)

            switch state {
            case .failed:
                clauses.append("\(subject)版本暂时查不到")
            case .hasUpdate:
                clauses.append(updateClause(subject: subject, app: app))
            case .latest:
                clauses.append(latestClause(subject: subject, app: app))
            case .unchecked:
                clauses.append("\(subject)还没查到版本")
            }

            rows.append(
                SkyVersionRowModel(
                    // `app.id` 理论上各服唯一，缺失时全部为空串，所以拼上序号兜底，
                    // 避免 ForEach 里出现重复 id 导致只渲染一行
                    id: "\(index)-\(fullName)",
                    name: fullName,
                    version: app.displayVersion,
                    status: state.text
                )
            )
        }

        let dialog = clauses.joined(separator: "；") + "。"
        return Outcome(dialog: dialog, snippet: SkyVersionSnippetModel(rows: rows, note: nil, cancelled: false))
    }

    private func missing() -> Outcome {
        Outcome(
            dialog: "版本信息暂时查不到，稍后再试。",
            snippet: SkyVersionSnippetModel(rows: [], note: "暂时查不到版本信息，稍后再试。", cancelled: false)
        )
    }

    private func cancelled() -> Outcome {
        Outcome(
            dialog: "好，不查了。",
            snippet: SkyVersionSnippetModel(rows: [], note: nil, cancelled: true)
        )
    }

    // MARK: - 单服文案

    /// `releaseDate` → `"11月15日"`；形状不对返回 nil（整段不提日期）。
    ///
    /// 为什么要形状校验：`Formatters.versionDateText` 解析失败时**原样返回**，
    /// 所以服务端哪天把 `releaseDate` 换成 ISO 时间戳，Siri 就会念
    /// 「2026-11-15T00:00:00.000Z 发布」。这里只认
    /// 「1–2 位月 + 月 + 1–2 位日 + 日」（等价于 `^\d{1,2}月\d{1,2}日$`），
    /// 其它一律省略 —— 宁可少说一句，也不能把机器格式念给用户。
    private func chineseDate(_ raw: String?) -> String? {
        guard let text = BriefText.clean(raw) else { return nil }
        let formatted = Formatters.versionDateText(text)
        guard formatted.hasSuffix("日") else { return nil }
        let body = formatted.dropLast()                     // 去掉收尾的"日"
        let halves = body.split(separator: "月", omittingEmptySubsequences: false)
        guard halves.count == 2,
              let month = Int(halves[0]),
              let day = Int(halves[1]),
              (1...12).contains(month),
              (1...31).contains(day) else { return nil }
        return formatted
    }

    private func updateClause(subject: String, app: SkyAppVersion) -> String {
        // 三个字段服务端冗余下发，任一个有值就能念；`displayVersion` 会给"—"，
        // 而"—"念出来是"破折号"，所以这里自己挑，不借用它
        guard let version = BriefText.clean(app.version)
                ?? BriefText.clean(app.current)
                ?? BriefText.clean(app.latest) else {
            return "\(subject)有新版本，版本号还没查到"
        }
        if let releaseText = chineseDate(app.releaseDate) {
            return "\(subject)更新到 \(version)，\(releaseText)发布"
        }
        return "\(subject)更新到 \(version)"
    }

    private func latestClause(subject: String, app: SkyAppVersion) -> String {
        if let version = BriefText.clean(app.version), version != "—" {
            return "\(subject) \(version)，已是最新"
        }
        return "\(subject)已是最新"
    }

    /// `SkyState` + `hasUpdate` + `lastError` → 三态（外加"尚未检查"）。
    ///
    /// 判定顺序有意为之：**`lastError` 先于 `hasUpdate`** —— 服务端这次抓取失败时，
    /// 历史字段可能还留着上一次的 `hasUpdate: true`，照它说"更新到 x.y.z"就是在编。
    private static func state(of app: SkyAppVersion) -> VersionState {
        let error = (app.lastError ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !error.isEmpty || app.status == .fetchFailed { return .failed }
        if app.hasUpdate || app.status == .newVersion { return .hasUpdate }
        if app.status == .noChange { return .latest }
        // `.init` / `.unknown`：服务端从没成功检查过。既不是"最新"也不是"失败"，如实说"还没查到"
        return .unchecked
    }

    private enum VersionState {
        case latest
        case hasUpdate
        case failed
        case unchecked

        var text: String {
            switch self {
            case .latest: return "已是最新"
            case .hasUpdate: return "有新版本"
            case .failed: return "查询失败"
            case .unchecked: return "尚未检查"
            }
        }
    }
}

// MARK: - 卡片

struct SkyVersionRowModel: Identifiable, Sendable {
    let id: String
    let name: String
    let version: String
    let status: String
}

struct SkyVersionSnippetModel: Sendable {
    let rows: [SkyVersionRowModel]
    /// `rows` 为空时的一句话
    let note: String?
    /// 用户取消时为 true：走极简占位，不显示任何错误措辞
    let cancelled: Bool
}

/// 每个服一行：名称 + 版本号 + 状态。纯系统视图（理由同 `TodayBriefSnippet`）。
struct SkyVersionSnippet: View {
    let model: SkyVersionSnippetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.cancelled {
                IntentCancelledSnippet()
            } else {
                Text("光遇版本")
                    .font(.headline)

                if model.rows.isEmpty {
                    if let note = model.note {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(model.rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.name)
                                .font(.callout.weight(.medium))
                            Text(row.version)
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 6)
                            Text(row.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
