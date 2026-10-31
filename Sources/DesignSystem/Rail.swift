import SwiftUI

/// 横向 rail 容器（设计报告 §2 R4 / §5 新组件）。
///
/// 为什么每条 rail 都得"露边"：这是"还有内容"的唯一低成本暗示。等宽平铺的卡片列表
/// 让人以为到底了；露出下一张的 1/3，页面自己就说出了"可以滑"。
struct Rail<Content: View>: View {
    /// 是否允许左右出血（滑到屏幕边）。默认 `true` —— 现有调用点一个都不用改。
    ///
    /// 出血的意义是"卡片滑到屏幕边"，前提是**列宽 = 屏宽**。宽屏下列宽 720 < 1194，
    /// 出血会让卡片滑到列外、压在空白上（设计文档 §4.3），所以宽屏传 `false`。
    ///
    /// 为什么默认值必须是 `true` 而不是 `false`：写成 `false` 时 iPhone 上 rail 不再出血，
    /// 右边永久留一条 20pt 白边 —— 而"卡片露在右边外面"正是 3.4.0 里"还能滑"的视觉暗示，
    /// 去掉之后看起来像"最后一张被切掉了"。
    var bleeds: Bool = true

    private let content: Content

    init(bleeds: Bool = true, @ViewBuilder content: () -> Content) {
        self.bleeds = bleeds
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
        //
        // 两个修饰器必须**成对**开合：只去掉 `padding(-20)` 会让内容起点再左移 20pt（左边不齐），
        // 只去掉 `safeAreaPadding` 会让卡片贴到屏幕边（等于强制出血）。所以条件包在一处。
        .modifier(RailBleed(enabled: bleeds))
    }
}

/// 把"出血 / 不出血"两种状态收进一个 `ViewModifier`。
///
/// 为什么不在 `Rail.body` 里直接写 `if bleeds { … } else { … }`：那会让 body 的返回类型
/// 分成两支，万一将来有人给两支各写一份修饰器，两边就开始各自演化。
/// 收到一个修饰器里，条件只影响 `.padding` 这两行，滚动区本身不被重建
/// （`@ViewBuilder` 在 modifier 的 body 里只包住修饰器链）。
private struct RailBleed: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .padding(.horizontal, -Spacing.page)
                .safeAreaPadding(.horizontal, Spacing.page)
        } else {
            content
        }
    }
}
