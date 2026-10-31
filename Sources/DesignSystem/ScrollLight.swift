import SwiftUI

// MARK: - 滚动光影的状态（3.6.0 新增）

/// 页面滚动位置 → 背景光影的两个归一化参数。
///
/// **为什么单独一个 Store 而不是让 `PageBackground` 自己读滚动偏移**：
/// `PageBackground` 是**背景层**，滚动偏移发生在**页面层**（5 个页面各自一个 `ScrollView`）。
/// 两者在 `RootView` 里是 `ZStack` 的兄弟节点，没有任何视图层级关系可以把偏移"传上去"——
/// 只能由一个共同祖先持有的对象来中转。这就是本类的全部职责：**接偏移、发参数**，
/// 不碰数据、不碰网络、不知道任何页面存在。
///
/// **为什么写 `@Published` 要节流**：滚动是每帧回调（iPhone 上 120Hz 就是每秒 120 次），
/// 而 `progress` 的唯一消费者是那块全屏背景。不节流的话背景层每帧 `body` 重算一次，
/// 一次重算要重建一个全屏径向渐变的渲染节点 —— 这正是 3.5.0 被性能问题咬过的形态。
/// 所以在**写入侧**就拦掉小于 `minDelta` 的变化，而不是指望下游去 diff。
@MainActor
final class ScrollLightStore: ObservableObject {

    /// 0 = 顶部；1 = 已下滑 `maxTravel`
    @Published private(set) var progress: Double = 0

    /// 顶部下拉超滚 0…1（`pullSpan` 到底 = 1）
    @Published private(set) var pull: Double = 0

    /// 从"顶部最亮"走到"最暗"所需的滚动距离。
    ///
    /// 900 ≈ 1.5 屏：文章 / 红石 / 收益都是 2000–6000pt 的长列表，560 只覆盖第一屏，
    /// 滑下去之后光就不动了 —— 后面几屏的滚动在光影上完全没有反馈。
    /// 用户原话是「往下滑、往上滑都要有反应」，所以行程必须跟着真实内容长度走，取 1.5 屏。
    /// 再长一点，光影的变化会慢到"看不出跟着手走"，那还不如不做。
    static let maxTravel: CGFloat = 900

    /// 顶部下拉超滚走完 0…1 所需的距离。120pt ≈ 触发 `refreshable` 的那一段行程。
    static let pullSpan: CGFloat = 120

    /// 写入阈值。滚动每帧回调，差得比这更少的写入只会让背景层白重建一次。
    /// 0.004 × 900pt = 3.6pt 位移 —— 滚动一帧的步长通常就小于这个数，够拦掉绝大多数中间帧。
    static let minDelta: Double = 0.004

    /// 为什么不写 `init()` 默认的 `@MainActor` 隔离：本类会被 `RootView` 的 `init` 直接构造，
    /// 而 View 的属性初始化器在 Swift 5 的 minimal 检查下**不一定是隔离上下文**——
    /// `SurveyStore` 的类型注释里踩过同一个坑（标了 `@MainActor` 反而报隔离错误）。
    /// 两个存储属性都有默认值、`init` 里不做任何需要 actor 的事，所以显式标 `nonisolated` 最稳。
    nonisolated init() {}

    /// 页面每帧上报滚动偏移（已含 `contentInsets.top` 的修正，即"内容顶边到容器顶的距离"）。
    /// - Parameter offset: 归一化前的原始偏移，单位 pt。负值 = 下拉超滚。
    func report(offset: CGFloat) {
        let nextProgress = Double(clamp(offset / Self.maxTravel))
        let nextPull = Double(clamp(-offset / Self.pullSpan))

        // 两个条件缺一不可，顺序也是必要的：
        //
        // 1. 前面先判 `!=`，是**节流真正生效的前提**。正常下滑时 `nextPull` 恒为 0、
        //    滑过行程终点后 `nextProgress` 恒为 1 —— 若只按"端点无条件写入"判，
        //    这两个条件就恒真，`@Published` 每帧被赋一次同值；而同值赋值**照样发
        //    `objectWillChange`**，于是"每帧节流"在真实滚动里等于不存在（QA 报的性能 bug）。
        // 2. 后面那半句"端点无条件写入"的意图保留：容差会让进度停在 0.003 这种值上，
        //    而"回到顶部 = 与 3.5.0 逐像素一致"是硬约束，差那 0.3% 就等于没回到原样。
        if nextProgress != progress,
           nextProgress == 0 || nextProgress == 1 || abs(nextProgress - progress) >= Self.minDelta {
            progress = nextProgress
        }
        if nextPull != pull,
           nextPull == 0 || nextPull == 1 || abs(nextPull - pull) >= Self.minDelta {
            pull = nextPull
        }
    }

    /// 换页时归零。
    ///
    /// 为什么必须显式调：新页面挂载后会立刻上报自己的位置（比如上次停在 400pt，
    /// 首帧就会报 0.71），但那之前有一帧的时间背景层还挂着**上一页**的进度——
    /// 表现就是"切到文章页的瞬间，光斑从上一个位置跳一下"。
    func reset() {
        // 有值才写：换页时 `reset()` 与 `withAnimation(Motion.tab)` 在同一个 runloop 里，
        // 无条件的两次赋值会多发一次 `objectWillChange`，正落在切换动画的第一帧上。
        if progress != 0 { progress = 0 }
        if pull != 0 { pull = 0 }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        // 用 `Swift.min / Swift.max` 的全名：`CGFloat` 与 CoreGraphics 的重载在这里容易选到
        // 返回 `CGFloat` 以外的版本，写明后类型推断不再依赖上下文。
        let lower = Swift.max(value, 0)
        return Swift.min(lower, 1)
    }
}

// MARK: - 环境注入

/// 默认值必须是 `nil`，不能是 `@EnvironmentObject`。
///
/// 理由：`PageBackground` 在全工程被 **9 处**调用（设置页、正文页、攻略页、监控页…），
/// 那些页面**没有** `ScrollLightStore`（它们没有滚动光影，也不该有）。
/// 若这个环境值的类型是不可选的 `ScrollLightStore` 或走 `@EnvironmentObject`，
/// SwiftUI 在那些页面上会直接 `fatalError`（"No ObservableObject of type … found"）——
/// 那是一个**只在特定 Tab 才会崩**的运行时炸弹。可选 + `nil` 默认值让"没有 store"
/// 成为一条正常路径：光固定在顶部，不随滚动动，页面照常显示。
private struct ScrollLightKey: EnvironmentKey {
    static let defaultValue: ScrollLightStore? = nil
}

extension EnvironmentValues {
    /// 滚动光影的共享状态。只在 `RootView` 注入，5 个有 `ScrollView` 的页面消费。
    var scrollLight: ScrollLightStore? {
        get { self[ScrollLightKey.self] }
        set { self[ScrollLightKey.self] = newValue }
    }
}

// MARK: - 一行接入

extension View {
    /// 给带 `ScrollView` 的页面接上滚动光影。
    ///
    /// 挂在 `ScrollView` 上（而不是里面的内容上）：`onScrollGeometryChange` 要的是
    /// **滚动容器的几何**，挂在内容上会量到内容自己的偏移，还得自己加 `insets` 之外的一堆修正。
    /// 没有注入 store 时这里是零成本的直通（`else { content }`）。
    func pageScrollLight() -> some View {
        modifier(PageScrollLightModifier())
    }
}

private struct PageScrollLightModifier: ViewModifier {
    @Environment(\.scrollLight) private var store

    func body(content: Content) -> some View {
        if let store {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                // 顶部静止时 `contentOffset.y` 等于 `-contentInsets.top`（安全区 + 导航条那段）：
                // 加回去才能让"停在顶部"精确等于 0。少这一项，iPhone 上一进页面进度就是 0.07 左右
                // （59pt 安全区 ÷ 900pt），光一开始就是暗的，"回顶部变亮"这件事永远做不到。
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newValue in
                // `store` 是 `@MainActor` 的类，而这个回调是 iOS 18 `onScrollGeometryChange`
                // 的 `@escaping (T, T) -> Void`。SwiftUI 一定在主线程调它，写明 `assumeIsolated`
                // 既让编译期隔离检查通过，也把"必须在主线程"这个前提写进代码而不是靠注释记住。
                MainActor.assumeIsolated {
                    store.report(offset: newValue)
                }
            }
        } else {
            content
        }
    }
}
