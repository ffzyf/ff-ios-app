import SwiftUI

/// Composer 上方的「能力 chip」行（5.1.2 · R4c 交互骨架，架构 §1.4 / §1.5.1）。
///
/// 本期只透传**一个**能力：联网搜索（Q6）。R4d 明确不做，所以这里
/// **不放任何占位 chip**（PRD 设计稿画过灰色的空壳，按「不渲染空壳」本期不画）。
///
/// 判定一律来自 `AIChatStore` 的 `@Published`：
/// · `searchCapability` 来自 `GET /api/ai/models` 的 `capabilities.webSearch`；
/// · 总闸 `enabled != true` 时 chip **置灰并给出 `reason`**，且不是 Button
///   （同 `AIModelPickerSheet` 对不可用项的处置：不给「点一下没反应」的假控件）；
/// · 点按只调 `setSearchEnabled(_:)`，「钳回 false / 按会话记忆」都在 Store 里，
///   View 不自己重算语义，也不碰 UserDefaults。
struct AIChatCapabilityBar: View {

    @ObservedObject private var chat = AIChatStore.shared

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            searchChip
            if let note = capabilityNote {
                Text(note)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.page)
        // 与 Composer 之间只留 2pt：能力行是「输入框的上一行」，不是一块独立卡片
        .padding(.bottom, 2)
    }

    // MARK: - 派生（只读 Store，不判定）

    private var capabilityEnabled: Bool {
        return chat.searchCapability?.enabled == true
    }

    /// 总闸关时的置灰说明（AC4-2）。开了就不占第二行。
    /// reason 是后端写的人话；空值给一句兜底，不编造「云端已支持」。
    private var capabilityNote: String? {
        guard !capabilityEnabled else { return nil }
        let reason = chat.searchCapability?.reason
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reason.isEmpty ? "联网搜索暂不可用" : reason
    }

    // MARK: - chip

    @ViewBuilder
    private var searchChip: some View {
        if capabilityEnabled {
            Button {
                Haptics.selection()
                chat.setSearchEnabled(!chat.searchEnabled)
            } label: {
                chipLabel
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(chipAccessibilityLabel)
        } else {
            // 不可用 = 一个纯 View，不给 Button：VoiceOver 不会聚焦到一个按不动的控件
            chipLabel
                .opacity(0.45)
                .accessibilityLabel("联网搜索暂不可用")
        }
    }

    private var chipLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "globe")
                .font(.system(size: 11, weight: .semibold))
            Text("联网搜索")
                .font(Typography.footnoteMedium)
        }
        .foregroundStyle(chipTextColor)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background {
            Capsule().fill(chipFill)
        }
        .overlay {
            Capsule().strokeBorder(Theme.divider, lineWidth: 1)
        }
        .contentShape(Capsule())
    }

    /// 选中：青柠底 + onLime 字；未选中：静态玻璃底 + divider 描边（架构 §7-4）
    private var chipFill: Color {
        return (chat.searchEnabled && capabilityEnabled) ? Theme.lime : Theme.glassStaticFill
    }

    private var chipTextColor: Color {
        return (chat.searchEnabled && capabilityEnabled) ? Theme.onLime : Theme.textSecondary
    }

    private var chipAccessibilityLabel: String {
        return chat.searchEnabled ? "联网搜索已开启，点按关闭" : "联网搜索已关闭，点按开启"
    }
}
