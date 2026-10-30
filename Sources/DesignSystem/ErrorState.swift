import SwiftUI

/// 错误态（PRD §5.2）：图标 + 一句现象 + 一句出路 + 一个重试按钮。
///
/// 硬约束（PRD §7）：错误态**不清空**已显示内容 —— 是否展示本视图由调用方决定，
/// 本视图只负责长相与文案。
struct ErrorStateView: View {
    var icon: String = "wifi.slash"
    var title: String
    var message: String
    var retryTitle: String = "重新加载"
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.statusError.opacity(0.10))
                Circle()
                    .strokeBorder(Theme.statusError.opacity(0.30), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Theme.statusError)
            }
            .frame(width: 76, height: 76)

            VStack(spacing: 6) {
                Text(title)
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.5))
            }

            if let onRetry = onRetry {
                Button(action: {
                    Haptics.light()
                    onRetry()
                }) {
                    Text(retryTitle)
                }
                .buttonStyle(PrimaryCTAStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, Spacing.page)
    }
}

/// 顶部离线细条（PRD §5.2「离线（有缓存）」）：不遮内容，只提示「这是上次看到的」。
struct OfflineBanner: View {
    var text: String = "现在没网。先把上次看到的给你。"

    var body: some View {
        Text(text)
            .font(Typography.captionXS)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(.chrome, in: Capsule())
    }
}
