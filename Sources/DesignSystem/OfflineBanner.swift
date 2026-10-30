import SwiftUI
import Foundation

/// 顶部细条的三态（PRD §5.2 的三种"不是错误但要说一句"的情况）。
///
/// 为什么分成三档而不是一个 `String`：三种情况的**分量不同** ——
/// 「现在没网」只是陈述事实（用次级文字色，不加图标，V2 就是这样）；
/// 「数据可能过期」「部分内容没拉到」是**可信度下降**，必须用警示色 + 图标，
/// 否则用户会以为看到的是最新的。
enum OfflineBannerKind {
    /// 没网，内容来自缓存
    case offline
    /// 有网但数据老了（红石日程超 7 天）
    case staleData
    /// 部分数据源失败（攻略多源聚合只成了一部分）
    case partialFailure

    /// 默认文案。`text` 传值时以调用方为准（例如带"N 天前"的动态文案）。
    var defaultText: String {
        switch self {
        case .offline: return "现在没网。先把上次看到的给你。"
        case .staleData: return "数据可能过期，先按上次看到的看。"
        case .partialFailure: return "部分内容没拉到，已显示缓存。"
        }
    }

    /// 图标：`.offline` 刻意**不加图标** —— 这一档要与 V2 逐像素一致（V2 就是一行字）。
    var icon: String? {
        switch self {
        case .offline: return nil
        case .staleData: return "clock.badge.exclamationmark"
        case .partialFailure: return "exclamationmark.triangle"
        }
    }

    /// 文字色：只有"可信度下降"才用警示色。`statusWarn` 浅色是 `#8A5B00`（4.9:1），
    /// 深色仍是 `#FFC24B` —— 这条也是"深色零变化"的一部分。
    var foreground: Color {
        switch self {
        case .offline: return Theme.textSecondary
        case .staleData, .partialFailure: return Theme.statusWarn
        }
    }
}

/// 顶部「离线 / 可能过期 / 部分失败」细条。
///
/// 用法（批次 2 接线）：挂在页面的 `safeAreaInset(edge: .top)`，占用自己的高度，
/// 不压内容、不遮标题。**本批只做组件，不接线** —— 现有调用点（概览 / 文章列表）
/// 保持 `OfflineBanner()` 的无参形式，外观与 V2 完全一致。
struct OfflineBanner: View {
    var kind: OfflineBannerKind = .offline
    /// 覆盖默认文案；传 nil 用 `kind.defaultText`
    var text: String? = nil

    init(kind: OfflineBannerKind = .offline, text: String? = nil) {
        self.kind = kind
        self.text = text
    }

    private var message: String {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.defaultText : trimmed
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = kind.icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(message)
                .font(Typography.captionXS)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(kind.foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.chrome, in: Capsule())
        .accessibilityAddTraits(.isStaticText)
    }
}
