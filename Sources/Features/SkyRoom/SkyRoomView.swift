import SwiftUI

/// 沉浸式「天光室」—— 把天光 / 日弧小组件那块**天空 + 地平线**放大成一整屏。
///
/// 视觉原型就是桌面上那张天光卡：`Theme.sky(phase)` 的六个 token 组成的天幕、
/// `HorizonGround` / `HorizonEdge` 那条二次贝塞尔地平线、按 `SunClock` 当日进度定位的太阳辉光点。
/// 数据源**不新造**：天光来自 `SunClock`（纯函数），天气来自 `WeatherStore`（App 侧既有缓存，
/// 本页只读不发新请求）。
///
/// ## 交互（这一页的全部设计都在这里）
///
/// ```
///            ● 黄昏            距离日落 23分钟     ← 顶部一行（左上角是关闭按钮）
///
///                  （天空 / 远山 / 云带 / 星点，上滑时按不同系数位移）
///         ────────────────────────────────────     ← 地平线（初始 58%）
///                    （玻璃质感的地面 + 太阳落下的余温）
///
///         日出 06:45 · 日落 17:32                  ← 底部一行
/// ```
///
/// - **上滑**：地平线上移（天空扩张）→ 吸附到三档（58% / 38% / 22%，见 `SkyRoomMetrics.detents`）。
///   叠加视差（太阳 > 远山 > 云带 > 星点），天幕整体提亮一档，太阳变大变亮。
/// - **下滑**：像天气 App 那样把天空整体下压，浮出「今日天气面板」（`SkyRoomWeatherPanel`）；
///   继续拉过阈值松手就关闭页面 —— 同时左上角常驻一个极简关闭按钮，
///   不让"只能下拉退出"成为唯一出路。
///
/// ## 三条铁律（本文件逐条遵守）
///
/// 1. **动画只走 `offset` / `scaleEffect` / `opacity`**：上滑/下滑只改这两个 `@State`
///    （`stage` 与 `dragOffset`），所有观感变化都由它们的派生数（`lift` / `expand` / `pull`）驱动。
///    "天空提亮一档"是**叠一层固定色的半透明面、只让不透明度变**，绝不逐帧改渐变色。
/// 2. **不用 `Timer`**：走时全部交给 `TimelineView`（外层 60s 刷新天色与太阳位置，
///    顶部倒计时内层 1s）。本文件没有任何 `Timer(`、没有 `DispatchQueue` 轮询。
/// 3. **尊重 `reduceMotion`**：太阳呼吸与云带漂移在 Reduce Motion 下完全不启动
///    （连初始值都不给），松手吸附改硬切 —— 用户要的结果（页面已到位）完全一样。
///
/// ## 入口（只有两个，见 DESIGN-RULES §4）
///
/// a. 小组件深链 `skyapp://sky`（天光 / 日弧 / 月相 / 风 四张卡，见 `WidgetDeepLink.sky`）；
/// b. 概览第二张卡（`TodayBriefTrackCard`）的「今日」。
/// 页面本身不接受任何参数，也**不再挂第二个入口**。
///
/// ## iPad 档（DESIGN-RULES §1）
///
/// 宽档（`LayoutMetrics.usesWideCards`）时天空舞台**居中限宽 880**，两侧由延展的同色渐变
/// 加暗角收边；字号 ×1.18；天气面板变成悬浮在右下角的一张 360pt 卡片。
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
    /// 太阳辉光呼吸（8s，opacity ±4%）
    @State private var breathe: Bool = false
    /// 云带漂移（40s，单程 6pt）
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

    private func scene(size: CGSize, insets: EdgeInsets, now: Date) -> some View {
        let frame = SkyRoomMetrics.Frame(
            size: size,
            wide: metrics.usesWideCards,
            horizon: horizonFraction(in: size)
        )
        let phase = SunClock.phase(at: now)
        let sky = Theme.sky(phase)

        return ZStack {
            // ① 天幕（含"提亮一档"的叠加层与宽档暗角）
            skyBase(sky: sky, frame: frame)
            // ② 视差层：远山 / 云带 / 星点（只改 offset / opacity）
            parallax(sky: sky, phase: phase, frame: frame)
            // ③ 太阳：**画在地面之前** —— 落下去时会被地面自然盖住，
            //    光晕的下半部分也被地平线裁掉，不需要任何 mask
            sun(sky: sky, frame: frame, now: now)
            // ④ 地面 + 地平线亮边
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

    private func skyBase(sky: Theme.SkyColors, frame: SkyRoomMetrics.Frame) -> some View {
        ZStack {
            LinearGradient(colors: [sky.top, sky.horizon], startPoint: .top, endPoint: .bottom)

            // 「上滑提亮一档」：叠一层**固定色**的半透明面，只有不透明度随 expand 走。
            // 这样整块渐变不需要重新插值（铁律 1），观感却确实是"天亮了"。
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
    }

    // MARK: - ② 视差层

    /// 远山 + 云带 + 星点。三层的位移系数在 `SkyRoomMetrics.Parallax`（近大远小），
    /// 全部用 `.offset` 表达 —— 没有任何一层改颜色或改尺寸（太阳除外，它读 `expand` 放大）。
    private func parallax(sky: Theme.SkyColors, phase: SkyPhase, frame: SkyRoomMetrics.Frame) -> some View {
        ZStack {
            if isStarry(phase) {
                stars(sky: sky, frame: frame)
            }
            clouds(sky: sky, phase: phase, frame: frame)
            mountains(sky: sky, frame: frame)
        }
    }

    /// 远山：两道错开的山脊，底边永远落在初始档的地平线上。
    ///
    /// 为什么锚在**初始档**而不是当前地平线：山必须"落在地平线上"才有距离感。
    /// 若跟着地平线走，山就变成了贴纸（永远贴着地面，看不出远近）。
    /// 锚在 58% 上、按 0.55 系数上移 → 天空扩张时山会慢慢沉到地平线以下被地面盖住，
    /// 这正是"抬头时远山退到视野之外"的正确读法。
    private func mountains(sky: Theme.SkyColors, frame: SkyRoomMetrics.Frame) -> some View {
        let baseY = SkyRoomMetrics.detents[SkyRoomMetrics.restStage] * frame.height
        let originX = (frame.width - frame.stageWidth) / 2
        let stone = sky.ground.opacity(0.42)

        return ZStack {
            SkyRoomRidge(apexX: 0.34)
                .fill(stone)
                .frame(width: frame.stageWidth * 0.58, height: frame.height * 0.11)
                .position(x: originX + frame.stageWidth * 0.30,
                          y: baseY - frame.height * 0.055)
            SkyRoomRidge(apexX: 0.66)
                .fill(stone.opacity(0.72))
                .frame(width: frame.stageWidth * 0.44, height: frame.height * 0.075)
                .position(x: originX + frame.stageWidth * 0.72,
                          y: baseY - frame.height * 0.038)
        }
        .offset(y: -frame.lift * SkyRoomMetrics.Parallax.mountain)
    }

    /// 云带：两条横向拉长的云，位置按天色挑（亮天用 `edge`，暗天用 `ink` —— 与天光小组件同一条规则）。
    /// 漂移是 40s 单程 6pt 的往复，`reduceMotion` 下不启动。
    private func clouds(sky: Theme.SkyColors, phase: SkyPhase, frame: SkyRoomMetrics.Frame) -> some View {
        let tint: Color
        switch phase {
        case .night, .blueDawn, .blueDusk:
            tint = sky.ink
        case .sunrise, .golden, .day, .sunset:
            tint = sky.edge
        }
        let drift = drifting ? SkyRoomMetrics.driftDistance : -SkyRoomMetrics.driftDistance
        let originX = (frame.width - frame.stageWidth) / 2

        return ZStack {
            Capsule()
                .fill(tint.opacity(0.16))
                .frame(width: frame.stageWidth * 0.46, height: frame.height * 0.022)
                .position(x: originX + frame.stageWidth * 0.36, y: frame.height * 0.22)
            Capsule()
                .fill(tint.opacity(0.11))
                .frame(width: frame.stageWidth * 0.34, height: frame.height * 0.016)
                .position(x: originX + frame.stageWidth * 0.66, y: frame.height * 0.33)
        }
        .offset(x: drift, y: -frame.lift * SkyRoomMetrics.Parallax.cloud)
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

    @ViewBuilder
    private func sun(sky: Theme.SkyColors, frame: SkyRoomMetrics.Frame, now: Date) -> some View {
        if let mark = SunClock.sunMark(at: now,
                                       on: now,
                                       crestY: SkyRoomMetrics.detents[SkyRoomMetrics.restStage]),
           mark.isUp, mark.intensity > 0.01 {
            let originX = (frame.width - frame.stageWidth) / 2
            let grow = 1 + SkyRoomMetrics.Sun.grow * frame.expand
            let core = SkyRoomMetrics.Sun.coreDiameter * grow
            let glow = SkyRoomMetrics.Sun.glowDiameter * grow
            let strength = Double(mark.intensity)

            ZStack {
                // 光晕：RadialGradient 伪造，零 blur（与小组件同一套配方）。
                // 呼吸只有这一层的不透明度在动（1.0 ↔ 0.92）。
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: sky.edge.opacity(SkyRoomMetrics.Sun.glowAlpha * strength), location: 0),
                                .init(color: sky.edge.opacity(SkyRoomMetrics.Sun.glowAlpha * 0.35 * strength), location: 0.35),
                                .init(color: sky.edge.opacity(0), location: 1)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: glow / 2
                        )
                    )
                    .frame(width: glow, height: glow)
                    .opacity(glowBreathAlpha)

                Circle()
                    .fill(sky.edge.opacity(0.95))
                    .frame(width: core, height: core)

                Circle()
                    .strokeBorder(sky.edge.opacity(0.55), lineWidth: SkyRoomMetrics.Sun.ringWidth)
                    .frame(width: core + 10, height: core + 10)
            }
            .position(x: originX + mark.point.x * frame.stageWidth,
                      y: mark.point.y * frame.height)
            // 太阳跟着地平线 1:1 上移（系数 1.0）：它是"贴着地平线落下去"的那个东西
            .offset(y: -frame.lift * SkyRoomMetrics.Parallax.sun)
        }
    }

    // MARK: - ④ 地面

    private func ground(sky: Theme.SkyColors, phase: SkyPhase, frame: SkyRoomMetrics.Frame) -> some View {
        let shape = HorizonGround(crestY: frame.horizon, edgeY: frame.arcEdgeY)
        let edge = HorizonEdge(crestY: frame.horizon, edgeY: frame.arcEdgeY)
        let isNight = phase == .night

        return ZStack {
            // 地面本体：该档天色的最暗端，底部留一点透（玻璃质感的一半来自这里）
            shape.fill(
                LinearGradient(
                    colors: [
                        sky.ground,
                        sky.ground.opacity(SkyRoomMetrics.Ground.bottomAlpha)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // 玻璃质感：顶部一层极淡的内亮（token 固定，不随帧变色）
            shape.fill(
                LinearGradient(
                    colors: [Theme.glassSheen, Theme.glassHighlightFade],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // 地平线：雾化层 + 实线层（夜里换成一道更细更淡的冷光）
            if !isNight {
                edge.stroke(sky.edge.opacity(SkyRoomMetrics.Ground.edgeHazeAlpha),
                            lineWidth: SkyRoomMetrics.Ground.edgeHazeWidth)
            }
            edge.stroke(
                sky.edge.opacity(isNight
                                ? SkyRoomMetrics.Ground.nightEdgeAlpha
                                : SkyRoomMetrics.Ground.edgeCoreAlpha),
                lineWidth: isNight
                    ? SkyRoomMetrics.Ground.nightEdgeWidth
                    : SkyRoomMetrics.Ground.edgeWidth
            )
        }
        .frame(width: frame.width, height: frame.height)
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
    /// 也就是**差值留在 `dragOffset` 上再动画归零，而不是换档即清零**：
    /// `detents[next] + residue / h ≡ live`，换档那一刻画面完全不动，动的是随后的 spring。
    /// 这也是上面 `pull` / 天气面板进度不用单独打补丁的原因 —— 它们由连续的 `horizon` 派生，
    /// 地平线连续，它们就连续。
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

    /// 只启动两个动画：太阳辉光呼吸（8s）、云带漂移（40s）。`reduceMotion` 下什么都不启动。
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

    /// 呼吸后的光晕不透明度。Reduce Motion 下恒为 1（不呼吸，也不留一个"半亮"的错值）。
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
        // 只在天空最上面 55% 撒点：贴近地平线会被远山与云带吃掉
        return CGPoint(x: x, y: y * 0.55)
    }
}

// MARK: - 山脊

/// 可调峰顶的三角山脊（`apexX` 让两座山的峰错开 —— 两个等腰三角形并排会像栅栏）。
///
/// 与 Widget 侧的 `RedstoneSpike` 是同一形状思路，但**不能复用**：那个类型属于 Widget target
/// （主 App 的 sources 明确 `excludes: Widget`）。所以这里是一份等价实现，
/// 只画上边两条斜线、底边落在 frame 底边（"从地面长出来"）。
private struct SkyRoomRidge: Shape {

    /// 峰顶横向位置（0…1，相对自身宽度）
    var apexX: CGFloat = 0.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * apexX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
