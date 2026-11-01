import SwiftUI

/// 沉浸式「天光室」——3.14.0 按《iOS 端设计报告 v3 定版》（用户提供，视觉基准
/// `sky-weather.html`）完成第二轮校准。3.13.0 已解决"温度藏进手势"的反模式
/// （标准滚动 + 温度常驻），本版把**质感**对齐报告规格：
///
/// | 报告 v3 规格 | 本版落地 |
/// |---|---|
/// | 大温度 104pt / UltraLight | `TextStyle.heroTemperature` 104pt `.ultraLight` rounded |
/// | 顶栏初始透明，滚动 >30pt 切毛玻璃 | `fixedTopBar` 固定层 + `TopBarGlass`（滚动态 `.card` 玻璃） |
/// | 视差：太阳 0.15 / 山 0.15·0.25·0.40 | `scene(parallaxY:)` 分层下沉，钳制 320pt 不露底 |
/// | hero 减速上滑 + 缩小淡出 | 净速度 0.55x、scale 1→0.70、160pt 内淡尽 |
/// | 太阳大核心 + 大半径辉光 | 核心 16pt、内晕 96、外晕 340（pt 折算，保各档天色层次） |
/// | 「上滑查看详情」bob 提示 | 2s ±4pt 呼吸，reduceMotion 不启动 |
/// | 湿度/能见度没数据不渲染空壳 | 接口无此字段，卡片区维持四张（§六铁律） |
///
/// 报告的色板是"黄昏专用"；本工程已有七档天色 token（`Theme.sky`），
/// 所以落的是报告的**结构与交互**，颜色仍逐字走各档 token —— 夜里不会出现橙天空。
///
/// ## 页面结构
///
/// ```
/// ZStack(alignment: .top) {
///   ① 天空场景（天幕 / 星 / 云 / 太阳 / 山脊 / 地面，滚动时分层下沉）
///        └ 滚动反馈：压暗 ≤0.45（只动 opacity，合成层变换）
///   ② ScrollView { hero（高 62%，减速淡出）→ 卡片流 }
///   ③ 固定顶栏（滚过 30pt 切毛玻璃）
/// }
/// ```
///
/// ## 四条铁律（3.12.0 原样继承，本文件逐条遵守）
///
/// 1. **动画只走 `offset` / `scaleEffect` / `opacity`**：滚动反馈只改一个 `@State`
///    （`scrollOffset`）的派生数；`MeshGradient` 的 16 个点**只随天色（60s 一帧）变**，
///    绝不随滚动逐帧重建 —— 重建一次网格 = 重新插值整块全屏像素，那正是"卡"的来源。
/// 2. **`blur` 半径是常量**：云朵模糊固定 18pt，只在合成时算一次。
/// 3. **不用 `Timer`**：走时全部交给 `TimelineView`（外层 60s 刷新天色与太阳位置，
///    顶部倒计时内层 1s）。
/// 4. **尊重 `reduceMotion`**：太阳呼吸、云漂移、背景微放大全部不启动 ——
///    但视觉完整（静态画面里云、山、星、太阳一样都在）。
///
/// ## 入口 / iPad 档（不变）
///
/// 入口只有两个（DESIGN-RULES §4）：小组件深链 `skyapp://sky`、概览第二张卡的「今日」。
/// 宽档（`LayoutMetrics.usesWideCards`）时舞台**居中限宽 880**（`frame(maxWidth:)`，
/// 不是固定宽度 —— 固定宽度会撑宽父级，那正是 3.12.0 修的 P0 事故），字号 ×1.18。
struct SkyRoomView: View {

    @Environment(\.dismiss) private var dismiss
    /// 尺寸模型（唯一"设备有多大"的判据，见 DESIGN-RULES §1）
    @Environment(\.layoutMetrics) private var metrics
    /// 前庭敏感用户：呼吸 / 漂移 / 背景微放大全部让位
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 滚动过的距离（pt，≥0）。它是本页唯一随手势变化的状态，
    /// 所有滚动反馈都是它的派生数（压暗 / 微放大 / 提示淡出）。
    @State private var scrollOffset: CGFloat = 0
    /// 天气快照（nil = 还没到，是正常状态）
    @State private var weatherNow: WeatherNow?
    /// 太阳外晕呼吸（8s，opacity ±4%）
    @State private var breathe: Bool = false
    /// 云漂移（40s，单程 6pt × 距离系数）
    @State private var drifting: Bool = false
    /// 滚动提示的 bob 呼吸（2s，±4pt；报告 §三，reduceMotion 不启动）
    @State private var hintBob: Bool = false
    /// 截图模式下的固定时刻（仅 Debug + bundle 里有 `preview-skyroom.json` 时非 nil）。
    /// CI 可能在任意时间跑，不钉住时刻的话半夜截图会得到一片夜空，
    /// 无法和用户反馈的黄昏场景对照。
    @State private var previewMoment: Date?

    var body: some View {
        GeometryReader { proxy in
            // 安全区**手动**折进全屏坐标：这一页的天空必须铺到状态栏与 Home Indicator 之外，
            // 而 `GeometryReader` 一旦自己 `ignoresSafeArea` 就拿不到 insets（会变成 0）。
            let insets = proxy.safeAreaInsets
            let full = CGSize(
                width: proxy.size.width + insets.leading + insets.trailing,
                height: proxy.size.height + insets.top + insets.bottom
            )
            // 60s 一格：天色与太阳位置每分钟重算一次就够（天色档位本身是整块跳变的）。
            // 秒级走时只发生在顶部倒计时与天光卡倒计时（内层 TimelineView）。
            TimelineView(.periodic(from: Date(), by: 60)) { context in
                page(size: full, insets: insets, now: previewMoment ?? context.date)
            }
            .frame(width: full.width, height: full.height)
            .offset(x: -insets.leading, y: -insets.top)
        }
        // 兜底底色：万一某一帧没画出天空（首帧量尺寸），也不会有白闪
        .background(Theme.bgBase)
        // 3.15.0：这一页**强制深色**。
        //
        // 天光页是沉浸式场景，它的明暗关系由天空决定，跟系统外观无关。
        // 浅色模式下 `glassSurface` 用「白 72%」的玻璃，叠在暖色天上会变成一块发闷的白板，
        // 而卡片文字又是深墨色 —— 真机截图里那几张"灰扑扑的卡片"就是这么来的。
        // 强制深色后：玻璃 = 白 6% + 厚材质、文字 = 近白，与天空同一套明暗逻辑。
        .preferredColorScheme(.dark)
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

    // MARK: - 页面装配

    /// 背景在**下层**、内容在**上层**：这是"天空是海报、信息是卡片"的分层
    /// （调研结论 §一.5）。背景不随内容滚动——它只按滚动进度做压暗与微放大，
    /// 于是卡片永远浮在同一片天上，而天在卡片滑过时慢慢静下来。
    private func page(size: CGSize, insets: EdgeInsets, now: Date) -> some View {
        let frame = SkyRoomMetrics.Frame(size: size, wide: metrics.usesWideCards)
        let phase = SunClock.phase(at: now)
        let sky = Theme.sky(phase)
        let progress = scrollProgress(height: frame.height)

        return ZStack(alignment: .top) {
            // ① 天空场景（六层：天幕 → 星 → 云 → 太阳 → 山脊 → 地面，
            //    太阳 / 云 / 山随滚动分层下沉——报告 §三 的视差）
            scene(sky: sky, phase: phase, frame: frame, now: now, parallaxY: parallaxY)
                // 压暗：滚过半屏后天空退成"安静的背景板"，卡片可读性随之上升。
                // 压暗不是动效（reduceMotion 用户也需要可读性），所以它不受铁律 4 管辖。
                .overlay(
                    Rectangle()
                        .fill(sky.ground)
                        .opacity(Double(progress) * SkyRoomMetrics.Scroll.dimAlpha)
                        .allowsHitTesting(false)
                )
            // ② 滚动内容（hero + 卡片流）
            scrollContent(sky: sky, frame: frame, insets: insets, now: now)
            // ③ 固定顶栏：初始透明，滚过 30pt 切毛玻璃（报告 §三）
            fixedTopBar(sky: sky, frame: frame, insets: insets, now: now)
        }
        .frame(width: size.width, height: size.height)
    }

    /// 滚动进度 0…1：滚过半屏（`Scroll.travel` × 屏高）算走满。
    private func scrollProgress(height: CGFloat) -> CGFloat {
        let span = max(height * SkyRoomMetrics.Scroll.travel, 1)
        return min(max(scrollOffset / span, 0), 1)
    }

    /// 视差行程：滚过的距离被钳制在 `parallaxClamp` 内 —— 远处的山与太阳
    /// 沉到这里就"停"，不会把地平线一路沉出屏幕（HTML 版用 `-10%` 余量兜底，
    /// 原生版钳制更稳：不露底、不越界）。
    private var parallaxY: CGFloat {
        return min(scrollOffset, SkyRoomMetrics.Scroll.parallaxClamp)
    }

    // MARK: - 滚动内容

    private func scrollContent(sky: Theme.SkyColors,
                               frame: SkyRoomMetrics.Frame,
                               insets: EdgeInsets,
                               now: Date) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                hero(sky: sky, frame: frame, insets: insets, now: now)
                cards(sky: sky, frame: frame, now: now)
                    .padding(.top, 6)
                Color.clear.frame(height: SkyRoomMetrics.Page.tailPadding)
            }
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            // 顶部有内容内边距时要把它折进来，否则第一帧 offset 不从 0 开始
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newValue in
            scrollOffset = max(0, newValue)
        }
    }

    // MARK: - hero（首屏：温度大字常驻）

    /// hero 区高 62%（地平线在 58%）——卡片流恰好从地平线略下方开始，
    /// 读起来是"信息从大地里长出来"。顶栏已上提到固定层（报告 §三），
    /// hero 内容从顶栏高度之下开始排。
    private func hero(sky: Theme.SkyColors,
                      frame: SkyRoomMetrics.Frame,
                      insets: EdgeInsets,
                      now: Date) -> some View {
        // 报告 §三：fade = y/160；温度大字 scale = 1 - fade*0.3，opacity = 1 - fade*1.25
        let fade = min(max(scrollOffset / SkyRoomMetrics.Scroll.heroFadeTravel, 0), 1)
        let gone = max(0, 1 - fade * 1.25)

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            // 温度大字的减速视差：净速度 0.55x，像贴在天上而不是印在纸上
            heroReadout(sky: sky, frame: frame)
                .scaleEffect(1 - SkyRoomMetrics.Scroll.heroShrink * fade)
                .opacity(gone)
                .offset(y: scrollOffset * SkyRoomMetrics.Scroll.heroLag)
            Spacer(minLength: 0)
            // 3.15.0：删掉「日出 06:45 · 日落 17:32」那一行 —— 它与「今日天光」卡完全重复，
            // 而且正好压在地平线上，滚动时和提示叠成一团。日出日落在卡里看得更清楚。
            scrollHint(sky: sky, frame: frame)
                .opacity(1 - fade)
                .padding(.bottom, 14)
        }
        .padding(.top, insets.top + SkyRoomMetrics.Page.topbarReserve)
        .padding(.horizontal, frame.wide ? SkyRoomMetrics.Page.wideInset : 0)
        .frame(height: frame.heroHeight)
        .frame(width: frame.stageWidth)
        .frame(maxWidth: .infinity)
    }

    /// 温度大字 + 现象 + 今日高低温 —— **常驻、零手势**（3.13.0 的立页之本）。
    ///
    /// 文字色走 `sky.ink` / `sky.inkDim`（该档天色配好的"墨色"），跟顶部状态行同源：
    /// 天幕是暖色时墨色自动转深，不会出现"白字贴亮天"。
    private func heroReadout(sky: Theme.SkyColors, frame: SkyRoomMetrics.Frame) -> some View {
        let weather = weatherNow
        let hasReading = weather?.ok == true
            && (weather?.temp != nil || conditionPhrase(weather) != nil)

        return VStack(spacing: 4) {
            if hasReading {
                if let temp = weather?.temp {
                    Text("\(Int(temp))°")
                        .font(SkyRoomMetrics.TextStyle.heroTemperature(frame.fontScale))
                        .foregroundStyle(sky.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let phrase = conditionPhrase(weather) {
                    Text(phrase)
                        .font(SkyRoomMetrics.TextStyle.heroCondition(frame.fontScale))
                        .foregroundStyle(sky.inkDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if let range = rangeText(weather) {
                    Text(range)
                        .font(SkyRoomMetrics.TextStyle.heroRange(frame.fontScale))
                        .foregroundStyle(sky.inkDim)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 2)
                }
            } else {
                // 没数据是正常状态（首装还没拉、断网）：说人话，不猜一个晴天出来
                Text("天气还没到")
                    .font(SkyRoomMetrics.TextStyle.heroCondition(frame.fontScale))
                    .foregroundStyle(sky.ink)
                Text("这一页主要看天光，天气到了自己会出现。")
                    .font(SkyRoomMetrics.TextStyle.heroRange(frame.fontScale))
                    .foregroundStyle(sky.inkDim)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, SkyRoomMetrics.Page.compactInset)
        // 3.15.0：文字阴影。`sky.ink` 是固定白，而七档天色里有四档的上半部是亮的 ——
        // 光靠色差读不住。柔和暗影是主流天气 App 的通行做法（把文字从背景里"拎"出来，
        // 不改字色，于是换档时字色不用跟着跳）。
        .shadow(color: .black.opacity(0.24), radius: 20, y: 2)
    }

    /// 天气现象：服务端中文描述优先，缺了才用八档视觉类型的中性名
    private func conditionPhrase(_ weather: WeatherNow?) -> String? {
        guard let weather, weather.ok else { return nil }
        if let text = weather.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        return weather.kind?.title
    }

    /// 高低温一行：`最高 16° · 最低 10°`。缺一头就整行不出（不写半句话）。
    private func rangeText(_ weather: WeatherNow?) -> String? {
        guard let weather, weather.ok, let high = weather.tMax, let low = weather.tMin else {
            return nil
        }
        return "最高 \(Int(high))° · 最低 \(Int(low))°"
    }

    /// 滚动提示：只在第一屏出现，滚过 1/4 屏就淡出（opacity 只减不增，不闪）。
    /// bob 动画（±4pt / 2s）是报告 §三 的「上滑查看详情」呼吸提示，reduceMotion 不启动。
    private func scrollHint(sky: Theme.SkyColors, frame: SkyRoomMetrics.Frame) -> some View {
        let fade = 1 - min(max(scrollOffset / (frame.height * 0.25), 0), 1)
        return VStack(spacing: 2) {
            Image(systemName: "chevron.up")
                .font(.system(size: 9, weight: .semibold))
            Text("向上滑动查看详情")
                .font(SkyRoomMetrics.TextStyle.scrollHint(frame.fontScale))
        }
        .foregroundStyle(sky.inkDim)
        .opacity(fade)
        .offset(y: hintBobOffset)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    /// 顶栏固定层的滚动反馈：滚过 `topbarThreshold` 切毛玻璃（报告 §三：复刻
    /// UIVisualEffectView 的"滚起来才知道自己在哪"）。动画只包这 0.25s 的材质切换。
    private func fixedTopBar(sky: Theme.SkyColors,
                             frame: SkyRoomMetrics.Frame,
                             insets: EdgeInsets,
                             now: Date) -> some View {
        let isScrolled = scrollOffset > SkyRoomMetrics.Scroll.topbarThreshold
        return topBar(sky: sky, frame: frame, now: now)
            .padding(.horizontal, frame.wide ? SkyRoomMetrics.Page.wideInset : SkyRoomMetrics.Page.compactInset)
            .padding(.vertical, 6)
            .modifier(TopBarGlass(active: isScrolled))
            .padding(.top, insets.top + 4)
            .animation(.easeOut(duration: 0.25), value: isScrolled)
            .frame(maxWidth: .infinity)
    }

    /// 顶部一行（关闭按钮 + 阶段名 + 倒计时）—— 3.12.0 原样保留。
    /// 关闭按钮常驻：手势永远只是快捷方式，必须留可见的替代路径。
    private func topBar(sky: Theme.SkyColors, frame: SkyRoomMetrics.Frame, now: Date) -> some View {
        HStack(spacing: 10) {
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
            //
            // 3.15.0 布局修正：原来是「● 阶段名 ——— Spacer ——— 2分钟59秒」，
            // 真机上两头被撑到屏幕两侧，中间一条空，读起来像两件不相干的事。
            // 现在两者紧挨着排，整行靠左，右侧留白 —— 一个"当前状态"才是一个句子。
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                // 截图模式下时刻是钉住的（`previewMoment`），倒计时不跟着真实秒数跑
                let moment = previewMoment ?? context.date
                HStack(spacing: 7) {
                    Circle()
                        .fill(sky.edge)
                        .frame(width: 5, height: 5)
                    Text(SunClock.phase(at: moment).label)
                        .font(SkyRoomMetrics.TextStyle.phase(frame.fontScale))
                        .foregroundStyle(sky.ink)
                        .lineLimit(1)
                    if let deadline = SunClock.phase(at: moment).deadline(at: moment) {
                        Text(shortCountdown(to: deadline, now: moment))
                            .font(SkyRoomMetrics.TextStyle.countdown(frame.fontScale))
                            .foregroundStyle(sky.inkDim)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 顶部倒计时的紧凑格式：`2:59` / `1 时 05 分`。
    ///
    /// 不复用 `SkyPhase.countdownText`（那是"2 分钟 59 秒"的完整表达，给小组件与卡片用）：
    /// 顶栏只有一行、旁边还挨着阶段名，完整表达会把这行撑得很长。
    private func shortCountdown(to deadline: Date, now: Date) -> String {
        let total = max(0, Int(deadline.timeIntervalSince(now).rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours) 时 \(minutes) 分" }
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - 卡片流

    /// 四张卡：天光进度（身份卡）→ 气温范围 →（风 | 云量）。
    /// 接口只有这几组数据，就只做这几张卡 —— 没有的数据不放假卡。
    private func cards(sky: Theme.SkyColors, frame: SkyRoomMetrics.Frame, now: Date) -> some View {
        VStack(spacing: SkyRoomMetrics.Page.cardSpacing) {
            if let times = sunTimes(now: now) {
                SkyRoomDaylightCard(now: now,
                                    sunrise: times.sunrise,
                                    sunset: times.sunset,
                                    sky: sky,
                                    scale: frame.fontScale)
            }
            SkyRoomTemperatureCard(weather: weatherNow,
                                   sky: sky,
                                   scale: frame.fontScale)
            HStack(spacing: SkyRoomMetrics.Page.cardSpacing) {
                SkyRoomWindCard(weather: weatherNow, scale: frame.fontScale)
                SkyRoomCloudCard(weather: weatherNow, scale: frame.fontScale)
            }
        }
        .frame(width: frame.cardColumnWidth)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 天气时刻（hero 行与天光卡共用）

    /// 今天的日出日落：优先天气接口的实际时刻（`WeatherNow.sunriseDate`），
    /// 缺了回落 `SunClock`（±3 分钟）。给的是**今天**这一对 —— 夜里天光卡的
    /// 游标停在端点、倒计时显示「已日落 / 距日出」，语义都是自洽的。
    private func sunTimes(now: Date) -> (sunrise: Date, sunset: Date)? {
        let sunrise = weatherNow?.sunriseDate
        let sunset = weatherNow?.sunsetDate
        if let sunrise, let sunset {
            return (sunrise, sunset)
        }
        return SunClock.times(on: now)
    }

    // MARK: - 场景装配（背景，3.12.0 的六层结构原样保留）

    /// 六层的顺序**就是物理距离的顺序**（远 → 近）：
    ///
    /// 天幕 → 星点 → 云 → **太阳** → 山脊 → 地面。
    ///
    /// 太阳排在**山脊之前**：日落时太阳会被山挡住一半，那是日落该有的读法。
    /// 它同时仍在地面之前 —— 落到地平线以下的部分被地面盖住，不需要任何 mask。
    ///
    /// 3.14.0 起接入**滚动视差**（报告 §三）：滚动时太阳 / 云 / 星 / 山按各自深度
    /// 向下沉——越近的层沉得越快，天"退到后面去"，纵深就是这样来的。
    /// 全部走 `offset`（合成层变换），天幕本体零重建；`parallaxY` 已钳制，
    /// 山沉进地面、太阳沉进地平线，都不露底。
    private func scene(sky: Theme.SkyColors,
                       phase: SkyPhase,
                       frame: SkyRoomMetrics.Frame,
                       now: Date,
                       parallaxY: CGFloat) -> some View {
        ZStack {
            // ① 天幕（网格 / 线性兜底 + 宽档暗角）—— 天幕不动（它是"无限远"）
            skyBase(sky: sky, phase: phase, frame: frame, now: now)
            // ② 星点 / 云 / 三层山脊（各带视差）
            parallax(sky: sky, phase: phase, frame: frame, parallaxY: parallaxY)
            // ③ 太阳：三层结构，画在山脊与地面之前，随滚动沉向地平线
            sun(sky: sky, phase: phase, frame: frame, now: now)
                .offset(y: parallaxY * SkyRoomMetrics.Scroll.sunDepth)
            // ④ 地面 + 地平线光带 + 暖色辉光 + 竖纹理（地面不沉：它是"脚下"）
            ground(sky: sky, phase: phase, frame: frame)
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
    }

    // MARK: - ① 天幕

    /// 天幕 = 网格（或线性兜底）+ 宽档暗角。
    private func skyBase(sky: Theme.SkyColors,
                         phase: SkyPhase,
                         frame: SkyRoomMetrics.Frame,
                         now: Date) -> some View {
        ZStack {
            dome(phase: phase, frame: frame, now: now)

            if frame.wide {
                // 宽档收边：舞台两侧压向该档天色里最暗的 `ground`，视线自然收回中间。
                LinearGradient(
                    stops: [
                        .init(color: sky.ground.opacity(SkyRoomMetrics.Page.vignetteAlpha), location: 0),
                        .init(color: sky.ground.opacity(0), location: 0.24),
                        .init(color: sky.ground.opacity(0), location: 0.76),
                        .init(color: sky.ground.opacity(SkyRoomMetrics.Page.vignetteAlpha), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }

    /// 天幕本体：交给 `SkyRoomDome`（一个 `Equatable` 包装）。
    ///
    /// **为什么要包一层**：滚动 / 呼吸 / 云漂移期间 `scene` 会重算，但这一层的输入
    /// （天色档位、画布尺寸、太阳位置）**一个都没变** —— `Equatable` 让 SwiftUI 直接跳过
    /// 整块全屏网格的重建。这是"滚动不卡"的关键：网格一旦逐帧重建，
    /// 每帧都要重新插值整屏像素。
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
    /// 网格的暖色团跟这两件事走。算不出（极昼极夜）时给
    /// "正中、中等高度" —— 不猜天色，只给一个不会出错的中间态。
    private func sunGeometry(now: Date) -> (x: Float, height: Float) {
        let horizonY = SkyRoomMetrics.Page.horizon
        let mark = SunClock.sunMark(at: now,
                                    on: now,
                                    crestY: horizonY)
        guard let mark else { return (0.5, 0.5) }
        let y = Float(mark.point.y)
        let height: Float = horizonY > 0 ? min(max(1 - y / Float(horizonY), 0), 1) : 0.5
        return (Float(mark.point.x), height)
    }

    // MARK: - ② 星 / 云 / 山

    private func parallax(sky: Theme.SkyColors,
                          phase: SkyPhase,
                          frame: SkyRoomMetrics.Frame,
                          parallaxY: CGFloat) -> some View {
        ZStack {
            if isStarry(phase) {
                stars(sky: sky, frame: frame)
                    .offset(y: parallaxY * SkyRoomMetrics.Scroll.starDepth)
            }
            clouds(sky: sky, phase: phase, frame: frame)
                .offset(y: parallaxY * SkyRoomMetrics.Scroll.cloudDepth)
            mountains(sky: sky, frame: frame, parallaxY: parallaxY)
        }
    }

    /// 三层山脊。锚在固定地平线上，层与层之间错开 8pt，
    /// 颜色随距离混入天空色（`haze`）—— 越远越淡越蓝，这就是大气透视。
    /// 滚动时各层按 `parallaxDepth` 下沉（远 0.15 / 中 0.25 / 近 0.40）。
    private func mountains(sky: Theme.SkyColors,
                           frame: SkyRoomMetrics.Frame,
                           parallaxY: CGFloat) -> some View {
        let baseY = frame.horizon * frame.height

        return ZStack {
            // 远 → 近：顺序即 z 轴（后面的盖住前面的）
            ForEach(Array(SkyRoomMetrics.Ridges.layers.enumerated()), id: \.offset) { pair in
                ridge(spec: pair.element,
                      sky: sky,
                      frame: frame,
                      baseY: baseY,
                      parallaxY: parallaxY)
            }
        }
    }

    /// 一层山脊：形状 + 大气透视 + 滚动视差
    ///
    /// **山脚的垂直位置是固定的**：矩形底统一落在 `horizon + buryDepth`（0.68H），
    /// 比地面最外端（0.65H）还低 —— 山一定是从地里长出来的，不存在"山脚露一条天"。
    /// 峰高由 `heightRatio × amplitude` 决定，三层分别落在 0.47H / 0.51H / 0.53H。
    ///
    /// 填充走 `Color.blend` 实色：远山 58% 混入天空色（化在天里），近山 14%（一块实剪影）。
    /// 3.14.0 用 `opacity` 的结果是一整块"土黄半透明板"——形状轮廓被冲没，只剩脏。
    private func ridge(spec: SkyRoomMetrics.RidgeSpec,
                       sky: Theme.SkyColors,
                       frame: SkyRoomMetrics.Frame,
                       baseY: CGFloat,
                       parallaxY: CGFloat) -> some View {
        let width = frame.stageWidth * spec.widthRatio
        let height = frame.height * spec.heightRatio
        // 山脚：固定埋进地面，与 index 无关（层与层的错落由峰高本身拉开）
        let footY = baseY + frame.height * SkyRoomMetrics.Ridges.buryDepth

        // 山体本色：远山更"化"在天里（混入更多 horizon），近山接近大地本色
        let ridgeTop = Color.blend(sky.ground, sky.horizon, spec.haze)
        let ridgeDeep = Color.blend(sky.ground, .black, 0.20)

        return SkyRoomRidge(crests: spec.crests,
                            amplitude: spec.amplitude,
                            seed: spec.seed,
                            sampleCount: SkyRoomMetrics.Ridges.sampleCount)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: ridgeTop, location: 0),
                        .init(color: Color.blend(ridgeTop, ridgeDeep, 0.55), location: 0.55),
                        .init(color: ridgeDeep, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width, height: height)
            // `.position` 返回的是**弹性视图**（铺满 proposal），所以固定尺寸的山不会撑宽父级
            .position(x: frame.stageOriginX + frame.stageWidth * spec.centerX,
                      y: footY - height / 2)
            // 视差下沉：山体下缘原本就埋在地面里，往下沉只会沉得更深，不露底
            .offset(y: parallaxY * spec.parallaxDepth)
    }

    /// 云：5 朵，每朵 3–4 个模糊椭圆叠成不规则形状。
    ///
    /// 三条纪律：
    /// 1. **模糊是对整朵云做一次**（`ZStack` 上挂一个 `.blur`）；
    /// 2. 模糊半径是**常量** 18pt，只有 `offset` / `opacity` 在动（铁律 2）；
    /// 3. 形状由**固定种子**推（`noise(_:_:)`），同一朵云每次进场都长一样。
    private func clouds(sky: Theme.SkyColors, phase: SkyPhase, frame: SkyRoomMetrics.Frame) -> some View {
        let tint = cloudTint(sky: sky, phase: phase)
        let drift = drifting ? SkyRoomMetrics.driftDistance : -SkyRoomMetrics.driftDistance

        return ZStack {
            ForEach(Array(SkyRoomMetrics.Clouds.specs.enumerated()), id: \.offset) { pair in
                cloud(spec: pair.element, tint: tint, frame: frame)
                    .position(x: frame.stageOriginX + frame.stageWidth * pair.element.centerX,
                              y: frame.height * pair.element.centerY)
                    .offset(x: drift * pair.element.drift)
            }
        }
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

    /// 星点：只有夜 / 晨蓝 / 暮蓝三档出现。位置由确定性哈希给出 ——
    /// 不用 `random`，否则星星会整体换位，看起来像闪烁故障。
    private func stars(sky: Theme.SkyColors, frame: SkyRoomMetrics.Frame) -> some View {
        return ZStack {
            ForEach(0..<SkyRoomMetrics.Stars.count, id: \.self) { index in
                let point = starPoint(index)
                Circle()
                    .fill(sky.ink)
                    .frame(width: SkyRoomMetrics.Stars.diameter,
                           height: SkyRoomMetrics.Stars.diameter)
                    .position(x: frame.stageOriginX + point.x * frame.stageWidth,
                              y: point.y * frame.height)
            }
        }
        .opacity(SkyRoomMetrics.Stars.baseAlpha)
    }

    // MARK: - ③ 太阳

    /// 三层结构的太阳（3.12.0 引入，原样保留）。
    ///
    /// | 层 | 尺寸 | 不透明度 | 颜色 |
    /// |---|---|---|---|
    /// | 外晕 | 直径 220 | 0.18 | 日出日落橙红、正午偏白（`sunOuterTint`） |
    /// | 内晕 | 直径 40 | 0.55 | 暖白（`sunInnerTint`） |
    /// | 核心 | 直径 12 | 1.00 | `sky.edge`（每档最亮的那支） |
    ///
    /// 三层**共用同一个位置**。呼吸只有外晕的 `opacity` 在动（1.0 ↔ 0.92）。
    @ViewBuilder
    private func sun(sky: Theme.SkyColors,
                     phase: SkyPhase,
                     frame: SkyRoomMetrics.Frame,
                     now: Date) -> some View {
        if let mark = SunClock.sunMark(at: now,
                                       on: now,
                                       crestY: SkyRoomMetrics.Page.horizon),
           mark.isUp, mark.intensity > 0.01 {
            let core = SkyRoomMetrics.Sun.coreDiameter
            let inner = SkyRoomMetrics.Sun.innerGlowDiameter
            let outer = SkyRoomMetrics.Sun.outerGlowDiameter
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
            .position(x: frame.stageOriginX + mark.point.x * frame.stageWidth,
                      y: mark.point.y * frame.height)
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
    private func ground(sky: Theme.SkyColors,
                        phase: SkyPhase,
                        frame: SkyRoomMetrics.Frame) -> some View {
        let shape = HorizonGround(crestY: frame.horizon, edgeY: frame.arcEdgeY)
        let edge = HorizonEdge(crestY: frame.horizon, edgeY: frame.arcEdgeY)
        let isNight = phase == .night
        let haze = horizonHaze(sky: sky, phase: phase)

        // 三段实色：地平线的暖大地 → 中段大地本色 → 底部压深
        let crest = Color.blend(sky.horizon, sky.ground, SkyRoomMetrics.Ground.crestMix)
        let mid = Color.blend(sky.horizon, sky.ground, SkyRoomMetrics.Ground.midMix)
        let deep = Color.blend(sky.ground, .black, SkyRoomMetrics.Ground.bottomDarken)

        return ZStack {
            // ① 本体：三段实色（3.15.0 起不再叠半透明 —— 那正是"地平线一片暧昧橙"的来源）
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: crest, location: 0),
                        .init(color: mid, location: SkyRoomMetrics.Ground.midStop),
                        .init(color: sky.ground, location: SkyRoomMetrics.Ground.midStop + 0.22),
                        .init(color: deep, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // ② 极淡的竖向纹理（0.02 不透明度）：用 `Canvas` 一次画完
            groundTexture(sky: sky, frame: frame)
            // ③ 地平线下方 20pt 的暖色辉光（从地平线往下淡出）
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
            // ⑤ 渐隐光带：横向从 `sky.edge` 淡到透明（地平线"消失在画面外"，不断在屏幕边）
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

    // MARK: - 动态（克制）

    /// 只启动三个动画：太阳外晕呼吸（8s）、云漂移（40s）、滚动提示 bob（2s）。
    /// `reduceMotion` 下什么都不启动。
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
        withAnimation(.easeInOut(duration: SkyRoomMetrics.hintBobDuration)
            .repeatForever(autoreverses: true)) {
            hintBob = true
        }
    }

    /// 静态兜底：把三个开关复位（视图离场后动画不该继续跑）。
    private func stopAmbient() {
        breathe = false
        drifting = false
        hintBob = false
    }

    /// bob 的瞬时位移（0 或 4pt，方向由动画插值）。
    private var hintBobOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        return hintBob ? SkyRoomMetrics.hintBobDistance : 0
    }

    /// 呼吸后的外晕不透明度。Reduce Motion 下恒为 1（不呼吸，也不留一个"半亮"的错值）。
    private var glowBreathAlpha: Double {
        guard !reduceMotion else { return 1 }
        return breathe ? 1 : SkyRoomMetrics.breatheFloor
    }

    // MARK: - 天气

    /// 读一次天气。`WeatherStore` 自带 10 分钟缓存与"失败保留旧值"，
    /// 所以这一页既不需要新 Store，也不会因为断网把页面变成错误态。
    @MainActor
    private func loadWeather() async {
        #if DEBUG
        // 截图模式：bundle 里有标记文件就用它，不请求网络（CI 模拟器可能没网）
        if let scene = SkyRoomPreviewScene.load() {
            weatherNow = scene.weather
            previewMoment = scene.moment
            return
        }
        #endif
        await WeatherStore.shared.load()
        weatherNow = WeatherStore.shared.current
    }

    // MARK: - 静态几何

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
    private func noise(_ seed: UInt32, _ index: Int) -> CGFloat {
        var value = seed &+ (UInt32(truncatingIfNeeded: index) &* 2_246_822_519)
        value = value ^ (value >> 13)
        value = value &* 2_654_435_761
        value = value ^ (value >> 16)
        return CGFloat(value % 10_000) / 10_000
    }
}

// MARK: - 顶栏滚动态玻璃

/// 报告 §三 的「topbar.scrolled」：激活时套 `.card` 级玻璃（全工程唯一玻璃入口，
/// iOS 26 走系统 `glassEffect`、18–25 走手工配方），未激活时完全透明。
private struct TopBarGlass: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.glassSurface(.card,
                                 in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            content
        }
    }
}

// MARK: - 截图场景（仅 Debug）

#if DEBUG
/// 从 bundle 里的 `preview-skyroom.json` 解出一份天气，并把页面时刻钉在**今天 17:25**（日落档）。
///
/// 这个文件只在"准备截图"的那次构建里提交，发版前删除；整段在 `#if DEBUG` 里，
/// Release 包里既没有这段代码，也没有那个 json。
private struct SkyRoomPreviewScene {

    let weather: WeatherNow
    let moment: Date

    static func load() -> SkyRoomPreviewScene? {
        guard let url = Bundle.main.url(forResource: "preview-skyroom", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let weather = try? JSONDecoder().decode(WeatherNow.self, from: data) else {
            return nil
        }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 17
        components.minute = 25
        let moment = Calendar.current.date(from: components) ?? Date()
        return SkyRoomPreviewScene(weather: weather, moment: moment)
    }
}
#endif

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
/// 太阳横坐标、太阳高度角 —— 滚动 / 云漂移 / 呼吸期间这四样都不变。
/// 加上 `Equatable`（配合调用点的 `.equatable()`）之后，SwiftUI 会拿新旧值比一次、
/// 相等就**整块跳过重建**：滚动时网格一次都不重算，只会被 `scaleEffect` / `opacity`
/// 做合成层变换。
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

    /// 某一行的颜色（天顶深 → 地平线暖）。
    ///
    /// **全部是 `Color.blend` 的实色混合，一个 `opacity` 都没有**（3.15.0 修的就是这一条）。
    /// 半透明色会让"天空的颜色"由底下垫着的东西决定，而 MeshGradient 底下什么都没有 ——
    /// 于是整片天被稀释成灰白。3.14.0 真机截图里那块灰白布就是这么来的。
    private func color(row: Int, warm: Color, depth: Double) -> Color {
        switch row {
        case 0:
            // 天顶：往该档最深的色里压 —— "冷"与"深"是同一件事
            return Color.blend(sky.top, sky.ground,
                               depth * SkyRoomMetrics.SkyDome.zenithMix)
        case 1:
            return Color.blend(sky.top, sky.horizon, SkyRoomMetrics.SkyDome.row1Warmth)
        case 2:
            return Color.blend(sky.top, sky.horizon, SkyRoomMetrics.SkyDome.row2Warmth)
        default:
            // 贴地平线那一行：该档最暖的色，实色
            return warm
        }
    }

    /// 地平线那一行的暖色 token。
    private var warmToken: Color {
        switch phase {
        case .sunrise, .sunset, .golden:
            return sky.horizon
        case .day, .night, .blueDawn, .blueDusk:
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

/// 平滑山脊（3.12.0 引入，原样保留）。
///
/// 三个不同频率的正弦叠加（0.55 / 0.30 / 0.15）再归一化到 0…1，得到一条**至少有 4 个波峰**、
/// 且峰高不等的起伏曲线；然后用 `quadCurve` 把采样点连成平滑曲线（不是折线）。
/// 固定种子保证同一台设备每次进来看见的是同一座山。
private struct SkyRoomRidge: Shape {

    /// 主频（视野内大约几个波峰）
    var crests: Double
    /// 高差（相对自身高度）
    var amplitude: CGFloat
    /// 固定种子（决定三个正弦的相位）
    var seed: UInt32
    /// 采样点数（72 段在 400pt 宽上每段约 5.5pt）
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
            let wave = sin(2 * .pi * crests * t + phase1) * 0.55
                + sin(2 * .pi * crests * 1.7 * t + phase2) * 0.30
                + sin(2 * .pi * crests * 2.6 * t + phase3) * 0.15
            let shape = CGFloat(min(max((wave + 1) / 2, 0), 1))
            let y = rect.maxY - rect.height * amplitude * (0.30 + 0.70 * shape)
            points.append(CGPoint(x: rect.minX + rect.width * CGFloat(t), y: y))
        }

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: points[0])
        // 平滑连接：每两点之间用"以上一点为控制点、以中点为终点"的二次曲线
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
