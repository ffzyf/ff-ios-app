import SwiftUI

/// 简报页的「两服版本对比」面板：只负责排版与差异提示，单服的五态渲染在 `SkyVersionColumn`。
///
/// 为什么与首页 `SkyStatusCard` 分成两个组件：首页卡只回答「今天有没有变化」，
/// 这里要给出每服的版本号 / 发布日期 / 检查时间 / 变化轨迹，文字量与层级都不同。
/// 复用同一张卡会把首页卡撑成一坨，也会让简报页永远拿不到它需要的细节。
struct SkyVersionPanel: View {
    let status: SkyStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            HStack(alignment: .top, spacing: Spacing.cardGap) {
                SkyVersionColumn(app: slot(0), fallbackRegion: "国服")
                SkyVersionColumn(app: slot(1), fallbackRegion: "国际服")
            }
            if let note = diffNote {
                diffRow(note)
            }
        }
    }

    // MARK: - 差异提示条

    private func diffRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(Typography.footnote)
                .foregroundStyle(Theme.lime)
            Image(systemName: "arrow.right")
                .font(Typography.caption)
                .foregroundStyle(Theme.lime)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    /// 只在「一服有更新另一服没有」或「两服版本号不同」时出现。
    ///
    /// 刻意**不说谁比谁新几个版本**：设计文档 §3.5 禁止 App 自己比较版本号
    /// （`previous` 在推送成功后即丢失，App 端比较必然做错），所以这里只陈述「不一致」。
    private var diffNote: String? {
        let apps = status?.apps ?? []
        guard apps.count >= 2 else { return nil }
        let first = apps[0]
        let second = apps[1]

        if first.hasUpdate != second.hasUpdate {
            let updated = first.hasUpdate ? first : second
            return regionText(updated, fallback: "其中一个服") + "有新版本"
        }
        if let left = first.version, let right = second.version,
           !left.isEmpty, !right.isEmpty, left != right {
            return "两个服的版本不一样"
        }
        return nil
    }

    // MARK: - 派生数据

    private func slot(_ index: Int) -> SkyAppVersion? {
        let apps = status?.apps ?? []
        guard index >= 0, index < apps.count else { return nil }
        return apps[index]
    }

    private func regionText(_ app: SkyAppVersion, fallback: String) -> String {
        let trimmed = app.region.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
