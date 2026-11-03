import SwiftUI

/// 宽档（iPad / iPad 竖屏）顶部导航条：44pt 高的居中胶囊（设计文档 §6.2 选 C）。
///
/// **为什么不沿用底部那枚胶囊**：HIG「Tab bars」iPadOS 段原文是
/// *"The system displays a tab bar near the top of the screen."* —— 底部浮动条在 1194 宽的
/// iPad 上就是 iPhone 的形态，也是用户说"像放大的手机"时第一眼看到的东西。
/// 换成顶部 44pt 条之后竖向占用从 `6 + 74 + 10 = 90` 降到 `6 + 44 = 50`，
/// viewport 700 → 760（横屏最贵的资源就是纵向：834 里要装 7 行月历）。
///
/// **为什么是两个组件而不是一个组件两套几何**：`FloatingTabBar` 的 74 / 40 / 21 / 8 / 10
/// 是逐条论证过的（选中圆 40 配 21 图标才有那组 36.9 / 46.4 的数字），
/// 改一个常量就会牵动整条推导。新开一个组件 = iPhone 那条代码一个字节都不动，
/// 315 行档（Slide Over / 1⁄3 分屏）走的还是老组件 —— 风险面从"两套几何"降到"零"。
///
/// 玻璃一律走 `glassSurface(.floating, in: Capsule())` 这个唯一入口（README §四）。
struct WideTabStrip: View {
    let tabs: [TabSpec]
    @Binding var selection: Int

    /// 选中胶囊的滑动命名空间（与 `FloatingTabBar` 同一手法：`matchedGeometryEffect` 在
    /// iOS 18 起就可用，换台设备动效也不会"消失"）
    @Namespace private var knobNamespace

    /// 单项最小槽宽 78。5 × 78 + 4 × 4（项间距）+ 10 × 2（条内边距）≈ 426，
    /// 槽宽远大于 44，所以 44pt 的点击目标在**横向**也满足（设计文档 §6.3）。
    private let itemMinWidth: CGFloat = 78
    /// 项间距 4：胶囊之间只留视觉缝，不留"两段各自为政"的距离
    private let itemSpacing: CGFloat = 4

    /// 显式 init：`@Namespace` 是私有属性，自动生成的 memberwise init 会有可见性风险，
    /// 手写一份确保跨文件构造一定可用（与 `FloatingTabBar` 同一条约定）。
    init(tabs: [TabSpec], selection: Binding<Int>) {
        self.tabs = tabs
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: itemSpacing) {
            // 与 `FloatingTabBar` 同一手法：按**位置**驱动，快捷键才拿得到"第几格"
            ForEach(Array(tabs.indices), id: \.self) { index in
                tabItem(tabs[index], position: index + 1)
            }
        }
        .padding(.horizontal, Layout.tabStripHorizontalPadding)
        .frame(height: Layout.tabStripHeight)
        // 整条只有这一处玻璃：条目本身不给底（五块玻璃并排会互相打架，也失去"一个控件"的读法）
        .glassSurface(.floating, in: Capsule(), interactive: true)
        .background {
            pageShortcuts
        }
    }

    // MARK: - 单项

    private func tabItem(_ tab: TabSpec, position: Int) -> some View {
        let isSelected = (selection == tab.id)
        return Button(action: {
            guard selection != tab.id else { return }
            // 触觉与 `withAnimation(Motion.tab)` 统一在 `RootView` 的 Binding setter 里给：
            // 这里再给一次会变成"两次触觉"，动画也会被包两遍
            selection = tab.id
        }) {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    // 15pt 图标：顶部条只有 44 高，21pt（底部栏的尺寸）在这里会顶满上下
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.onLime : Theme.textTertiary)
                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
                    // 未选中用 `textSecondary`（与底部栏同一条理由：压在玻璃上的小字不能太淡）
                    .foregroundStyle(isSelected ? Theme.onLime : Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            // 8pt 纵向内边距让选中胶囊落在 44 高的槽**中间**（约 34 高、上下各留 5），
            // 于是胶囊是"条里面的一枚 chip"，而不是把整条填满的分段控件
            .padding(.vertical, 8)
            // 胶囊背景加在 padding 之后、44pt 槽之前：顺序反了胶囊会被拉成满高
            .background {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.lime, Theme.limeDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .matchedGeometryEffect(id: "strip.knob", in: knobNamespace)
                }
            }
            // 44pt 的点击槽（槽宽 78，远大于 44 → 横向也达标）
            .frame(minWidth: itemMinWidth, minHeight: Layout.tabStripHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // ⌘1–⌘5 切页：与底部栏**同一个键位**，用户不必记住"键盘上哪一条"。
        // 必须挂在每个 Button 自己身上（挂包装 View 不保证进快捷键表）。
        // 数字取"栏内位置 + 1"（`position` 由 `body` 的下标传入），与 `FloatingTabBar.commandKey(at:)`
        // 逐字同一套规则 —— **不按 `tab.id + 1`**：`TabSpec.id` 来自 `AppTab.rawValue`，
        // 那里留着 earnings = 3 / articles = 5 / ai = 6 的空位，`id + 1` 会把 AI 推到 ⌘7。
        .keyboardShortcut(commandKey(at: position), modifiers: .command)
        // 指针悬停高亮：纯叠加，不改几何与字色
        .hoverEffect(.highlight)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    /// 栏内位置（1 起）→ ⌘ 数字键。
    ///
    /// 与 `FloatingTabBar.commandKey(at:)` 是同一套规则的两份实现（两个组件互不依赖，
    /// 各自 keep 一份比抽公共类型更省事：抽出来就要在 DesignSystem 里多一个 internal 类型，
    /// 而它只服务这两个文件的各一行）。改规则时两处一起改。
    ///
    /// 10 项以上用 `min(position, 9)` 夹住：`Character(String(10))` 是两个字素簇，会崩。
    private func commandKey(at position: Int) -> KeyEquivalent {
        assert(position >= 1 && position <= 9, "Tab 栏超过 9 项时 ⌘ 数字键不够用")
        return KeyEquivalent(Character(String(min(position, 9))))
    }

    // MARK: - ⌃Tab / ⌃⇧Tab

    /// 顺序切页的两个隐藏按钮（设计文档 §7.1）。
    ///
    /// 挂 `.background` 里：不参与布局、不占位、不改任何像素（与 `refreshShortcut` 同一手法）。
    /// 为什么是隐藏按钮而不是 `onKeyPress`：`keyboardShortcut` 只挂在 Button 上才保证被注册进
    /// 系统快捷键表；`onKeyPress` 需要视图先拿到焦点，键盘用户会遇到"按了没反应"。
    /// 无键盘时这一段是死代码。
    private var pageShortcuts: some View {
        HStack(spacing: 0) {
            Button {
                step(by: -1)
            } label: {
                Color.clear
            }
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
            .keyboardShortcut(.tab, modifiers: [.control, .shift])

            Button {
                step(by: 1)
            } label: {
                Color.clear
            }
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
            .keyboardShortcut(.tab, modifiers: .control)
        }
    }

    /// 循环切上一页 / 下一页。
    ///
    /// 循环而不是到头停住：5 个平级目的地没有"第一页/最后一页"的语义，
    /// 从「更多」按 ⌃Tab 回到「概览」符合"翻页"的直觉；写死边界反而要多一个"到头了"的静默状态。
    ///
    /// **当前页不在顶部条里时（文章，rawValue 5）**：先归一化到"起点前一格"，再按方向走 ——
    /// 往后翻从 −1 起（+1 落到第一项「概览」），往前翻从 0 起（−1 落到最后一项「更多」）。
    /// 不能一律 `?? 0`：那样 ⌃Tab 会落到第二项、⌃⇧Tab 落到最后一项，两条都不是"翻到相邻那一页"。
    private func step(by offset: Int) {
        guard tabs.isEmpty == false else { return }
        let current = tabs.firstIndex { $0.id == selection } ?? (offset > 0 ? -1 : 0)
        let nextIndex = (current + offset + tabs.count) % tabs.count
        let nextId = tabs[nextIndex].id
        guard nextId != selection else { return }
        selection = nextId
    }
}
