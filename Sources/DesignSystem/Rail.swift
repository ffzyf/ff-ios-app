import SwiftUI

/// 横向 rail 容器（设计报告 §2 R4 / §5 新组件）。
///
/// 为什么每条 rail 都得"露边"：这是"还有内容"的唯一低成本暗示。等宽平铺的卡片列表
/// 让人以为到底了；露出下一张的 1/3，页面就自己说出了"可以滑"。
struct Rail<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: Layout.railGap) {
                content
            }
            // 告诉系统"每个卡是一页"，配合 `.viewAligned` 才有吸附手感
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        // 横向出血：先把滚动区向两侧各顶出页边距（父级已有 `Spacing.page` 的 padding），
        // 让卡片能一直滑到屏幕边；再用 `safeAreaPadding` 把内容的起点推回页面边距，
        // 于是"左边与正文对齐、右边出血"两件事同时成立。
        .padding(.horizontal, -Spacing.page)
        .safeAreaPadding(.horizontal, Spacing.page)
    }
}
