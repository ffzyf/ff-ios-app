import SwiftUI

/// Tab 栏的数据描述（DesignSystem 不认识 AppTab，只认识这个纯数据）。
struct TabSpec: Identifiable, Equatable {
    let id: Int
    let title: String
    let icon: String
}

/// 浮动玻璃胶囊 Tab 栏（层 2）。
///
/// 为什么自绘（设计文档 §5.1 #4）：PRD 要的是「左右内缩 24pt、高 56pt、距底 16pt、不贴边」，
/// 系统 TabView 的 bar 无法满足；`.toolbar(.hidden, for: .tabBar)` 再自绘会让安全区塌陷。
///
/// 三层结构 = 玻璃底（glassSurface 唯一入口）+ 高亮胶囊（matchedGeometryEffect）+ 图标文字。
/// 高亮刻意用 `matchedGeometryEffect` 而不是系统玻璃容器的 morph 效果：
/// iOS 18–25 没有 morph，靠系统 morph 会导致「换台设备动效就消失」（设计文档 §5.3-①）。
struct FloatingTabBar: View {
    let tabs: [TabSpec]
    @Binding var selection: Int
    @Namespace private var highlightNamespace

    /// 显式 init：`@Namespace` 是私有属性，自动生成的 memberwise init 会有可见性风险，
    /// 这里手写一份，确保跨文件构造一定可用。
    init(tabs: [TabSpec], selection: Binding<Int>) {
        self.tabs = tabs
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                tabItem(tab)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: Spacing.tabBarHeight)
        .glassSurface(.floating, in: Capsule(), interactive: true)
    }

    private func tabItem(_ tab: TabSpec) -> some View {
        let isSelected = (selection == tab.id)
        return Button(action: {
            guard selection != tab.id else { return }
            // 动画与轻触觉统一在 RootView 的 Binding setter 里给，这里只改值
            selection = tab.id
        }) {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isSelected ? Theme.lime : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: Spacing.tabBarHeight - 14)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.lime.opacity(0.14))
                        .overlay {
                            Capsule().strokeBorder(Theme.lime.opacity(0.35), lineWidth: 1)
                        }
                        .matchedGeometryEffect(id: "tab.highlight", in: highlightNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
