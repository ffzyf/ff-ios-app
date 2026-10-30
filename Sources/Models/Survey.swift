import Foundation

// MARK: - 题型

/// 后端 `type` 的 7 个取值，逐字对齐 `survey/public/renderer.js` 的 `TYPE_NAMES`
/// 与 `app.js` 的 `Q_TYPES`（radio / checkbox / dropdown / rating / scale / date / text）。
///
/// 为什么"当 String 存、computed 转枚举"（设计文档 §7.1）：后端新增一个题型时
/// （例如排序题），App 不能因为解不出枚举就整页解码失败 —— `questionType` 返回 nil，
/// 单题降级成「这一题请在网页端填写」，其余题目照常作答与提交。
enum SurveyQuestionType: String, CaseIterable, Sendable {
    case radio
    case checkbox
    case dropdown
    case rating
    case scale
    case date
    case text

    /// 上屏名称（与网页端 `TYPE_NAMES` 同口径，短一档：这里用在题目右侧的小标签上）
    var label: String {
        switch self {
        case .radio: return "单选"
        case .checkbox: return "多选"
        case .dropdown: return "下拉"
        case .rating: return "评分"
        case .scale: return "量表"
        case .date: return "日期"
        case .text: return "文本"
        }
    }

    /// 是否「选项类」题型（结果页画条形图，填答页画选项行）
    var isChoice: Bool {
        switch self {
        case .radio, .checkbox, .dropdown: return true
        case .rating, .scale, .date, .text: return false
        }
    }
}

// MARK: - 列表

/// 顶部三个计数（后端 `countsOf`）。
///
/// `total` 是「全部问卷」而不是筛选后的条数 —— 服务端刻意这么算，
/// 否则用户按状态筛选时顶部数字会忽大忽小，看起来像数据丢了。
struct SurveyCounts: Codable, Sendable, Equatable {
    var total: Int
    var published: Int
    var responses: Int
}

/// 列表项（后端 `projectListItem`）。
///
/// 刻意没有 `structure` / `description` / `settings` / `cover`：列表用不上，
/// 而 `cover` 是 base64 图片（单个可能几百 KB），裁掉之后列表响应才压得进 2KB。
struct SurveySummary: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var status: String
    var questionCount: Int
    var responseCount: Int
    /// `isoOf()` 在时间戳为 0 时返回 null —— 所以这三个时间**必须可空**，
    /// 解码成非可选 `Date` 会在老数据上直接抛错（整页失败，只为一条时间）。
    var createdAt: Date?
    var updatedAt: Date?
    /// nil = 不限时
    var endAt: Date?
    /// 服务端拼好的填答页地址（App 只负责复制与生成二维码，不做拼接）
    var fillUrl: String

    /// 状态文案（PRD P08：草稿 / 收集中 / 已截止）。
    ///
    /// 为什么 `published` 还要看 `endAt`：服务端的 `status` 只在"手动截止"时才变 `closed`，
    /// 到点自动结束的问卷 status 仍是 `published`。徽标必须跟着时间走，
    /// 否则会出现「显示收集中、点进去却填不了」这种自相矛盾的界面。
    func statusLabel(now: Date = Date()) -> String {
        switch status {
        case "draft":
            return "草稿"
        case "closed":
            return "已截止"
        case "published":
            if let endAt = endAt, endAt < now { return "已截止" }
            return "收集中"
        default:
            // 未知状态不倒推成"草稿"（会误导），按中性文案显示原值
            return status
        }
    }

    /// 是否正在收集（决定徽标是青柠实心还是中性灰）
    func isCollecting(now: Date = Date()) -> Bool {
        guard status == "published" else { return false }
        if let endAt = endAt, endAt < now { return false }
        return true
    }
}

/// `GET /api/app/surveys` 的完整响应。
struct SurveyListResponse: Codable, Sendable, Equatable {
    var ok: Bool
    /// 契约版本（服务端 `API_VERSION`）。当前恒为 1，先收着，将来破坏性改动时用得上
    var apiVersion: Int?
    var counts: SurveyCounts
    var surveys: [SurveySummary]
}

// MARK: - 详情

/// 单问卷详情（后端 `projectDetail`）。
///
/// **不含 `structure`**：详情页不需要题面（填答走公开接口），
/// 下发题面还会泄露测评的算分标记（`optionScores` / `optionTypes`）。
struct SurveyDetail: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var description: String
    var status: String
    var questionCount: Int
    var responseCount: Int
    var createdAt: Date?
    var updatedAt: Date?
    var endAt: Date?
    var fillUrl: String
    /// "normal" | "test"（测评型问卷）
    var kind: String
    /// 服务端算的"还能不能填"（status == published 且未截止）。App 不自己推状态机
    var canFill: Bool
    /// 服务端算的"有没有答卷可看"（responseCount > 0）
    var canSeeResult: Bool

    var isTest: Bool { kind == "test" }

    /// 状态文案：与列表同一套口径（时间参与判断）
    func statusLabel(now: Date = Date()) -> String {
        switch status {
        case "draft": return "草稿"
        case "closed": return "已截止"
        case "published":
            if let endAt = endAt, endAt < now { return "已截止" }
            return "收集中"
        default: return status
        }
    }

    func isCollecting(now: Date = Date()) -> Bool {
        guard status == "published" else { return false }
        if let endAt = endAt, endAt < now { return false }
        return true
    }
}

/// `GET /api/app/surveys/{id}`
struct SurveyDetailResponse: Codable, Sendable, Equatable {
    var ok: Bool
    var apiVersion: Int?
    var survey: SurveyDetail
}

// MARK: - 结果

/// 结果页头部用的极简问卷信息（只有四个字段）
struct SurveyBrief: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var status: String
    var kind: String

    var isTest: Bool { kind == "test" }
}

/// 答卷时间范围（PRD P11「共 N 份 + 时间范围」）
struct ResultWindow: Codable, Sendable, Equatable {
    var total: Int
    var firstAt: Date?
    var lastAt: Date?
}

/// 一个「选项/刻度 → 人数」的切片。
///
/// 单独建模而不是直接用 `[String: Int]`：**字典没有顺序**，而图表与列表都需要稳定顺序，
/// 排序规则只写一次（在 `QuestionStat` 的 computed 里），视图层不许再排。
struct SurveyCountSlice: Identifiable, Sendable, Equatable {
    /// 原始 key（选项文字 / 刻度值 / 月份），同时作为 ForEach 的稳定 id
    let id: String
    /// 上屏文字（`__other__` 已翻成「其他」、月份已翻成「2026年10月」）
    let label: String
    let count: Int
}

/// 单题统计（直接透传服务端 `_lib/stats.js` 的 `computeStats`，字段逐个登记）。
///
/// 所有"题型专属"字段都是可选的：`counts` 只在选项类题型出现、`buckets` 只在评分/量表出现、
/// `texts` 只在文本题出现。Swift 合成的解码对 `Optional` 用 `decodeIfPresent`，
/// 所以字段缺席不会抛错（设计文档 §7.1 的"可选字段"约定）。
struct QuestionStat: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var type: String
    var required: Bool?
    var answered: Int
    var skipped: Int
    /// 选项类：选项文字 → 人数（`__other__` 是"其他"汇总）
    var counts: [String: Int]?
    /// 评分 / 量表：刻度值（字符串化的数字）→ 人数
    var buckets: [String: Int]?
    var average: Double?
    var min: Int?
    var max: Int?
    /// 文本题的回答（服务端最多下发 50 条，见 D-4）
    var texts: [String]?
    /// 「其他」选项的自定义文字
    var otherTexts: [String]?
    /// 文本答案是否被服务端截断过（截断时页脚要说明，否则用户会以为只有 50 份）
    var textTruncated: Bool?

    var questionType: SurveyQuestionType? { SurveyQuestionType(rawValue: type) }
    var isRequired: Bool { required ?? false }

    /// 选项类切片：按人数降序，「其他」恒排最后。
    ///
    /// 为什么不是原始选项顺序：服务端的 JSON 对象虽然保留了选项声明顺序，
    /// 但解码进 `[String: Int]` 就丢了。想还原顺序必须让服务端下发数组 —— V3 契约没有，
    /// 于是选一个"稳定且对读者有用"的顺序（人多在前）。
    var choiceSlices: [SurveyCountSlice] {
        guard let counts = counts else { return [] }
        let items = counts.map { key, value in
            SurveyCountSlice(
                id: key,
                label: key == "__other__" ? "其他" : key,
                count: value
            )
        }
        return items.sorted { lhs, rhs in
            if lhs.id == "__other__" { return false }
            if rhs.id == "__other__" { return true }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.label < rhs.label
        }
    }

    /// 评分 / 量表切片：按刻度数值升序（0,1,2…），不能按字典顺序
    var bucketSlices: [SurveyCountSlice] {
        guard let buckets = buckets else { return [] }
        let items = buckets.map { key, value in
            SurveyCountSlice(id: key, label: key, count: value)
        }
        return items.sorted { lhs, rhs in
            let left = Int(lhs.id) ?? 0
            let right = Int(rhs.id) ?? 0
            if left != right { return left < right }
            return lhs.id < rhs.id
        }
    }

    /// 日期题切片：按月聚合（服务端 `String(v).slice(0, 7)`），按月份升序
    var dateSlices: [SurveyCountSlice] {
        guard let counts = counts else { return [] }
        let items = counts.map { key, value in
            SurveyCountSlice(id: key, label: QuestionStat.monthLabel(key), count: value)
        }
        return items.sorted { $0.id < $1.id }
    }

    /// `"2026-10"` → `"2026年10月"`；解析失败原样返回（绝不显示"未知"）
    static func monthLabel(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count >= 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return key
        }
        return "\(year)年\(month)月"
    }

    /// 作答率（分母是"回答了这一题的人数"，不是总答卷数）
    var answeredRate: Double {
        let base = answered + skipped
        guard base > 0 else { return 0 }
        return Double(answered) / Double(base)
    }
}

/// 整份统计
struct SurveyStats: Codable, Sendable, Equatable {
    var total: Int
    var perQuestion: [QuestionStat]
}

/// 类型分布的一个桶（如 INFP 12 人）
struct TypeBucket: Codable, Sendable, Identifiable, Equatable {
    var label: String
    var count: Int

    /// `label` 在同一个响应里唯一（服务端按 key 聚合），可以安全当 id
    var id: String { label }
}

/// 测试型问卷的类型分布。
///
/// 服务端在「维度型（MBTI）」时**返回 null**，语义是"这个问卷类型 V3 不做"，
/// 不是"没人填" —— 所以 App 侧 null 时整块不渲染（不显示"暂无数据"）。
struct TypeDistribution: Codable, Sendable, Equatable {
    /// "type"（类型累加）| "sum"（总分区间）
    var kind: String
    var buckets: [TypeBucket]

    var kindLabel: String {
        switch kind {
        case "sum": return "得分区间分布"
        case "type": return "类型分布"
        default: return "分布"
        }
    }
}

/// 一个答卷值。
///
/// 后端 `answers` 是 `qid → 任意 JSON`：字符串（单选/下拉/文本/日期）、
/// 字符串数组（多选）、数字（评分/量表），"其他"是 `__other__:自定义文字`。
/// 用一个枚举收口而不是 `Any` —— `Any` 不能 `Codable`，而结果响应要进快照缓存。
enum SurveyAnswerValue: Codable, Hashable, Sendable {
    case text(String)
    case number(Double)
    case flag(Bool)
    case list([SurveyAnswerValue])
    case empty

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .empty
            return
        }
        // 顺序有意义：Bool 必须先试（JSON 的 true/false 解 Double 会抛），
        // 然后 Double（`1` 与 `1.5` 都能吃），再 String，最后数组。
        if let value = try? container.decode(Bool.self) {
            self = .flag(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .text(value)
            return
        }
        if let value = try? container.decode([SurveyAnswerValue].self) {
            self = .list(value)
            return
        }
        // 解不出来（对象 / 嵌套结构）：当空值，绝不让一条怪数据毁掉整页
        self = .empty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .empty:
            try container.encodeNil()
        case .text(let value):
            try container.encode(value)
        case .number(let value):
            // 整数值不要写成 `3.0`：服务端 `Number(val)` 两种都能吃，
            // 但明细里显示 `3.0 分` 比 `3 分` 难看
            if value == value.rounded(), abs(value) < 1e15 {
                try container.encode(Int(value))
            } else {
                try container.encode(value)
            }
        case .flag(let value):
            try container.encode(value)
        case .list(let values):
            try container.encode(values)
        }
    }

    /// 是否算「已作答」。注意 0 分与「否」都是合法答案，不能用"是否有值"糊过去
    var isFilled: Bool {
        switch self {
        case .empty:
            return false
        case .text(let value):
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .number, .flag:
            return true
        case .list(let values):
            return values.contains { $0.isFilled }
        }
    }

    /// 上屏文字（明细 / 结果页文本列表用）
    var displayText: String {
        switch self {
        case .empty:
            return ""
        case .text(let value):
            return SurveyAnswerValue.prettyOther(value)
        case .number(let value):
            if value == value.rounded() {
                return String(Int(value))
            }
            return String(format: "%.2f", value)
        case .flag(let value):
            return value ? "是" : "否"
        case .list(let values):
            let texts = values.map { $0.displayText }.filter { !$0.isEmpty }
            return texts.joined(separator: "、")
        }
    }

    /// `__other__` / `__other__:文字` 是网页端 `renderer.js` 的"其他"约定，
    /// 直接上屏会显示成乱码一样的占位符，所以统一翻成「其他」/「其他：文字」
    static func prettyOther(_ raw: String) -> String {
        if raw == "__other__" { return "其他" }
        let prefix = "__other__:"
        if raw.hasPrefix(prefix) {
            let body = String(raw.dropFirst(prefix.count))
            return body.isEmpty ? "其他" : "其他：" + body
        }
        return raw
    }
}

/// 一份答卷（后端 `projectResponses`；刻意不含 ip / ua，App 没用途）
struct SurveyResponseRow: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var createdAt: Date?
    /// 省 市（国外是城市 国家），可为 ""
    var location: String?
    var answers: [String: SurveyAnswerValue]

    var locationText: String {
        let trimmed = (location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    /// 按题目顺序取出「题 → 答案」列表（字典顺序不可靠，必须由外部给定题序）
    func orderedAnswers(_ order: [String]) -> [SurveyAnswerItem] {
        var items: [SurveyAnswerItem] = []
        for qid in order {
            guard let value = answers[qid] else { continue }
            let text = value.displayText
            if text.isEmpty { continue }
            items.append(SurveyAnswerItem(id: qid, text: text))
        }
        return items
    }
}

/// 明细里的一行「题 → 答案」（`id` 是题目 id，仅用于 ForEach）
struct SurveyAnswerItem: Identifiable, Sendable, Equatable {
    let id: String
    let text: String
}

/// `GET /api/app/surveys/{id}/result` 的完整响应。
///
/// 统计与明细在**同一个响应**里：分两个请求会出现"顶部写共 48 份、明细里 49 条"
/// （同一秒有人提交），一次快照才能自洽。
struct SurveyResultResponse: Codable, Sendable, Equatable {
    var ok: Bool
    var survey: SurveyBrief
    var window: ResultWindow
    var stats: SurveyStats
    /// 测试型问卷的类型分布；nil = 这个问卷类型 V3 不做（维度报告），整块不渲染
    var typeDistribution: TypeDistribution?
    var responses: [SurveyResponseRow]
}

// MARK: - 公开填答

/// 条件显示：`{ qid, value }`（网页端 `showIf`，选定某选项后这一题才出现）
struct SurveyShowIf: Codable, Sendable, Equatable {
    var qid: String
    var value: String

    init(qid: String, value: String) {
        self.qid = qid
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case qid
        case value
    }

    /// `value` 在网页编辑器里可能被存成数字（选项值是 "5"），这里一并吃下来。
    /// 解不出就当空串：条件空串永远匹配不上，题目只是不显示，不会崩。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.qid = (try? container.decode(String.self, forKey: .qid)) ?? ""
        if let text = try? container.decode(String.self, forKey: .value) {
            self.value = text
        } else if let number = try? container.decode(Int.self, forKey: .value) {
            self.value = String(number)
        } else if let flag = try? container.decode(Bool.self, forKey: .value) {
            self.value = String(flag)
        } else {
            self.value = ""
        }
    }
}

/// 题面（公开填答接口原样下发的 `structure[i]`）。
///
/// 除 `id/title/type` 外**全部可选**：网页端不同题型只写自己那几个字段
/// （评分没有 `options`、文本没有 `min/max`），缺字段是常态而不是异常。
struct SurveyQuestion: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var type: String
    var required: Bool?
    var options: [String]?
    /// 「其他」选项（答案写成 `__other__:文字`）
    var allowOther: Bool?
    /// 评分题星数（网页端 clamp 在 3...10）
    var maxRating: Int?
    /// 量表的下限 / 上限 / 步长
    var min: Int?
    var max: Int?
    var step: Int?
    /// 量表两端的锚点文案
    var minLabel: String?
    var maxLabel: String?
    /// 文本题的占位提示
    var placeholder: String?
    var showIf: SurveyShowIf?

    var questionType: SurveyQuestionType? { SurveyQuestionType(rawValue: type) }
    var isRequired: Bool { required ?? false }
    var optionList: [String] { options ?? [] }
    var allowsOther: Bool { allowOther ?? false }

    /// 评分题星数：与网页端 `renderer.js` 完全一致（`min(max(q.maxRating||5, 3), 10)`）
    var ratingMax: Int {
        let raw = maxRating ?? 5
        return Swift.min(Swift.max(raw, 3), 10)
    }

    /// 量表刻度值：与网页端 `scaleConfig()` 同一套防御性修正
    /// （min 缺省 0、max 缺省 5、step 缺省 1、至少 2 档、单屏最多 11 档）
    var scaleValues: [Int] {
        let low = min ?? 0
        var high = max ?? 5
        var stride = step ?? 1
        if stride <= 0 { stride = 1 }
        if high <= low { high = low + 5 }
        var values: [Int] = []
        var current = low
        while current <= high && values.count < 11 {
            values.append(current)
            current += stride
        }
        if values.isEmpty { values = [low] }
        return values
    }

    var minAnchor: String {
        let trimmed = (minLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "完全不会" : trimmed
    }

    var maxAnchor: String {
        let trimmed = (maxLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "一定会" : trimmed
    }
}

/// 公开填答时需要下发的设置（服务端 `public.js` 白名单）
struct SurveyPublicSettings: Codable, Sendable, Equatable {
    var submitTip: String?
    var kind: String?
    var confetti: String?

    var submitMessage: String {
        let trimmed = (submitTip ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "提交成功，感谢参与！" : trimmed
    }
}

/// 公开填答的问卷本体。
///
/// ⚠️ 与 `/api/app/surveys/{id}` 不同：这里是**原始行**，`endAt` 是毫秒时间戳（数字），
/// 不是 ISO 字符串。两者不能共用模型，否则时间解码必错一个。
struct SurveyPublic: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var title: String
    var description: String?
    /// 毫秒时间戳；0 / nil = 不限时
    var endAt: Double?
    var structure: [SurveyQuestion]
    var settings: SurveyPublicSettings?

    var descriptionText: String {
        (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isTest: Bool {
        (settings?.kind ?? "normal") == "test"
    }

    var submitMessage: String {
        settings?.submitMessage ?? "提交成功，感谢参与！"
    }

    /// 是否已截止（本地时间判断只用于**展示**：能不能填最终由服务端 403 说了算）
    func isEnded(now: Date = Date()) -> Bool {
        guard let endAt = endAt, endAt > 0 else { return false }
        return Date(timeIntervalSince1970: endAt / 1000) < now
    }
}

/// `GET /api/surveys/{id}/public`（公开，无需 Cookie）
struct SurveyPublicResponse: Codable, Sendable, Equatable {
    var ok: Bool
    var survey: SurveyPublic
    var responseCount: Int?
}

/// `POST /api/surveys/{id}/submit` 的响应。
///
/// 刻意不塞进统一信封解析（设计文档 §2.10 脚注）：它的成功体是 `{ok,message}`，
/// 失败体是 `{error:"字符串"}` —— 两种都不是 `{ok,error:{code,message}}`。
struct SurveySubmitResponse: Codable, Sendable, Equatable {
    var ok: Bool?
    var message: String?
}

/// 提交结果（页面只需要"成功提示语"或"一句能上屏的失败原因"）
enum SurveySubmitOutcome: Sendable, Equatable {
    case success(String)
    case failure(String)
}
