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

// 说明：`OfflineBanner` 已移到 `Sources/DesignSystem/OfflineBanner.swift`（批次 1 双主题改造，
// 从"一行灰字"扩成离线 / 可能过期 / 部分失败三态）。这里刻意不再保留第二份定义，
// 否则同名 `struct` 在同一 target 内会直接编译失败。
