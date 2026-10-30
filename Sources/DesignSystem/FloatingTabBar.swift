import SwiftUI

/// Tab 栏的数据描述（DesignSystem 不认识 AppTab，只认识这个纯数据）。
///
/// `showsDot` 是「更多」那一个格子上的青柠小圆点（PRD §2.2）：出现条件由业务侧决定
/// （①有新版本 ②已登录且存在未读答卷），本层只负责画。默认 false，所以 V2 的构造点不用改。
struct TabSpec: Identifiable, Equatable {
    let id: Int
    let title: String
    let icon: String
    /// 是否显示右上角提示点（仅「更多」允许有，且同一条规则不叠加多个点）
    var showsDot: Bool = false
}

/// 浮动玻璃胶囊 Tab 栏（层 2）。
///
/// 为什么自绘（设计文档 §5.1 #4）：PRD 要的是「左右内缩 24pt、高 56pt、距底 16pt、不贴边」，
/// 系统 TabView 的 bar 无法满足；`.toolbar(.hidden, for: .tabBar)` 再自绘会让安全区塌陷。
///
/// 三层结构 = 玻璃底（glassSurface 唯一入口）+ 高亮胶囊（matchedGeometryEffect）+ 图标文字。
/// 高亮刻意用 `matchedGeometryEffect` 而不是系统玻璃容器的 morph 效果：
/// iOS 18–25 没有 morph，靠系统 morph 会导致「换台设备动效就消失」（设计文档 §5.3-①）。
///
/// 批次 1 的三处改动：
/// 1. 从 3 项扩到 5 项 —— 每项 `frame(maxWidth: .infinity)` 均分，项间间距随项数收窄，
///    图标 15pt / 文字 10pt 保持不变（PRD §2.2 的定稿字号，不要动）；
/// 2. 选中态从 `lime` 改成 `limeInk`（深色同值 `#6BDB5C` → 零变化；浅色 `#1F6B22` 才读得清）；
/// 3. 支持 `TabSpec.showsDot`（「更多」的青柠小圆点）。
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

    /// 项数 ≥5 时把项间距收到 0：5 项在 390pt 屏上每项约 64pt，
    /// 再留 2pt 间距会让「更多」两字贴近胶囊边缘。
    private var itemSpacing: CGFloat {
        return tabs.count >= 5 ? 0 : 2
    }

    var body: some View {
        HStack(spacing: itemSpacing) {
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
                    // 5 项时可用宽度约 64pt，中文两字刚好；三字标签靠缩字保住单行，不换行
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Theme.limeInk : Theme.textTertiary)
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
            .overlay(alignment: .topTrailing) {
                if tab.showsDot {
                    Circle()
                        .fill(Theme.lime)
                        .frame(width: 5, height: 5)
                        .padding(.top, 2)
                        .padding(.trailing, 8)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}
