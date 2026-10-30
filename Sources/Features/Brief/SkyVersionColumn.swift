import SwiftUI

/// 版本对比里的单列（一个服）。
///
/// 五态全覆盖（服务端判定，App 只 switch、不比版本号）：
/// · `newVersion` → 版本号青柠 + 列顶 3pt 青柠短线 + NEW 胶囊 + `previous → current`；
/// · `noChange` → 版本号 `textPrimary` + 中性「已是最新」（绿色只代表「有变化」）；
/// · `initial` → 「已开始记录」，胶囊「待确认」；
/// · `fetchFailed` → 整列降饱和 + 显示上次已知版本 + 暖红「检查失败」，**不影响另一列**；
/// · `unknown` / 整段缺失 → 「暂未获取到版本信息」。
struct SkyVersionColumn: View {
    let app: SkyAppVersion?
    /// 服务端没给 region 时的兜底名（国服 / 国际服）
    let fallbackRegion: String

    var body: some View {
        GlassCard(level: .card, tint: isNew ? Theme.glassTintLime : nil) {
            VStack(alignment: .leading, spacing: 8) {
                // 该服自己的新版本才给青柠短线；两服互不影响
                Capsule()
                    .fill(Theme.lime)
                    .frame(width: 28, height: 3)
                    .opacity(isNew ? 1 : 0)

                Text(regionText)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)

                Text(versionText)
                    .font(Typography.versionLarge)
                    .foregroundStyle(versionColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let change = changeText {
                    Text(change)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                if let release = releaseText {
                    Text(release)
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }

                Text(checkedText)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                StatusPill(kind: pillKind, text: pillText)
            }
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 检查失败的那一列整体降饱和：一眼看出「这列的数字是旧的」
            .saturation(isFailed ? 0.35 : 1)
        }
    }

    // MARK: - 派生数据

    private var isNew: Bool {
        return app?.hasUpdate ?? false
    }

    private var isFailed: Bool {
        return app?.status == .fetchFailed
    }

    private var regionText: String {
        guard let app = app else { return fallbackRegion }
        let trimmed = app.region.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallbackRegion : trimmed
    }

    /// `unknown` 与整段缺失都不显示版本号 —— 显示「—」不如直说「还没拿到」
    private var versionText: String {
        guard let app = app, app.status != .unknown else { return "暂未获取到版本信息" }
        return app.displayVersion
    }

    private var versionColor: Color {
        if isNew { return Theme.statusNew }
        if app == nil || app?.status == .unknown { return Theme.textTertiary }
        return Theme.textPrimary
    }

    /// 有新版本时摊开「上一版 → 当前版」；`previous` 丢了就只显示当前版（不显示孤零零的箭头）
    private var changeText: String? {
        guard let app = app, app.hasUpdate else { return nil }
        guard let previous = app.previous, !previous.isEmpty else { return nil }
        return previous + " → " + app.displayVersion
    }

    /// `releaseDate` 是 date-only 字符串，走 `Formatters.versionDateText` 拼成「10月28日」，
    /// 不转 `Date`（时区会把 28 号漂成 27 号）
    private var releaseText: String? {
        guard let app = app else { return nil }
        let text = Formatters.versionDateText(app.releaseDate)
        return text == "—" ? nil : text + " 发布"
    }

    private var checkedText: String {
        guard let app = app else { return "暂未获取到版本信息" }
        switch app.status {
        case .fetchFailed:
            return "未更新 · 上次记录 " + Formatters.relative(app.checkedAt)
        case .initial:
            return "已开始记录，下次变动会更新"
        case .unknown:
            return "暂未获取到版本信息"
        case .newVersion, .noChange:
            return "检查于 " + Formatters.relative(app.checkedAt)
        }
    }

    private var pillKind: StatusPillKind {
        switch app?.status {
        case .some(.newVersion):
            return .newVersion
        case .some(.noChange):
            return .upToDate
        case .some(.fetchFailed):
            return .failed
        case .some(.initial), .some(.unknown), .none:
            return .pending
        }
    }

    private var pillText: String {
        switch app?.status {
        case .some(.newVersion):
            return "NEW"
        case .some(.noChange):
            return "已是最新"
        case .some(.fetchFailed):
            return "检查失败"
        case .some(.initial):
            return "待确认"
        case .some(.unknown), .none:
            return "未知"
        }
    }
}
