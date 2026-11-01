import SwiftUI

/// 设置页里「不是列表行」的内容：顶部 toast。
///
/// 3.10.0 起本文件只剩 toast 一件东西：原「关于卡」（`SettingsAboutCard`）与
/// 页脚署名（`SettingsFooterLine`）是**只读的说明性内容**，已按"设置只留可操作项"
/// 的原则整体挪到「更多 → 关于」（`MoreAboutSheet`，原句未改地合并进「边界说明」组）——
/// 同一句话在两处各写一份，迟早有一份过期，所以是**搬走并删除**，不是留着不用。

/// 顶部轻提示（复制成功 / 缓存已清空）。1.8s 自动消失，不打断操作。
struct SettingsToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.captionXS)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassSurface(.floating, in: Capsule())
            .padding(.top, 8)
            .transition(.opacity)
            .accessibilityAddTraits(.isStaticText)
    }
}
