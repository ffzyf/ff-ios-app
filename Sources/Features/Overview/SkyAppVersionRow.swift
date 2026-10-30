import SwiftUI

/// 单服一行：站点名 + 版本号（有新版本时摊开 `旧 → 新`）+ 发布日期 + 状态胶囊。
///
/// 版本号用 `Typography.versionValue`（15pt 等宽 Semibold）：`0.16.6` 与 `0.16.10`
/// 不会因字符宽度抖动；发布日期走 `Formatters.versionDateText`（服务端给的是 date-only
/// 字符串，转 Date 会被时区把 28 号漂成 27 号）。
struct SkyAppVersionRow: View {
    let app: SkyAppVersion

    var body: some View {
        HStack(spacing: 10) {
            Text(app.region.isEmpty ? "光遇" : app.region)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 46, alignment: .leading)
            Text(versionText)
                .font(Typography.versionValue)
                .foregroundStyle(app.hasUpdate ? Theme.statusNew : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            if let releaseText = releaseText {
                Text(releaseText)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            StatusPill(kind: pillKind, text: pillText)
        }
    }

    /// 有新版本时把「上一版 → 当前版」摊开，用户不用点进去就知道变了什么
    private var versionText: String {
        if app.hasUpdate, let previous = app.previous, !previous.isEmpty {
            return previous + " → " + app.displayVersion
        }
        return app.displayVersion
    }

    /// `Formatters.versionDateText` 拿不到合法日期时返回破折号，这里转成 nil 让整块不占位
    private var releaseText: String? {
        let text = Formatters.versionDateText(app.releaseDate)
        return text == "—" ? nil : text
    }

    private var pillKind: StatusPillKind {
        switch app.status {
        case .newVersion:
            return .newVersion
        case .noChange:
            return .upToDate
        case .fetchFailed:
            return .failed
        case .initial, .unknown:
            return .pending
        }
    }

    private var pillText: String {
        switch app.status {
        case .newVersion:
            return "更新"
        case .noChange:
            return "最新"
        case .fetchFailed:
            return "失败"
        case .initial, .unknown:
            return "未知"
        }
    }
}
