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

                // 3.16.0：补一句"上一版是什么时候发的"。
                // 只给版本号时用户没法判断"上次更新是三天前还是三个月前"，
                // 而服务端从 v2.3.0 起已经在版本流水里带了这一条。
                // 日期是 date-only 串，走 `Formatters.versionDateText`（**不要**转 Date，
                // 时区会把 21 号漂成 20 号）；解析不出来就整行不画。
                if let previousDate = previousReleaseText(app) {
                    Text("上一版 " + previousDate + " 发布")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
            } else {
                // 原来的文案是「暂无上一版本记录」—— 读起来像功能坏了。
                // 真相是：版本流水从 3.16.0 这次改版才开始累积，所以第一个被记录的版本
                // 本来就没有"上一版"。说清楚从哪个版本开始记，比说"暂无"诚实。
                row(label: "上一版本", value: recordStartText(app), mono: false, color: Theme.textTertiary)
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
                .fill(Theme.surfaceTint2)
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

    /// 「上一版是什么时候发布的」。
    ///
    /// 服务端给的是 date-only 串（`2026-10-21`），走 `Formatters.versionDateText` 统一成
    /// 「10月21日」；它拿不到时会返回 `"—"`，那种情况整行不画（宁可少一行，也不要一个破折号）。
    private func previousReleaseText(_ app: SkyAppVersion) -> String? {
        let text = Formatters.versionDateText(app.previousReleaseDate)
        return text == "—" ? nil : text
    }

    /// 没有上一版本时的说明文案。
    ///
    /// 为什么不是「暂无上一版本记录」：版本流水是 3.16.0 才开始按版本号累积的，
    /// 第一个被记下的版本天生没有"上一版"。「从 0.16.7 起开始记录」既解释了原因，
    /// 也告诉用户下一次更新后这里就会出现真实的上一版。
    private func recordStartText(_ app: SkyAppVersion) -> String {
        let current = clean(app.version) ?? clean(app.displayVersion)
        guard let current = current else { return "从这个版本起开始记录" }
        return "从 " + current + " 起开始记录"
    }
}
