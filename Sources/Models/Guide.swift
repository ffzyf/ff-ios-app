import Foundation

/// `GET /api/app/guide` 的响应（攻略图文流）。
///
/// 时间字段 `builtAt` 保持 `String`：契约里它是 ISO 字符串且**可能缺失**，
/// 而 App 只用它显示「缓存 24 小时」，不做时间运算 —— 转 `Date` 只会多一个失败点（§7.1）。
struct GuideResponse: Codable, Sendable {
    let ok: Bool
    let apiVersion: Int?
    let builtAt: String?
    let ttlSec: Int
    /// 是否有源拉取失败（用于顶部「部分内容没拉到」）
    let partial: Bool
    let sources: [GuideSource]
    let items: [GuideItem]

    private enum CodingKeys: String, CodingKey {
        case ok
        case apiVersion
        case builtAt
        case ttlSec
        case partial
        case sources
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        apiVersion = try? container.decode(Int.self, forKey: .apiVersion)
        builtAt = try? container.decode(String.self, forKey: .builtAt)
        ttlSec = (try? container.decode(Int.self, forKey: .ttlSec)) ?? 0
        partial = (try? container.decode(Bool.self, forKey: .partial)) ?? false
        sources = (try? container.decode([GuideSource].self, forKey: .sources)) ?? []
        items = (try? container.decode([GuideItem].self, forKey: .items)) ?? []
    }

    init(
        ok: Bool,
        apiVersion: Int?,
        builtAt: String?,
        ttlSec: Int,
        partial: Bool,
        sources: [GuideSource],
        items: [GuideItem]
    ) {
        self.ok = ok
        self.apiVersion = apiVersion
        self.builtAt = builtAt
        self.ttlSec = ttlSec
        self.partial = partial
        self.sources = sources
        self.items = items
    }
}

/// 一个攻略源的状态（只用于「部分失败」提示，不展示给用户看域名）
struct GuideSource: Codable, Sendable, Identifiable, Equatable {
    let url: String
    let ok: Bool
    let count: Int
    let error: String?

    var id: String { url }

    private enum CodingKeys: String, CodingKey {
        case url
        case ok
        case count
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = (try? container.decode(String.self, forKey: .url)) ?? ""
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        count = (try? container.decode(Int.self, forKey: .count)) ?? 0
        error = try? container.decode(String.self, forKey: .error)
    }

    init(url: String, ok: Bool, count: Int, error: String?) {
        self.url = url
        self.ok = ok
        self.count = count
        self.error = error
    }
}

/// 一条攻略条目：图片或文字。
///
/// 刻意**不实现 `Identifiable`**：同一条文字可能被多个源返回两次，`url` / `content` 都不是天然主键。
/// 列表侧用 `enumerated + id: \.offset`（同一份响应内稳定），转场用的 key 也是序号 —— 比编一个假 id 诚实。
struct GuideItem: Codable, Sendable, Equatable {
    /// `"img"` | `"text"`
    let type: String
    /// 原始图片地址（`type == "img"` 时非空）
    let url: String?
    /// 站内图代理地址（**返回图片二进制**，见 §2.4 的批次 2 修正）
    let thumbUrl: String?
    let title: String
    /// 服务端算出的宽高比；nil 时用 4:3（PRD P06）
    let aspect: Double?
    let content: String?

    var isImage: Bool { type == "img" }

    /// 列表里真正要加载的地址：优先走站内代理（外部图床可能防盗链）
    var displayURL: String? {
        if let thumb = thumbUrl, !thumb.isEmpty { return thumb }
        if let raw = url, !raw.isEmpty { return raw }
        return nil
    }

    /// 宽高比兜底：服务端算不出就给 4:3，绝不是 0（0 会让 `aspectRatio` 布局塌掉）
    var displayAspect: Double {
        guard let aspect = aspect, aspect.isFinite, aspect > 0.1 else { return 4.0 / 3.0 }
        return aspect
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case url
        case thumbUrl
        case title
        case aspect
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? "text"
        url = try? container.decode(String.self, forKey: .url)
        thumbUrl = try? container.decode(String.self, forKey: .thumbUrl)
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        aspect = try? container.decode(Double.self, forKey: .aspect)
        content = try? container.decode(String.self, forKey: .content)
    }

    init(type: String, url: String?, thumbUrl: String?, title: String, aspect: Double?, content: String?) {
        self.type = type
        self.url = url
        self.thumbUrl = thumbUrl
        self.title = title
        self.aspect = aspect
        self.content = content
    }
}
