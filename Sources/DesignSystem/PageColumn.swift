import SwiftUI

/// 宽屏页面的两个通用容器能力：列宽上限 + ⌘R 刷新。
///
/// 为什么单独一个文件而不是塞进 `LayoutMetrics.swift`：一个是"值 + 注入"，
/// 一个是"给 View 用的修饰器"，混在一起会让 `LayoutMetrics.swift` 从"纯数据"
/// 变成"数据 + 视图扩展"，以后想单测 `widthClass` 就得连视图层一起编译。
extension View {
    /// 列宽上限 + 水平居中。容器比上限窄时**完全无副作用**（不会多一层 padding）。
    ///
    /// 两次 `frame` 的顺序不能反，理由是两者管的不是同一件事：
    /// - `frame(maxWidth: maxWidth, alignment: .leading)` = "这块最多这么宽，内容靠左"；
    /// - `frame(maxWidth: .infinity, alignment: .center)` = "把这整块放到可用宽度中间"。
    ///
    /// 反过来写（先 `.infinity` 居中再限宽）会在 720 的框里再居中一次，
    /// 于是所有左对齐的标题、正文、列表都跑到屏幕中间 —— 全页偏移 20pt 起，
    /// 而且"看起来像是居中排版"，很难一眼认出是写错了顺序。
    ///
    /// 窄屏下为什么零影响：iPhone 393 的 proposal 是 353（扣掉 page padding 20×2），
    /// 比 720 / 640 都小，`maxWidth` 不生效；第二个 `frame(maxWidth: .infinity)` 的
    /// proposal 也是 353，等于没做事。
    func pageColumn(_ maxWidth: CGFloat) -> some View {
        self
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// 用隐藏按钮挂 ⌘R（iPad 外接键盘）。无键盘时零影响。
    ///
    /// 为什么不新增一个可见的刷新按钮：iPhone 上多一个按钮就是多一处观感回归，
    /// 而这些页面的刷新入口已经在页面自己的头部（概览下拉、收益的 ⟳ 等）。
    /// 快捷键要的是"手指不离开键盘能做的事"，不是"多一个控件"。
    ///
    /// 实现细节逐条都有原因：
    /// - 挂在 `.background` 里：不参与页面布局，不占位、不影响任何 frame；
    /// - `opacity(0)` + `frame(width: 0, height: 0)`：即使布局异常也不会挤出 1pt 白块；
    /// - `accessibilityHidden(true)`：VoiceOver 不应该读到一个看不见的按钮；
    /// - `.buttonStyle(.plain)`：不加的话 `Button` 的默认样式（iOS 上其实是 plain，
    ///   但 macOS/iPadOS 语境下会带一层高亮）可能留下可见痕迹，且会参与按压动画；
    /// - 用 `Button` 而不是 `.onKeyPress`：`keyboardShortcut` 只挂在 Button 上能保证
    ///   系统把它注册进快捷键表（含 iPad 上长按 ⌘ 的快捷键面板），`onKeyPress` 需要
    ///   视图获得焦点才收得到，键盘用户会"按了没反应"。
    func refreshShortcut(_ action: @escaping () -> Void) -> some View {
        self.background {
            Button(action: action) {
                Color.clear
            }
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    /// 用隐藏按钮挂 ⌘,（打开设置）。iPad 上 ⌘, 是肌肉记忆，iPhone 无键盘时是死代码。
    ///
    /// 与 `refreshShortcut` 逐行同款，只换键：隐藏按钮的四个约束（不占位 / 不可见 /
    /// VoiceOver 跳过 / 一定挂在本层）在那边已经论证过，这里不重复第二套写法 ——
    /// 两套写法迟早会有一套忘记 `frame(0,0)`，然后某个页面多出 1pt 白块。
    func settingsShortcut(_ action: @escaping () -> Void) -> some View {
        self.background {
            Button(action: action) {
                Color.clear
            }
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    /// 量出本子树的真实高度，写回 `Binding`。
    ///
    /// **为什么需要它**（设计文档 §4.0 规则 1 的落地难点）：
    /// 规则原文是"副列 `VStack` 里在会变长的内容之后放 `Spacer(minLength: columnGap)`，
    /// 它把最后一组压到底边"。但 `Spacer` 只吸不放 —— 它吸的是**父级给出的高度**，
    /// 而在 `ScrollView` 里 `HStack(alignment: .top)` 拿到的纵向 proposal 是"未定"
    /// （滚动轴方向不约束），副列于是只按内容自然高排列，`Spacer` 只贡献 32pt。
    /// 结果是"规则写了、底边依旧不齐"。
    ///
    /// 所以先量主列、再给副列一个确定高度：`Spacer` 这时才吸得到差额。
    /// 用 `GeometryReader` + `PreferenceKey`（与 `ArticleDetailView` 采集滚动偏移同一手法），
    /// 不引 iOS 17+ 的 `onGeometryChange` —— 本机无 Xcode，签名没把握的 API 不赌。
    /// 挂在 `.background` 里，不参与布局、不改任何尺寸。
    func measureHeight(into height: Binding<CGFloat>) -> some View {
        self
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: MeasuredHeightKey.self, value: proxy.size.height)
                }
            }
            .onPreferenceChange(MeasuredHeightKey.self) { value in
                // 只在真的变了才写：量到的小数抖动会让页面反复重算 body
                if abs(height.wrappedValue - value) > 0.5 {
                    height.wrappedValue = value
                }
            }
    }
}

/// 子树高度的采集键。取 `max` 而不是后者覆盖前者：同一子树里可能有多个生产者。
private struct MeasuredHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
