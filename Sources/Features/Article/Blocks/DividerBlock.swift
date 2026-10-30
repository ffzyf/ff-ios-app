import SwiftUI

/// 分割线块（PRD §3.3 divider 行）：1pt、白 8%，左右各内缩 40pt。
///
/// 短分割线比通栏更克制，这里的内缩是「页面 20pt 边距 + 再缩 20pt」= 距屏幕边 40pt。
struct DividerBlock: View {
    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.page)
            .accessibilityHidden(true)
    }
}
