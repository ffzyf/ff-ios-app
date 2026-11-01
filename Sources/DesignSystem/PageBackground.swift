import SwiftUI

/// 深空三层背景（PRD §4.1，3.6.0 起把光斑换成"跟着滚动走的光影"）：
/// 1. **底色渐变**（顶 → 底）：`bgRaise` → `bgBase`（55% 处）→ `bgDeep`（最底）
/// 2. **滚动光影**：跟着滚动沉下去的主光 + 底部浮起的余晖（`glow == true` 时）
/// 3. **底部压影**：底部 35% 的灰蓝渐变，浅色靠它给页脚一点重量，深色下等于没画
///
/// 对外签名 `PageBackground(glow:)` **一个字都没改** —— 全工程 9 处调用点零改动。
///
/// **为什么第 1 层要加 `bgDeep`**：3.5.0 是 `[bgRaise, bgBase, bgBase]`，后 45% 完全是同一个色，
/// 浅色下（`#F7F9F6` → `#EDF1EC`）从上到下几乎一个色，用户的原话是"一片白"。
/// 第三段压暗 3–6% 之后，整页有了明确的明暗方向，光斑沉下去时才有"底下有东西接住"的感觉。
///
/// 双主题（批次 1）：光的**半径与强度**是全工程仅有的几个"必须随外观变、又不能写成 Color"的数值，
/// 它们走 `ThemeMetrics`（`ThemeScope` 注入）。这里不判深浅 —— 只乘环境给的数。
struct PageBackground: View {
    var glow: Bool = true

    /// 滚动光影的共享状态。**可选**：设置页 / 正文页 / 攻略页等没有 store，走 `nil` 分支。
    @Environment(\.scrollLight) private var scrollLight

    var body: some View {
        ZStack {
            baseGradient
            if glow {
                lightLayer
            }
            footerShadow
        }
        // 3.12.0 修「手机版整页横向溢出」（P0 事故）：
        //
        // 3.11.0 把 `ambientDrift` 写成 `ZStack` 的**兄弟节点**，而 `AmbientDriftLayer`
        // 内部是固定 520×520 的圆（`blobDiameter = 520`）。`ZStack` 的尺寸 = 子视图最大尺寸，
        // 于是整个 `PageBackground` 被撑到 **520pt 宽**；它又是 `RootView.pageContent` 那个
        // `ZStack` 的最底层，于是根视图一起被撑到 520 —— 在 393pt 的 iPhone 上居中后
        // 左右各溢出 63.5pt（用户截图里左边"11月1日"的 `11` 被切、右边卡片被切）。
        //
        // `.overlay` 与 `ZStack` 的本质区别：overlay 的**尺寸由父视图决定**，
        // 它自己画多大都**不参与父级布局**（会溢出，但不会反过来撑大父视图）。
        // 氛围层本来就该"铺满一屏、画到屏幕外也没关系"，这正是 overlay 的语义。
        //
        // 顺序也保住了：原来是 base → light → ambient → footerShadow，
        // 现在 footerShadow 在 ZStack 里、ambient 叠在**最上面**。
        // footerShadow 在深色下是全透明、浅色下是 5% 灰蓝，氛围层（≤0.05）压在它之上
        // 像素级不可辨；而"氛围层在光影之上"这条原先的层次关系一字未变。
        .overlay {
            ambientDrift
        }
        // 3.12.0 第二层保险：**即使将来某一层又引入了一个固定大尺寸子视图**，
        // 这一句也把背景钉回"父视图给的 proposal"（全屏），而不是让 `ZStack` 去取最大值。
        // 只有 `maxWidth/maxHeight`，没有写死的数字 —— 旋转 / 分屏 / Stage Manager 全都跟着走。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// 第 1 层：底色渐变。
    ///
    /// `locations` 写在 0.55 而不是 0.5：`bgBase` 是"大面积主段"，它该覆盖屏幕中段偏下，
    /// 让页脚的最深一档（`bgDeep`）只占最后那一截。0.5 会让过渡线正好落在视觉中线上，
    /// iPad 竖屏上那条线看得出来。
    private var baseGradient: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.bgRaise, location: 0),
                .init(color: Theme.bgBase, location: 0.55),
                .init(color: Theme.bgDeep, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 第 2 层：滚动光影。
    ///
    /// 有 store → 交给会订阅 `@Published` 的 `ScrollLightHost`（`@ObservedObject` 是唯一
    /// 能让 `ObservableObject` 的变化驱动重绘的方式；`@Environment` 只拿引用，不订阅）；
    /// 没有 store → 直接给一份恒为 0 的参数，与 3.5.0 的静态光斑完全一致。
    @ViewBuilder
    private var lightLayer: some View {
        if let scrollLight {
            ScrollLightHost(store: scrollLight)
        } else {
            ScrollLightLayer(progress: 0, pull: 0)
        }
    }

    /// 第 3 层（3.11.0）：氛围漂移。
    ///
    /// 用户原话："现在的所有主题背景都很统一感觉，我不是让你设计动态效果了吗但是也别太动态"。
    /// 所以这一层只做一件事：让背景在**几十秒的尺度上**呼吸一下，不做任何看得出来的位移。
    private var ambientDrift: some View {
        AmbientDriftLayer()
    }

    /// 第 3 层：底部压影。
    ///
    /// **为什么用 `glassShadowNear` 而不是 `glassShadow` / 任何黑影 token**：
    /// `glassShadowNear` 在深色下是 `#000000` 透明度 **0.00** —— 也就是说这一层在深色模式
    /// 画了等于没画，深色像素零变化（本轮"加东西但深色不脏"的全部秘密就在这一个 token 上）。
    /// 浅色下它是灰蓝 5%（`#1B2E3F`），正是 PRD §3.1 第 4 条要的"不能用黑影做投影，会发灰显脏"。
    ///
    /// **为什么用 stops 而不是 `.frame(height:)`**：把停靠点压到 0.65→1.0 与"底部 35% 高的一条"
    /// 在像素上等价，但前者不需要 `GeometryReader` 参与布局 —— 背景层每帧被滚动驱动重绘，
    /// 任何一次额外的几何 proposal 都是白给的代价。旋转 / 分屏下也自动正确。
    private var footerShadow: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.glassHighlightFade, location: 0.65),
                .init(color: Theme.glassShadowNear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - 订阅层（只有这一层会因为滚动重绘）

/// 把 `ScrollLightStore` 的两个数取出来，交给纯渲染的 `ScrollLightLayer`。
///
/// 为什么要拆出这一个小壳：`@ObservedObject` 需要一个**非可选**的对象，
/// 而环境里拿到的 store 是可选的（见 `ScrollLightKey`）。拆开之后
/// "订阅"与"渲染"各自单一职责，`ScrollLightLayer` 也能在没有 store 的页面上直接复用。
private struct ScrollLightHost: View {
    @ObservedObject var store: ScrollLightStore

    var body: some View {
        ScrollLightLayer(progress: store.progress, pull: store.pull)
    }
}

// MARK: - 光本身

/// 两束光的渲染层。**输入只有两个归一化参数**，不含任何状态。
///
/// 三条硬约束（都是 3.5.0 性能事故换来的）：
/// 1. `RadialGradient` 的 `colors` / `center` / `endRadius` **在滚动期间恒定**，
///    所有动态只走 `.offset` / `.scaleEffect` / `.opacity` 三个合成层变换。
///    渐变对象每变一次，SwiftUI 要重新插值整块全屏像素；而变换只是把已画好的图层挪一下。
/// 2. 半径仍然以「**实际被涂区域的最长边 × 0.9**」为基准，仍在 `onAppear` / `onChange` 里量，
///    初值仍是 852 —— 这套做法是上一版为了「分屏 / 旋转半径不算错」定的，不许退回 `UIScreen`。
/// 3. 不判 `colorScheme`：深浅差异全部来自 `ThemeMetrics.scrollGlowAlpha`。
private struct ScrollLightLayer: View {
    /// 滚动进度 0…1
    let progress: Double
    /// 顶部下拉超滚 0…1
    let pull: Double

    /// 数值 token（唯一允许随外观变的一组，见 ThemeMetrics）
    @Environment(\.themeMetrics) private var metrics

    /// 前庭敏感用户：光斑不该被整页拖着走。关掉时把两个参数都当 0（光固定在顶部、不亮不暗）。
    /// **在 View 层判它是对的**（lint 只拦 `colorScheme`），因为 Reduce Motion 本来就是视图级偏好。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 绘制区域的最大边。只在 `onAppear` 与尺寸真变时写入，滚动 / Tab 动画期间不变 → 不重算渐变。
    ///
    /// 初值 852 = 393×852 的长边，于是首帧半径 = 852 × 0.9 = **766.8**，
    /// 与 3.5.0 在 iPhone 上逐像素相同 —— 即使 `onAppear` 因为任何原因没跑到，也不会闪一个错的半径。
    @State private var maxDimension: CGFloat = 852

    /// 主光的覆盖比例：0.9（沿用 3.5.0 的 766.8 基准）
    private static let spanRatio: CGFloat = 0.9
    /// 底部余晖比主光再收一档，压住"两个一样亮的光球"的廉价感
    private static let afterglowRatio: CGFloat = 0.85

    /// 下拉最亮一档（pull = 1 时的系数）。见 `mainLight` 里的解释。
    private static let pullPeak: Double = 1.85

    // Reduce Motion 下的两个"冻结"参数
    private var p: Double { reduceMotion ? 0 : progress }
    private var q: Double { reduceMotion ? 0 : pull }

    var body: some View {
        ZStack {
            mainLight
            afterglow
        }
        // 半径与几何布局无关（只取决于被绘制的区域有多大），不进 GeometryReader 的每帧布局路径。
        // 为什么不复用 `layoutMetrics.containerSize`：根部量到的那个尺寸是不是含状态栏 / Home
        // Indicator，取决于 SwiftUI 在该层的 proposal 语义；半径应当相对「**实际被涂的那块区域**」算，
        // 那就到涂它的这一层去量。`PageBackground` 带 `.ignoresSafeArea()`，这里量到的就是全屏。
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { maxDimension = max(proxy.size.width, proxy.size.height) }
                    .onChange(of: proxy.size) { _, newSize in
                        let next = max(newSize.width, newSize.height)
                        // 只在尺寸真变时写：旋转 / 分屏才触发，滚动与 Tab 滑动期间恒定
                        if next > 0, next != maxDimension { maxDimension = next }
                    }
            }
        }
    }

    /// 主光 A：左上角那束。下滑 → 沉下去、变暗、收一点；顶部下拉 → 亮一档、扩一圈。
    ///
    /// **为什么 alpha 烘进渐变、`.opacity` 只乘一个 ≤ 1 的系数**：
    /// `.opacity(_:)` 的入参会被合成层钳在 0…1，若渐变里直接烘 0.07、下拉时乘 1.85，
    /// 那 85% 的提亮会被**静默吃掉**（用户看到的是"下拉完全没反应"）。
    /// 所以渐变里烘的是 `0.07 × 1.85`，静止时再乘回 `1 / 1.85`：
    /// 有效 alpha = 0.07 —— **与 3.5.0 逐像素相同**，同时给下拉留出了提亮空间。
    private var mainLight: some View {
        RadialGradient(
            gradient: Self.gradient(baseAlpha: metrics.scrollGlowAlpha * Self.pullPeak),
            center: UnitPoint(x: 0.20, y: -0.10),
            startRadius: 0,
            endRadius: maxDimension * Self.spanRatio
        )
        // 1 - 0.16p：下滑时收 16%（光"退远"了）；+ 0.10q：下拉时涨 10%（回弹时扩散一下）
        .scaleEffect(CGFloat((1 - 0.16 * p) + 0.10 * q))
        // (1 - 0.40p)：下滑变暗 40%；(1 + 0.85q)：下拉提亮 85%；再除以 pullPeak 归一到 0…1
        .opacity(((1 - 0.40 * p) * (1 + 0.85 * q)) / Self.pullPeak)
        // 0.30 × 长边：下滑到底时整束光下沉 30% 屏高，正好落到"页脚压影"上方
        .offset(y: 0.30 * maxDimension * CGFloat(p))
    }

    /// 余晖 B：右下角浮起的那层。`p = 0` 时**完全不出**（不透明度 0），
    /// 所以顶部未滚动时这一束对像素零贡献 —— 3.5.0 的那颗光斑在哪，现在还在哪。
    private var afterglow: some View {
        RadialGradient(
            gradient: Self.gradient(baseAlpha: metrics.scrollGlowAlpha),
            center: UnitPoint(x: 0.84, y: 1.06),
            startRadius: 0,
            endRadius: maxDimension * Self.spanRatio * Self.afterglowRatio
        )
        // 系数 0.45p（基准 alpha 已经烘在渐变里，见 `gradient(baseAlpha:)`）：
        // 最深时只有主光的 45%，是"余晖"不是"第二颗太阳"
        .opacity(0.45 * p)
        // -0.14 × 长边：往上浮 14%，与主光的下沉形成对冲，屏幕才不会整体变暗
        .offset(y: -0.14 * maxDimension * CGFloat(p))
    }

    /// 颜色停靠点固定（只随外观变、不随滚动变）：抽成函数，避免每次 `body` 重建 `Gradient` 对象。
    ///
    /// 两束光共用同一个颜色形状（中心 → 边缘淡出），只有基准 alpha 不同：
    /// 渐变里**只有这一个不透明度值**，圆心与半径都是常量，所以滚动期间这个对象是稳定的。
    private static func gradient(baseAlpha: Double) -> Gradient {
        Gradient(colors: [
            Theme.lime.opacity(baseAlpha),
            Theme.lime.opacity(0)
        ])
    }
}

// MARK: - 氛围漂移（3.11.0）

/// 极慢氛围层：两团**极淡**的色斑沿对角线来回漂移，单程 60s。
///
/// ## 判据（写在这里，验收时逐条比）
///
/// **静止盯着看 10 秒，不应该注意到它在动**；但截图对比能看出层次，
/// 来回切两个页面时能感觉到"背景是活的"。三条数字就是为了这个判据定的：
///
/// | 参数 | 值 | 为什么 |
/// |---|---|---|
/// | 单团不透明度 | ≤0.05 | 0.07 以上在纯深底上就能看出"一块雾在挪" |
/// | 单程时长 | 60s（铁律下限 40s） | 60s 走 18pt ≈ 0.3pt/s，肉眼无从察觉 |
/// | 单程位移 | ≤18pt | 相对 852pt 屏高只有 2%，是"呼吸"不是"平移" |
///
/// ## 三条纪律
///
/// 1. **只动 `offset`**：颜色、半径、圆心全固定，不参与任何逐帧重算；
/// 2. **不读 `scrollLight`**：它与滚动完全解耦（`ScrollLightLayer` 的语义因此一字未变）；
/// 3. **`reduceMotion` 下完全不启动**：连初始的偏移都不给，图层退化成一张静态柔光。
///
/// 为什么不做成第三束"光"：光是方向的（有明暗中心），氛围层是**没有方向**的 ——
/// 它得看起来像背景本身在缓慢地变化，而不是又打了一盏灯。
private struct AmbientDriftLayer: View {

    /// 前庭敏感用户：整层退化为静态
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 是否已漂到另一头（`false` = 起点）
    @State private var drifted: Bool = false

    /// 单团直径（pt）。520 约等于 61% 屏高：大到看不出"这是一个圆"，
    /// 只剩中心到边缘的渐变 —— 那才是"背景在变"的观感。
    private static let blobDiameter: CGFloat = 520
    /// 单团峰值不透明度（判据表里的 0.05）
    private static let blobAlpha: Double = 0.05
    /// 单程时长（秒）
    private static let tripDuration: Double = 60

    var body: some View {
        ZStack {
            blob(Theme.lime)
                .offset(x: (drifted ? 18 : -18) - 96,
                        y: (drifted ? 14 : -14) - 210)
            blob(Theme.limeBright)
                .offset(x: (drifted ? -16 : 16) + 104,
                        y: (drifted ? -12 : 12) + 240)
        }
        // 3.12.0：这一层现在挂在 `PageBackground` 的 `.overlay` 上（不再参与父级布局），
        // 但它仍然是"背景"，不该吃任何触摸。外层虽然已经 `allowsHitTesting(false)`，
        // 这里再写一次是**局部自洽**：把这一层单独搬进别的容器时它也不会变成一个隐形挡板。
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: Self.tripDuration).repeatForever(autoreverses: true)) {
                drifted = true
            }
        }
        // 退场复位：`repeatForever` 的动画挂在 `drifted` 这个 `@State` 上，而 `@State` 会在
        // 视图被移出层级后**继续持有**它的值（包含退场前已为 true 的那一份）。二次进场时
        // `withAnimation { drifted = true }` 就是"true → true"，SwiftUI 认为没有变化，
        // 于是整层永久静止 —— 现象是"第二次进这个页面，氛围层不漂了"，且极难复现。
        // 这里显式复位：退场即回到起点，每次进场都是一次全新的 0 → 1 动画。
        .onDisappear {
            drifted = false
        }
    }

    /// 一团柔光：中心 0.05 → 边缘 0 的径向渐变，没有任何描边与模糊
    private func blob(_ color: Color) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(Self.blobAlpha), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: Self.blobDiameter / 2
                )
            )
            .frame(width: Self.blobDiameter, height: Self.blobDiameter)
    }
}
