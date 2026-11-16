import Foundation

/// 文章封面（服务端 `cover` 字段）。
///
/// 旧版 `/api/app/feed` 没有封面，App 只能用 `coverSeed` 画渐变；
/// 现在服务端会下发真实封面，App 优先显示它，为空时才退回渐变。
/// `width` / `height` 只是提示，缺了也不影响布局（16:9 由容器裁切决定）。
struct ArticleCover: Decodable, Equatable {
    let url: String
    let width: Int?
    let height: Int?

    /// 解码失败不抛错：封面只是锦上添花，不能拖垮整页。
    private enum CodingKeys: String, CodingKey {
        case url
        case width
        case height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = ((try? container.decode(String.self, forKey: .url)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        width = try? container.decode(Int.self, forKey: .width)
        height = try? container.decode(Int.self, forKey: .height)
    }

    /// 空串或非法地址一律当没有封面，交给渐变兜底。
    var imageURL: URL? {
        guard !url.isEmpty else { return nil }
        return URL(string: url)
    }
}
