import SwiftUI
import UIKit

/// 正文图片的下载与尺寸探测。
///
/// **为什么不用系统自带的异步图片视图**：它只给「成功/失败/空」三态，拿不到 `UIImage.size`，
/// 于是无法按真实宽高比预留高度 —— 结果是图片一加载完布局就跳一下（PRD P0-4 明确禁止）。
///
/// 这里自己拿字节再 `UIImage(data:)`：
/// 1. 网络走 `APIClient.shared.getData`（复用全局 `URLCache` 与 UA，不另起一套网络栈）；
/// 2. 拿到 `image.size` 算宽高比，**钳制在 0.6…2.0**；
/// 3. 比例变化只发生在「占位 → 加载完成」这一次，且由视图侧走 spring 动画。
///
/// 下限取 0.6 而不是设计文档的 0.5：正文栏宽约 353pt（393pt 机型减 40pt 边距），
/// 353 / 0.6 ≈ 588pt，正好压在「高度不超过屏高 70%（≈596pt）」这条 PRD 约束内，
/// 而且不需要在视图里读屏幕尺寸（少一次 GeometryReader，少一次布局抖动）。
@MainActor
final class InlineImageLoader: ObservableObject {

    enum Phase {
        case idle
        case loading
        case loaded(UIImage)
        case failed
    }

    /// 加载前的占位比例：16:10，与列表卡封面、详情 Hero 同一套视觉语言
    static let placeholderRatio: CGFloat = 1.6
    private static let minRatio: CGFloat = 0.6
    private static let maxRatio: CGFloat = 2.0

    @Published private(set) var phase: Phase = .idle
    /// 宽 / 高。占位固定 16:10，加载成功后过渡到真实比例。
    @Published private(set) var ratio: CGFloat = InlineImageLoader.placeholderRatio

    private var currentURL: URL?

    /// 下载并解析一张图。同一个 URL 已经加载成功 / 正在加载时直接返回，不重复下载。
    func load(_ url: URL) async {
        if currentURL == url {
            switch phase {
            case .loaded, .loading:
                return
            case .idle, .failed:
                break
            }
        }
        currentURL = url
        phase = .loading
        do {
            let data = try await APIClient.shared.getData(url)
            guard let image = UIImage(data: data), image.size.height > 0 else {
                phase = .failed
                return
            }
            ratio = clamp(image.size.width / image.size.height)
            phase = .loaded(image)
        } catch {
            // 不重试循环（PRD §7）：失败就是失败，用户点一下才重来
            phase = .failed
        }
    }

    /// 用户点「图片加载失败」占位块时的重试
    func retry(_ url: URL) async {
        currentURL = nil
        phase = .idle
        await load(url)
    }

    private func clamp(_ raw: CGFloat) -> CGFloat {
        guard raw.isFinite, raw > 0 else { return Self.placeholderRatio }
        return min(max(raw, Self.minRatio), Self.maxRatio)
    }
}
