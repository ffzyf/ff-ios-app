import Foundation

// MARK: - 通用信封

/// 追光计划 API 的统一响应信封。
///
/// 服务端 `zg-store.js` 的 `envelope()` / `fail()` 产出 `{ok, apiVersion, serverTime, data, ...}`，
/// 与收益总览（字段平铺在顶层）不同 —— 所以这里单独定义，**不复用** `EarningsResponse`。
/// `apiVersion` 是字符串（`'zg-1.0'`），`data` 在错误响应里缺省，故为可选。
struct ZGEnvelope<T: Codable & Sendable>: Codable, Sendable {
    let ok: Bool
    let apiVersion: String?
    let serverTime: String?
    let data: T?
    let error: String?
    let status: Int?
    /// 结果接口附带的服务端时间戳 / 指针版本（用于缓存与去重展示）
    let t: Int64?
    let rev: Int?

    private enum CodingKeys: String, CodingKey {
        case ok, apiVersion, serverTime, data, error, status, t, rev
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        apiVersion = try? c.decode(String.self, forKey: .apiVersion)
        serverTime = try? c.decode(String.self, forKey: .serverTime)
        data = try? c.decode(T.self, forKey: .data)
        error = try? c.decode(String.self, forKey: .error)
        status = try? c.decode(Int.self, forKey: .status)
        t = try? c.decode(Int64.self, forKey: .t)
        rev = try? c.decode(Int.self, forKey: .rev)
    }

    /// 金额单位说明：结果 data 里自带 `amountUnit`，端侧只用它做展示格式化。
    init(ok: Bool, data: T?, error: String? = nil) {
        self.ok = ok
        self.apiVersion = nil
        self.serverTime = nil
        self.data = data
        self.error = error
        self.status = nil
        self.t = nil
        self.rev = nil
    }
}

/// 任意 JSON 值的弱类型容器。
///
/// 规则文档（`rules`）与清洗报告的分平台明细字段多且随期次变化，UI 只需要"读出来展示"，
/// 不需要逐字段强类型。用一个可递归的 JSON 值承接，避免每加一个规则字段都要改模型。
/// 金额口径仍以 `ZGResult` 的强类型字段为准 —— 这里只做规则/报告的原文展示。
indirect enum ZGJSONValue: Codable, Sendable, Equatable {
    case object([String: ZGJSONValue])
    case array([ZGJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Int.self) {
            self = .number(Double(v))
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([ZGJSONValue].self) {
            self = .array(v)
        } else if let v = try? c.decode([String: ZGJSONValue].self) {
            self = .object(v)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    /// 递归取对象成员（规则 UI 用路径读，如 `["awards", "tier_cumulative", "cap"]`）。
    func member(_ path: [String]) -> ZGJSONValue? {
        var cur = self
        for key in path {
            guard case .object(let dict) = cur, let next = dict[key] else { return nil }
            cur = next
        }
        return cur
    }

    /// 展示用的纯文本（数字去掉无意义的 `.0`）。
    var displayText: String {
        switch self {
        case .object: return "{…}"
        case .array(let v): return "[\(v.count)]"
        case .string(let v): return v
        case .number(let v): return v == v.rounded() ? String(Int(v)) : String(v)
        case .bool(let v): return v ? "是" : "否"
        case .null: return "—"
        }
    }
}

// MARK: - 结果（/api/zg/result）

/// 单个奖项的计算结果。六个奖项字段名一致，差异字段全部可选 —— 用一套类型承接，
/// 端侧只读 `rawCents` / `cappedCents` / `capYuan` 做展示，不参与任何运算。
struct ZGAward: Codable, Sendable {
    let rawCents: Int
    let cappedCents: Int
    let capYuan: Double?
    let capResolved: Double?
    let ambiguityStatus: String?
    let capRaw: String?
    let validPosts: Int?
    let activeCents: Int?
    let fullCents: Int?
    let newcomerCappedCents: Int?
    let recruiterCents: Int?
    /// 档位累加 / 多平台的明细。异构（数组或对象），用通用 JSON 值承接。
    let breakdown: ZGJSONValue?
    let band: ZGJSONValue?

    private enum CodingKeys: String, CodingKey {
        case rawCents, cappedCents, capYuan
        case capResolved = "capResolved"
        case ambiguityStatus, capRaw, validPosts, activeCents, fullCents
        case newcomerCappedCents, recruiterCents, breakdown, band
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawCents = (try? c.decode(Int.self, forKey: .rawCents)) ?? 0
        cappedCents = (try? c.decode(Int.self, forKey: .cappedCents)) ?? 0
        capYuan = try? c.decode(Double.self, forKey: .capYuan)
        capResolved = try? c.decode(Double.self, forKey: .capResolved)
        ambiguityStatus = try? c.decode(String.self, forKey: .ambiguityStatus)
        capRaw = try? c.decode(String.self, forKey: .capRaw)
        validPosts = try? c.decode(Int.self, forKey: .validPosts)
        activeCents = try? c.decode(Int.self, forKey: .activeCents)
        fullCents = try? c.decode(Int.self, forKey: .fullCents)
        newcomerCappedCents = try? c.decode(Int.self, forKey: .newcomerCappedCents)
        recruiterCents = try? c.decode(Int.self, forKey: .recruiterCents)
        breakdown = try? c.decode(ZGJSONValue.self, forKey: .breakdown)
        band = try? c.decode(ZGJSONValue.self, forKey: .band)
    }
}

/// 档位明细行（服务端 `breakdown.douyin[]` / `kuaishou[]` 元素）。字段名服务端已是 camelCase。
struct ZGTierLine: Codable, Sendable {
    let lv: Int
    let plays: Int?
    let poolYuan: Double?
    let qualified: Int?
    let amountCents: Int
}

/// 六奖项集合。字段 snake_case → camelCase。
struct ZGAwards: Codable, Sendable {
    let tierCumulative: ZGAward?
    let risingStar: ZGAward?
    let active: ZGAward?
    let multiPlatform: ZGAward?
    let referral: ZGAward?

    private enum CodingKeys: String, CodingKey {
        case tierCumulative = "tier_cumulative"
        case risingStar = "rising_star"
        case active
        case multiPlatform = "multi_platform"
        case referral
    }

    /// 稳定顺序的展示列表（金额只渲染服务端结果，顺序是固定的产品口径）。
    var ordered: [(key: String, award: ZGAward)] {
        let all: [(String, ZGAward?)] = [
            ("档位累加奖", tierCumulative),
            ("新星成长奖", risingStar),
            ("活跃奖", active),
            ("多平台奖", multiPlatform),
            ("拉新奖", referral)
        ]
        return all.compactMap { pair in pair.1.map { (key: pair.0, award: $0) } }
    }
}

/// 自动预估的单一档位（low / mid / high）。
struct ZGRangePoint: Codable, Sendable {
    let rawCents: Int
    let cappedCents: Int
    let cappedYuan: Double?
}

/// 自动预估三档区间。
struct ZGRange: Codable, Sendable {
    let low: ZGRangePoint?
    let mid: ZGRangePoint?
    let high: ZGRangePoint?
}

/// `/api/zg/result?period=&mode=` 的 data（calc.js 写入 result 的原样结构）。
struct ZGResult: Codable, Sendable {
    let ok: Bool
    let amountUnit: String?
    let awards: ZGAwards?
    let totalCents: Int
    let cappedCents: Int
    let cappedYuan: Double?
    let warnings: [String]
    let watermark: String
    let period: Int?
    let ruleVersion: String?
    let calculatedAt: String?
    let exportCapNote: String?
    // auto 模式专有
    let range: ZGRange?
    let byAward: [String: [String: Int]]?
    let message: String?
    let priorPeriod: Int?
    let priorSource: String?

    private enum CodingKeys: String, CodingKey {
        case ok, amountUnit, awards, totalCents, cappedCents, cappedYuan
        case warnings, watermark, period, ruleVersion, calculatedAt
        case exportCapNote = "export_cap_note"
        case range, byAward, message
        case priorPeriod = "priorPeriod"
        case priorSource = "priorSource"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        amountUnit = try? c.decode(String.self, forKey: .amountUnit)
        awards = try? c.decode(ZGAwards.self, forKey: .awards)
        totalCents = (try? c.decode(Int.self, forKey: .totalCents)) ?? 0
        cappedCents = (try? c.decode(Int.self, forKey: .cappedCents)) ?? 0
        cappedYuan = try? c.decode(Double.self, forKey: .cappedYuan)
        warnings = (try? c.decode([String].self, forKey: .warnings)) ?? []
        watermark = (try? c.decode(String.self, forKey: .watermark)) ?? ""
        period = try? c.decode(Int.self, forKey: .period)
        ruleVersion = try? c.decode(String.self, forKey: .ruleVersion)
        calculatedAt = try? c.decode(String.self, forKey: .calculatedAt)
        exportCapNote = try? c.decode(String.self, forKey: .exportCapNote)
        range = try? c.decode(ZGRange.self, forKey: .range)
        byAward = try? c.decode([String: [String: Int]].self, forKey: .byAward)
        message = try? c.decode(String.self, forKey: .message)
        priorPeriod = try? c.decode(Int.self, forKey: .priorPeriod)
        priorSource = try? c.decode(String.self, forKey: .priorSource)
    }

    /// 是不是预估值（服务端 watermark = '预估'）。
    var isEstimate: Bool { watermark == "预估" }
}

// MARK: - 话题告警（/api/zg/topics）

/// 服务端 `checkTopics()` 产出：`{workId, platform, seq, title, missing}`。
/// `title` 是原始标题，端侧只展示，绝不改写（铁律2）。
struct ZGTopicWarning: Codable, Sendable {
    let workId: String
    let platform: String?
    let seq: Int?
    let title: String
    let missing: [String]

    private enum CodingKeys: String, CodingKey {
        case workId, platform, seq, title, missing
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 服务端 workId 可能是字符串或数字，双向兼容
        if let s = try? c.decode(String.self, forKey: .workId) {
            workId = s
        } else if let i = try? c.decode(Int.self, forKey: .workId) {
            workId = String(i)
        } else {
            workId = ""
        }
        platform = try? c.decode(String.self, forKey: .platform)
        seq = try? c.decode(Int.self, forKey: .seq)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        missing = (try? c.decode([String].self, forKey: .missing)) ?? []
    }
}

/// `/api/zg/topics` 的 data。
struct ZGTopicsData: Codable, Sendable {
    let warnings: [ZGTopicWarning]
    /// 已忽略的 workId 集合（服务端布尔字典的 key）。
    let ignoredIds: [String: Bool]
    let effectiveIds: [String]
    let distributionRecords: [ZGJSONValue]?

    private enum CodingKeys: String, CodingKey {
        case warnings, ignoredIds, effectiveIds, distributionRecords
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        warnings = (try? c.decode([ZGTopicWarning].self, forKey: .warnings)) ?? []
        ignoredIds = (try? c.decode([String: Bool].self, forKey: .ignoredIds)) ?? [:]
        effectiveIds = (try? c.decode([String].self, forKey: .effectiveIds)) ?? []
        distributionRecords = try? c.decode([ZGJSONValue].self, forKey: .distributionRecords)
    }
}

// MARK: - 合并建议（/api/zg/merge）

/// 服务端 `suggestMerges()` 产出：`{douyin, kuaishou, time_diff_sec, similarity, titles}`。
struct ZGMergeSuggestion: Codable, Sendable {
    let douyin: String
    let kuaishou: String
    let timeDiffSec: Int
    let similarity: Double
    /// 原文标题对（抖音 / 快手）
    let titles: [String]

    private enum CodingKeys: String, CodingKey {
        case douyin, kuaishou
        case timeDiffSec = "time_diff_sec"
        case similarity, titles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        douyin = (try? c.decode(String.self, forKey: .douyin)) ?? ""
        kuaishou = (try? c.decode(String.self, forKey: .kuaishou)) ?? ""
        timeDiffSec = (try? c.decode(Int.self, forKey: .timeDiffSec)) ?? 0
        similarity = (try? c.decode(Double.self, forKey: .similarity)) ?? 0
        titles = (try? c.decode([String].self, forKey: .titles)) ?? []
    }

    /// 稳定的选中标识（旋转 / 尺寸变化时不丢选中态）。
    var id: String { "\(douyin)|\(kuaishou)" }
}

/// `/api/zg/merge` 的 data。
struct ZGMergeData: Codable, Sendable {
    let suggestions: [ZGMergeSuggestion]
    let relations: [ZGJSONValue]

    private enum CodingKeys: String, CodingKey { case suggestions, relations }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        suggestions = (try? c.decode([ZGMergeSuggestion].self, forKey: .suggestions)) ?? []
        relations = (try? c.decode([ZGJSONValue].self, forKey: .relations)) ?? []
    }
}

// MARK: - 规则（/api/zg/rules）

/// `/api/zg/rules` 的 data：`{rules, ruleVersion, updatedAt}`。
/// `rules` 用通用 JSON 值承接（字段随期次变化，UI 按点路径读取口径卡）。
struct ZGRules: Codable, Sendable {
    let rules: ZGJSONValue?
    let ruleVersion: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey { case rules, ruleVersion, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try? c.decode(ZGJSONValue.self, forKey: .rules)
        ruleVersion = try? c.decode(String.self, forKey: .ruleVersion)
        updatedAt = try? c.decode(String.self, forKey: .updatedAt)
    }
}

// MARK: - 清洗报告（/api/zg/clean-report）

/// 汇总清洗报告（`clean-report.js` 的 `report` 对象）。字段名 snake_case。
struct ZGCleanSummary: Codable, Sendable {
    let totalRows: Int
    let auditRemoved: Int
    let timelineRemoved: Int
    let nonMainRemoved: Int
    let placeholderAnomalies: Int
    let validTier: Int
    let validRising: Int
    let validActive: Int
    let overriddenCount: Int
    let truncated: Bool

    private enum CodingKeys: String, CodingKey {
        case totalRows = "total_rows"
        case auditRemoved = "audit_removed"
        case timelineRemoved = "timeline_removed"
        case nonMainRemoved = "non_main_removed"
        case placeholderAnomalies = "placeholder_anomalies"
        case validTier = "valid_tier"
        case validRising = "valid_rising"
        case validActive = "valid_active"
        case overriddenCount = "overridden_count"
        case truncated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalRows = (try? c.decode(Int.self, forKey: .totalRows)) ?? 0
        auditRemoved = (try? c.decode(Int.self, forKey: .auditRemoved)) ?? 0
        timelineRemoved = (try? c.decode(Int.self, forKey: .timelineRemoved)) ?? 0
        nonMainRemoved = (try? c.decode(Int.self, forKey: .nonMainRemoved)) ?? 0
        placeholderAnomalies = (try? c.decode(Int.self, forKey: .placeholderAnomalies)) ?? 0
        validTier = (try? c.decode(Int.self, forKey: .validTier)) ?? 0
        validRising = (try? c.decode(Int.self, forKey: .validRising)) ?? 0
        validActive = (try? c.decode(Int.self, forKey: .validActive)) ?? 0
        overriddenCount = (try? c.decode(Int.self, forKey: .overriddenCount)) ?? 0
        truncated = (try? c.decode(Bool.self, forKey: .truncated)) ?? false
    }
}

/// `/api/zg/clean-report` 的 data：`{report, byPlatform}`。
struct ZGCleanReport: Codable, Sendable {
    let report: ZGCleanSummary?
    let byPlatform: [String: ZGJSONValue]?

    private enum CodingKeys: String, CodingKey { case report, byPlatform }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        report = try? c.decode(ZGCleanSummary.self, forKey: .report)
        byPlatform = try? c.decode([String: ZGJSONValue].self, forKey: .byPlatform)
    }
}

// MARK: - 写接口回包

/// `POST /api/zg/topics/ignore` → `{ignoredIds}` 的 data。
struct ZGIgnoreResponse: Codable, Sendable {
    let ignoredIds: [String: Bool]
}

/// `POST /api/zg/merge/confirm` → `{relations}` 的 data。
struct ZGMergeConfirmResponse: Codable, Sendable {
    let relations: [ZGJSONValue]
}
