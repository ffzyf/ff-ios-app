import SwiftUI
import UIKit

/// 正文图片块（PRD §3.3 image 行）。
///
/// 五条硬要求，逐条对应实现：
/// 1. **不用系统自带的异步图片视图**：走 `InlineImageLoader` 拿 `UIImage.size` 算真实宽高比；
/// 2. **任何时刻都有非零高度**：加载前 16:10 占位块，成功后 spring 过渡到真实比例
///    （`Motion.imageResize` = 0.35s / damping 0.9），不会出现 0↔N 的布局跳动；
/// 3. **`http://` 不发请求**：ATS 必拦，直接给一句「不支持 http 图片」；
/// 4. 失败给可点重试的占位块（不自动重试循环，PRD §7）；
/// 5. 圆角 `Radius.inlineImage`，点开进全屏查看。
struct ImageBlock: View {
    let url: String
    let alt: String?

    @StateObject private var loader = InlineImageLoader()
    @State private var showsViewer: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if let caption = captionText {
                Text(caption)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: url) {
            guard let target = secureURL else { return }
            await loader.load(target)
        }
        .fullScreenCover(isPresented: $showsViewer) {
            if case .loaded(let image) = loader.phase {
                ImageViewer(image: image)
            }
        }
    }

    // MARK: - 三种状态

    @ViewBuilder
    private var content: some View {
        if trimmedURL.isEmpty {
            EmptyView()
        } else if secureURL == nil {
            BlockNoticeRow(icon: "exclamationmark.triangle", text: "不支持 http 图片")
        } else {
            switch loader.phase {
            case .idle, .loading:
                MediaPlaceholder(ratio: InlineImageLoader.placeholderRatio)
            case .loaded(let image):
                loadedImage(image)
            case .failed:
                retryBlock
            }
        }
    }

    /// 加载成功：容器比例 = 真实宽高比，图片填满容器（比例已对齐，fill 等价于 fit）
    private func loadedImage(_ image: UIImage) -> some View {
        Button(action: {
            Haptics.light()
            showsViewer = true
        }) {
            Color.clear
                .aspectRatio(loader.ratio, contentMode: .fit)
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.inlineImage, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Radius.inlineImage, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(captionText ?? "文章图片")
        // 比例只在「占位 → 成功」时变一次，这一行就是那次平滑过渡
        .animation(Motion.imageResize, value: loader.ratio)
    }

    /// 加载失败：仍是占位块尺寸（版面不跳），整块可点重试
    private var retryBlock: some View {
        Button(action: {
            guard let target = secureURL else { return }
            Haptics.light()
            Task { await loader.retry(target) }
        }) {
            MediaPlaceholder(
                ratio: InlineImageLoader.placeholderRatio,
                caption: "图片没加载出来，点一下再试"
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 派生数据

    private var trimmedURL: String {
        return url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 只认 https（不写协议字面量：从 scheme 判断，全工程唯一的协议前缀在 `API.swift`）
    private var secureURL: URL? {
        guard let parsed = URL(string: trimmedURL) else { return nil }
        guard parsed.scheme?.lowercased() == "https" else { return nil }
        return parsed
    }

    /// `alt` 即图注；空串 / 纯空白视为没有
    private var captionText: String? {
        guard let alt = alt else { return nil }
        let trimmed = alt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
