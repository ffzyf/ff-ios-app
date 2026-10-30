import SwiftUI

/// 版本记录卡（PRD §3.5 的 P0 形态）。
///
/// **刻意不做时间线**：KV 里 `app_monitor_history` 是扁平快照，没有历史数组（PRD F4），
/// 时间线的数据源根本不存在。用假数据糊一条漂亮时间线，比不做更糟。
/// 所以这里只做「当前版本 / 上一版本」两行 + 发布日期 + 最近检查 + 失败原因。
struct VersionRecordCard: View {
    let status: SkyStatus?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("版本记录")
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)

                if visibleApps.isEmpty {
                    Text("还没有版本记录。等后台第一次检查完成，这里会出现当前版本。")
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                } else {
                    ForEach(visibleApps) { app in
                        block(app)
                    }
                }
            }
            .padding(Spacing.cardPadding)
        }
    }

    // MARK: - 单个服的记录

    private func block(_ app: SkyAppVersion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(regionText(app))
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 6)
                if let release = releaseText(app) {
                    Text(release)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
            }

            row(label: "当前版本", value: app.displayVersion, mono: true, color: Theme.textPrimary)

            if let previous = clean(app.previous) {
                row(label: "上一版本", value: previous, mono: true, color: Theme.textSecondary)
            } else {
                row(label: "上一版本", value: "暂无上一版本记录", mono: false, color: Theme.textTertiary)
            }

            Text("检查于 " + Formatters.relative(app.checkedAt))
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)

            if let error = clean(app.lastError) {
                Text(error)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.statusError)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                .fill(Color.white.opacity(0.03))
        }
    }

    private func row(label: String, value: String, mono: Bool, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(mono ? Typography.versionValue : Typography.footnote)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 派生数据

    private var visibleApps: [SkyAppVersion] {
        return Array((status?.apps ?? []).prefix(2))
    }

    private func regionText(_ app: SkyAppVersion) -> String {
        let trimmed = app.region.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "光遇" : trimmed
    }

    private func releaseText(_ app: SkyAppVersion) -> String? {
        let text = Formatters.versionDateText(app.releaseDate)
        return text == "—" ? nil : text + " 发布"
    }

    private func clean(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
