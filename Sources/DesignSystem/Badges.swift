import SwiftUI

// MARK: - 徽标（三种标记不可混用同一套样式，PRD §3.2）

enum BadgeKind {
    /// 公告：实心 #D4F36E，字 #0A0D14，12pt
    case announce
    /// 置顶：透明底 + 青柠 60% 描边 + 青柠字
    case pinned
    /// NEW：青柠实心 + 深字
    case newVersion
    /// 中性（「更新于 N 天前」这类语义徽标）
    case neutral
}

struct BadgePill: View {
    let kind: BadgeKind
    let text: String

    var body: some View {
        Text(text)
            .font(kind == .announce ? Typography.caption : Typography.captionXS)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background { backgroundShape }
            .overlay { borderShape }
    }

    /// 公告是 6pt 小圆角，置顶 / NEW / 中性是胶囊。
    /// 这里用两个 `@ViewBuilder` 分支而不是 `AnyShape`：`strokeBorder` 需要 `InsettableShape`，
    /// 而 `AnyShape` 只是 `Shape`，混用会编译不过。
    @ViewBuilder
    private var backgroundShape: some View {
        if kind == .announce {
            RoundedRectangle(cornerRadius: Radius.badge, style: .continuous)
                .fill(background)
        } else {
            Capsule()
                .fill(background)
        }
    }

    @ViewBuilder
    private var borderShape: some View {
        if kind == .announce {
            RoundedRectangle(cornerRadius: Radius.badge, style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        } else {
            Capsule()
                .strokeBorder(border, lineWidth: 1)
        }
    }

    /// 字色。青柠底的两种徽标（公告 / NEW）统一走 `onLime`（PRD §3.2「面上字」）：
    /// 深色 `#0A0D14` 与 V2 的 `bgBase` 是同一个值 → 深色零变化；浅色 `#0F2410`，5.4:1。
    private var foreground: Color {
        switch kind {
        case .announce: return Theme.onLime
        case .pinned: return Theme.limeInk
        case .newVersion: return Theme.onLime
        case .neutral: return Theme.textTertiary
        }
    }

    private var background: Color {
        switch kind {
        case .announce: return Theme.limeBright
        case .pinned: return Color.clear
        case .newVersion: return Theme.lime
        case .neutral: return Theme.surfaceTint3
        }
    }

    private var border: Color {
        switch kind {
        case .announce: return Color.clear
        // 置顶徽标的描边是「青柠色的线」→ 跟着字色走 limeInk（深色 60% 与 V2 完全一致）
        case .pinned: return Theme.limeInk.opacity(0.60)
        case .newVersion: return Theme.glassStrokeTop
        case .neutral: return Theme.surfaceTint4
        }
    }
}

// MARK: - 快捷入口（3 枚玻璃胶囊，相邻玻璃交给 GlassGroup）

struct QuickEntry: Identifiable {
    let id: Int
    let title: String
    let icon: String?
}

struct QuickEntryRow: View {
    let entries: [QuickEntry]
    let onSelect: (QuickEntry) -> Void

    var body: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(entries) { entry in
                    CapsuleGlassButton(title: entry.title, icon: entry.icon) {
                        onSelect(entry)
                    }
                }
            }
        }
    }
}
