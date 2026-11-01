import SwiftUI

/// 沉浸式「天光室」—— 把天光 / 日弧小组件那块**天空 + 地平线**放大成一整屏。
///
/// 视觉原型是桌面上那张天光卡：`Theme.sky(phase)` 的六个 token 组成的天幕、
/// `HorizonGround` / `HorizonEdge` 那条二次贝塞尔地平线、按 `SunClock` 当日进度定位的太阳。
/// 数据源**不新造**：天光来自 `SunClock`（纯函数），天气来自 `WeatherStore`（App 侧既有缓存，
/// 本页只读不发新请求）。
///
/// ## 交互（这一页的全部设计都在这里）
///
/// ```
///            ● 黄昏            距离日落 23分钟     ← 顶部一行（左上角是关闭按钮）
///
///             （天幕网格 / 星点 / 云 / 三层山脊 / 太阳，上滑时按 0.2 / 0.2 / 0.5 / 0.75 位移）
///         ────────────────────────────────────     ← 地平线（渐隐光带，初始 58%）
///                    （从天色渐变到深色的地面 + 竖纹理 + 20pt 暖色辉光）
///
///         日出 06:45 · 日落 17:32                  ← 底部一行
/// ```
///
/// - **上滑**：地平线上移（天空扩张）→ 吸附到三档（58% / 38% / 22%，见 `SkyRoomMetrics.detents`）。
/// - **下滑**：像天气 App 那样把天空整体下压，浮出「今日天气面板」（`SkyRoomWeatherPanel`）；
///   继续拉过阈值松手就关闭页面 —— 同时左上角常驻一个极简关闭按钮。
///
/// ## 3.12.0 视觉重做（用户对 3.11.0 的评价："一塌糊涂"）
///
/// 逐条对应（旧 → 新）：
///
/// | 元素 | 3.11.0 | 现在 |
/// |---|---|---|
/// | 天空 | 一条平直双色线性渐变 | `MeshGradient` 4×4 网格（iOS 18）/ `LinearGradient` 兜底 |
/// | 太阳 | 一个白色实心圆 + 一圈光晕 | 三层：核心 12pt + 内晕 40 + 外晕 220 |
/// | 云 | 两条圆角胶囊 | 5 朵云 × 3–4 个模糊椭圆（远小近大、远淡近实） |
/// | 远山 | 两个硬边三角形 | 3 层 `quadCurve` 山脊（≥4 峰、固定种子、大气透视） |
/// | 地平线 | 一条纯白细线 | 渐隐光带（2.5pt）+ 下方 20pt 暖色辉光 |
/// | 地面 | 一整块深色（断面生硬） | 天色 → 深色的多段渐变 + 0.02 竖向纹理 |
///
/// ## 四条铁律（本文件逐条遵守）
///
/// 1. **动画只走 `offset` / `scaleEffect` / `opacity`**：上滑/下滑只改两个 `@State`
///    （`stage` 与 `dragOffset`），所有观感变化都由它们的派生数（`lift` / `expand` / `pull`）驱动。
///    `MeshGradient` 的 16 个点**只随天色（60s 一帧）变**，绝不随拖动逐帧重建 ——
///    重建一次网格 = 重新插值整块全屏像素，那正是"卡"的来源。
/// 2. **`blur` 半径是常量**：云朵模糊固定 18pt，只在合成时算一次，之后只动 `offset` / `opacity`。
///    逐帧改模糊半径会强制每帧离屏渲染（掉帧的经典写法），本文件一处都没有。
/// 3. **不用 `Timer`**：走时全部交给 `TimelineView`（外层 60s 刷新天色与太阳位置，
///    顶部倒计时内层 1s）。本文件没有任何 `Timer(`、没有 `DispatchQueue` 轮询。
/// 4. **尊重 `reduceMotion`**：太阳呼吸、云漂移全部不启动（连初始值都不给），
///    松手吸附改硬切 —— **但视觉完整**（静态画面里云、山、星、太阳一样都在，不是白屏）。
///
/// ## 入口（只有两个，见 DESIGN-RULES §4）
///
/// a. 小组件深链 `skyapp://sky`（天光 / 日弧 / 月相 / 风 四张卡，见 `WidgetDeepLink.sky`）；
/// b. 概览第二张卡（`TodayBriefTrackCard`）的「今日」。
///
/// ## iPad 档（DESIGN-RULES §1）
///
/// 宽档（`LayoutMetrics.usesWideCards`）时天空舞台**居中限宽 880**（`frame(maxWidth:)`，
/// 不是固定宽度 —— 固定宽度会撑宽父级，那正是 3.12.0 修的 P0 事故），
/// 两侧由延展的同色渐变加暗角收边；字号 ×1.18；天气面板变成悬浮在右下角的一张 360pt 卡片。
/// 窄档一个像素都不变：舞台满宽、面板贴底满宽。
struct SkyRoomView: View {

    @Environment(\.dismiss) private var dismiss
    /// 尺寸模型（唯一"设备有多大"的判据，见 DESIGN-RULES §1）
    @Environment(\.layoutMetrics) private var metrics
    /// 前庭敏感用户：呼吸 / 漂移 / 吸附弹簧全部让位
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 当前吸附档下标（0 = 58% / 1 = 38% / 2 = 22%）
    @State private var stage: Int = SkyRoomMetrics.restStage
    /// 拖动中的实时位移（pt，向下为正）。松手后回 0，吸收到 `stage` 里。
    ///
    /// 注意它不是"纯粹的手指位移"：换档那一帧它会被改写成「新档位与原画面之间的差值」，
    /// 再动画归零 —— 这样地平线在换档瞬间逐点连续（推导见 `settle`）。
    @State private var dragOffset: CGFloat = 0
    /// 天气快照（nil = 还没到，是正常状态）
    @State private var weatherNow: WeatherNow?
    /// 太阳外晕呼吸（8s，opacity ±4%）
    @State private var breathe: Bool = false
    /// 云漂移（40s，单程 6pt × 距离系数）
    @State private var drifting: Bool = false

    var body: some View {
        GeometryReader { proxy in
            // 安全区**手动**折进全屏坐标：这一页的天空必须铺到状态栏与 Home Indicator 之外，
            // 而 `GeometryReader` 一旦自己 `ignoresSafeArea` 就拿不到 insets（会变成 0）。
            // 所以先按安全区量，再用「全屏尺寸 + 反向外移」把画布对回屏幕原点。
            let insets = proxy.safeAreaInsets
            let full = CGSize(
                width: proxy.size.width + insets.leading + insets.trailing,
                height: proxy.size.height + insets.top + insets.bottom
            )
            // 60s 一格：天色与太阳位置每分钟重算一次就够（七档天色本身是整块跳变的，
            // 更快只会白刷）。秒级走时只发生在顶部倒计时那一行（内层 TimelineView）。
            TimelineView(.periodic(from: Date(), by: 60)) { context in
                scene(size: full, insets: insets, now: context.date)
            }
            .frame(width: full.width, height: full.height)
            .offset(x: -insets.leading, y: -insets.top)
        }
        // 兜底底色：万一某一帧没画出天空（首帧量尺寸），也不会有白闪
        .background(Theme.bgBase)
        .task {
            await loadWeather()
        }
        .onAppear {
            startAmbient()
        }
        .onDisappear {
            stopAmbient()
        }
    }

    // MARK: - 场景装配

    /// 六层的顺序**就是物理距离的顺序**（远 → 近）：
    ///
    /// 天幕 → 星点 → 云 → **太阳** → 山脊 → 地面。
    ///
    /// 太阳排在**山脊之前**（这是 3.12.0 的一处修正）：3.11.0 把太阳画在远山之上，
    /// 于是"日落"看起来像"太阳贴着山前落地"；压到山脊之下后，太阳会自然被山挡住一半，
    /// 那才是日落该有的读法。它同时仍在地面之前 —— 落到地平线以下的部分被地面盖住，
    /// 光晕的下半部分也被裁掉，不需要任何 mask。
    private func scene(size: CGSize, insets: EdgeInsets, now: Date) -> some View {
        let frame = SkyRoomMetrics.Frame(
            size: size,
            wide: metrics.usesWideCards,
            horizon: horizonFraction(in: size)
        )
        let phase = SunClock.phase(at: now)
        let sky = Theme.sky(phase)

        return ZStack {
            // ① 天幕（网格 / 线性兜底 + "提亮一档"叠加层 + 宽档暗角）
            skyBase(sky: sky, phase: phase, frame: frame, now: now)
            // ② 视差层：星点 / 云 / 三层山脊（只改 offset / opacity）
            parallax(sky: sky, phase: phase, frame: frame)
            // ③ 太阳：三层结构，画在山脊与地面之前
            sun(sky: sky, phase: phase, frame: frame, now: now)
            // ④ 地面 + 地平线光带 + 暖色辉光 + 竖纹理
            ground(sky: sky, phase: phase, frame: frame)
            // ⑤ 文字层（顶部状态行 / 底部日出日落）
            chrome(sky: sky, frame: frame, insets: insets, now: now)
            // ⑥ 天气面板（下拉才浮出）
            if frame.pull > 0.001 {
                weatherLayer(frame: frame, insets: insets)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(dragGesture(height: size.height))
    }

    // MARK: - ① 天幕

    /// 天幕 = 网格（或线性兜底）+ 提亮面 + 宽档暗角，整层按 0.20 做视差。
    ///
    /// **为什么整层可以安全地上移 20%**：地面从 `horizon`（最低 0.22）一直铺到屏底，
    /// 天幕上移最多 `0.20 × lift`（极限档 lift ≈ 0.36h → 0.072h ≈ 61pt @852），
    /// 天幕的下边缘仍远高于地平线，被地面完整盖住 —— 不会露出背景底色。
    private func skyBase(sky: Theme.SkyColors,
                        phase: SkyPhase,
                        frame: SkyRoomMetrics.Frame,
                        now: Date) -> some View {
        ZStack {
            dome(phase: phase, frame: frame, now: now)

            // 「上滑提亮一档」：叠一层**固定色**的半透明面，只有不透明度随 expand 走。
            // 这样整块网格不需要重新插值（铁律 1），观感却确实是"天亮了"。
            Rectangle()
                .fill(sky.horizon)
                .opacity(Double(frame.expand) * SkyRoomMetrics.Sky.liftAlpha)

            if frame.wide {
                // 宽档收边：舞台两侧压向该档天色里最暗的 `ground`，视线自然收回中间。
                // 只在宽档出现 —— 窄档满宽，加暗角等于给手机屏加两条黑边。
                LinearGradient(
                    stops: [
                        .init(color: sky.ground.opacity(SkyRoomMetrics.vignetteAlpha), location: 0),
                        .init(color: sky.ground.opacity(0), location: 0.24),
                        .init(color: sky.ground.opacity(0), location: 0.76),
                        .init(color: sky.ground.opacity(SkyRoomMetrics.vignetteAlpha), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .offset(y: -frame.lift * SkyRoomMetrics.Parallax.sky)
    }

    /// 天幕本体：交给 `SkyRoomDome`（一个 `Equatable` 包装）。
    ///
    /// **为什么要包一层**：拖动 / 呼吸 / 云漂移期间 `scene` 会重算，但这一层的输入
    /// （天色档位、画布尺寸、太阳位置）**一个都没变** —— `Equatable` 让 SwiftUI 直接跳过
    /// 整块全屏网格的重建。这是"上滑不卡"的关键：网格一旦逐帧重建，
    /// 每帧都要重新插值整屏像素，那正是 3.11.0 那版"卡"的来源之一。
    private func dome(phase: SkyPhase,
                      frame: SkyRoomMetrics.Frame,
                      now: Date) -> some View {
        let sun = sunGeometry(now: now)
        return SkyRoomDome(phase: phase,
                           width: frame.width,
                           height: frame.height,
                           sunX: sun.x,
                           sunHeight: sun.height)
            .equatable()
    }

    /// 太阳的横坐标（0…1）与高度角（0 = 贴地平线、1 = 正当空）。
    ///
    /// 网格的暖色团跟这两件事走（见 `SkyRoomDome`）。算不出（极昼极夜）时给
    /// "正中、中等高度" —— 不猜天色，只给一个不会出错的中间态。
    private func sunGeometry(now: Date) -> (x: Float, height: Float) {
        let mark = SunClock.sunMark(at: now,
                                    on: now,
                                    crestY: SkyRoomMetrics.detents[SkyRoomMetrics.restStage])
        guard let mark else { return (0.5, 0.5) }
        let horizonY = Float(SkyRoomMetrics.detents[SkyRoomMetrics.restStage])
        let y = Float(mark.point.y)
        let height: Float = horizonY > 0 ? min(max(1 - y / horizonY, 0), 1) : 0.5
        return (Float(mark.point.x), height)
    }

    // MARK: - ② 视差层

    /// 星点 + 云 + 三层山脊。三层的位移系数在 `SkyRoomMetrics.Parallax`（近大远小），
    /// 全部用 `.offset` 表达 —— 没有任何一层改颜色或改尺寸（太阳除外，它读 `expand` 放大）。
    private func parallax(sky: Theme.SkyColors,
                          phase: SkyPhase,
                          frame: SkyRoomMetrics.Frame) -> some View {
        ZStack {
            if isStarry(phase) {
                stars(sky: sky, frame: frame)
            }
            clouds(sky: sky, phase: phase, frame: frame)
            mountains(sky: sky, frame: frame)
        }
    }

    /// 三层山脊。
    ///
    /// 锚在**初始档**的地平线上（`baseY`），再按 0.75 系数上移：山必须"落在地平线上"
    /// 才有距离感；跟着地平线走就变成贴纸。层与层之间错开 8pt（`layerOffset`），
    /// 颜色随距离混入天空色（`haze`）—— 越远越淡越蓝，这就是大气透视。
    private func mountains(sky: Theme.SkyColors, frame: SkyRoomMetrics.Frame) -> some View {
        let baseY = SkyRoomMetrics.detents[SkyRoomMetrics.restStage] * frame.height
        let originX = (frame.width - frame.stageWidth) / 2

        return ZStack {
            // 远 → 近：顺序即 z 轴（后面的盖住前面的）
            // 单参数闭包（`pair.element`）：不依赖闭包参数对元组的解构推断
            ForEach(Array(SkyRoomMetrics.Ridges.layers.enumerated()), id: \.offset) { pair in
                ridge(spec: pair.element,
                      index: pair.offset,
                      sky: sky,
                      frame: frame,
                      baseY: baseY,
                      originX: originX)
            }
        }
        .offset(y: -frame.lift * SkyRoomMetrics.Parallax.mountain)
    }

    /// 一层山脊：形状 + 大气透视渐变 + 层间错位
    private func ridge(spec: SkyRoomMetrics.RidgeSpec,
                       index: Int,
                       sky: Theme.SkyColors,
                       frame: SkyRoomMetrics.Frame,
                       baseY: CGFloat,
                       originX: CGFloat) -> some View {
        let width = frame.stageWidth * spec.widthRatio
        let height = frame.height * spec.heightRatio
        // 层间错位：远层更高、更靠上（远景先露头）
        let offsetY = -(CGFloat(index) * SkyRoomMetrics.Ridges.layerOffset) - frame.height * spec.rise

        return SkyRoomRidge(crests: spec.crests,
                            amplitude: spec.amplitude,
                            seed: spec.seed,
                            sampleCount: SkyRoomMetrics.Ridges.sampleCount)
            // 大气透视：顶部混入更多天空色（远山更"化"在天里），底部才是山体本色
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: sky.horizon.opacity(spec.haze), location: 0),
                        .init(color: sky.ground.opacity(spec.density), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width, height: height)
            // `.position` 返回的是**弹性视图**（铺满 proposal），所以固定尺寸的山不会撑宽父级
            .position(x: originX + frame.stageWidth * spec.centerX,
                      y: baseY + offsetY - height / 2)
    }

    /// 云：5 朵，每朵 3–4 个模糊椭圆叠成不规则形状。
    ///
    /// 三条纪律：
    /// 1. **模糊是对整朵云做一次**（`ZStack` 上挂一个 `.blur`），不是每团椭圆各来一次 ——
    ///    5 次离屏渲染而不是 20 次；
    /// 2. 模糊半径是**常量** 18pt，只有 `offset` / `opacity` 在动（铁律 2）；
    /// 3. 形状由**固定种子**推（`noise(_:_:)`），同一朵云每次进场都长一样。
    private func clouds(sky: Theme.SkyColors, phase: SkyPhase, frame: SkyRoomMetrics.Frame) -> some View {
        let tint = cloudTint(sky: sky, phase: phase)
        let drift = drifting ? SkyRoomMetrics.driftDistance : -SkyRoomMetrics.driftDistance
        let originX = (frame.width - frame.stageWidth) / 2

        return ZStack {
            ForEach(Array(SkyRoomMetrics.Clouds.specs.enumerated()), id: \.offset) { pair in
                cloud(spec: pair.element, tint: tint, frame: frame)
                    .position(x: originX + frame.stageWidth * pair.element.centerX,
                              y: frame.height * pair.element.centerY)
                    .offset(x: drift * pair.element.drift)
            }
        }
        .offset(y: -frame.lift * SkyRoomMetrics.Parallax.cloud)
    }

    /// 一朵云：3–4 个椭圆 + 一次模糊
    private func cloud(spec: SkyRoomMetrics.CloudSpec,
                       tint: Color,
                       frame: SkyRoomMetrics.Frame) -> some View {
        let width = frame.stageWidth * spec.width
        let height = width / SkyRoomMetrics.cloudAspect
        let blobCount = SkyRoomMetrics.Clouds.minBlobs
            + Int(noise(spec.seed, 99) * CGFloat(SkyRoomMetrics.Clouds.maxBlobs
                                                 - SkyRoomMetrics.Clouds.minBlobs + 1))

        return ZStack {
            ForEach(0..<max(SkyRoomMetrics.Clouds.minBlobs, blobCount), id: \.self) { index in
                Ellipse()
                    .fill(tint.opacity(SkyRoomMetrics.Clouds.blobAlpha * blobAlpha(spec, index)))
                    .frame(width: width * blobWidth(spec, index),
                           height: height * blobHeight(spec, index))
                    .offset(x: width * blobOffsetX(spec, index),
                            y: height * blobOffsetY(spec, index))
            }
        }
        // 固定半径模糊：整朵云只做一次离屏渲染
        .blur(radius: SkyRoomMetrics.Clouds.blur)
        .opacity(spec.alpha / SkyRoomMetrics.Clouds.blobAlpha)
        .allowsHitTesting(false)
    }

    /// 云的颜色：亮天用 `edge`（近白），暗天用 `ink`（与天光小组件同一条规则）
    private func cloudTint(sky: Theme.SkyColors, phase: SkyPhase) -> Color {
        switch phase {
        case .night, .blueDawn, .blueDusk:
            return sky.ink
        case .sunrise, .golden, .day, .sunset:
            return sky.edge
        }
    }

    // MARK: 云团形状（固定种子 → 每次一样）

    /// 单团椭圆的不透明度系数（0.55…0.95 —— 叠起来才是一朵云，不是一块板）
    private func blobAlpha(_ spec: SkyRoomMetrics.CloudSpec, _ index: Int) -> Double {
        return 0.55 + Double(noise(spec.seed, index * 7 + 1)) * 0.40
    }

    /// 单团椭圆的宽（相对云宽）
    private func blobWidth(_ spec: SkyRoomMetrics.CloudSpec, _ index: Int) -> CGFloat {
        return 0.42 + noise(spec.seed, index * 7 + 2) * 0.36
    }

    /// 单团椭圆的高（相对云高）—— 与宽度**不成比例**，才会有"不规则"的轮廓
    private func blobHeight(_ spec: SkyRoomMetrics.CloudSpec, _ index: Int) -> CGFloat {
        return 0.52 + noise(spec.seed, index * 7 + 3) * 0.46
    }

    /// 单团椭圆的横向偏移（相对云宽，-0.28…0.28）
    private func blobOffsetX(_ spec: SkyRoomMetrics.CloudSpec, _ index: Int) -> CGFloat {
        return (noise(spec.seed, index * 7 + 4) - 0.5) * 0.56
    }

    /// 单团椭圆的纵向偏移（相对云高，-0.22…0.22）
    private func blobOffsetY(_ spec: SkyRoomMetrics.CloudSpec, _ index: Int) -> CGFloat {
        return (noise(spec.seed, index * 7 + 5) - 0.5) * 0.44
    }

    /// 星点：只有夜 / 晨蓝 / 暮蓝三档出现。位置由 `starPoint(_:)` 的确定性哈希给出 ——
    /// 不用 `random`，否则每一帧（60s）星星会整体换位，看起来像闪烁故障。
    private func stars(sky: Theme.SkyColors, frame: SkyRoomMetrics.Frame) -> some View {
        let originX = (frame.width - frame.stageWidth) / 2
        return ZStack {
            ForEach(0..<SkyRoomMetrics.Stars.count, id: \.self) { index in
                let point = starPoint(index)
                Circle()
                    .fill(sky.ink)
                    .frame(width: SkyRoomMetrics.Stars.diameter,
                           height: SkyRoomMetrics.Stars.diameter)
                    .position(x: originX + point.x * frame.stageWidth,
                              y: point.y * frame.height)
            }
        }
        .opacity(SkyRoomMetrics.Stars.baseAlpha)
        .offset(y: -frame.lift * SkyRoomMetrics.Parallax.star)
    }

    // MARK: - ③ 太阳

    /// 三层结构的太阳（3.12.0 重做：3.11.0 只有"一个白色实心圆 + 一圈光晕"）。
    ///
    /// | 层 | 尺寸 | 不透明度 | 颜色 |
    /// |---|---|---|---|
    /// | 外晕 | 直径 220 | 0.18 | 日出日落橙红、正午偏白（`sunOuterTint`） |
    /// | 内晕 | 直径 40 | 0.55 | 暖白（`sunInnerTint`） |
    /// | 核心 | 直径 12 | 1.00 | `sky.edge`（每档最亮的那支） |
    ///
    /// 三层**共用同一个位置**（`mark.point`），随 `expand` 一起放大（`Sun.grow`）。
    /// 呼吸只有外晕的 `opacity` 在动（1.0 ↔ 0.92）—— 不重建任何渐变。
    @ViewBuilder
    private func sun(sky: Theme.SkyColors,
                     phase: SkyPhase,
                     frame: SkyRoomMetrics.Frame,
                     now: Date) -> some View {
        if let mark = SunClock.sunMark(at: now,
                                       on: now,
                                       crestY: SkyRoomMetrics.detents[SkyRoomMetrics.restStage]),
           mark.isUp, mark.intensity > 0.01 {
            let originX = (frame.width - frame.stageWidth) / 2
            let grow = 1 + SkyRoomMetrics.Sun.grow * frame.expand
            let core = SkyRoomMetrics.Sun.coreDiameter * grow
            let inner = SkyRoomMetrics.Sun.innerGlowDiameter * grow
            let outer = SkyRoomMetrics.Sun.outerGlowDiameter * grow
            let strength = Double(mark.intensity)

            ZStack {
                // 外晕：整片天被照亮的那一层（只有它在呼吸）
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: sunOuterTint(sky: sky, phase: phase)
                                    .opacity(SkyRoomMetrics.Sun.outerGlowAlpha * strength), location: 0),
                                .init(color: sunOuterTint(sky: sky, phase: phase)
                                    .opacity(SkyRoomMetrics.Sun.outerGlowAlpha * 0.30 * strength), location: 0.45),
                                .init(color: sunOuterTint(sky: sky, phase: phase).opacity(0), location: 1)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: outer / 2
                        )
                    )
                    .frame(width: outer, height: outer)
                    .opacity(glowBreathAlpha)

                // 内晕：贴着核心的那圈亮边（把核心从背景里"托"出来）
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: sunInnerTint(sky: sky, phase: phase)
                                    .opacity(SkyRoomMetrics.Sun.innerGlowAlpha * strength), location: 0),
                                .init(color: sunInnerTint(sky: sky, phase: phase).opacity(0), location: 1)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: inner / 2
                        )
                    )
                    .frame(width: inner, height: inner)

                // 核心：实心圆
                Circle()
                    .fill(sky.edge)
                    .frame(width: core, height: core)

                // 核心外面那圈高光环（让核心"立"起来，不是一块贴纸）
                Circle()
                    .strokeBorder(sky.edge.opacity(SkyRoomMetrics.Sun.ringAlpha),
                                  lineWidth: SkyRoomMetrics.Sun.ringWidth)
                    .frame(width: core + SkyRoomMetrics.Sun.ringWidth * 4,
                           height: core + SkyRoomMetrics.Sun.ringWidth * 4)
            }
            .position(x: originX + mark.point.x * frame.stageWidth,
                      y: mark.point.y * frame.height)
            // 太阳跟着地平线 1:1 上移（系数 1.0）：它是"贴着地平线落下去"的那个东西
            .offset(y: -frame.lift * SkyRoomMetrics.Parallax.sun)
            .allowsHitTesting(false)
        }
    }

    /// 外晕颜色：日出 / 日落取 `sky.top`（那两档就是橙红），黄金时刻取 `sky.horizon`（暖黄），
    /// 白天取 `sky.edge`（近白）。夜里根本不会走到这里（`mark.isUp` 为 false）。
    private func sunOuterTint(sky: Theme.SkyColors, phase: SkyPhase) -> Color {
        switch phase {
        case .sunrise, .sunset:
            return sky.top
        case .golden:
            return sky.horizon
        case .day, .night, .blueDawn, .blueDusk:
            return sky.edge
        }
    }

    /// 内晕颜色：暖时段给暖白（`sky.horizon`），其余给 `sky.edge`
    private func sunInnerTint(sky: Theme.SkyColors, phase: SkyPhase) -> Color {
        switch phase {
        case .sunrise, .sunset, .golden:
            return sky.horizon
        case .day, .night, .blueDawn, .blueDusk:
            return sky.edge
        }
    }

    // MARK: - ④ 地面

    /// 地面 = 本体渐变 + 玻璃内亮 + 竖纹理 + 地平线暖色辉光 + 渐隐光带。
    ///
    /// **为什么不加 `.offset(y: -lift × 1.0)`**：地面形状的顶边就是 `frame.horizon`，
    /// 它**已经**随地平线逐点移动（系数天然就是 1.0）。再加一次 offset 就成了 2 倍速，
    /// 上滑时地面会比地平线快一倍，两者之间会裂开一条缝。
    private func ground(sky: Theme.SkyColors,
                        phase: SkyPhase,
                        frame: SkyRoomMetrics.Frame) -> some View {
        let shape = HorizonGround(crestY: frame.horizon, edgeY: frame.arcEdgeY)
        let edge = HorizonEdge(crestY: frame.horizon, edgeY: frame.arcEdgeY)
        let isNight = phase == .night
        let haze = horizonHaze(sky: sky, phase: phase)

        return ZStack {
            // ① 本体：从地平线的**天色**渐到深色（不是一刀切 —— 那正是"断面生硬"的来源）
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: sky.horizon.opacity(SkyRoomMetrics.Ground.skyBleed), location: 0),
                        .init(color: sky.ground, location: SkyRoomMetrics.Ground.midStop),
                        .init(color: sky.ground.opacity(SkyRoomMetrics.Ground.bottomAlpha), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // ② 玻璃质感：一层极淡的内亮（token 固定，不随帧变色）
            shape.fill(
                LinearGradient(
                    colors: [Theme.glassSheen, Theme.glassHighlightFade],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // ③ 极淡的竖向纹理（0.02 不透明度）：只在截图对比里看得见 —— 那是"质感"，
            //    不能变成"线条"。用 `Canvas` 一次画完，不是 30 个 Rectangle 视图。
            groundTexture(sky: sky, frame: frame)
            // ④ 地平线下方 20pt 的暖色辉光（从地平线往下淡出）
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: haze.opacity(SkyRoomMetrics.Horizon.glowAlpha), location: 0),
                        .init(color: haze.opacity(0), location: frame.horizonGlowFraction)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // ⑤ 渐隐光带：横向从 `sky.edge` 淡到透明（地平线"消失在画面外"，不断在屏幕边），
            //    厚度 2.5pt。夜里换成一道更细更淡的冷光。
            edge.stroke(
                LinearGradient(
                    stops: [
                        .init(color: sky.edge.opacity(SkyRoomMetrics.Horizon.bandFadeAlpha), location: 0),
                        .init(color: sky.edge.opacity(isNight
                                                      ? SkyRoomMetrics.Ground.nightEdgeAlpha
                                                      : SkyRoomMetrics.Horizon.bandAlpha), location: 0.5),
                        .init(color: sky.edge.opacity(SkyRoomMetrics.Horizon.bandFadeAlpha), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: isNight
                    ? SkyRoomMetrics.Ground.nightEdgeWidth
                    : SkyRoomMetrics.Horizon.bandWidth
            )
            // ⑥ 光带外再压一层雾化（粗而淡，无 blur —— 与桌面小组件同一套"伪造柔光"配方）
            if !isNight {
                edge.stroke(sky.edge.opacity(SkyRoomMetrics.Ground.edgeHazeAlpha),
                            lineWidth: SkyRoomMetrics.Ground.edgeHazeWidth)
            }
        }
        .frame(width: frame.width, height: frame.height)
    }

    /// 地面纹理：等距竖线，向上收窄（模拟草地 / 水面的透视），不透明度 0.02。
    ///
    /// 用 `Canvas` 而不是 `ForEach` + `Rectangle`：一屏要 15 条线，`ForEach` 会造 15 个视图
    /// 进视图树（每次重绘都要 diff），`Canvas` 是一次绘制调用。
    private func groundTexture(sky: Theme.SkyColors, frame: SkyRoomMetrics.Frame) -> some View {
        Canvas { context, size in
            let spacing = SkyRoomMetrics.Ground.textureSpacing
            guard spacing > 0 else { return }
            var path = Path()
            let topY = size.height * frame.horizon
            var x = spacing * 0.5
            while x < size.width {
                path.move(to: CGPoint(x: x, y: topY))
                path.addLine(to: CGPoint(x: x - size.width * SkyRoomMetrics.Ground.textureSlant,
                                         y: size.height))
                x += spacing
            }
            context.stroke(path,
                           with: .color(sky.edge.opacity(SkyRoomMetrics.Ground.textureAlpha)),
                           lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    /// 地平线辉光的颜色：暖时段暖色、白天近白、夜里冷光
    private func horizonHaze(sky: Theme.SkyColors, phase: SkyPhase) -> Color {
        switch phase {
        case .sunrise, .sunset, .golden:
            return sky.horizon
        case .day, .night, .blueDawn, .blueDusk:
            return sky.edge
        }
    }

    // MARK: - ⑤ 文字层

    /// 顶部一行（关闭按钮 + 阶段名 + 倒计时）与底部一行（日出 / 日落）。
    /// 两行都落在舞台列宽里：宽档字跟着舞台走，而不是贴到 1194 的两端。
    private func chrome(sky: Theme.SkyColors,
                        frame: SkyRoomMetrics.Frame,
                        insets: EdgeInsets,
                        now: Date) -> some View {
        VStack(spacing: 0) {
            topBar(sky: sky, frame: frame, now: now)
                .padding(.top, insets.top + 10)
            Spacer(minLength: 0)
            bottomBar(sky: sky, frame: frame, now: now)
                // 下拉时底部那行让位给天气面板（只改不透明度，不改布局）
                .opacity(1 - Double(frame.pull))
                .padding(.bottom, insets.bottom + 18)
        }
        .padding(.horizontal, SkyRoomMetrics.compactPanelInset)
        .frame(width: frame.stageWidth)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func topBar(sky: Theme.SkyColors, frame: SkyRoomMetrics.Frame, now: Date) -> some View {
        HStack(spacing: 10) {
            // 极简关闭按钮（左上角）：不让"只能下拉退出"成为唯一出路
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(sky.ink)
                    .frame(width: 32, height: 32)
                    .glassSurface(.floating, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭天光页")

            // 阶段名 + 倒计时：秒在走，交给 TimelineView 自己刷（本文件没有 Timer）
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                HStack(spacing: 6) {
                    Circle()
                        .fill(sky.edge)
                        .frame(width: 5, height: 5)
                    Text(SunClock.phase(at: context.date).label)
                        .font(SkyRoomMetrics.TextStyle.phase(frame.fontScale))
                        .foregroundStyle(sky.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let deadline = SunClock.phase(at: context.date).deadline(at: context.date) {
                        Text(SkyPhase.countdownText(to: deadline, now: context.date))
                            .font(SkyRoomMetrics.TextStyle.countdown(frame.fontScale))
                            .foregroundStyle(sky.inkDim)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func bottomBar(sky: Theme.SkyColors, frame: SkyRoomMetrics.Frame, now: Date) -> some View {
        if let text = sunTimesText(now: now) {
            Text(text)
                .font(SkyRoomMetrics.TextStyle.sunTime(frame.fontScale))
                .foregroundStyle(sky.inkDim)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - ⑥ 天气面板

    /// 下拉时浮出：**只改 offset 与 opacity**（面板本体不参与手势，纯展示）。
    private func weatherLayer(frame: SkyRoomMetrics.Frame, insets: EdgeInsets) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if frame.wide {
                    Spacer(minLength: 0)
                }
                SkyRoomWeatherPanel(weather: weatherNow,
                                    scale: frame.fontScale,
                                    wide: frame.wide)
                    .frame(width: frame.panelWidth)
                if !frame.wide {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, frame.wide ? 32 : 0)
        }
        .padding(.bottom, insets.bottom + 16)
        .opacity(Double(frame.pull))
        // 从下方 60pt 浮上来：位移与不透明度同步，读起来是"面板被拉出来的"
        .offset(y: (1 - frame.pull) * 60)
        .allowsHitTesting(false)
    }

    // MARK: - 手势

    /// 上滑 = 天空扩张（`dragOffset` 变负）；下滑 = 天空下压 + 天气面板浮出。
    /// 松手一律交给 `settle` 决定"吸附到哪一档"或"关闭"。
    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: SkyRoomMetrics.dragMinimum)
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                settle(translation: value.translation.height,
                       predicted: value.predictedEndTranslation.height,
                       height: height)
            }
    }

    /// 松手结算。
    ///
    /// 三条规则，顺序不能换：
    /// 1. **在初始档继续下拉**：实拖或惯性任一越过 `closeFraction` → 关闭页面；
    /// 2. 其余情况一律吸附到**最近**的档位（含"上滑过半再松手"的回弹）；
    /// 3. `reduceMotion` 时硬切（不播弹簧）—— 用户要的结果完全一样。
    ///
    /// ## 换档为什么不能把 `dragOffset` 直接清零（3.11.0 QA 必修）
    ///
    /// 地平线 = `detents[stage] + dragOffset / h`（见 `horizonFraction`）。松手时 `stage`
    /// 是**立即**跳到 `next` 的（它不该有动画：档位是离散量），如果此刻还把 `dragOffset`
    /// 一并清零，那么"已经换成新档位、但残留位移已经没了"这一帧就会画成 `detents[next] + 0`，
    /// 与松手前的 `base_old + t/h` 差出整整 `|base_new − base_old|` ——
    /// 实测 stage0 上滑 100pt 跳 170pt、stage1 下拉 90pt 跳 148pt。
    ///
    /// 而且跳变会**连带**毁掉两个派生量（它们都只读 `horizon` / 也就是间接读 `dragOffset`）：
    /// `pull` 换档帧被算成 1 → 天气面板整帧全亮闪现、底部日出日落 opacity 掉 0；
    /// `expand` / `lift` 同理会硬顶一下。所以修法必须是**保位移连续**：
    ///
    /// ```swift
    /// let residue = (live - detents[next]) * h    // live = 换档前一帧真正画出来的比例
    /// stage = next
    /// dragOffset = residue                        // 不带动画：这一帧的地平线逐点不变
    /// withAnimation(snapAnimation) { dragOffset = 0 }   // 从 residue 出发滑到新档位
    /// ```
    ///
    /// ## 为什么归零要延后一个 runloop
    ///
    /// `stage` 与 `dragOffset` 写在同一个更新周期里时，SwiftUI 只提交**最终值**：
    /// 中间那句 `dragOffset = residue` 不会单独渲染，于是弹簧动画的起点会退回成
    /// 松手前的 raw 位移（`translation`）—— 换成新档位后从旧残留起跳，等于又跳一次。
    /// 隔一个 runloop（`Task { @MainActor in … }`）后 `residue` 已经是屏幕上的值，
    /// spring 从它出发，视觉上的起点正好是手指松开的位置。代价是 1 帧（≈16ms），不可见。
    private func settle(translation: CGFloat, predicted: CGFloat, height: CGFloat) {
        let h = max(height, 1)
        let base = SkyRoomMetrics.detents[SkyRoomMetrics.clampedStage(stage)]
        let raw = base + translation / h
        let projected = base + predicted / h

        if stage == SkyRoomMetrics.restStage,
           raw >= SkyRoomMetrics.closeFraction
            || projected >= SkyRoomMetrics.closeFraction + SkyRoomMetrics.flickMargin {
            Haptics.light()
            dismiss()
            return
        }

        let next = SkyRoomMetrics.nearestStage(for: min(raw, SkyRoomMetrics.maxPullFraction))
        // 换档前这一帧**真正画出来**的地平线比例：与 `horizonFraction` 用同一套夹取，
        // 所以它就是屏幕上的值（越界拖动时屏幕上是 0.22 / 0.66，不是 raw）。
        let live = SkyRoomMetrics.clampedFraction(raw)
        Haptics.light()
        guard !reduceMotion else {
            // 硬切：不播弹簧，直接落到新档位（`dragOffset` 一起清零，一步到位 —— 没有中间帧，
            // 所以不存在上面那条"换档帧跳变"的问题，也就没必要留 residue）
            stage = next
            dragOffset = 0
            return
        }

        // 差值留在 dragOffset 上，再动画归零（推导见方法注释）
        let residue = (live - SkyRoomMetrics.detents[next]) * h
        stage = next
        dragOffset = residue
        // 延后一个 runloop：让 residue 先成为"已渲染值"，弹簧才从松手处出发（见注释末节）
        Task { @MainActor in
            withAnimation(SkyRoomMetrics.snapAnimation) {
                dragOffset = 0
            }
        }
    }

    /// 当前地平线比例（吸附档 + 实时拖动位移，夹进合法区间）
    private func horizonFraction(in size: CGSize) -> CGFloat {
        let h = max(size.height, 1)
        let base = SkyRoomMetrics.detents[SkyRoomMetrics.clampedStage(stage)]
        return SkyRoomMetrics.clampedFraction(base + dragOffset / h)
    }

    // MARK: - 动态（克制）

    /// 只启动两个动画：太阳外晕呼吸（8s）、云漂移（40s）。`reduceMotion` 下什么都不启动。
    ///
    /// **注意 `reduceMotion` 不等于"没有画面"**：云的形状、山脊、星点、太阳三层全都照画，
    /// 只是它们静止 —— 静止的一帧本身就是完整的视觉（这正是铁律 4 的要求）。
    private func startAmbient() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: SkyRoomMetrics.breatheDuration)
            .repeatForever(autoreverses: true)) {
            breathe = true
        }
        withAnimation(.linear(duration: SkyRoomMetrics.driftDuration)
            .repeatForever(autoreverses: true)) {
            drifting = true
        }
    }

    /// 静态兜底：把两个开关复位（视图离场后动画不该继续跑）。
    private func stopAmbient() {
        breathe = false
        drifting = false
    }

    /// 呼吸后的外晕不透明度。Reduce Motion 下恒为 1（不呼吸，也不留一个"半亮"的错值）。
    private var glowBreathAlpha: Double {
        guard !reduceMotion else { return 1 }
        return breathe ? 1 : SkyRoomMetrics.breatheFloor
    }

    // MARK: - 天气

    /// 读一次天气。`WeatherStore` 自带 10 分钟缓存与"失败保留旧值"，
    /// 所以这一页既不需要新 Store，也不会因为断网把面板变成错误态。
    ///
    /// 标 `@MainActor`：`WeatherStore` 是主 actor 上的类型，`.task` 的闭包是非隔离的 ——
    /// 在调用点 `await` 一次由编译器插 hop（与 `RootView` 里 `LocationStore.shared` 同一写法）。
    @MainActor
    private func loadWeather() async {
        await WeatherStore.shared.load()
        weatherNow = WeatherStore.shared.current
    }

    // MARK: - 派生文案

    /// 底部那行：`日出 06:45 · 日落 17:32`。
    ///
    /// 优先用天气接口给的实际时刻（`WeatherStore` → `WeatherNow.sunriseDate`），
    /// 缺了才回落 `SunClock`（±3 分钟）。日落之后换成**明天**那一对 ——
    /// 那时页面顶部数的是"距日出 N 小时"，底部写今天早上那次会让人以为时间错了。
    private func sunTimesText(now: Date) -> String? {
        var sunrise = weatherNow?.sunriseDate
        var sunset = weatherNow?.sunsetDate

        if sunrise == nil || sunset == nil {
            let computed = displayTimes(now: now)
            sunrise = sunrise ?? computed?.sunrise
            sunset = sunset ?? computed?.sunset
        }

        var parts: [String] = []
        if let sunrise {
            parts.append("日出 " + Formatters.timeHHmm(sunrise))
        }
        if let sunset {
            parts.append("日落 " + Formatters.timeHHmm(sunset))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `SunClock` 的日出日落，夜里顺延到明天
    private func displayTimes(now: Date) -> (sunrise: Date, sunset: Date)? {
        guard let today = SunClock.times(on: now) else { return nil }
        guard SunClock.phase(at: now) == .night, now >= today.sunset else { return today }
        return SunClock.times(on: now.addingTimeInterval(86_400)) ?? today
    }

    /// 夜空三档才画星点
    private func isStarry(_ phase: SkyPhase) -> Bool {
        switch phase {
        case .night, .blueDawn, .blueDusk:
            return true
        case .sunrise, .golden, .day, .sunset:
            return false
        }
    }

    /// 星点位置：确定性哈希（同一 index 永远同一个点）。
    ///
    /// 为什么不能 `Double.random`：这一页每 60s 重算一次 body，随机数会让星星整片换位，
    /// 观感是"屏幕在闪"。哈希保证星图整晚不变，唯一在动的是它们随天空扩张的位移。
    private func starPoint(_ index: Int) -> CGPoint {
        var value = UInt32(truncatingIfNeeded: index) &* 2_654_435_761
        value = value ^ (value >> 13)
        value = value &* 1_274_126_177
        value = value ^ (value >> 16)
        let x = CGFloat(value % 1_000) / 1_000
        let y = CGFloat((value >> 10) % 1_000) / 1_000
        // 只在天空最上面 55% 撒点：贴近地平线会被远山与云吃掉
        return CGPoint(x: x, y: y * 0.55)
    }

    /// 确定性噪声（0…1）：云团的形状、山脊的相位都用它。
    ///
    /// 同一个 `seed` + `index` 永远得到同一个数 —— 这是"固定种子"这条要求的实现，
    /// 也是整页"每次进来看见同一片云、同一座山"的保证（绝不用 `Double.random`）。
    private func noise(_ seed: UInt32, _ index: Int) -> CGFloat {
        var value = seed &+ (UInt32(truncatingIfNeeded: index) &* 2_246_822_519)
        value = value ^ (value >> 13)
        value = value &* 2_654_435_761
        value = value ^ (value >> 16)
        return CGFloat(value % 10_000) / 10_000
    }
}

// MARK: - 天幕网格的几何结果

/// 4×4 网格算出来的 16 个点与 16 个颜色。
///
/// 单独一个 struct 而不是在 `body` 里就地算：`MeshGradient` 的两个参数组长度必须严格相等
/// （都是 16），把它们放在一起构造，就不可能出现"点数 16、色数 15"这种运行时黑屏。
struct SkyDomeGeometry {
    let points: [SIMD2<Float>]
    let colors: [Color]
}

// MARK: - 天幕（4×4 MeshGradient，3.12.0）

/// 天幕本体：iOS 18 用 `MeshGradient`，否则退回一条线性渐变。
///
/// ## 为什么是 `Equatable`
///
/// 这一层是全屏的、GPU 填充的、**最贵**的一层。它的输入只有四样：天色档位、画布宽高、
/// 太阳横坐标、太阳高度角 —— 拖动 / 云漂移 / 呼吸期间这四样都不变。
/// 加上 `Equatable`（配合调用点的 `.equatable()`）之后，SwiftUI 会拿新旧值比一次、
/// 相等就**整块跳过重建**：上滑时网格一次都不重算，只会被 `.offset` 平移（合成层变换）。
///
/// ## 两个分支都必须能编译
///
/// `else` 分支不是死代码，而是"在旧系统上仍然好看"的保证（本工程 deployment target 是 18.0，
/// 但 `#available` 分支是给将来降 target 留的门 —— 那一支画的是 3.11.0 那条线性渐变）。
///
/// ## 颜色全部从 token 派生
///
/// - 天顶那一行 = `sky.ground`（该档最深的色）压一层 → "天顶保持冷/深"；
/// - 中间两行 = `sky.horizon` 半透明 → 大气由深转暖的过渡；
/// - 地平线那一行 = 暖色 token（见 `warmToken`）→ "地平线一带加暖色"。
///
/// 为什么不去算"两个 token 的插值色"：那等于在 View 层就地造色（主题闸门明令禁止）。
/// token + 不透明度叠加由 GPU 混合，既合规又比手算更准。
private struct SkyRoomDome: View, Equatable {

    /// 这一帧的天色档位（`Theme.sky(phase)` 是纯函数，所以不需要把颜色传进来）
    let phase: SkyPhase
    /// 画布宽 / 高（相对坐标用）
    let width: CGFloat
    let height: CGFloat
    /// 太阳横坐标（0…1）与高度角（0 = 贴地平线、1 = 正当空）
    let sunX: Float
    let sunHeight: Float

    private var sky: Theme.SkyColors {
        return Theme.sky(phase)
    }

    var body: some View {
        if #available(iOS 18.0, *) {
            let geometry = domeGeometry()
            MeshGradient(width: SkyRoomMetrics.SkyDome.columns,
                         height: SkyRoomMetrics.SkyDome.rows,
                         points: geometry.points,
                         colors: geometry.colors)
        } else {
            LinearGradient(stops: [
                .init(color: sky.top, location: 0),
                .init(color: sky.top, location: 0.42),
                .init(color: sky.horizon, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    /// 16 个控制点 + 16 个颜色（顺序一一对应）
    private func domeGeometry() -> SkyDomeGeometry {
        let columns = SkyRoomMetrics.SkyDome.columns
        let rows = SkyRoomMetrics.SkyDome.rows
        let warm = warmToken
        let depth = zenithDepth

        var points: [SIMD2<Float>] = []
        var colors: [Color] = []
        points.reserveCapacity(columns * rows)
        colors.reserveCapacity(columns * rows)

        for row in 0..<rows {
            for column in 0..<columns {
                let baseX = Float(column) / Float(columns - 1)
                let baseY = rowY(row)

                // 角点固定：整块网靠四个角"钉"在画布上（角一动整块网就"扭"）
                let isCorner = (row == 0 || row == rows - 1)
                    && (column == 0 || column == columns - 1)
                if isCorner {
                    points.append(SIMD2<Float>(baseX, baseY))
                } else {
                    // 越靠近地平线、太阳越低 → 位移越大（暖色团跟着太阳走）
                    let rowWeight: Float = row == 0 ? 0.25 : (row == rows - 1 ? 0.15 : 1.0)
                    let pull = (sunX - baseX) * SkyRoomMetrics.SkyDome.sway * rowWeight
                    let rise = (0.5 - sunHeight) * SkyRoomMetrics.SkyDome.bob * rowWeight
                    points.append(SIMD2<Float>(min(max(baseX + pull, 0.02), 0.98),
                                               min(max(baseY + rise, 0.01), 0.97)))
                }
                colors.append(color(row: row, warm: warm, depth: depth))
            }
        }
        return SkyDomeGeometry(points: points, colors: colors)
    }

    /// 某一行的基准高度：天顶 0 / 0.32 / 0.46 / 贴地平线 0.78
    private func rowY(_ row: Int) -> Float {
        switch row {
        case 0:
            return 0
        case 1:
            return SkyRoomMetrics.SkyDome.zenithRow + 0.16
        case 2:
            return SkyRoomMetrics.SkyDome.midRow
        default:
            return 0.78
        }
    }

    /// 某一行的颜色（天顶深 → 地平线暖）
    private func color(row: Int, warm: Color, depth: Double) -> Color {
        switch row {
        case 0:
            // 天顶：该档最深的 token 压一层 —— "冷"与"深"是同一件事
            return sky.ground.opacity(depth * SkyRoomMetrics.SkyDome.zenithAlpha)
        case 1:
            return sky.horizon.opacity(SkyRoomMetrics.SkyDome.midWarmth * 0.45)
        case 2:
            return sky.horizon.opacity(SkyRoomMetrics.SkyDome.midWarmth)
        default:
            return warm.opacity(SkyRoomMetrics.SkyDome.horizonWarmth)
        }
    }

    /// 地平线那一行的暖色 token。
    ///
    /// 日出 / 日落 / 黄金时刻取 `sky.horizon`（那三档的 horizon 就是暖橙 / 暖黄）；
    /// 白天取 `sky.edge`（近白的天光）；夜里与蓝调取 `sky.edge`（冷蓝灰的一线光）。
    private var warmToken: Color {
        switch phase {
        case .sunrise, .sunset, .golden:
            return sky.horizon
        case .day:
            return sky.edge
        case .night, .blueDawn, .blueDusk:
            return sky.edge
        }
    }

    /// 天顶压深的强度：夜里最重（深空），白天最轻（太阳把大气照亮了）
    private var zenithDepth: Double {
        switch phase {
        case .night:
            return 0.88
        case .blueDawn, .blueDusk:
            return 0.70
        case .sunrise, .sunset:
            return 0.46
        case .golden:
            return 0.38
        case .day:
            return 0.30
        }
    }
}

// MARK: - 山脊

/// 平滑山脊（3.12.0 重做：旧版是"可调峰顶的三角山脊" —— 两条直线，像几何拼贴）。
///
/// ## 形状怎么来的
///
/// 三个不同频率的正弦叠加（0.55 / 0.30 / 0.15）再归一化到 0…1，得到一条**至少有 4 个波峰**、
/// 且峰高不等的起伏曲线；然后用 `quadCurve` 把采样点连成平滑曲线（不是折线）。
///
/// ## 为什么用固定种子而不是 `random`
///
/// 这一页每 60s 重算一次 body，`Double.random` 会让山"每次刷新换一座"（观感像故障）。
/// 三个相位全部由 `seed` 的位段派生，于是同一台设备每次进来看见的是同一座山。
///
/// 与 Widget 侧的 `RedstoneSpike` 是两套实现（那个属于 Widget target，主 App 引用不到），
/// 但**形状思路不同**：那个是"单峰三角"，这个是"多峰起伏"。
private struct SkyRoomRidge: Shape {

    /// 主频（视野内大约几个波峰）
    var crests: Double
    /// 高差（相对自身高度，0…1）
    var amplitude: CGFloat
    /// 固定种子（决定三个正弦的相位）
    var seed: UInt32
    /// 采样点数（越多越平滑，72 段在 400pt 宽上每段约 5.5pt）
    var sampleCount: Int

    func path(in rect: CGRect) -> Path {
        let steps = max(8, sampleCount)
        guard rect.width > 0, rect.height > 0 else { return Path() }

        // 三个相位：从 seed 的三段位各取 10 位，映射到 0…2π
        let phase1 = Self.phase(seed, shift: 0)
        let phase2 = Self.phase(seed, shift: 10)
        let phase3 = Self.phase(seed, shift: 20)

        var points: [CGPoint] = []
        points.reserveCapacity(steps + 1)
        for index in 0...steps {
            let t = Double(index) / Double(steps)
            // 三个频率叠加：主频给出"几个山头"，1.7 / 2.6 倍频给出"峰高不等"
            let wave = sin(2 * .pi * crests * t + phase1) * 0.55
                + sin(2 * .pi * crests * 1.7 * t + phase2) * 0.30
                + sin(2 * .pi * crests * 2.6 * t + phase3) * 0.15
            // 归一化到 0…1（理论范围是 ±1，实际很难打满，所以再夹一次）
            let shape = CGFloat(min(max((wave + 1) / 2, 0), 1))
            let y = rect.maxY - rect.height * amplitude * (0.30 + 0.70 * shape)
            points.append(CGPoint(x: rect.minX + rect.width * CGFloat(t), y: y))
        }

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: points[0])
        // 平滑连接：每两点之间用"以上一点为控制点、以中点为终点"的二次曲线
        // —— 这是把折线变成起伏山脊的最小改动（不引入任何控制点表）。
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2,
                              y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        if let last = points.last {
            path.addLine(to: last)
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    /// 从种子里取一段相位（0…2π）
    private static func phase(_ seed: UInt32, shift: UInt32) -> Double {
        let slice = (seed >> shift) & 0x3FF
        return Double(slice) / 1_024 * 2 * .pi
    }
}
