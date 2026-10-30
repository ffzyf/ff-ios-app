import SwiftUI

/// 媒体块共用的「暗底提示条」：图片/视频的「不支持 http」「格式放不了」都长这样。
///
/// 抽出来的理由很实在：同一句话如果在两个块里各画一份，圆角、内距、图标字号
/// 迟早会漂成两套 —— 而这两条提示恰恰是用户唯一会盯着看几秒的失败态。
struct BlockNoticeRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(Typography.caption)
                .foregroundStyle(Theme.statusError)
            Text(text)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Spacing.smallCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                .fill(Theme.bgElevated)
        }
    }
}

/// 媒体块共用的占位块：按给定宽高比铺满整个栏宽，中间一枚图标 + 可选一行小字。
///
/// 关键点是**占位块任何时刻都有非零高度**（由 `aspectRatio` 决定），
/// 所以图片从「占位」切到「已加载」时只是高度平滑变化，不会出现 0↔N 的跳动。
struct MediaPlaceholder: View {
    let ratio: CGFloat
    var icon: String = "photo"
    var caption: String? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.inlineImage, style: .continuous)
            .fill(Theme.skeleton)
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(Typography.titleL)
                        .foregroundStyle(Theme.textTertiary)
                    if let caption = caption {
                        Text(caption)
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, Spacing.smallCardPadding)
            }
    }
}
