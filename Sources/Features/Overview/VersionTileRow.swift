import SwiftUI

/// 首页「今日一览」的两张版本 tile（P0-7，设计报告 §4.1）。
///
/// 为什么把原来那张大号 `SkyStatusCard` 拆成两张 96pt tile：那张卡与红石卡、简报卡
/// 同宽同圆角同阴影，三块"一样重"，一屏没有主次。tile 只有首屏锚点的 40% 高，
/// 一眼就能读成"这是次级信息"。
///
/// 业务判定**不复制**：四态全部来自 `SkyCardPhase.resolve(_ app:)`（与整卡用的是同一张映射表），
/// 本文件只负责长相。原 `SkyStatusCard` 保留不动 —— 简报页还要用它的整卡形态。
struct VersionTileRow: View {
    /// tile 高度走 `cardHeight(.tile)`：窄档 96（今天）、宽档 120（同比例 ×1.25）
    @Environment(\.layoutMetrics) private var metrics
    let status: SkyStatus?
    /// 点任意一张 tile（首页：切到简报 Tab 看两服详情）
    let onTap: () -> Void

    /// 显式 init：`@Environment` 是 private 存储属性，会把自动生成的 memberwise init 降级成
    /// private，跨文件 `VersionTileRow(status:onTap:)` 就构造不了（与 `RootView` 同一条约定）。
    init(status: SkyStatus?, onTap: @escaping () -> Void) {
        self.status = status
        self.onTap = onTap
    }

    var body: some View {
        HStack(spacing: Spacing.cardGap) {
            if apps.isEmpty {
                // 没有任何版本数据时仍然占住两张 tile 的位置：这里画"—"而不是空卡，
                // 是为了避免"加载完成时区块突然出现"把下面的内容顶下去
                tile(phase: .unchecked, region: "国服", version: "—")
                tile(phase: .unchecked, region: "国际服", version: "—")
            } else {
                ForEach(Array(apps.enumerated()), id: \.offset) { _, app in
                    tile(app: app)
                }
            }
        }
    }

    // MARK: - 卡面

    private func tile(app: SkyAppVersion) -> some View {
        let phase = SkyCardPhase.resolve(app)
        return tile(
            phase: phase,
            region: app.region.isEmpty ? app.name : app.region,
            version: app.displayVersion
        )
    }

    /// 一张 tile：服名（20pt）+ 版本号（等宽）+ 四态文案（13pt）。
    ///
    /// 高度用 `CardTier.tile`：96pt 是"并排小卡"的唯一档位，其它页拿同一档并排时才不会出现
    /// "收益页 96、首页 100"这种一眼看得出又说不清的差。
    private func tile(phase: SkyCardPhase, region: String, version: String) -> some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(region)
                        .font(Typography.titleM)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if phase == .newVersion {
                        StatusPill(kind: phase.pillKind, text: phase.pillText)
                    }
                }

                Text(version)
                    .font(Typography.versionValue)
                    .foregroundStyle(phase == .newVersion ? Theme.statusNew : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                Text(phase.title)
                    .font(Typography.captionXS)
                    .foregroundStyle(phase.titleColor)
                    .lineLimit(1)
            }
            .padding(Spacing.smallCardPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.cardHeight(.tile), alignment: .topLeading)
            .glassStatic(
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous),
                tint: phase.tint
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(region + "，" + version + "，" + phase.title)
    }

    // MARK: - 派生数据

    private var apps: [SkyAppVersion] {
        guard let apps = status?.apps else { return [] }
        return Array(apps.prefix(2))
    }
}
