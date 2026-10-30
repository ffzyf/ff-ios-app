import SwiftUI

/// 文章列表页的页头（PRD §3.2 第 1 条）。
///
/// 刻意不接导航栏：本工程没有系统 TabBar/NavigationBar 参与布局（浮动 Tab 栏是自绘的），
/// 大标题留在内容流里，随滚动一起走，比「滚动后收进玻璃条」更简单也更稳。
struct ArticlesHeader: View {
    /// 已加载的文章数（**不用 `total`**：设计文档明确 App 的分页只认 `hasMore`）
    let count: Int
    let isRefreshing: Bool
    let lastUpdatedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("文章")
                .font(Typography.display)
                .tracking(Typography.trackingLarge)
                .foregroundStyle(Theme.textPrimary)
            Text("\(count) 篇 · " + hint)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var hint: String {
        if isRefreshing {
            return "正在刷新…"
        }
        if let updated = lastUpdatedAt {
            return "更新于 " + Formatters.relative(updated)
        }
        return "下拉可以刷新"
    }
}
