import SwiftUI
import UserNotifications

/// 设置页「设备通知」组：只验证本机通知能力，不接远程推送、不触碰 Bark 链路。
///
/// 与 `AlertStore.deliver(_:)` 完全独立：这里只在用户主动点击时申请权限并投递本地
/// 测试通知（即时一条 / 60 秒延迟一条）；天气预警的授权时机与兜底顺序保持原样。
struct DeviceNotificationTestSection: View {
    @State private var authorizationText: String = "读取中…"
    @State private var isSending: Bool = false
    // 5.6.3：延迟通知按钮独立状态，避免和即时按钮的 isSending 互相干扰。
    @State private var isScheduling: Bool = false
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

            // 5.6.3：延迟通知测试。由系统按时间调度，App 划到后台/被杀掉后照样弹出，
            // 用来验证离线通知是否可用；loading 用独立的 isScheduling，不影响上面的即时按钮。
            Button {
                Task { await scheduleDelayedNotification() }
            } label: {
                HStack(spacing: 8) {
                    if isScheduling {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isScheduling ? "安排中…" : "60 秒后发送测试通知")
                }
            }
            .buttonStyle(PrimaryCTAStyle())
            .disabled(isScheduling)
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
            // 5.6.2：代理挂好后前台也会直接弹横幅+响铃（见 NotificationCenterDelegate），
            // 文案跟着改，避免用户还在等"通知中心里那一条"而以为没生效。
            inlineMessage = "测试通知已发送：前台会弹出横幅并响铃，也可在通知中心查看"
            Haptics.success()
        } catch {
            messageIsError = true
            inlineMessage = "发送失败：\(error.localizedDescription)"
            Haptics.error()
        }
        await refreshAuthorizationStatus()
    }

    /// 60 秒后投递的本地测试通知：由系统接管调度，把 App 划掉后台后仍会弹出。
    /// 只复用授权申请逻辑；状态、identifier 与即时按钮完全隔离，不碰预警与 Bark 链路。
    @MainActor
    private func scheduleDelayedNotification() async {
        isScheduling = true
        defer { isScheduling = false }

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
        content.title = "延迟通知测试"
        content.body = "60 秒到啦！即使 App 已划掉后台也能收到，说明离线通知可用 ✅"
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        // 唯一 identifier：前缀与即时通知不同，避免互相覆盖；Date() 保证连点不撞车。
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: "device-notification-delay-\(Date())",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            messageIsError = false
            // 明确告诉用户"划掉后台"就是在验证离线通知，避免用户以为必须停在 App 里等。
            inlineMessage = "已安排：60 秒后发送。现在可以把 App 划到后台，等通知弹出"
            Haptics.success()
        } catch {
            messageIsError = true
            inlineMessage = "安排失败：\(error.localizedDescription)"
            Haptics.error()
        }
        await refreshAuthorizationStatus()
    }

    /// iOS 15+ 额外申请 `.timeSensitive`；`.communication` 需额外 entitlement 且弹通知非必需，故不申请。低版本退回基础权限。
    @MainActor
    private func requestAuthorization(center: UNUserNotificationCenter) async -> Bool {
        do {
            if #available(iOS 15.0, *) {
                return try await center.requestAuthorization(
                    options: [.alert, .sound, .badge, .timeSensitive]
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
