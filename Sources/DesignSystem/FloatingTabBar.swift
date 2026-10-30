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
/// 三层结构 = 玻璃底（glassSurface 唯一入口）+ 高亮胶囊（滑动）+ 图标文字。
///
/// **iOS 26 液态玻璃（已验证签名）**：用 `GlassEffectContainer` 包住整个 Tab 栏、
/// 每个 tab 项是 `.glassEffect(in: Capsule())` 的玻璃体，选中项叠加
/// `.glassEffectID("tab.highlight", in: tabNS)`。由于 5 项都位于同一容器、共享同一 Namespace，
/// 切台时「tabHighlight」这块玻璃会在容器内**液态 morph** 到新位置（不是滑一个胶囊，而是
/// 选中/未选中两块玻璃互相吸引合并）。
///
/// 降级（iOS 18–25）：选中胶囊用 `matchedGeometryEffect` 滑动 + 顶部高光渐变模拟玻璃折射。
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
        if #available(iOS 26.0, *) {
            tabBarGlass26
        } else {
            tabBarLegacy
        }
    }

    // MARK: - iOS 26 液态玻璃路径

    @available(iOS 26.0, *)
    private var tabBarGlass26: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: itemSpacing) {
                ForEach(tabs) { tab in
                    tabItemGlass26(tab)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: Spacing.tabBarHeight)
        }
    }

    @available(iOS 26.0, *)
    private func tabItemGlass26(_ tab: TabSpec) -> some View {
        let isSelected = (selection == tab.id)
        let label = VStack(spacing: 3) {
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
        // 每个 tab 都是一块玻璃；选中项复用 "tab.highlight" 这个 id，
        // SwiftUI 会把这块玻璃从旧位置 morph 到新位置（液态融合）。
        .glassEffect(in: Capsule())
        .glassEffectID(isSelected ? "tab.highlight" : "tab.\(tab.id)", in: highlightNamespace)
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

        return Button(action: {
            guard selection != tab.id else { return }
            // 动画与轻触觉统一在 RootView 的 Binding setter 里给，这里只改值
            selection = tab.id
        }) {
            label
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    // MARK: - iOS 18–25 降级路径

    private var tabBarLegacy: some View {
        HStack(spacing: itemSpacing) {
            ForEach(tabs) { tab in
                tabItemLegacy(tab)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: Spacing.tabBarHeight)
        // Tab 栏保留真玻璃：它是「必须透出滚动内容才能证明自己浮着」的唯一上层元素（B1 设计 §5.3.2），
        // 不改成静态配方。
        .glassSurface(.floating, in: Capsule(), interactive: true)
    }

    private func tabItemLegacy(_ tab: TabSpec) -> some View {
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
                    selectedHighlight
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

    /// 选中态胶囊（iOS 18–25 降级分支，观感明显优于现版）：
    /// 填充从 14% 提到约 22% + 1pt 描边（青柠 50%），并叠一层**顶部高光渐变**模拟玻璃折射，
    /// 让胶囊有「浮起玻璃」的反射感，比现版「14% 填充 + 1pt 描边」更通透。
    /// 滑动仍由 `matchedGeometryEffect` 承担 —— iOS 18 没有 morph API，靠它会「换台设备动效消失」。
    private var selectedHighlight: some View {
        Capsule()
            .fill(Theme.lime.opacity(0.22))
            .overlay {
                // 顶部高光：玻璃边缘的折射感（走 token，不写白/黑 opacity）
                Capsule()
                    .fill(LinearGradient(
                        colors: [Theme.glassSheen, Theme.glassHighlightFade],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            }
            .overlay {
                Capsule().strokeBorder(Theme.lime.opacity(0.5), lineWidth: 1)
            }
            // 与全部 5 个 tab 项共享 namespace，选中项在容器内液态滑动到新位置
            .matchedGeometryEffect(id: "tab.highlight", in: highlightNamespace)
    }
}
