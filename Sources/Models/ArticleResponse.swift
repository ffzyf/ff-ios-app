import Foundation

/// `GET /api/app/article?id=<id>`（博客站）的响应。
///
/// 真实字段以已部署实现为准（`blog/functions/api/app/[[path]].js` 的 `handleArticle`）：
/// 服务端把 `content` 解析成块后**不再回传原文**（避免双倍体积），
/// 也不返回 `status` / `hidden`（内部字段不外泄）。
struct ArticleResponse: Decodable {
    let ok: Bool
    let apiVersion: Int?
    let serverTime: Date?
    let article: ArticleDetail?

    /// 手写 `init(from:)` 后编译器不再自动合成 `CodingKeys`，必须显式声明。
    /// 服务端键名与属性名逐字一致（camelCase），故无需写 rawValue。
    private enum CodingKeys: String, CodingKey {
        case ok
        case apiVersion
        case serverTime
        case article
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        apiVersion = try? container.decode(Int.self, forKey: .apiVersion)
        serverTime = try? container.decode(Date.self, forKey: .serverTime)
        article = try? container.decode(ArticleDetail.self, forKey: .article)
    }
}

/// 文章详情。
///
/// `blocksTruncated` / `omittedBlocks` 是服务端的体积保护（单篇 ≤180KB）：
/// 超出时从头保留块直到预算用尽，App 在文末提示「内容过长，已省略 N 段」。
struct ArticleDetail: Decodable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let announce: Bool
    let pinned: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let wordCount: Int
    let readingMinutes: Int
    let coverSeed: Int
    let blocks: [Block]
    let blockCount: Int
    let blocksTruncated: Bool
    let omittedBlocks: Int

    /// 手写 `init(from:)` 后编译器不再自动合成 `CodingKeys`，必须显式声明。
    /// 只列存储属性；计算属性 `wordCountText` 不属于解码契约，不得放进来。
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case announce
        case pinned
        case createdAt
        case updatedAt
        case wordCount
        case readingMinutes
        case coverSeed
        case blocks
        case blockCount
        case blocksTruncated
        case omittedBlocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = (try? container.decode(String.self, forKey: .id)) ?? ""
        id = rawID
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        // 与 ArticleSummary 一致：脏摘要服务端洗成空串，这里再去一次首尾空白
        summary = ((try? container.decode(String.self, forKey: .summary)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        announce = (try? container.decode(Bool.self, forKey: .announce)) ?? false
        pinned = (try? container.decode(Bool.self, forKey: .pinned)) ?? false
        createdAt = try? container.decode(Date.self, forKey: .createdAt)
        updatedAt = try? container.decode(Date.self, forKey: .updatedAt)
        wordCount = (try? container.decode(Int.self, forKey: .wordCount)) ?? 0
        readingMinutes = (try? container.decode(Int.self, forKey: .readingMinutes)) ?? 1
        let decodedSeed = try? container.decode(Int.self, forKey: .coverSeed)
        coverSeed = decodedSeed ?? CoverSeed.value(for: rawID)
        blocks = (try? container.decode([Block].self, forKey: .blocks)) ?? []
        blockCount = (try? container.decode(Int.self, forKey: .blockCount)) ?? blocks.count
        blocksTruncated = (try? container.decode(Bool.self, forKey: .blocksTruncated)) ?? false
        omittedBlocks = (try? container.decode(Int.self, forKey: .omittedBlocks)) ?? 0
    }

    /// 元信息行用：`10月28日 发布 · 1,284 字 · 约 4 分钟`
    var wordCountText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        let text = formatter.string(from: NSNumber(value: wordCount)) ?? "\(wordCount)"
        return "\(text) 字"
    }
}
