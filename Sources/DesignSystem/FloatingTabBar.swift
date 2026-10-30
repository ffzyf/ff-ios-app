import SwiftUI

/// Tab 栏的数据描述（DesignSystem 不认识 AppTab，只认识这个纯数据）。
///
/// `badge` 是右上角的红色徽标（参考图四）：数字串画胶囊数字，空串只画一个圆点，
/// `nil` 什么都不画。出现条件由业务侧决定（①有新版本 ②已登录且有未读答卷），本层只负责画。
/// 默认 nil，所以旧构造点不用改。
struct TabSpec: Identifiable, Equatable {
    let id: Int
    let title: String
    let icon: String
    /// 右上角徽标文案。`nil` = 不画；`""` = 只画圆点；其他 = 数字（>99 走 `99+`）
    var badge: String? = nil
}

/// 底部液态玻璃 Tab 栏（层 2，V3.1 返工：照参考图四重做）。
///
/// 旧版是「左右内缩 24pt 的窄胶囊 + 图标 15pt + 标签 10pt」—— 五项挤成一团，
/// 选中态只是淡青柠胶囊，远看跟没选中一样。新版三处改动：
///
/// 1. **整幅宽**：只留 8pt 屏幕边距，几乎顶满，手指落点大了近一倍；
/// 2. **选中态 = 一枚 46pt 实心圆**（青柠渐变面 + 外投影），图标落在圆上用 `onLime` 字色；
///    未选中项**不给底**，只有图标 + 标签，干净；
/// 3. **徽标**挂在图标右上角，不挤占圆心。
///
/// 玻璃一律走 `glassSurface` 这个唯一入口（README §四 的硬规则）：
/// iOS 26 由 `GlassCompat` 内部落到系统 `glassEffect`，iOS 18–25 走手工玻璃 —— 本文件不出现
/// 任何 `glassEffect*` 符号，深浅两套外观因此只在一处收敛。
///
/// 选中圆的滑动用 `matchedGeometryEffect`：它在 iOS 18 起就可用，
/// 换台设备动效也不会"消失"（morph API 只有 iOS 26 有）。
struct FloatingTabBar: View {
    let tabs: [TabSpec]
    @Binding var selection: Int

    @Namespace private var knobNamespace

    /// 显式 init：`@Namespace` 是私有属性，自动生成的 memberwise init 会有可见性风险，
    /// 这里手写一份，确保跨文件构造一定可用。
    init(tabs: [TabSpec], selection: Binding<Int>) {
        self.tabs = tabs
        self._selection = selection
    }

    // MARK: - 布局常量（照参考图四的比例）

    /// 栏高：旧版 56pt 撑不下「大圆 + 标签」，提到 74pt 才有呼吸感
    private let barHeight: CGFloat = 74
    /// 选中圆直径
    private let knobSize: CGFloat = 46
    /// 未选中图标尺寸
    private let iconSize: CGFloat = 20

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(tabs) { tab in
                tabItem(tab)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(height: barHeight)
        .frame(maxWidth: .infinity)
        // 整条栏的真玻璃（唯一入口）：它是「必须透出滚动内容才能证明自己浮着」的上层元素
        .glassSurface(.floating, in: RoundedRectangle(cornerRadius: 30, style: .continuous), interactive: true)
    }

    // MARK: - 单项

    private func tabItem(_ tab: TabSpec) -> some View {
        let isSelected = (selection == tab.id)
        return Button(action: {
            guard selection != tab.id else { return }
            // 动画与轻触觉统一在 RootView 的 Binding setter 里给，这里只改值
            selection = tab.id
        }) {
            VStack(spacing: 3) {
                knob(icon: tab.icon, badge: tab.badge, selected: isSelected)
                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.limeInk : Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    /// 图标 / 选中圆 / 徽标三层。
    ///
    /// 选中时给一枚 46pt 青柠渐变圆（带投影），图标换成 `onLime` 字色；
    /// 未选中时不给底，只有图标本身 —— 五项并排不会变成五块玻璃互相打架。
    private func knob(icon: String, badge: String?, selected: Bool) -> some View {
        ZStack {
            if selected {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.lime, Theme.limeDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: Theme.limeGlow, radius: 12, y: 5)
                    // 与全部 5 个 tab 项共享 namespace：切换时圆从旧位置滑到新位置
                    .matchedGeometryEffect(id: "tab.knob", in: knobNamespace)
            }
            Image(systemName: icon)
                .font(.system(size: selected ? iconSize + 1 : iconSize, weight: .semibold))
                .foregroundStyle(selected ? Theme.onLime : Theme.textTertiary)
        }
        .frame(width: knobSize + 8, height: knobSize + 8)
        .overlay(alignment: .topTrailing) {
            badgeView(badge)
        }
    }

    // MARK: - 徽标

    /// 右上角红色徽标：空串画圆点，否则画数字胶囊。
    @ViewBuilder
    private func badgeView(_ badge: String?) -> some View {
        if let badge {
            if badge.isEmpty {
                Circle()
                    .fill(Theme.badgeRed)
                    .frame(width: 9, height: 9)
                    .offset(x: 2, y: 0)
                    .accessibilityHidden(true)
            } else {
                Text(badge)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.badgeRedInk)
                .monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background {
                    Capsule().fill(Theme.badgeRed)
                }
                .offset(x: 4, y: -2)
                .accessibilityLabel("有 " + badge + " 条新消息")
            }
        }
    }
}
