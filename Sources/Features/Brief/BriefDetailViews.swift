import SwiftUI

/// 简报卡里三块「非通用行」的展示组件：宜忌标签、星座段、黄历整段。
///
/// 单独成文件是为了守住 `TodayBriefCard.swift ≤ 220 行`（QA 会数行数），
/// 也因为这三块都是纯展示、只吃已经算好的文案，与卡片状态（可用 / 空 / 展开）解耦。

// MARK: - 宜 / 忌

/// 宜：青柠点；忌：暖红点。横向可滚动 —— 宜忌条目数量不可控，
/// 挤成多行会把卡片撑得很高，横滑一行更稳。
struct BriefLuckChips: View {
    let yi: [String]
    let ji: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !yi.isEmpty {
                row(label: "宜", items: yi, color: Theme.limeInk)
            }
            if !ji.isEmpty {
                row(label: "忌", items: ji, color: Theme.statusError)
            }
        }
    }

    private func row(label: String, items: [String], color: Color) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(Typography.captionXS)
                .foregroundStyle(color)
                .frame(width: 14, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { entry in
                        chip(entry.element, color: color)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(Typography.footnote)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(color.opacity(0.10))
        }
        .overlay {
            Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1)
        }
    }
}

// MARK: - 星座

/// 星座段：标题行（星座 + 综合分）+ 幸运三件套 + 一句概述。三者都可缺，缺的整行不渲染。
struct BriefHoroscopeSection: View {
    let title: String
    let lucky: String?
    let overview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.limeInk)
                Text(title)
                    .font(Typography.titleM)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            if let lucky = lucky {
                Text(lucky)
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let overview = overview {
                Text(overview)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 15, multiple: 1.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 黄历整段

/// 黄历整段：`codeBg` 暗底 + 等宽字体（干支、宜忌条目在等宽下更齐），不做额外折叠。
struct BriefAlmanacBox: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("黄历")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(Typography.code)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                .fill(Theme.codeBg)
        }
    }
}
