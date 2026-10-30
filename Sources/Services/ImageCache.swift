import SwiftUI
import Foundation

/// URLCache 统一配置 + 一个「零风险」的远程图片视图。
///
/// 图片策略（设计文档 §8.4）：
///   · 协议层：全局 `URLCache`（内存 20MB / 磁盘 200MB），接口 JSON 与图片字节共用
///   · 解码层：先用系统 `AsyncImage` —— 它自带 `URLCache` 命中，**不需要**我们自建 ImageLoader
///
/// 为什么先不自己写 ImageLoader：PRD 要求「图片按真实宽高比平滑过渡」，那需要 `UIImage.size`；
/// 但本批任务不做详情页，先把「零风险、能用」的一层做完，等 T07 真正需要宽高比时再补。
/// `AsyncImage` 是 iOS 15+ 的公开 API，签名简单，编译风险为零。
enum ImageCache {
    /// 在 App 启动、第一个请求之前调用（见 `FFWangApp.init`）。
    static func configure() {
        URLCache.shared = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
    }
}

/// 远程图片：占位态是深空渐变块（不是空白），失败态是渐变块 + `photo` 图标（PRD §5.2）。
struct RemoteImage<Placeholder: View>: View {
    private let url: URL?
    private let contentMode: ContentMode
    private let placeholder: () -> Placeholder

    init(
        urlString: String?,
        contentMode: ContentMode = .fit,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        if let urlString = urlString, !urlString.isEmpty {
            self.url = URL(string: urlString)
        } else {
            self.url = nil
        }
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failure:
                failedView
            case .empty:
                placeholder()
            default:
                placeholder()
            }
        }
    }

    private var failedView: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.bgElevated, Theme.bgBase],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                Text("图片没加载出来")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}
