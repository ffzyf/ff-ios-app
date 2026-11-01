import SwiftUI

/// iPad **与 iPhone** 的立体卡（伪 3D 视差）—— 手指拖动时卡片随视角倾斜 + 分层深度 + 高光随动。
///
/// 为什么是"伪 3D"（`rotation3DEffect`）而不是 SceneKit / RealityKit + usdz，
/// 见设计报告 §3.1 的四条。最硬的一条是：本机没有 Xcode、CI 只做 `xcodebuild build`，
/// 真 3D 的材质 / 光照 / 相机角全是**编译期零信号**，改一次参数要拿一轮 CI（8 分钟起）
/// 赌一个看不见的结果。而这个实现最坏也只是"难看"，不会崩。
///
/// ## 挂载条件（3.10.0 从"仅宽档"下放到全部档位）
/// 旧版只在宽档（iPad）挂载，理由是 `DragGesture` 会与 `ScrollView` 竞争竖直拖拽。
/// 但这个风险**已经被轴向锁（`axisLock`）彻底解决**：判出纵向拖拽就整轮不倾斜、
/// 把手势整个让给滚动 —— "iPhone 卡片区页面滚不动"在物理上不可能发生，
/// 真正剩下的挂载条件只有前庭安全这一条。所以现在的条件是：
///
/// 1. **`accessibilityReduceMotion` 为真 → 整个 modifier 不挂载**（不是角度归零）：
///    前庭敏感的用户是"拖一下晃一下"比"完全不动"糟得多；
/// 2. 全部档位都挂载（iPhone 单列全宽卡同样有玻璃厚度感）；
///    iPhone 的最大倾角收一档（4° vs iPad 5.5°），理由见
///    `LayoutMetrics.cardTiltMaxAngle` 的注释 —— 单列全宽卡同样的角度视觉幅度更大。
extension View {

    /// 给卡片挂伪 3D 倾斜。**减弱动态效果时不挂载**；其余档位生效
    ///（窄档角度由 `LayoutMetrics.cardTiltMaxAngle` 收敛到 4°）。
    ///
    /// 调用点必须挂在卡片**最外层**（`.glassSurface` 之外）：旋转要作用在玻璃的外层，
    /// 玻璃才能继续采样它背后的页面背景；塞进玻璃内部会被离屏渲染，采样到透明 §3.4。
    ///
    /// - Parameter cornerRadius: 高光遮罩的圆角，必须与卡本身的圆角一致，否则遮罩在圆角处露直角。
    func cardTilt(cornerRadius: CGFloat = Radius.card) -> some View {
        modifier(CardTiltModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - 实现

private struct CardTiltModifier: ViewModifier {

    /// 减弱动态效果 → 整个 modifier 不挂载（见文件头的理由，不是角度归零）。
    /// **这是唯一的挂载条件**（3.10.0 起）：轴向锁已经兜住了"卡 vs ScrollView"的
    /// 手势竞争，宽窄档都能安全挂载。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 档位与最大倾角：窄档 4° / 宽档 5.5°，判据与常量都在 `LayoutMetrics`
    ///（角度跟卡宽走，是版式档位的属性，见那里的注释）
    @Environment(\.layoutMetrics) private var metrics

    /// 每轴 −1…1 的归一化倾斜量。用 `CGSize` 装两个轴而不是开两个 `@State`：
    /// 回弹动画的 `value:` 只要观察这一个值就够，两轴的回弹必然同时开始、同时结束。
    @State private var tilt: CGSize = .zero
    /// 手指是否还在拖：跟手时不给动画（每帧直接写 `@State`），松手才给 spring
    @State private var isDragging: Bool = false
    /// 本轮手势锁定的轴向。`nil` = 还没判出来（位移不足 8pt）或手势已结束。
    ///
    /// ## 为什么必须先锁轴，再决定"这一次谁赢"
    /// 这个手势挂在 `highPriorityGesture` 上：一旦识别，它就压过祖先 `ScrollView`
    /// 的拖拽手势 —— 手指落在卡里**竖着**拖，页面纹丝不动，只有卡在倾斜。iPad 上
    /// 红石倒计时卡 344pt 高，几乎占掉首屏一半，等于把首屏一半面积的竖直手势全吞掉，
    /// 用户读到的是"页面滚不动、App 卡死了"。而这类回归在模拟器里极难复现：
    /// 必须恰好拖在卡片区域内才会出现。
    ///
    /// 所以规则只有一条：**横向拖 = 用户在玩这张卡（我们倾斜）；纵向拖 = 用户想滚页面，
    /// 必须是滚动赢。** 锁只在 `onChanged` 里判一次、整轮手势不再改判 —— 中途改判会让
    /// 一次拖动里"先倾斜后滚动"，两种反馈混在一起比只做一件更难读。
    @State private var axisLock: Axis? = nil

    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = Radius.card) {
        self.cornerRadius = cornerRadius
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        // 挂载条件只剩前庭安全这一条（3.10.0 起 iPhone 也挂载）：
        // 轴向锁（axisLock）已保证"纵向拖 = 滚动赢"，DragGesture 不再吞掉卡片区滚动；
        // 角度由 `metrics.cardTiltMaxAngle` 按档位收敛（窄 4° / 宽 5.5°）。
        if !reduceMotion {
            decorated(content)
        } else {
            // 与"减弱动态效果"的用户设置逐像素一致：连一个 modifier 都不多
            content
        }
    }

    /// 完整的 modifier 链。**顺序不能调**（设计报告 §3.2）：
    /// 高光用 `.overlay` 挂在旋转**之前**，于是它跟着卡一起转；`.shadow` 画的是旋转之后的
    /// 整个轮廓，所以影跟着歪、不会被留在原地。
    private func decorated(_ content: Content) -> some View {
        content
            // 1 高光层：不占布局、不吃触摸，静止时 α=0（见 `highlight`）
            .overlay { highlight }
            // 2 两次 3D 旋转：绕两个正交轴各转一次 = 复合旋转，比构造一条斜轴好读
            .rotation3DEffect(
                .degrees(pitch),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                perspective: Tilt.perspective
            )
            .rotation3DEffect(
                .degrees(yaw),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                perspective: Tilt.perspective
            )
            // 3 卡面视差：整卡随倾斜平移一点点，读作"这块玻璃有厚度"
            .offset(x: tilt.width * Tilt.parallaxCard, y: tilt.height * Tilt.parallaxCard)
            // 4 接触影。深色下 `glassShadowNear` 全透明 → 深色模式零视觉变化
            .shadow(
                color: Theme.glassShadowNear,
                radius: Tilt.shadowRadius(magnitude),
                x: tilt.width * Tilt.shadowShift,
                y: tilt.height * Tilt.shadowShift + Tilt.shadowRestY
            )
            // 5 手势
            .highPriorityGesture(drag)
            // 6 回弹：跟手给 nil（无动画、每帧直写），松手那一帧才切到 spring。
            //    不能写成 `withAnimation` —— `RootView` 在祖先层挂了
            //    `.transaction { $0.animation = nil }`，会被整棵吃掉（§3.4）
            .animation(isDragging ? nil : Tilt.settle, value: tilt)
            // 7 倾斜中的卡压住邻居（静止时回到同一层，不改变任何静态布局）
            .zIndex(tilt == .zero ? 0 : 1)
    }

    // MARK: - 手势

    /// 为什么是 `highPriorityGesture` 而不是 `simultaneousGesture`（§3.5 三种接法的取舍）：
    /// `simultaneousGesture` 下拖拽与卡片的 `Button` 会**同时识别**，松手时 Button 照样触发
    /// action → "斜着拖一下就打开了详情页"。而 `minimumDistance: 0` 的普通 `.gesture` 会把
    /// 所有触摸都判成拖拽 → 卡点不开了。
    /// 只有 `highPriorityGesture` + 8pt 死区能做到互斥且阈值明确：
    /// 位移 < 8pt 高优先级手势不识别 → Button 正常触发；≥ 8pt 它胜出 → Button 的 tap 被取消。
    ///
    /// `onEnded` **只回弹**，绝不调用 action / 触发导航：拖一下≠点一下。
    ///
    /// 上面只解决了"卡 vs Button"的互斥，**没解决"卡 vs ScrollView"** —— 后者由 `axisLock`
    /// 兜住：判出纵向就整轮不倾斜，把竖直手势整个让给 `ScrollView`。少了这一步，
    /// iPad 上 344pt 高的红石卡会吞掉首屏一半面积的滚动（理由见 `axisLock` 的注释）。
    private var drag: some Gesture {
        DragGesture(minimumDistance: Tilt.minimumDistance)
            .onChanged { value in
                isDragging = true

                // ① 锁轴：还没判过、且位移已经够大时判这一次。
                // 阈值与手势自己的死区取同一个数（`Tilt.minimumDistance`）——
                // 系统刚把这一下判成"拖"的同一刻我们就定轴，不会出现"已经倾斜了才
                // 想起来要判方向"。用平方比大小，省一次 `sqrt`。
                if axisLock == nil {
                    let width = value.translation.width
                    let height = value.translation.height
                    let threshold = Tilt.minimumDistance
                    if width * width + height * height >= threshold * threshold {
                        axisLock = abs(width) >= abs(height) ? .horizontal : .vertical
                    }
                }

                // ② 纵向（以及还没判出来的那几帧）：一个像素都不倾斜。
                // `tilt` 原样不动（静止时本来就是 `.zero`），于是这一整轮手势里
                // 卡面没有任何位移，手势竞争自然由祖先 `ScrollView` 接手 ——
                // 不是"我们倾斜完再让给它"，是"我们从头到尾没接"。
                guard axisLock == .horizontal else { return }

                // 位移取 `value.translation`（累积位移），不需要 `value.location` 与
                // 卡宽做除法 —— 于是**一个 GeometryReader 都不引入**，
                // `LayoutMetricsScope` 那条"全工程只有一个 GeometryReader 参与尺寸判定"的纪律继续成立
                tilt = Tilt.clamped(
                    width: value.translation.width / Tilt.travel,
                    height: value.translation.height / Tilt.travel
                )
            }
            .onEnded { _ in
                isDragging = false
                tilt = .zero
                // 轴锁是"这一轮手势"的私有状态，必须与倾斜量一起清掉：
                // 留到下一轮，用户上一次横着拖过之后竖着拖就又滚不动了。
                axisLock = nil
            }
    }

    // MARK: - 派生量

    /// 绕 X 轴：上下拖。负号让"往下拖"读作"上缘朝观者抬起来"。
    /// 角度来自 `LayoutMetrics.cardTiltMaxAngle`（窄档收敛到 4°，理由见那边）
    private var pitch: Double { -Double(tilt.height) * metrics.cardTiltMaxAngle }

    /// 绕 Y 轴：左右拖
    private var yaw: Double { Double(tilt.width) * metrics.cardTiltMaxAngle }

    /// 倾斜强度 0…1：高光透明度与阴影半径都只看这一维，不同方向同强度应当长得一样
    private var magnitude: CGFloat {
        min(1, (tilt.width * tilt.width + tilt.height * tilt.height).squareRoot())
    }

    // MARK: - 高光

    /// 随倾斜滑动的斜向渐变 = 光源固定在天上、玻璃在自己转。
    ///
    /// 颜色两端都是 token（`Theme.glassSheen` → `Theme.glassHighlightFade`），**不现造色**：
    /// ① 就地为白底加压透明度直接违反主题闸门规则 3；② 题目已给 `glassSheen`（深 3.5% /
    /// 浅 30%）—— 浅色卡上它的 α 天生就低，而 `glassHighlight`（浅 95%）压上去是一块白斑；
    /// ③ `glassHighlightFade` 是"两端都是 token 的 0"，渐变的透明端也不写 `.opacity(0)`，
    ///    浅色外观下不会冒出一个没人审过的硬编码值。
    ///
    /// 静止时 `magnitude == 0` → 整层完全不可见，浅色卡不会被糊一层。
    private var highlight: some View {
        LinearGradient(
            colors: [Theme.glassSheen, Theme.glassHighlightFade],
            startPoint: UnitPoint(x: 0.5 - tilt.width * Tilt.highlightSlide,
                                  y: 0.5 - tilt.height * Tilt.highlightSlide),
            endPoint: UnitPoint(x: 1.0 - tilt.width * Tilt.highlightSlide,
                                y: 1.0 - tilt.height * Tilt.highlightSlide)
        )
        .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .opacity(Tilt.highlightAlpha * magnitude)
        .allowsHitTesting(false)
    }
}

// MARK: - 参数表

/// 参数集中在一处，全部 private —— **不进 `Motion` / `Spacing`**，避免动那两个热点文件。
///
/// 每一条的取值依据见设计报告 §3.2 的表，这里只写"量纲"：角度是 `Double`（喂 `Angle.degrees`），
/// 位移与透视是 `CGFloat`（与 SwiftUI 的 pt 参数天然同类型，省掉满屏的显式转换）。
private enum Tilt {
    // 最大倾角已下沉到 `LayoutMetrics.tiltAngleWide / tiltAngleCompact`
    //（角度跟版式档位走，不跟手势走；两个档的取值理由见 `LayoutMetrics.cardTiltMaxAngle`）。
    /// 透视强度。0.45 时近/远边的长度差约 8%，玻璃描边还看不出破绽
    static let perspective: CGFloat = 0.45
    /// 手势行程（pt）：拖满 260pt 才到角度上限，这就是阻尼（软映射，不是 1:1 跟手）
    static let travel: CGFloat = 260
    /// 跟手死区（pt）：8pt 以内判"点击卡"，超过才判"拖卡"
    static let minimumDistance: CGFloat = 8
    /// 回弹。`response 0.42` 与 `Motion.push` 同量级（一次呼吸），`damping 0.72`
    /// 比 `Motion.press`(0.7) 略高 → 只过冲一丁点就停，不晃
    static let settle: Animation = .spring(response: 0.42, dampingFraction: 0.72)
    /// 卡面视差（pt）。太大就是"卡片在飘"，不是"卡片有厚度"
    static let parallaxCard: CGFloat = 4
    /// 高光反向位移系数：文档里的 `parallaxHighlight = −10` 在这里是"— tilt.width × 0.6"，
    /// 即逆着倾斜方向以更大幅度滑动 = 光源固定、玻璃在转（§3.2 唯一能明显读出深度的量）
    static let highlightSlide: CGFloat = 0.6
    /// 高光不透明度上限：再乘 `glassSheen` 自身的 α（深 3.5% / 浅 30%）
    static let highlightAlpha: CGFloat = 0.6
    /// 阴影随倾斜偏移的最大值（pt），方向朝"远离光源"
    static let shadowShift: CGFloat = 10
    /// 静止时阴影的固有下沉量（pt）：不加这一项，倾斜的卡静止时会比邻居缺少离地感
    static let shadowRestY: CGFloat = 8
    /// 静止基础扩散。抬起来时影更大更散
    static let shadowRadiusBase: CGFloat = 22
    static let shadowRadiusGain: CGFloat = 8

    /// 阴影半径：`22 + 8×|tilt|`
    static func shadowRadius(_ magnitude: CGFloat) -> CGFloat {
        shadowRadiusBase + shadowRadiusGain * magnitude
    }

    /// 把"位移 / 行程"钳到每轴 −1…1。写成一处而不是内联两次 `min(max())`：
    /// 两个轴是同一条规则，漏改一处就会让某一轴比另一轴更早到顶（看着像卡坏了一半）。
    static func clamped(width: CGFloat, height: CGFloat) -> CGSize {
        CGSize(width: min(max(width, -1), 1), height: min(max(height, -1), 1))
    }
}
