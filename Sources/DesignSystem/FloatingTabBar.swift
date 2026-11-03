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
/// 1. **整幅宽**：只留 8pt 屏幕边距（`Spacing.tabBarInset`），几乎顶满，手指落点大了近一倍；
/// 2. **选中态 = 一枚 40pt 实心圆**（青柠渐变面 + 内描边 + 外投影），图标落在圆上用 `onLime` 字色；
///    未选中项**不给底**，只有图标 + 标签，干净；
/// 3. **徽标**挂在图标右上角，不挤占圆心。
///
/// 玻璃一律走 `glassSurface` 这个唯一入口（README §四 的硬规则）：
/// iOS 26 由 `GlassCompat` 内部落到系统 `glassEffect`，iOS 18–25 走手工玻璃 —— 本文件不出现
/// 任何 `glassEffect*` 符号，深浅两套外观因此只在一处收敛。
///
/// 选中圆的滑动用 `matchedGeometryEffect`：它在 iOS 18 起就可用，
/// 换台设备动效也不会"消失"（morph API 只有 iOS 26 有）。
///
/// **V3.3「观感不对称」修正**：几何本来是绝对对称的（5 项等分、首末项中心镜像），
/// 但选中圆 40pt 与未选中图标 21pt 宽度不同，两者都在槽心居中，于是**圆的左右各多鼓出一截**。
/// 选中第 1 项时，左端只剩 36.9pt 留白、右端有 46.4pt，差 9.5pt，眼睛读成「左边顶到边、右边空一截」。
/// 所以这一版不是去挪槽位（那会破坏真正的对称），而是把「圆与图标的宽度差」收窄：
/// 圆径收窄、未选中图标微增、左右内边距外移。推导见下方布局常量。
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

    /// 栏高：3.8.1 用户反馈"栏下留了这么大的空地方"，74 → 66。
    ///
    /// 66 仍是算出来的，不是拍的：纵向内容 = 圆 40 + 间距 3 + 11pt 标签行高约 13.1
    /// ≈ **56.1pt**，加上内边距 6（上）+ 4（下）= 66.1，取 66 贴住（与旧版 74.1 → 74
    /// 同一约定：0.1pt 的缺口由行高估算值吸收，VStack 不会被压出可见的挤）。上下死空间
    /// 从 18pt 压到 10pt，栏整体上提，手指落点更贴近内容。
    /// 选中圆 40pt 的推导体系（另一套论证，见 `knobSize`）一行未动；
    /// 每项 `.contentShape(Rectangle())` + `frame(maxWidth: .infinity)` 等分也在 ——
    /// "点击不顺手"的死空间不在命中区，在栏的位置与内边距。
    private let barHeight: CGFloat = 66

    /// 选中圆直径。
    ///
    /// 为什么是 40：圆相对槽宽的"鼓出量"= (圆径 − 图标宽) / 2，圆径越接近槽宽，
    /// 居中时两侧各多出的那一截越宽，选中项在末尾时视觉重心就越偏。
    /// 收到 40 之后（栏宽 393 − 8×2 = 377，减内边距 14×2 后 5 项等分）：
    /// - 槽宽 = (377 − 14×2) / 5 = **69.8pt**
    /// - 选中圆左边缘距屏幕边 = 8 + 14 + (69.8 − 40) / 2 = **36.9pt**
    /// - 未选中图标左边缘距屏幕边 = 8 + 14 + (69.8 − 21) / 2 = **46.4pt**
    /// - 右端镜像，两端最外元素留白差 = 46.4 − 36.9 = **9.5pt**（上一版约 12.6pt）
    /// 差值没法归零 —— 圆天生比图标宽，除非牺牲"选中要一眼看出"；
    /// 能修的是把它压到 10pt 以内，并且让圆的边缘从 30.7pt 退到 36.9pt，不再"顶到屏幕边"。
    private let knobSize: CGFloat = 40

    /// 未选中图标尺寸。20 → 21：圆缩小后不补这 1pt，
    /// 未选中态会显得比选中态"虚"，切换时像图标缩水了一下。
    private let iconSize: CGFloat = 21

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // 用**位置**而不是 `tab` 本身驱动：快捷键要的是"第几格"，位置只有在这里才知道。
            // `Array(tabs.indices)` 而不是 `tabs.indices`：后者会撞上 `ForEach(Range<Int>)`
            // 那条重载（它按"range 常量"优化，与我们要的 id 语义不是一回事）。
            ForEach(Array(tabs.indices), id: \.self) { index in
                tabItem(tabs[index], position: index + 1)
            }
        }
        // 14 而不是 10：两端多出的 4pt 全部让给最外侧项，把「圆的左边缘」往外推，
        // 这是上面 36.9 / 46.4 那组数字里唯一能同时改善两端的旋钮（槽位本身必须等分，不能动）。
        .padding(.horizontal, 14)
        // 上下内边距 6 + 4（3.8.1：10 + 8 压缩而来）—— 与 barHeight = 66 的推导绑定，
        // 单独改这一对会让 VStack 的 0.9pt 余量变成负数（标签行被挤）
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(height: barHeight)
        .frame(maxWidth: .infinity)
        // 整条栏的真玻璃（唯一入口）：它是「必须透出滚动内容才能证明自己浮着」的上层元素
        .glassSurface(.floating, in: RoundedRectangle(cornerRadius: 30, style: .continuous), interactive: true)
    }

    // MARK: - 单项

    private func tabItem(_ tab: TabSpec, position: Int) -> some View {
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
                    // 未选中标签从 `textTertiary` 提到 `textSecondary`（设计文档 §8「Liquid Glass 更新」）。
                    //
                    // 这不是随手调色，理由是 iOS 27 的 Liquid Glass 新增了「玻璃着色」滑块
                    // （超清透 → 完全着色）：用户把它拉满时，玻璃底色会变深、变彩，而 11pt 的
                    // `textTertiary` 在着色玻璃上对比不足。全工程"压在浮动玻璃上的小字"只有这一处
                    // （Tab 标签），所以也只改这一处 —— 图标（21pt）不在此列：它大得多，
                    // 且未选中态靠形状而不是明度区分，提亮反而会让它去抢选中圆的注意力。
                    //
                    // 为什么不去读系统的着色设置：没有公开 API，猜一个等于把系统行为写死。
                    // 为什么不去调 `Glass` 参数：系统着色是**叠加**在用户偏好之上的，
                    // 我们调 tint 只会让深浅两套外观更难对齐，且 iPhone 上会立刻看到颜色变化 = 回归。
                    .foregroundStyle(isSelected ? Theme.limeInk : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        // ⌘1–⌘5 切页（设计文档 §7.1）。iPad 外接键盘才有意义，iPhone 上无键盘时是死代码、
        // 不占布局、不改变任何像素。
        //
        // 数字取的是**栏内位置 + 1**（`position` 由 `body` 的下标传入），**不是** `tab.id + 1`。
        // 3.28.0 修正：`TabSpec.id` 来自 `AppTab.rawValue`，而那一列刻意留着空位
        // （`earnings = 3` / `articles = 5` / 新增的 `ai = 6`），`id + 1` 会让 AI 变成 ⌘7 ——
        // 既跳号、又与视觉顺序（第 3 格）矛盾。快捷键表达的是"第几格"。
        //
        // 为什么不用 `.keyboardShortcut(.defaultAction)` 之类：只有"切到第 N 页"有天然的
        // 数字对应关系，其余动作刻意不配快捷键（§7.1 末段）。
        .keyboardShortcut(commandKey(at: position), modifiers: .command)
        // 指针悬停高亮（§7.2）：叠加在 `PressableStyle` / 裸 Button 之上，不改任何几何与字色。
        // iPad 上无指针 —— 完全无影响。
        .hoverEffect(.highlight)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    /// 栏内位置（1 起）→ ⌘ 数字键。
    ///
    /// 为什么单独一个函数：`KeyEquivalent` 只吃 `Character`，而"位置 → 字符"这个转换
    /// 与"取第几格"是同一件事的两面，写在调用处会让那条注释与代码分家。
    ///
    /// 10 项以上用 `min(position, 9)` 夹住：`Character(String(10))` 是**两个**字素簇，
    /// `Character` 的初始化会在运行期崩。栏里现在只有 5 项，`assert` 只在开发期兜底。
    private func commandKey(at position: Int) -> KeyEquivalent {
        assert(position >= 1 && position <= 9, "Tab 栏超过 9 项时 ⌘ 数字键不够用")
        return KeyEquivalent(Character(String(min(position, 9))))
    }

    /// 图标 / 选中圆 / 徽标三层。
    ///
    /// 选中时给一枚 40pt 青柠渐变圆（内描边 + 投影），图标换成 `onLime` 字色；
    /// 未选中时不给底，只有图标本身 —— 五项并排不会变成五块玻璃互相打架。
    ///
    /// **槽位对齐（V3.2 修正「文字隔一条河」，参数已随 V3.3 更新）**：槽高恒为 `knobSize`（40pt），
    /// 但图标**底部对齐槽底**，不在槽心 —— 旧的居中写法让未选中图标下方空出 17pt，
    /// 再叠 3pt 间距，图标与文字之间就横了一条 20pt 的河。
    /// 选中时用 `padding(.bottom:)` 把图标抬回圆心（圆 40、选中图标 22 → 底部留 (40−22)/2 − 1 = 8），
    /// 所以「圆底 → 文字」与「图标底 → 文字」都是 3pt，**切换时文字位置不动**。
    /// 那 −1 是光学修正：图标是方的、圆是圆的，方底压到几何圆心会显得偏上，抬 1pt 回正。
    private func knob(icon: String, badge: String?, selected: Bool) -> some View {
        let glyph = selected ? iconSize + 1 : iconSize
        return ZStack(alignment: .bottom) {
            if selected {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.lime, Theme.limeDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    // 顶部高光内描边：0.5pt、只在圆的上半圈最亮，往下收到几乎看不见。
                    // 为什么需要它：纯渐变填充在玻璃背景上是一块"平"的色片，像贴纸；
                    // 有了这道边，上半圈有亮边、下半圈没有，人眼立刻读成"有厚度的实体键"。
                    // 颜色由 `onLime` 派生（不硬编码白，也不在 View 里造色），
                    // 深浅两套外观仍由 Theme token 决定。
                    .overlay {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Theme.onLime.opacity(0.25), Theme.onLime.opacity(0.04)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    }
                    .frame(width: knobSize, height: knobSize)
                    // radius 14 / y 6：圆变小之后，原来的 12 / 5 相对而言"太硬"，
                    // 散开一点才配得上变大后的圆角玻璃，同时保持圆浮在玻璃**之上**的层次。
                    .shadow(color: Theme.limeGlow, radius: 14, y: 6)
                    // 与全部 5 个 tab 项共享 namespace：切换时圆从旧位置滑到新位置
                    .matchedGeometryEffect(id: "tab.knob", in: knobNamespace)
            }
            Image(systemName: icon)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(selected ? Theme.onLime : Theme.textTertiary)
                // 选中：抬到圆心；未选中：贴槽底，让文字接在图标脚下
                .padding(.bottom, selected ? (knobSize - glyph) / 2 - 1 : 0)
        }
        .frame(width: knobSize + 8, height: knobSize, alignment: .bottom)
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
