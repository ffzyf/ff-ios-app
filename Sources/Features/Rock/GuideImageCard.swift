import SwiftUI

/// 攻略图片卡（4:3，P06）。
///
/// 三件事必须做对：
/// 1. **4:3 固定比例**（PRD P06）：图墙里每张卡同高，滚动时不会一张高一张矮。
///    服务端给了 `aspect` 也不用 —— 混排比例会让图墙变成"手风琴"；
/// 2. **`imageHairline` 1pt 描边**（PRD §3.4 第 3 条）：浅色模式下图片边缘与白底粘连，
///    这是"显廉价"的第一来源；
/// 3. **`matchedGeometryEffect` 做转场**：iOS 14 就有的 API，不依赖 iOS 26 才出现的那套
///    整屏缩放转场符号（本地无法编译验证新签名，写错就是 CI 红）。转场的 id 由调用方给（序号），
///    来源与目标必须用**同一个 Namespace + 同一个 id**。
struct GuideImageCard: View {
    let item: GuideItem
    /// 转场 id（同一份列表内稳定；用序号而不是 URL，重复 URL 也能正确配对）
    let transitionID: Int
    /// 由 `RockGuideView` 提供的命名空间
    let namespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                imageFrame
                if !item.title.isEmpty {
                    Text(item.title)
                        .font(Typography.footnoteMedium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityLabel(item.title.isEmpty ? "攻略图片" : item.title)
    }

    // MARK: - 图

    private var imageFrame: some View {
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder(icon: "photo", text: "图片没加载出来")
                    case .empty:
                        placeholder(icon: "photo", text: "")
                    default:
                        placeholder(icon: "photo", text: "")
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                    .strokeBorder(Theme.imageHairline, lineWidth: 1)
            }
            .matchedGeometryEffect(id: transitionID, in: namespace)
            .clipped()
    }

    private var imageURL: URL? {
        guard let raw = item.displayURL else { return nil }
        return URL(string: raw)
    }

    /// 占位与失败态都用同一块"深空/浅灰"底：不闪白、不闪空
    private func placeholder(icon: String, text: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [Theme.bgElevated, Theme.bgBase],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                if !text.isEmpty {
                    Text(text)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}
