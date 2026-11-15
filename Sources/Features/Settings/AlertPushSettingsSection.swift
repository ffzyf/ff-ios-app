import SwiftUI

/// 设置页「天气预警推送」组（5.1.2 · R2 / AC2-3，架构 §1.2 / §3.4）。
///
/// 三项：总开关 / 最低级别 / 免打扰（含起止时刻）。
/// **配置真相源只有一个**：KV `alert_push_config`，App 只是 `GET` 读、`POST` 写，
/// 不在本地再存一份（Q3 / §7-7）。`GET` 匿名只读；`POST` 复用 `x-ai-token`
/// （`API.aiRequest` 是全模块唯一写这个头名的地方，零新增密钥、零新增 env）。
///
/// 取不到配置时保持默认值并把错误说清，**不写「未知」占位**；`POST` 失败保留用户
/// 刚改的值（下一点「保存」还能再试），不悄悄回滚成服务端旧值。
struct AlertPushSettingsSection: View {

    @State private var config = AlertPushConfig()
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @State private var savedHint: String? = nil

    init() {}

    var body: some View {
        VStack(spacing: 8) {
            enabledRow
            minLevelRow
            dndRow
            if config.dndEnabled {
                dndTimeRow
            }
            actionRow

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            if let savedHint = savedHint {
                Text(savedHint)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.limeInk)
                    .padding(.horizontal, 4)
            }

            Text("只对新增或升级的预警推送，解除不推；最低级别默认「黄色及以上」，免打扰默认关闭以免漏报。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)
        }
        .task {
            await load()
        }
        .task(id: savedHint) {
            guard savedHint != nil else { return }
            try? await Task.sleep(for: .seconds(1.8))
            savedHint = nil
        }
    }

    // MARK: - 三项设置

    private var enabledRow: some View {
        rowShell(icon: "bell.badge") {
            Text("天气预警推送")
                .font(Typography.callout)
                .foregroundStyle(Theme.textPrimary)
            Text("由服务端定时检测并差异推送，App 未启动也能送达")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
        } control: {
            Toggle("", isOn: $config.enabled)
                .labelsHidden()
                .tint(Theme.lime)
                .accessibilityLabel("天气预警推送")
        }
    }

    private var minLevelRow: some View {
        rowShell(icon: "flag") {
            Text("最低级别")
                .font(Typography.callout)
                .foregroundStyle(Theme.textPrimary)
            Text("低于这一级别的预警不推送")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
        } control: {
            Picker("最低级别", selection: $config.minLevel) {
                ForEach(Self.levels) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.textSecondary)
            .accessibilityLabel("最低级别")
        }
    }

    private var dndRow: some View {
        rowShell(icon: "moon.zzz") {
            Text("免打扰")
                .font(Typography.callout)
                .foregroundStyle(Theme.textPrimary)
            Text("开启后该时段内不推送，默认关闭")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
        } control: {
            Toggle("", isOn: $config.dndEnabled)
                .labelsHidden()
                .tint(Theme.lime)
                .accessibilityLabel("免打扰")
        }
    }

    private var dndTimeRow: some View {
        rowShell(icon: "clock") {
            Text("免打扰时段")
                .font(Typography.callout)
                .foregroundStyle(Theme.textPrimary)
            Text("北京时间 HH:mm，可跨零点，如 23:00 – 07:00")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
        } control: {
            HStack(spacing: 6) {
                timeField($config.dndStart)
                Text("–")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                timeField($config.dndEnd)
            }
        }
    }

    private func timeField(_ text: Binding<String>) -> some View {
        TextField("23:00", text: text)
            .font(Typography.captionXS)
            .foregroundStyle(Theme.textPrimary)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .frame(width: 54)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.glassStaticFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await save() }
            } label: {
                Text(isSaving ? "保存中…" : "保存")
            }
            .buttonStyle(PrimaryCTAStyle())
            .disabled(isLoading || isSaving)

            Button {
                Task { await load() }
            } label: {
                Text("重新读取")
            }
            .buttonStyle(SecondaryCTAStyle())
            .disabled(isLoading || isSaving)
        }
        .padding(.horizontal, 4)
    }

    private func rowShell<Label: View, Control: View>(
        icon: String,
        @ViewBuilder label: () -> Label,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                label()
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: Spacing.listItemMinHeight)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
    }

    // MARK: - 级别选项（四档中文 ↔ 后端 severity）

    private struct LevelOption: Identifiable {
        let value: String
        let label: String
        var id: String { value }
    }

    /// 与 `alert-push-core.js::levelRank` 的四色字典对齐：
    /// minor=蓝色及以上 / moderate=黄色及以上 / severe=橙色及以上 / extreme=仅红色。
    private static let levels: [LevelOption] = [
        LevelOption(value: "minor", label: "蓝色及以上"),
        LevelOption(value: "moderate", label: "黄色及以上"),
        LevelOption(value: "severe", label: "橙色及以上"),
        LevelOption(value: "extreme", label: "仅红色")
    ]

    // MARK: - 读写

    /// GET 匿名只读。响应全 `try?`：老后端 / KV 没写过时退回默认值，
    /// 并把「读取失败」说清 —— 不冒充「服务端就是这么配的」。
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let url = API.alertPushConfig() else {
            errorMessage = "接口地址不可用"
            return
        }
        do {
            let data = try await APIClient.shared.getData(url)
            guard let response = try? JSONDecoder().decode(ConfigResponse.self, from: data) else {
                errorMessage = "配置读取失败：响应格式不是预期对象"
                return
            }
            config = response.toConfig()
            errorMessage = nil
        } catch let error as APIError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "配置读取失败"
        }
    }

    /// POST 用 `x-ai-token`（`API.aiRequest`），body 只带三个字段。
    private func save() async {
        if config.dndEnabled,
           !isValidTime(config.dndStart) || !isValidTime(config.dndEnd) {
            errorMessage = "免打扰时间要写成 23:00 这种 HH:mm"
            return
        }
        isSaving = true
        defer { isSaving = false }
        guard let url = API.alertPushConfig(),
              let body = try? JSONEncoder().encode(config.toBody()) else {
            errorMessage = "保存失败：请求没能编码"
            return
        }
        let request = API.aiRequest(
            url: url,
            method: "POST",
            token: AIKeychain.token(),
            body: body
        )
        do {
            let raw = try await APIClient.shared.send(request)
            guard raw.isSuccess else {
                errorMessage = "保存失败（HTTP \(raw.statusCode)）"
                return
            }
            errorMessage = nil
            savedHint = "已保存"
            Haptics.success()
        } catch let error as APIError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "保存失败"
        }
    }

    private func isValidTime(_ raw: String) -> Bool {
        let parts = raw.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return false }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }
}

// MARK: - 本地值类型（只在设置页内存，不落盘）

private struct AlertPushConfig: Equatable {
    var enabled: Bool = true
    var minLevel: String = "moderate"
    var dndEnabled: Bool = false
    var dndStart: String = "23:00"
    var dndEnd: String = "07:00"
}

private struct ConfigResponse: Decodable {
    let config: Payload?

    struct Payload: Decodable {
        let enabled: Bool?
        let minLevel: String?
        let dnd: DND?

        struct DND: Decodable {
            let enabled: Bool?
            let start: String?
            let end: String?
        }
    }

    func toConfig() -> AlertPushConfig {
        var result = AlertPushConfig()
        if let enabled = config?.enabled { result.enabled = enabled }
        if let minLevel = config?.minLevel, !minLevel.isEmpty { result.minLevel = minLevel }
        if let dnd = config?.dnd {
            if let enabled = dnd.enabled { result.dndEnabled = enabled }
            if let start = dnd.start, !start.isEmpty { result.dndStart = start }
            if let end = dnd.end, !end.isEmpty { result.dndEnd = end }
        }
        return result
    }
}

private struct ConfigBody: Encodable {
    let enabled: Bool
    let minLevel: String
    let dnd: DND

    struct DND: Encodable {
        let enabled: Bool
        let start: String
        let end: String
    }
}

private extension AlertPushConfig {
    func toBody() -> ConfigBody {
        return ConfigBody(
            enabled: enabled,
            minLevel: minLevel,
            dnd: ConfigBody.DND(
                enabled: dndEnabled,
                start: dndStart,
                end: dndEnd
            )
        )
    }
}
