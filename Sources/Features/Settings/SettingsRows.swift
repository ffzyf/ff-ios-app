import SwiftUI

/// 设置页里三块「不是列表行」的内容：关于卡、页脚署名、顶部 toast。
///
/// 单独放一个文件是为了守住 `SettingsView.swift ≤ 200 行`的硬约束（T09 会数行数），
/// 也因为这三块都是纯展示，跟设置页的业务动作（清缓存 / 复制域名）没有耦合。

/// 关于：一句话定位 + 两句边界说明（不给开源库列表，P1 再说）
struct SettingsAboutCard: View {
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("一个安静的阅读入口")
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)
                Text("只放三样东西：博客文章、光遇版本、每天一份简报。没有账号，没有推荐，没有广告位。")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                Text("浅色和深色都做好了。在「外观」里三选一：跟随系统、始终浅色、始终深色，选了立刻生效。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
            }
            .padding(Spacing.cardPadding)
        }
    }
}

/// 页脚：一枚 40pt 青柠短线 + 一行版本署名（PRD §3.6 底部一行）
struct SettingsFooterLine: View {
    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Theme.lime)
                .frame(width: 40, height: 3)
            Text("FF大王 V2 · 原生重写版")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
}

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
