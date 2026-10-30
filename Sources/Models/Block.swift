import Foundation

/// 正文块协议（设计文档 §4.2）。
///
/// 服务端（`blog/functions/_lib/md-blocks.js`）把 Markdown 解析成这 8 种块，**不再返回原始 content**。
/// 字段名与服务端逐字一致：`paragraph.text` / `heading.level+text` / `image.url+alt` /
/// `video.url+poster` / `code.lang+text` / `quote.text` / `list.ordered+items` / `divider`（无字段）。
///
/// 前向兼容铁律：**未知 `type` 必须降级成 `.unknown`，绝不 throw**。
/// 否则服务端以后加一种块类型，老版本 App 整页白屏。
enum Block: Decodable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case image(url: String, alt: String?)
    case video(url: String)
    case code(lang: String?, text: String)
    case quote(String)
    case list(ordered: Bool, items: [String])
    case divider
    /// 服务端新增但本版本还不认识的块（渲染层直接跳过）
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case level
        case url
        case alt
        case lang
        case ordered
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? ""

        switch type {
        case "paragraph":
            let text = (try? container.decode(String.self, forKey: .text)) ?? ""
            self = .paragraph(text)

        case "heading":
            let level = (try? container.decode(Int.self, forKey: .level)) ?? 2
            let text = (try? container.decode(String.self, forKey: .text)) ?? ""
            self = .heading(level: level, text: text)

        case "image":
            let url = (try? container.decode(String.self, forKey: .url)) ?? ""
            let alt = try? container.decode(String.self, forKey: .alt)
            self = .image(url: url, alt: alt)

        case "video":
            let url = (try? container.decode(String.self, forKey: .url)) ?? ""
            // poster 恒为 null（服务端首帧由 App 用 AVAssetImageGenerator 自己取），本版本忽略
            self = .video(url: url)

        case "code":
            let lang = try? container.decode(String.self, forKey: .lang)
            let text = (try? container.decode(String.self, forKey: .text)) ?? ""
            self = .code(lang: lang, text: text)

        case "quote":
            let text = (try? container.decode(String.self, forKey: .text)) ?? ""
            self = .quote(text)

        case "list":
            let ordered = (try? container.decode(Bool.self, forKey: .ordered)) ?? false
            let items = (try? container.decode([String].self, forKey: .items)) ?? []
            self = .list(ordered: ordered, items: items)

        case "divider":
            self = .divider

        default:
            self = .unknown
        }
    }
}
