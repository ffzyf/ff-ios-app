import SwiftUI
import UserNotifications

/// 设置页「设备通知」组：只验证本机通知能力，不接远程推送、不触碰 Bark 链路。
///
/// 与 `AlertStore.deliver(_:)` 完全独立：这里只在用户主动点击时申请权限并投递一条
/// 本地测试通知；天气预警的授权时机与兜底顺序保持原样。
struct DeviceNotificationTestSection: View {
    @State private var authorizationText: String = "读取中…"
    @State private var isSending: Bool = false
    @State private var inlineMessage: String?
    @State private var messageIsError: Bool = false

    init() {}

    var body: some View {
        VStack(spacing: 8) {
            statusRow

            Button {
                Task { await sendTestNotification() }
            } label: {
                HStack(spacing: 8) {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isSending ? "发送中…" : "发送测试通知")
                }
            }
            .buttonStyle(PrimaryCTAStyle())
            .disabled(isSending)
            .padding(.horizontal, 4)

            if let inlineMessage = inlineMessage {
                Text(inlineMessage)
                    .font(Typography.captionXS)
                    .foregroundStyle(messageIsError ? Theme.textPrimary : Theme.limeInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            Text("此功能用于测试设备通知能力；无需网络，通知在本机弹出。若权限被拒绝，请到系统设置中允许通知。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .task {
            await refreshAuthorizationStatus()
        }
    }

    // MARK: - UI

    private var statusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.limeInk)
                .frame(width: 22, alignment: .center)

            Text("授权状态")
                .font(Typography.callout)
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 8)

            Text(authorizationText)
                .font(Typography.footnote)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, Spacing.cardPadding)
        .frame(minHeight: Spacing.listItemMinHeight)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
    }

    // MARK: - 动作

    @MainActor
    private func sendTestNotification() async {
        isSending = true
        defer { isSending = false }

        let center = UNUserNotificationCenter.current()
        let granted = await requestAuthorization(center: center)

        guard granted else {
            await refreshAuthorizationStatus()
            messageIsError = true
            inlineMessage = "通知权限被拒绝，请到系统设置开启"
            Haptics.error()
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "设备通知测试"
        content.body = "如果你看到这条通知，说明设备通知可用 ✅"
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let request = UNNotificationRequest(
            identifier: "device-notification-test-\(Date())",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            messageIsError = false
            inlineMessage = "测试通知已发送，请查看通知中心"
            Haptics.success()
        } catch {
            messageIsError = true
            inlineMessage = "发送失败：\(error.localizedDescription)"
            Haptics.error()
        }
        await refreshAuthorizationStatus()
    }

    /// iOS 15+ 额外申请 `.timeSensitive` / `.communication`；低版本退回基础权限。
    @MainActor
    private func requestAuthorization(center: UNUserNotificationCenter) async -> Bool {
        do {
            if #available(iOS 15.0, *) {
                return try await center.requestAuthorization(
                    options: [.alert, .sound, .badge, .timeSensitive, .communication]
                )
            }
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    @MainActor
    private func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationText = Self.authorizationLabel(settings.authorizationStatus)
    }

    // MARK: - 状态文案

    private static func authorizationLabel(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "未请求"
        case .denied:
            return "已拒绝"
        case .authorized:
            return "已授权"
        case .provisional:
            return "临时授权"
        case .ephemeral:
            return "本次安装有效"
        @unknown default:
            return "未知状态"
        }
    }
}
