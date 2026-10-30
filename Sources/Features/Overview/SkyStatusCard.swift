import SwiftUI

/// 首页最重要的信号卡：两服版本 + 四态（PRD §3.1 / 设计文档 T05）。
///
/// 交互：点整卡切到简报 Tab。`onTap` 由上层注入，本组件不持有 Tab 状态。
/// 四态判定全部收在 `SkyCardPhase.resolve(_:)`，本文件只负责长相。
struct SkyStatusCard: View {
    let status: SkyStatus?
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 左缘光晕呼吸（只在 A 态存在，全 App 唯一的循环动画，PRD §4.6 克制原则）
    @State private var glowBright: Bool = false

    init(status: SkyStatus?, onTap: @escaping () -> Void) {
        self.status = status
        self.onTap = onTap
    }

    var body: some View {
        let phase = SkyCardPhase.resolve(status)
        PressableGlassCard(
            level: .card,
            tint: phase.tint,
            action: {
                onTap()
            }
        ) {
            cardContent(phase: phase)
        }
    }

    // MARK: - 卡面

    private func cardContent(phase: SkyCardPhase) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(phase.title)
                    .font(Typography.titleM)
                    .foregroundStyle(phase.titleColor)
                Spacer(minLength: 8)
                StatusPill(kind: phase.pillKind, text: phase.pillText)
            }
            rows
            footer
        }
        .padding(Spacing.cardPadding)
        .overlay(alignment: .leading) {
            if phase == .newVersion {
                edgeGlow
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        if visibleApps.isEmpty {
            Text("版本数据还没到。下拉刷新一次试试。")
                .font(Typography.footnote)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(Array(visibleApps.indices), id: \.self) { index in
                SkyAppVersionRow(app: visibleApps[index])
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(footerText)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text("简报 ›")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.limeInk)
        }
    }

    /// 左缘 3pt 青柠光晕：呼吸 0.45 ↔ 0.9；`reduceMotion` 下静止（PRD §4.6 / §7）
    private var edgeGlow: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Theme.lime, Theme.lime.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 3)
            .padding(.vertical, 14)
            .opacity(glowBright ? 0.9 : 0.45)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Motion.glow) {
                    glowBright = true
                }
            }
    }

    // MARK: - 派生数据

    private var visibleApps: [SkyAppVersion] {
        guard let apps = status?.apps else { return [] }
        return Array(apps.prefix(2))
    }

    /// 卡底一行：失败态给错误摘要，其余给「检查于 N 小时前」（全走 `Formatters`）
    private var footerText: String {
        switch SkyCardPhase.resolve(status) {
        case .failed:
            if let message = firstError, !message.isEmpty {
                return message
            }
            return "上次记录还在，稍后自动重试。"
        case .newVersion:
            if let checked = status?.checkedAt {
                return "检查于 " + Formatters.relative(checked)
            }
            return "点开看两服版本对比。"
        case .upToDate:
            if let checked = status?.checkedAt {
                return "检查于 " + Formatters.relative(checked)
            }
            return "两个服都跟上了，安心玩。"
        case .unchecked:
            return "还不知道两服各是什么版本，点开简报看看。"
        }
    }

    private var firstError: String? {
        guard let apps = status?.apps else { return nil }
        for app in apps {
            if let error = app.lastError, !error.isEmpty {
                return error
            }
        }
        return nil
    }
}
