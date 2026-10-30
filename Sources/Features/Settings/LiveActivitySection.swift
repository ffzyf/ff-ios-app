import SwiftUI

/// 设置页的「红石」组（PRD P14 第 ② 项）。
///
/// 一个开关 + 两句说明：
/// · 开关落盘用 `@AppStorage`（键名与 `LiveActivityCoordinator` 共用一个常量，
///   避免"设置里关了、Coordinator 还在读旧值"这种最难查的分歧）；
/// · 关掉时立刻 `endAll()`，不等下一次评估 —— 用户关了就该马上从锁屏消失。
///
/// 为什么不做「跳系统设置」按钮：`UIApplication.openSettingsURLString` 打开的是**本 App** 的设置页，
/// 而实时活动/小组件的总开关在"设置 → 通知"与"长按桌面"里，跳过去也未必直达，
/// 写一个跳不到地方的按钮比写一句话更糟。
struct LiveActivitySection: View {

    /// 与 `SunEventSettings.storageKey` 同一个键；默认开启
    @AppStorage(SunEventSettings.storageKey) private var isEnabled: Bool = true

    /// 显式空 init：`@AppStorage` 是 private 存储属性，避免 memberwise init 被降级
    init() {}

    var body: some View {
        VStack(spacing: 8) {
            toggleRow

            Text("开启后，场次落地前 20 分钟会在锁屏与灵动岛出现倒计时，落地后 52 分钟自动消失。22:30 之后的场次不提醒。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)

            Text("桌面小组件在桌面长按 → 编辑 → 添加，与这个开关无关，随时可用。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)
        }
    }

    // MARK: - 开关行

    private var toggleRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isEnabled ? Theme.limeInk : Theme.textTertiary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("红石实时活动")
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                Text("锁屏与灵动岛显示下一场倒计时")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .tint(Theme.lime)
                .accessibilityLabel("红石实时活动")
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: Spacing.listItemMinHeight)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
        .onChange(of: isEnabled) { _, newValue in
            Haptics.light()
            if !newValue {
                // 关掉即收尾：不等下一次 60 秒评估
                LiveActivityCoordinator.shared.endAll()
            }
        }
    }
}
