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
/// **iOS 26 液态玻璃（候选，⚠️ 待验证）**：用 `GlassEffectContainer` 包住整个 Tab 栏、
/// 选中项叠加 `.glassEffect(in: Capsule())` + `.glassEffectID("tabHighlight", in: tabNS)`，
/// 与全部 5 个 tab 项共享同一 `Namespace`，切台时「tabHighlight」这块玻璃在容器内液态 morph 到新位置。
/// 但该分支依赖 iOS 26 专有符号（GlassEffectContainer / glassEffect / glassEffectID），
/// 本工程以 iOS 18 SDK 编译会直接报「symbol not found」，**整段注释**（见文件末尾），
/// 待 macos-26 runner + 真机验证后再点亮。下面这条 iOS 18–25 分支是**当前生效路径**，已保证可编译可运行。
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
        // Tab 栏保留真玻璃：它是「必须透出滚动内容才能证明自己浮着」的唯一上层元素（B1 设计 §5.3.2），
        // 不改成静态配方。
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

/*
 ⚠️ 待验证 · iOS 26 液态玻璃候选分支（macos-26 runner 验证后再启用）
 ───────────────────────────────────────────────────────────────────────
 本段整段注释，原因是它引用 iOS 26 专有符号（GlassEffectContainer / glassEffect / glassEffectID），
 当前以 iOS 18 SDK 编译会直接失败。验证通过后再替换进上面的 `body` / `tabItem` / 选中胶囊逻辑，
 且务必包在 `if #available(iOS 26.0, *)` 里，并保留下方 iOS 18–25 分支作为降级。

 改造要点：
 1. 外层 `glassSurface(.floating, ...)` 改为 `GlassEffectContainer(spacing: 0, in: highlightNamespace) { ... }`
    —— 液态玻璃要求「容器内多块玻璃融合」，外层不能再是玻璃（否则玻璃套玻璃、双重采样且 morph 失效）。
 2. 选中项：`.glassEffect(Glass.regular.interactive(true), in: Capsule())`
            `.glassEffectID("tabHighlight", in: highlightNamespace)`
 3. 未选中项：普通 `Button { ... }`（无玻璃），与选中项同处一个 `GlassEffectContainer`、共享 `highlightNamespace`，
    这样「tabHighlight」这块玻璃会在切换时从旧位置液态 morph 到新位置。
 4. 删除 `matchedGeometryEffect`，改用玻璃容器自己的 morph。

 降级的「反向」红线（绝不可引入未登记的 morph 相关私有 API）。
 仅允许使用 GlassEffectContainer / glassEffect / glassEffectID 这套已登记待验证的 API。
 */
