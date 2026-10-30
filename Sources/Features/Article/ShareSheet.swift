import SwiftUI
import UIKit

/// 系统分享面板（`UIActivityViewController` 包一层）。
///
/// 为什么用 `UIViewControllerRepresentable` 而不是 `ShareLink`：`ShareLink` 在 iOS 16+
/// 可用，但它把 items 绑定在按钮上，而详情页的分享钮是**玻璃圆钮**（层 2 浮层），
/// 用 `ShareLink` 会把按钮样式锁进系统控件。这里只包一层，按钮仍由 `IconGlassButton` 提供。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // 分享内容在创建时就定好，不需要更新
    }
}

extension ShareSheet {
    /// 分享内容：标题 + 文章链接。标题为空时只分享链接，避免出现一个空字符串气泡。
    static func items(title: String, articleID: String) -> [Any] {
        var items: [Any] = []
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(trimmed)
        }
        if let url = link(articleID: articleID) {
            items.append(url)
        }
        return items
    }

    /// 文章链接：域名一律取 `API.blogHost`（全工程唯一 URL 常量来源，页面里不写协议字面量）。
    ///
    /// 已知限制：主站是单页应用，目前没有「文章级深链」（`openPost(id)` 只在内存里切视图），
    /// 所以现在点开这条链接会落在站点首页；`article` 查询参数先留着，
    /// 后端补深链后这条链接自动生效，不用再改客户端。
    static func link(articleID: String) -> URL? {
        guard var components = URLComponents(string: API.blogHost) else { return nil }
        components.queryItems = [URLQueryItem(name: "article", value: articleID)]
        return components.url
    }
}
