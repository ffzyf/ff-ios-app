import Foundation

/// `GET /api/app/feed`（博客站）的响应。
///
/// 真实字段以**已部署实现**为准（`blog/functions/api/app/[[path]].js`），
/// 不是设计文档的想象版本。实测 envelope 是「设计字段 + 任务字段」的并集：
///   `{ ok, apiVersion, serverTime, generatedAt, articles{...}, notice, stats }`
/// 设计文档里的 `sky` / `brief` 目前**不会**出现在 feed 里（跨站 KV 不聚合），
/// 所以模型把它们保留成可空字段：现在解出来是 nil，将来后端补上就能直接吃。
struct FeedResponse: Decodable {
    let ok: Bool
    let apiVersion: Int?
    let serverTime: Date?
    let generatedAt: Date?
    let articles: FeedArticles
    let notice: FeedNotice?
    let stats: FeedStats?
    /// 设计文档 §3.3 的 best-effort 附带字段，当前实现不返回
    let sky: SkyStatus?
    /// 同上
    let brief: BriefSnapshot?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        apiVersion = try? container.decode(Int.self, forKey: .apiVersion)
        serverTime = try? container.decode(Date.self, forKey: .serverTime)
        generatedAt = try? container.decode(Date.self, forKey: .generatedAt)
        articles = (try? container.decode(FeedArticles.self, forKey: .articles)) ?? FeedArticles.empty
        notice = try? container.decode(FeedNotice.self, forKey: .notice)
        stats = try? container.decode(FeedStats.self, forKey: .stats)
        sky = try? container.decode(SkyStatus.self, forKey: .sky)
        brief = try? container.decode(BriefSnapshot.self, forKey: .brief)
    }

    /// 逐字段重建（`FeedPaging.merging` 用）。必须放在类型体内：
    /// extension 里的 init 不允许直接给 `let` 赋值，只能委派。
    init(
        ok: Bool,
        apiVersion: Int?,
        serverTime: Date?,
        generatedAt: Date?,
        articles: FeedArticles,
        notice: FeedNotice?,
        stats: FeedStats?,
        sky: SkyStatus?,
        brief: BriefSnapshot?
    ) {
        self.ok = ok
        self.apiVersion = apiVersion
        self.serverTime = serverTime
        self.generatedAt = generatedAt
        self.articles = articles
        self.notice = notice
        self.stats = stats
        self.sky = sky
        self.brief = brief
    }
}

/// 分页容器。`hasMore` 是 App **唯一**的分页依据；`total` 只用于展示，不得拿来算页码。
struct FeedArticles: Decodable {
    let pinned: [ArticleSummary]
    let items: [ArticleSummary]
    let page: Int
    let size: Int
    let total: Int
    let hasMore: Bool

    static let empty = FeedArticles(
        pinned: [],
        items: [],
        page: 1,
        size: 15,
        total: 0,
        hasMore: false
    )

    init(pinned: [ArticleSummary], items: [ArticleSummary], page: Int, size: Int, total: Int, hasMore: Bool) {
        self.pinned = pinned
        self.items = items
        self.page = page
        self.size = size
        self.total = total
        self.hasMore = hasMore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pinned = (try? container.decode([ArticleSummary].self, forKey: .pinned)) ?? []
        items = (try? container.decode([ArticleSummary].self, forKey: .items)) ?? []
        page = (try? container.decode(Int.self, forKey: .page)) ?? 1
        size = (try? container.decode(Int.self, forKey: .size)) ?? 15
        total = (try? container.decode(Int.self, forKey: .total)) ?? 0
        hasMore = (try? container.decode(Bool.self, forKey: .hasMore)) ?? false
    }
}

/// 列表项。真实响应**额外**带 `wordCount` / `readingMinutes`（服务端 `toSummary` 里算好的），
/// 设计文档没写但确实存在，这里一并收下，列表页可直接显示「约 N 分钟」。
struct ArticleSummary: Decodable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let announce: Bool
    let pinned: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let coverSeed: Int
    let wordCount: Int?
    let readingMinutes: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = (try? container.decode(String.self, forKey: .id)) ?? ""
        id = rawID
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        summary = (try? container.decode(String.self, forKey: .summary)) ?? ""
        announce = (try? container.decode(Bool.self, forKey: .announce)) ?? false
        pinned = (try? container.decode(Bool.self, forKey: .pinned)) ?? false
        createdAt = try? container.decode(Date.self, forKey: .createdAt)
        updatedAt = try? container.decode(Date.self, forKey: .updatedAt)
        wordCount = try? container.decode(Int.self, forKey: .wordCount)
        readingMinutes = try? container.decode(Int.self, forKey: .readingMinutes)
        // 服务端一定会算好 coverSeed；字段缺失时用同算法本地兜底，保证封面永远有渐变
        let decodedSeed = try? container.decode(Int.self, forKey: .coverSeed)
        coverSeed = decodedSeed ?? CoverSeed.value(for: rawID)
    }

    /// 用于「更新于 N 天前」等展示：优先更新 时间，退回创建时间
    var displayDate: Date? {
        if let updatedAt = updatedAt {
            return updatedAt
        }
        return createdAt
    }
}

/// 站点公告（当前最新一篇勾选公告的文章，只含摘要级字段）
struct FeedNotice: Decodable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let updatedAt: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        summary = (try? container.decode(String.self, forKey: .summary)) ?? ""
        updatedAt = try? container.decode(Date.self, forKey: .updatedAt)
    }
}

/// 访问统计（直读 KV，只读不自增；读不到时服务端给 null）
struct FeedStats: Decodable {
    let totalViews: Int?
    let todayVisitors: Int?
    let checkins: Int?
    let daysOnline: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalViews = try? container.decode(Int.self, forKey: .totalViews)
        todayVisitors = try? container.decode(Int.self, forKey: .todayVisitors)
        checkins = try? container.decode(Int.self, forKey: .checkins)
        daysOnline = try? container.decode(Int.self, forKey: .daysOnline)
    }
}

/// `coverSeed` 本地兜底：与服务端 `fnv1a(id) % 4` 同算法（0–3）。
///
/// 服务端（`blog/functions/api/app/[[path]].js` 的 `coverSeed`）一定会下发该字段，
/// 这里只是「字段缺失也别让封面失去身份」的保底。
/// 注意：服务端按 UTF-16 码元算，本实现按 UTF-8 字节算 —— 对 ASCII id 完全等价，
/// 非 ASCII id 只影响选哪组渐变，不影响任何正确性。
enum CoverSeed {
    static func value(for id: String) -> Int {
        var hash: UInt32 = 0x811c_9dc5
        for byte in id.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return Int(hash % 4)
    }
}
