import SwiftUI

/// 单服版本卡（PRD P12：国服 / 国际服各一张）。
///
/// 一张卡只说三件事，顺序固定：
/// ① 这是哪个服 + 有没有新版本（右上状态胶囊）；② 当前版本号（等宽大字）；
/// ③ 最近一次检查是什么时候 —— 失败时改成「检查失败，上次成功 X 前」，从未成功过就说「尚未检查」。
///
/// 一条纪律：**不编时间**。「X 前」只由 `Formatters.relative` 算，它拿不到时间就给 `—`；
/// 卡片在这里把 `—` 换成一句人话（「尚未检查」），而不是让用户读到一个破折号。
struct VersionStatusCard: View {

    private let app: MonitorAppVersion
    /// 传入当前时刻而不是在 body 里 `Date()`：多张卡共享同一个 now，
    /// 刷新时不会出现「上面卡说 3 小时前、下面卡说 4 小时前」。
    private let now: Date

    init(app: MonitorAppVersion, now: Date = Date()) {
        self.app = app
        self.now = now
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                headerRow
                versionRow
                if let subtitle = releaseText {
                    Text(subtitle)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                checkRow
            }
            .padding(Spacing.cardPadding)
        }
    }

    // MARK: - 行

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(app.regionText)
                .font(Typography.captionXS)
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)

            Spacer(minLength: 8)

            StatusPill(kind: pillKind, text: pillText)
        }
    }

    private var versionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(app.displayVersion)
                .font(Typography.versionLarge)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()

            if app.hasNew, let previous = app.previousVersion, !previous.isEmpty {
                Text("上次 \(previous)")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
    }

    private var checkRow: some View {
        HStack(spacing: 6) {
            Image(systemName: checkIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(checkTint)
            Text(checkText)
                .font(Typography.captionXS)
                .foregroundStyle(checkTint)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
    }

    // MARK: - 派生

    private var pillKind: StatusPillKind {
        if app.hasNew { return .newVersion }
        if app.lastError != nil { return .failed }
        if app.checkedAt == nil { return .pending }
        return .upToDate
    }

    /// 状态胶囊文案。**「已是最新」只在真的检查成功过之后才敢说**
    private var pillText: String {
        if app.hasNew { return "有新版本" }
        if app.lastError != nil { return "检查失败" }
        if app.checkedAt == nil { return "尚未检查" }
        return "已是最新"
    }

    /// 发布日期（date-only 字符串，不转 Date，避免时区把日期漂一天）
    private var releaseText: String? {
        guard let release = app.releaseDate, !release.isEmpty else { return nil }
        return "发布于 " + Formatters.versionDateText(release)
    }

    private var checkIcon: String {
        if app.lastError != nil { return "exclamationmark.triangle" }
        if app.checkedAt == nil { return "clock" }
        return "clock.arrow.circlepath"
    }

    private var checkTint: Color {
        if app.lastError != nil { return Theme.statusError }
        return Theme.textTertiary
    }

    /// 最近检查说明。四种情况各有各的说法，绝不用一条「—」糊过去
    private var checkText: String {
        if let lastError = app.lastError, !lastError.isEmpty {
            if let checked = app.checkedAt {
                return "检查失败，上次成功 " + Formatters.relative(checked, now: now)
            }
            return "检查失败，还没有成功记录"
        }
        guard let checked = app.checkedAt else { return "尚未检查" }
        return "最近检查 " + Formatters.relative(checked, now: now)
    }
}
