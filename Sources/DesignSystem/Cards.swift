import SwiftUI

// MARK: - 卡片容器（层 3）

/// 玻璃卡片容器。所有内容卡（状态卡 / 简报卡 / 文章卡 / 版本双列卡）都套这一层。
///
/// 注意「同心圆角」规则（PRD §4.3）：卡内子元素圆角 = 卡片圆角 − 内间距，
/// 例如 24 − 16 = 8（见 `Radius.insideCard`）；封面出血到卡边则沿用 24。
struct GlassCard<Content: View>: View {
    var level: GlassLevel
    var cornerRadius: CGFloat
    var tint: Color?
    private let content: Content

    init(
        level: GlassLevel = .card,
        cornerRadius: CGFloat = Radius.card,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.level = level
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(
                level,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                tint: tint
            )
    }
}

/// 可点按的玻璃卡片：整卡可点 + 按压 0.97 + 轻触觉。
struct PressableGlassCard<Content: View>: View {
    var level: GlassLevel
    var cornerRadius: CGFloat
    var tint: Color?
    private let content: Content
    private let action: () -> Void

    init(
        level: GlassLevel = .card,
        cornerRadius: CGFloat = Radius.card,
        tint: Color? = nil,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.level = level
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            GlassCard(level: level, cornerRadius: cornerRadius, tint: tint) {
                content
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - 列表卡

/// 玻璃列表项（设置页 / 「查看版本记录 ›」这类单行入口）。
struct GlassListRow: View {
    let icon: String?
    let title: String
    var detail: String? = nil
    var showsChevron: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.lime)
                        .frame(width: 22, alignment: .center)
                }
                Text(title)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                if let detail = detail {
                    Text(detail)
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, Spacing.cardPadding)
            .frame(minHeight: Spacing.listItemMinHeight)
            .contentShape(Rectangle())
            .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - 状态胶囊

/// 光遇状态卡的四种状态（PRD §3.1 四态）。
///
/// **颜色铁律**：绿色只代表「有变化」。已是最新用中性灰 —— 否则满屏绿等于没有信号。
enum StatusPillKind {
    /// A 有新版本
    case newVersion
    /// B 已是最新
    case upToDate
    /// C 首次记录 / 未检查
    case pending
    /// D 检查失败
    case failed
}

/// 状态胶囊（右上角）
struct StatusPill: View {
    let kind: StatusPillKind
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.captionXS)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(background)
            }
            .overlay {
                Capsule().strokeBorder(border, lineWidth: 1)
            }
    }

    private var foreground: Color {
        switch kind {
        case .newVersion: return Theme.bgBase
        case .upToDate: return Theme.statusOk
        case .pending: return Theme.textTertiary
        case .failed: return Theme.statusError
        }
    }

    private var background: Color {
        switch kind {
        case .newVersion: return Theme.lime
        case .upToDate: return Color.white.opacity(0.06)
        case .pending: return Color.white.opacity(0.04)
        case .failed: return Theme.statusError.opacity(0.12)
        }
    }

    private var border: Color {
        switch kind {
        case .newVersion: return Color.white.opacity(0.20)
        case .upToDate: return Color.white.opacity(0.10)
        case .pending: return Color.white.opacity(0.08)
        case .failed: return Theme.statusError.opacity(0.35)
        }
    }
}
