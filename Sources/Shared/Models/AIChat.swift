import Foundation

// MARK: - 角色

/// 一条消息是谁说的。
///
/// `system` 不会在界面上出现（人设 system prompt 在服务端拼，不下发给客户端），
/// 这里留着它只是为了能解服务端可能回放的完整历史。
///
/// 解码时未知 / 缺省的角色一律落到 `.assistant`（见 `AIChatMessage.init(from:)`）：
/// 把 AI 的话错当成用户的话，界面上就会出现"用户说了句莫名其妙的话"，
/// 而把用户的话错当成 AI 的话，只是气泡颜色不对 —— 两害相权取后者。
enum AIChatRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

// MARK: - 消息

/// 一条聊天消息。
///
/// 同一个类型身兼两职：
/// · 服务端回来的历史消息（`id` 是服务端 uuid，`status` 恒为 `.done`）；
/// · 本机的乐观消息（`id` 形如 `local-<UUID>`，`status` 会经历 `.streaming → .done/.failed/.cancelled`）。
///
/// `text` 与 `status` 是 `var`：流式期间要逐字往上贴。
/// `model` 也是 `var`：`model = "auto"` 时，真正答题的是谁只有末帧才知道，
/// 收尾时要把它写回这条消息（气泡底下那行模型名就靠它）。
struct AIChatMessage: Identifiable, Codable, Equatable, Sendable {

    /// 一条消息的四种状态。
    ///
    /// `.streaming` **只可能由本机产生**（乐观占位的 assistant 消息），
    /// 从服务端读回来的消息永远是 `.done` —— 服务端只存写完的消息。
    enum Status: String, Codable, Sendable {
        case streaming
        case done
        case failed
        case cancelled
    }

    /// 服务端 uuid；本机乐观消息用 `"local-\(UUID().uuidString)"`
    let id: String

    let role: AIChatRole

    /// 正文。流式期间持续追加
    var text: String

    var status: Status

    /// 出这条消息的模型；用户消息为 nil
    var model: String?

    /// 服务端时间（ISO8601 带毫秒，走 `APIJSON.decoder`）。本机乐观消息为 nil
    let createdAt: Date?

    /// `.failed` 时的原因（一句可直接上屏的中文）
    var errorText: String?

    init(id: String,
         role: AIChatRole,
         text: String,
         status: Status = .done,
         model: String? = nil,
         createdAt: Date? = nil,
         errorText: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.status = status
        self.model = model
        self.createdAt = createdAt
        self.errorText = errorText
    }

    /// 手写 `init(from:)` 后编译器不再自动合成 `CodingKeys`，必须显式声明。
    /// 服务端键名与属性名逐字一致（camelCase），故无需写 rawValue。
    enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case status
        case model
        case createdAt
        case errorText
    }
}

extension AIChatMessage {

    /// 逐个 `try?`：任何一个字段解不开都只是"这个字段没有"，不毁掉整条消息。
    /// 这是全工程对"空值不占位"接口的统一写法（见 `WeatherNow.init(from:)`）。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 没有 id 就没法进 ForEach。宁可用一个临时 id，也不让整页崩
        let rawID = (try? container.decode(String.self, forKey: .id)) ?? ""
        id = rawID.isEmpty ? "local-\(UUID().uuidString)" : rawID

        let rawRole = (try? container.decode(String.self, forKey: .role)) ?? ""
        role = AIChatRole(rawValue: rawRole) ?? .assistant

        text = (try? container.decode(String.self, forKey: .text)) ?? ""

        // status 缺失或是个没见过的值，都按"已经写完"算（理由见 `Status` 的注释）
        let rawStatus = (try? container.decode(String.self, forKey: .status)) ?? ""
        status = Status(rawValue: rawStatus) ?? .done

        model = try? container.decodeIfPresent(String.self, forKey: .model)
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        errorText = try? container.decodeIfPresent(String.self, forKey: .errorText)
    }
}

// MARK: - 会话

/// 一条会话的元数据（历史列表里的一行）。
///
/// `updatedAt` / `createdAt` 在契约里是必填，但 `POST /api/ai/conversation` 新建时
/// 只回 `{id, title, createdAt, messageCount}` —— 没有 `updatedAt`、没有 `preview`。
/// 所以解码时做了兜底（见 `init(from:)`），让同一个类型能吃下所有端点。
struct AIConversation: Identifiable, Codable, Equatable, Sendable {

    /// 22 字符 ULID 风格
    let id: String

    /// 首条用户消息前 18 字；空串 → 界面显示「新对话」
    var title: String

    /// 末条消息前 40 字
    var preview: String

    var updatedAt: Date
    var createdAt: Date
    var messageCount: Int
    var lastModel: String?

    init(id: String,
         title: String,
         preview: String = "",
         updatedAt: Date,
         createdAt: Date,
         messageCount: Int = 0,
         lastModel: String? = nil) {
        self.id = id
        self.title = title
        self.preview = preview
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.messageCount = messageCount
        self.lastModel = lastModel
    }

    /// 列表上屏用的标题：空标题不许出现空行
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "新对话" : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case preview
        case updatedAt
        case createdAt
        case messageCount
        case lastModel
    }
}

extension AIConversation {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawID = (try? container.decode(String.self, forKey: .id)) ?? ""
        id = rawID.isEmpty ? "unknown-\(UUID().uuidString)" : rawID

        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        preview = (try? container.decode(String.self, forKey: .preview)) ?? ""

        // 时间兜底链：createdAt → updatedAt → 现在。
        // 为什么不把它们做成可选：列表排序与「今天 / 更早」分组全靠 `updatedAt`，
        // 设成可选会逼着每一处调用点写一遍 `?? Date()`，那才是真的会漏。
        let created = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        let updated = try? container.decodeIfPresent(Date.self, forKey: .updatedAt)
        createdAt = created ?? updated ?? Date()
        updatedAt = updated ?? createdAt

        messageCount = (try? container.decode(Int.self, forKey: .messageCount)) ?? 0
        lastModel = try? container.decodeIfPresent(String.self, forKey: .lastModel)
    }
}

// MARK: - 模型清单

/// 一个可选模型。
///
/// `id` 的取值：`"auto"`（服务端按 §1.4 规则自动选）/ `"deepseek-chat"` / `"hunyuan-standard"`。
/// `note` 是置灰原因（"云端未配置 SecretId / SecretKey"），`available == false` 时才有意义。
struct AIModelOption: Identifiable, Codable, Equatable, Sendable {

    let id: String

    /// 「自动选择」「DeepSeek」「腾讯混元」
    let label: String

    /// 云端配置齐了没有。缺省按**不可用**算 —— 拿不准就别让用户点
    let available: Bool

    let note: String?

    init(id: String, label: String, available: Bool = true, note: String? = nil) {
        self.id = id
        self.label = label
        self.available = available
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case available
        case note
    }
}

extension AIModelOption {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawID = (try? container.decode(String.self, forKey: .id)) ?? ""
        id = rawID

        // 没有 label 就拿 id 顶上：界面上宁可出现 "deepseek-chat"，也不要出现一个空白的选项
        let rawLabel = (try? container.decode(String.self, forKey: .label)) ?? ""
        label = rawLabel.isEmpty ? rawID : rawLabel

        available = (try? container.decode(Bool.self, forKey: .available)) ?? false
        note = try? container.decodeIfPresent(String.self, forKey: .note)
    }
}

/// `GET /api/ai/models` 里 `auto` 那一块：服务端算好的自动选择结果 + 给用户看的理由。
///
/// `needStrong` 与 `signals` 只做判据回显。`signals` **刻意不解**：
/// 界面不展示它（一行小字写 reason 就够了），多解一层就多一处会漂的契约。
struct AIModelAuto: Codable, Equatable, Sendable {

    /// 这次 auto 会选谁
    let picked: String?

    /// 「短问题，走便宜模型（便宜模型未配置，回退）」—— 这句话要显示在界面上
    let reason: String?

    /// 是否被判为"需要强模型"
    let needStrong: Bool?

    init(picked: String? = nil, reason: String? = nil, needStrong: Bool? = nil) {
        self.picked = picked
        self.reason = reason
        self.needStrong = needStrong
    }

    enum CodingKeys: String, CodingKey {
        case picked
        case reason
        case needStrong
    }
}

extension AIModelAuto {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        picked = try? container.decodeIfPresent(String.self, forKey: .picked)
        reason = try? container.decodeIfPresent(String.self, forKey: .reason)
        needStrong = try? container.decodeIfPresent(Bool.self, forKey: .needStrong)
    }
}

/// 今日配额（服务端 `ai:quota:<yyyyMMdd>` 的读数）。
///
/// 客户端只显示、不判定：超限时服务端会回 429，那才是唯一权威的"用完了"。
/// 界面上拿这个数做乐观提示就好 —— 多设备同时用，本地数总会偏。
struct AIQuota: Codable, Equatable, Sendable {

    /// `"20261103"`
    let day: String?
    let used: Int?

    /// 每日上限（当前 200）
    let limit: Int?
    let remaining: Int?

    init(day: String? = nil, used: Int? = nil, limit: Int? = nil, remaining: Int? = nil) {
        self.day = day
        self.used = used
        self.limit = limit
        self.remaining = remaining
    }

    enum CodingKeys: String, CodingKey {
        case day
        case used
        case limit
        case remaining
    }
}

extension AIQuota {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try? container.decodeIfPresent(String.self, forKey: .day)
        used = try? container.decodeIfPresent(Int.self, forKey: .used)
        limit = try? container.decodeIfPresent(Int.self, forKey: .limit)
        remaining = try? container.decodeIfPresent(Int.self, forKey: .remaining)
    }
}

/// `GET /api/ai/models` 的完整响应。
struct AIModelsResponse: Codable, Sendable {

    let ok: Bool

    /// 接口版本（当前 1）。将来加字段时靠它判断兼容性
    let apiVersion: Int?

    /// 服务端建议的默认模型（当前就是 `"auto"`）
    let defaultModel: String?
    let auto: AIModelAuto?
    let models: [AIModelOption]
    let quota: AIQuota?

    init(ok: Bool = false,
         apiVersion: Int? = nil,
         defaultModel: String? = nil,
         auto: AIModelAuto? = nil,
         models: [AIModelOption] = [],
         quota: AIQuota? = nil) {
        self.ok = ok
        self.apiVersion = apiVersion
        self.defaultModel = defaultModel
        self.auto = auto
        self.models = models
        self.quota = quota
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case apiVersion
        case defaultModel
        case auto
        case models
        case quota
    }
}

extension AIModelsResponse {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `ok` 缺失按失败算：拿不准成功就不当成有模型可用
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        apiVersion = try? container.decodeIfPresent(Int.self, forKey: .apiVersion)
        defaultModel = try? container.decodeIfPresent(String.self, forKey: .defaultModel)
        auto = try? container.decodeIfPresent(AIModelAuto.self, forKey: .auto)
        models = (try? container.decode([AIModelOption].self, forKey: .models)) ?? []
        quota = try? container.decodeIfPresent(AIQuota.self, forKey: .quota)
    }
}

// MARK: - 流式事件

/// 流里的一个错误帧：`data: {"error":{"code":"upstream_auth","message":"…"}}`。
///
/// 它同时是 `Error`：`AIChatStore` 的循环里可以直接 `throw event.error!`，
/// 让"流内业务失败"和"传输失败"走同一条 catch —— 只有一条收尾路径才不会漏状态。
struct AIStreamError: Codable, Error, Equatable, Sendable {

    let code: String
    let message: String

    init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case code
        case message
    }
}

extension AIStreamError {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? container.decode(String.self, forKey: .code)) ?? ""
        message = (try? container.decode(String.self, forKey: .message)) ?? ""
    }
}

/// 末帧带的用量统计（服务端原样透传上游）。
///
/// 界面当前不显示它，解出来的意义是：`assistant` 消息"到底花了多少"将来要做成本视图时，
/// 数据已经在手里，不用再改契约。
struct AIUsage: Codable, Equatable, Sendable {

    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    init(promptTokens: Int = 0, completionTokens: Int = 0, totalTokens: Int = 0) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens
        case completionTokens
        case totalTokens
    }
}

extension AIUsage {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = (try? container.decode(Int.self, forKey: .promptTokens)) ?? 0
        completionTokens = (try? container.decode(Int.self, forKey: .completionTokens)) ?? 0
        totalTokens = (try? container.decode(Int.self, forKey: .totalTokens)) ?? 0
    }
}

/// SSE 里的一帧（每行 `data: {…}` 解一次）。
///
/// 所有字段都可选 —— 三种帧共用一个类型：
/// · 增量帧 `{"delta":"光遇"}`
/// · 末帧   `{"done":true,"convId":"…","finish":"stop","usage":{…},"model":"…","reason":"…"}`
/// · 错误帧 `{"error":{"code":"…","message":"…"}}`
///
/// 与架构文档 §4 的差异：多了 `usage` / `model` / `reason` 三个字段。
/// 理由很硬：实测末帧就带这三个，而 `reason` 是「界面上要显示 auto 为什么这么选」的唯一来源，
/// `model` 是"auto 到底选了谁"的唯一凭据。少解它们，界面上那行小字就只能写死。
struct AIStreamEvent: Codable, Sendable {

    let delta: String?
    let done: Bool?
    let convId: String?

    /// 上游收尾原因：`"stop"` / `"length"` …
    let finish: String?
    let error: AIStreamError?

    /// 本轮实际使用的模型（末帧才有）
    let model: String?

    /// 本轮 auto 选择原因（末帧才有）
    let reason: String?

    let usage: AIUsage?

    init(delta: String? = nil,
         done: Bool? = nil,
         convId: String? = nil,
         finish: String? = nil,
         error: AIStreamError? = nil,
         model: String? = nil,
         reason: String? = nil,
         usage: AIUsage? = nil) {
        self.delta = delta
        self.done = done
        self.convId = convId
        self.finish = finish
        self.error = error
        self.model = model
        self.reason = reason
        self.usage = usage
    }

    enum CodingKeys: String, CodingKey {
        case delta
        case done
        case convId
        case finish
        case error
        case model
        case reason
        case usage
    }
}

extension AIStreamEvent {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 全 `try?`：一个帧里多出未知字段、少一个字段，都不该让整条流断掉
        delta = try? container.decodeIfPresent(String.self, forKey: .delta)
        done = try? container.decodeIfPresent(Bool.self, forKey: .done)
        convId = try? container.decodeIfPresent(String.self, forKey: .convId)
        finish = try? container.decodeIfPresent(String.self, forKey: .finish)
        error = try? container.decodeIfPresent(AIStreamError.self, forKey: .error)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        reason = try? container.decodeIfPresent(String.self, forKey: .reason)
        usage = try? container.decodeIfPresent(AIUsage.self, forKey: .usage)
    }
}

// MARK: - 请求体

/// `POST /api/ai/chat` 的请求体。
///
/// `weather` / `earnings` 是**这次请求的上下文快照**：服务端不会自己去查天气和账本，
/// 它只把这两个对象压成摘要拼进 system prompt（见后端 `ai-context.js` 的
/// `weatherDigest` / `earningsDigest`）。所以「AI 到底知不知道今天多少度、这个月赚了多少」，
/// 唯一取决于这里有没有传。
///
/// 两个字段都可选且默认 nil：没定位 / 没登录收益时就**不传**，
/// 服务端退化成「这次没拿到数据」，AI 老实说没拿到 —— 比编一个数诚实。
struct AIChatRequest: Encodable, Sendable {

    /// 续聊时带上；新对话为 nil（服务端会建一条并回 `convId`）
    let convId: String?

    /// `"auto"` 或具体模型 id
    let model: String
    let text: String

    /// 天气快照（见 `AIChatWeather`）。nil = 这次没有可用天气
    let weather: AIChatWeather?

    /// 收益快照（见 `AIChatEarnings`）。nil = 没登录 / 还没拉到账本
    let earnings: AIChatEarnings?

    /// 两个上下文都给默认值：现有调用点（只传三件）一个字都不用改
    init(convId: String?,
         model: String,
         text: String,
         weather: AIChatWeather? = nil,
         earnings: AIChatEarnings? = nil) {
        self.convId = convId
        self.model = model
        self.text = text
        self.weather = weather
        self.earnings = earnings
    }
}

/// 随聊天请求上传的天气快照。
///
/// 键名与后端 `weatherDigest` 认的键**逐字对齐**（`city` / `temp` / `tMin` / …），
/// 全部可选、缺省不占位（合成的 `Encodable` 对 Optional 用 `encodeIfPresent`）：
/// 拿不到的那项就不发，服务端少说那一句，而不是拼出「undefined℃」——
/// 模型会把那种串当真，再复述给用户。
struct AIChatWeather: Encodable, Sendable {

    /// 地名（"登封"）。来自 `LocationStore.displayName`
    let city: String?

    /// 当前气温
    let temp: Double?

    /// 今日最低 / 最高气温
    let tMin: Double?
    let tMax: Double?

    /// 体感温度
    let feelsLike: Double?

    /// 天气现象（"多云"、"小雨"）
    let text: String?

    /// 相对湿度（0…100）
    let humidity: Double?

    /// 风速（m/s）
    let wind: Double?

    /// 风向中文（"东南"）。服务端已经换算好，客户端只负责透传
    let windDirText: String?

    /// 分钟级降水时段。
    ///
    /// `WeatherNow` 目前只有「过去一小时降水量」这一个数（`precip: Double?`），
    /// **没有分段时段** —— 所以实际调用时这里恒为 nil。留着字段是为了将来分钟降水
    /// 真接进来时不必再改一次请求契约；但**绝不为了填满它去硬造数据**。
    let precip: [AIChatPrecipSlot]?

    init(city: String? = nil,
         temp: Double? = nil,
         tMin: Double? = nil,
         tMax: Double? = nil,
         feelsLike: Double? = nil,
         text: String? = nil,
         humidity: Double? = nil,
         wind: Double? = nil,
         windDirText: String? = nil,
         precip: [AIChatPrecipSlot]? = nil) {
        self.city = city
        self.temp = temp
        self.tMin = tMin
        self.tMax = tMax
        self.feelsLike = feelsLike
        self.text = text
        self.humidity = humidity
        self.wind = wind
        self.windDirText = windDirText
        self.precip = precip
    }
}

/// 一个降水时段（`{from,to,level}`）。
///
/// 为什么不复用 `AIOutfitPrecipSlot`：那是 outfit 那份契约的从属类型。
/// 两个请求体的字段形状今天一样，明天不一定（outfit 已经在讨论加"强度数值"），
/// 共用之后「改 outfit 顺手改了 chat」就是一次没有任何报错的连锁事故。
/// 类型只有三个字段，抄一份比拆依赖便宜。
struct AIChatPrecipSlot: Encodable, Sendable, Equatable {

    /// 形状未定死（"14:00"？ISO 时刻？），原样透传，不做类型假设
    let from: String
    let to: String

    /// 强度档位（服务端自定义的名字，客户端不解释）
    let level: String

    init(from: String, to: String, level: String) {
        self.from = from
        self.to = to
        self.level = level
    }
}

/// 随聊天请求上传的收益账本快照。
///
/// 金额单位一律是**分**，与 `GET /api/app/earnings` 的 `summary` 完全一致 ——
/// 客户端**不做任何换算**（换算是展示层 `EarningsMoney` 的事），
/// 分转元发生在服务端 `earningsDigest` 里。少一层换算就少一处会对不上的账。
///
/// 字段都是非可选整数：`EarningsSummary` 解码时缺键已经填了 0，
/// 到这一层再套一层 Optional 只会让调用点多写几个 `?? 0`。
struct AIChatEarnings: Encodable, Sendable {

    /// 总收益（分）≡ pending + receivedUnclosed + closed
    let total: Int

    /// 待发放 / 已到账未结 / 已结清（分）
    let pending: Int
    let receivedUnclosed: Int
    let closed: Int

    /// 本月新增（分）
    let monthAdded: Int

    /// 活动总数 / 未结清活动数
    let activityCount: Int
    let pendingActivityCount: Int

    /// 平台数
    let platformCount: Int

    /// 各平台金额（分），服务端已按金额降序；这里只带前几个由服务端自己截断
    let breakdown: [AIChatEarningsPlatform]

    /// 这份数据的生成时刻（ISO8601 字符串）。nil = 不知道什么时候拉的
    let updatedAt: String?

    init(total: Int = 0,
         pending: Int = 0,
         receivedUnclosed: Int = 0,
         closed: Int = 0,
         monthAdded: Int = 0,
         activityCount: Int = 0,
         pendingActivityCount: Int = 0,
         platformCount: Int = 0,
         breakdown: [AIChatEarningsPlatform] = [],
         updatedAt: String? = nil) {
        self.total = total
        self.pending = pending
        self.receivedUnclosed = receivedUnclosed
        self.closed = closed
        self.monthAdded = monthAdded
        self.activityCount = activityCount
        self.pendingActivityCount = pendingActivityCount
        self.platformCount = platformCount
        self.breakdown = breakdown
        self.updatedAt = updatedAt
    }
}

/// 收益快照里的一个平台（名字 + 金额分）。
struct AIChatEarningsPlatform: Encodable, Sendable {

    /// 平台名（"抖音"、"哔哩哔哩"）
    let name: String

    /// 该平台金额（分）
    let amount: Int

    init(name: String, amount: Int) {
        self.name = name
        self.amount = amount
    }
}

/// `POST /api/ai/conversation` 的请求体（`title` 可选，服务端会用首条用户消息兜底）
struct AIConversationCreateRequest: Encodable, Sendable {

    let title: String?

    init(title: String? = nil) {
        self.title = title
    }
}

// MARK: - 其余端点响应

/// `GET /api/ai/conversations?cursor=` 的响应
struct AIConversationsResponse: Codable, Sendable {

    let ok: Bool
    let conversations: [AIConversation]
    let hasMore: Bool?

    /// 下一页游标；`hasMore == false` 时无意义
    let nextCursor: String?

    init(ok: Bool = false,
         conversations: [AIConversation] = [],
         hasMore: Bool? = nil,
         nextCursor: String? = nil) {
        self.ok = ok
        self.conversations = conversations
        self.hasMore = hasMore
        self.nextCursor = nextCursor
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case conversations
        case hasMore
        case nextCursor
    }
}

extension AIConversationsResponse {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        conversations = (try? container.decode([AIConversation].self, forKey: .conversations)) ?? []
        hasMore = try? container.decodeIfPresent(Bool.self, forKey: .hasMore)
        nextCursor = try? container.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

/// `GET /api/ai/conversation?id=` 的响应：会话元数据 + 全部消息
struct AIConversationDetailResponse: Codable, Sendable {

    let ok: Bool
    let conversation: AIConversation?
    let messages: [AIChatMessage]

    init(ok: Bool = false, conversation: AIConversation? = nil, messages: [AIChatMessage] = []) {
        self.ok = ok
        self.conversation = conversation
        self.messages = messages
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case conversation
        case messages
    }
}

extension AIConversationDetailResponse {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        conversation = try? container.decodeIfPresent(AIConversation.self, forKey: .conversation)
        messages = (try? container.decode([AIChatMessage].self, forKey: .messages)) ?? []
    }
}

/// `POST /api/ai/conversation` 的响应
struct AIConversationCreateResponse: Codable, Sendable {

    let ok: Bool
    let conversation: AIConversation?

    init(ok: Bool = false, conversation: AIConversation? = nil) {
        self.ok = ok
        self.conversation = conversation
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case conversation
    }
}

extension AIConversationCreateResponse {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        conversation = try? container.decodeIfPresent(AIConversation.self, forKey: .conversation)
    }
}

/// `DELETE /api/ai/conversation?id=` 的响应：`{ok, deleted:n}`
struct AIConversationDeleteResponse: Codable, Sendable {

    let ok: Bool

    /// 实际删掉的键数（会话 meta + 消息 + 索引项）。0 也是成功
    let deleted: Int?

    init(ok: Bool = false, deleted: Int? = nil) {
        self.ok = ok
        self.deleted = deleted
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case deleted
    }
}

extension AIConversationDeleteResponse {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        deleted = try? container.decodeIfPresent(Int.self, forKey: .deleted)
    }
}

// MARK: - 错误

/// AI 模块的错误，归一成 8 个 case（每个都带可直接上屏的中文）。
///
/// 为什么在 `APIError` 之外再造一套：`APIError` 的文案是给"读文章 / 看天气"写的
/// （"下拉重试一次"），而聊天要的东西不一样 —— 用户需要知道**这条消息**怎么了
/// （没写完？额度没了？通行证过期？），以及**能不能重试**。
///
/// 定义在 `Shared/Models` 里，所以**不许**引用 `APIError`（那个在 `Services/`，
/// 不进小组件 target）。转换在 `AIFailure.from(_:)`（`Services/AIChatStore.swift`）。
enum AIError: Error, Equatable, Sendable {

    /// 连接失败 / 离线 / 超时
    case network

    /// 401 / 403：`x-ai-token` 不对（多半是服务端轮换了 token，App 太旧）
    case unauthorized

    /// 429：今日配额用完。关联值是服务端原话（可能是空的）
    case quota(String)

    /// 流内错误帧 / 502 上游不通。关联值是服务端原话
    case upstream(String)

    /// 其他 4xx / 5xx。关联值是服务端原话
    case server(String)

    /// 30 秒没收到任何字节（含心跳），主动掐断
    case idleTimeout

    /// 流被对端关掉但**没给末帧** —— 半截回复，不能冒充完整
    case interrupted

    /// 用户点了停止
    case cancelled

    /// 可直接上屏的一句话
    var userMessage: String {
        switch self {
        case .network:
            return "网络好像断了一下，等会儿再试。"
        case .unauthorized:
            return "AI 通行证没通过校验，更新一下 App 再试。"
        case .quota(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "今天的 AI 额度用完了，明天再来。" : trimmed
        case .upstream(let message), .server(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "服务器打了个喷嚏，等会儿再试。" : trimmed
        case .idleTimeout:
            return "等了半分钟没有新内容，这条没写完。"
        case .interrupted:
            return "回复没写完就断了，可以重试。"
        case .cancelled:
            return "已停止。"
        }
    }

    /// 重试有没有意义。`.cancelled` / 额度用完 / 通行证过期，重试一次只会得到同样的结果
    var isRetryable: Bool {
        switch self {
        case .cancelled, .unauthorized, .quota:
            return false
        case .network, .upstream, .server, .idleTimeout, .interrupted:
            return true
        }
    }

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}
