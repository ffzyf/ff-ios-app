import ActivityKit
import SwiftUI
import WidgetKit

/// 天光实时活动的锁屏 / 灵动岛界面（设计文档 §1.4）。
///
/// 与 `SunEventLiveActivity` 的关系：两个**互不相干**的实时活动，各画一套，
/// 连配色都不是一家 —— 红石用 `TrackGradient`（"事件状态"的语义色），天光用 `Theme.sky(_:)`
/// （**固定物理天色**，不随系统深浅变）。后者正好适配灵动岛永远黑底这件事：
/// 浅色模式下 `Theme.textPrimary` 是近黑，压在黑底上等于没有。
///
/// 这个文件只管画。什么时候出现、什么时候消失全在 App 侧的 `DaylightActivityCoordinator`
/// （Widget target 不编译 `Sources/Services`）。
///
/// 三条不能破的规则：
/// 1. `Text(timerInterval:)` / `ProgressView(timerInterval:)` 拿到**非法区间**（上界 < 下界）
///    会**运行期崩**，而活动内容会在另一个进程里被解码、被系统自己重绘 —— 构造前一律判 `>`，
///    不成立就改画静态文案 / 静态条，绝不把非法 Range 交给系统；
/// 2. 一个 Shape 都不新建：地平线复用 `HorizonGround` / `HorizonEdge`，太阳位置复用
///    `SunClock.sunMark(at:on:)`，纵比例常量引用 `SunClock.SunTrack.crestY`
///    （**不写 0.62 字面量**，它与桌面「天光」组件、App 内天际线是同一条不变量）；
/// 3. 颜色全部走 `Theme.sky(phase)` 的六个 token；`weatherCode` 翻译成 `WeatherKind` 失败
///    （未知 WMO 码 / nil）就**不画天气元素** —— 缺数据不猜、不兜底成晴天。
struct DaylightLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DaylightActivityAttributes.self) { context in
            DaylightLockScreenView(state: context.state, attributes: context.attributes)
                // 锁屏卡的底色跟着天色走（与红石那套 TrackGradient 是两套配方，不复用）
                .activityBackgroundTint(Theme.sky(SunClock.phase(at: Date())).top)
                .activitySystemActionForegroundColor(Theme.sky(SunClock.phase(at: Date())).ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DaylightIslandLeading(state: context.state)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    DaylightIslandTrailing(state: context.state)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    DaylightIslandBottom(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: DaylightMetric.compactIconSize, weight: .semibold))
                    // 固定亮色，不读随深浅变化的 textPrimary：灵动岛永远是黑底
                    .foregroundStyle(Theme.sky(SunClock.phase(at: Date())).edge)
            } compactTrailing: {
                DaylightCompactCountdown(state: context.state)
            } minimal: {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: DaylightMetric.compactIconSize, weight: .semibold))
                    .foregroundStyle(Theme.sky(SunClock.phase(at: Date())).edge)
            }
        }
    }
}

// MARK: - 尺寸与几何

/// 天光这套界面的全部数字。
///
/// 单独一个 namespace 是为了让"改一个字号"有唯一入口：这是两个活动里唯一一套可以与
/// 桌面「天光」组件对表的数字，散在视图里就会各自漂。
private enum DaylightMetric {

    /// 地平线弧顶（占高度比例）。**引用 `SunClock.SunTrack.crestY`**：这条比例与桌面组件、
    /// App 内天际线共用同一份，写 0.62 就是许愿它们永远同步
    static let crestY: CGFloat = SunClock.SunTrack.crestY
    /// 地平线两端（占高度比例）。与 `WidgetTheme.skyEdgeY` 同源
    static let edgeY: CGFloat = WidgetTheme.skyEdgeY

    /// 地平线亮边线宽
    static let edgeWidth: CGFloat = 1
    /// 太阳点直径（pt）：这是"看得见但不抢戏"的尺寸，与「天光」小组件的 9pt 相比，
    /// 实时活动里它是背景的一部分，不是主角
    static let sunDiameter: CGFloat = 4

    /// 灵动岛展开区的天际线高度
    static let islandSkylineHeight: CGFloat = 28
    /// 灵动岛展开区的进度条高度
    static let islandProgressHeight: CGFloat = 3
    /// 锁屏卡的进度条高度（比岛里更细：卡片面积大，粗了会抢地平线的戏）
    static let lockProgressHeight: CGFloat = 2
    /// 锁屏卡内容的内边距
    static let lockPadding: CGFloat = 16
    /// 锁屏卡「倒计时 → 进度条」之间的间距
    static let lockFooterGap: CGFloat = 6

    /// 灵动岛紧凑态图标
    static let compactIconSize: CGFloat = 12
    /// 灵动岛紧凑态倒计时
    static let countdownSize: CGFloat = 12
    /// 锁屏卡底部的距日落倒计时
    static let lockCountdownSize: CGFloat = 17
    /// 左上日期
    static let dayTextSize: CGFloat = 13
    /// 天气行（符号与文案）
    static let weatherTextSize: CGFloat = 11
    /// 展开区左侧：天气符号 + 时段名
    static let islandLabelSize: CGFloat = 13
    /// 展开区右侧：气温
    static let islandTempSize: CGFloat = 15
    /// 展开区右侧：天气文案
    static let islandDetailSize: CGFloat = 11
    /// 展开区底部：倒计时
    static let islandNoteSize: CGFloat = 12
}

// MARK: - 天气符号

/// 天气类型 → SF Symbol 名字（只用系统已经存在的那几个）。
///
/// 入参是**非可选**的 `WeatherKind`：**"天气未知"这件事由调用方表达（整格不画）**，
/// 而不是由这里返回一个"不知道该画什么"的默认值 —— 一旦这里给默认值，
/// 上游缺数据时卡片就会画出一个不存在的天气（这个工程在缺数据兜底上已经踩过一次）。
enum DaylightSymbol {

    static func of(_ kind: WeatherKind) -> String {
        switch kind {
        case .clear:
            return "sun.max.fill"
        case .partly:
            return "cloud.sun.fill"
        case .overcast:
            return "cloud.fill"
        case .fog:
            return "cloud.fog.fill"
        case .drizzle:
            return "cloud.drizzle.fill"
        case .rain:
            return "cloud.rain.fill"
        case .snow:
            return "cloud.snow.fill"
        case .thunder:
            return "cloud.bolt.fill"
        }
    }
}

// MARK: - 天际线（锁屏卡与灵动岛共用）

/// 天际线本体：渐变天幕 + 地面 + 亮边 + 太阳。
///
/// 锁屏卡（铺满整张卡）与灵动岛展开区（固定 28pt）**共用这一个视图**，
/// 目的不是省代码而是保证同源：两处的地平线必须落在同一高度上。
/// 它不接 `ContentState` —— 天际线画的永远是"此刻"（几何全由 `Date()` + `SunClock` 现算），
/// 与这次 update 送进来的数据无关。
///
/// 画布尺寸用 `GeometryReader` 读，`sunMark` 返回的是归一化坐标 ——
/// 这是全工程画太阳的唯一方式（`SkyLightFace` 同款），不在任何地方手写 x/y 的比例算式。
private struct DaylightSkyline: View {

    /// 太阳点直径（pt）
    let sunDiameter: CGFloat
    /// 高度。`nil` = 撑满父容器（锁屏卡）；给值则按值定高（灵动岛展开区）
    let height: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let sky = Theme.sky(SunClock.phase(at: Date()))
            ZStack {
                // ① 天幕：顶 → 地平线一整段渐变，在 `crestY`（= `SunTrack.crestY`）处
                //    硬切到地面色，
                //    这样地平线上下是"天 / 地"两块，而不是一条糊渐变
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: sky.top, location: 0),
                        .init(color: sky.horizon, location: DaylightMetric.crestY),
                        .init(color: sky.ground, location: DaylightMetric.crestY)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                // ② 地面：弧线以下压深 —— 日出日落两个时刻太阳自动退到次要层级
                HorizonGround(crestY: DaylightMetric.crestY, edgeY: DaylightMetric.edgeY)
                    .fill(sky.ground)

                // ③ 地平线亮边：整张卡最硬的一根线
                HorizonEdge(crestY: DaylightMetric.crestY, edgeY: DaylightMetric.edgeY)
                    .stroke(sky.edge, lineWidth: DaylightMetric.edgeWidth)

                // ④ 太阳：只有"在地平线以上"才画本体（夜里连余晖都不画）
                sunLayer(sky: sky, size: size)
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(height: height)
    }

    /// 太阳点。位置按 `Date()` **现算**（§1.4）：系统在"锁屏点亮 / 岛展开 / 收到 update"
    /// 时才重绘，现算得到的永远是那一刻的真实位置 —— 比"上次 App 写进来的位置"更准，
    /// 而且 App 被杀之后也不会永远冻在当初那一格。
    @ViewBuilder
    private func sunLayer(sky: Theme.SkyColors, size: CGSize) -> some View {
        let now = Date()
        if let mark = SunClock.sunMark(at: now, on: now, crestY: DaylightMetric.crestY),
           mark.isUp {
            Circle()
                .fill(sky.edge)
                .frame(width: sunDiameter, height: sunDiameter)
                .position(x: mark.point.x * size.width, y: mark.point.y * size.height)
        }
    }
}

// MARK: - 锁屏视图

/// 锁屏天光卡：天际线铺满整卡，文字浮在上面。
///
/// 布局刻意只有左上（日期 + 天气）与右下（倒计时 + 进度条）两坨：
/// 中间整片留给天空 —— 这张卡要传达的是"此刻天怎么样"，信息块多了就把主角挤没了。
struct DaylightLockScreenView: View {

    let state: DaylightActivityAttributes.ContentState
    let attributes: DaylightActivityAttributes

    var body: some View {
        let sky = Theme.sky(SunClock.phase(at: Date()))
        ZStack(alignment: .topLeading) {
            DaylightSkyline(sunDiameter: DaylightMetric.sunDiameter,
                            height: nil)
            VStack(alignment: .leading, spacing: 0) {
                topRow(sky: sky)
                Spacer(minLength: 8)
                bottomRow(sky: sky)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, DaylightMetric.lockPadding)
            .padding(.vertical, DaylightMetric.lockPadding)
        }
    }

    // MARK: 左上：日期 + 天气

    @ViewBuilder
    private func topRow(sky: Theme.SkyColors) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // dayText 在 attributes 里（创建后不变），不参与 update 的 diff
            Text(attributes.dayText)
                .font(.system(size: DaylightMetric.dayTextSize, weight: .semibold))
                .foregroundStyle(sky.ink)
                .lineLimit(1)

            // weatherCode 解不出就不画这一整行的**任何一部分**：
            // 没有云的"多云"比什么都没有更糟
            if let kind = WeatherKind.from(code: state.weatherCode) {
                HStack(spacing: 4) {
                    Image(systemName: DaylightSymbol.of(kind))
                        .font(.system(size: DaylightMetric.weatherTextSize, weight: .medium))
                        .foregroundStyle(sky.edge)
                    if let text = state.weatherText {
                        Text(text)
                            .font(.system(size: DaylightMetric.weatherTextSize, weight: .medium))
                            .foregroundStyle(sky.inkDim)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: 右下：倒计时 + 进度条

    @ViewBuilder
    private func bottomRow(sky: Theme.SkyColors) -> some View {
        VStack(alignment: .trailing, spacing: DaylightMetric.lockFooterGap) {
            Text(SkyPhase.countdownText(to: state.sunset, now: Date()))
                .font(.system(size: DaylightMetric.lockCountdownSize, weight: .bold, design: .monospaced))
                .foregroundStyle(sky.ink)
                .monospacedDigit()
                .lineLimit(1)
            DaylightProgress(state: state, sky: sky, height: DaylightMetric.lockProgressHeight)
        }
    }
}

// MARK: - 灵动岛 · 展开区

/// 展开区左侧：天气符号 + 当前时段名（"距离日落" / "黄金时刻" …）。
///
/// 时段名用现成的 `SkyPhase.label` 七档文案，不自造 —— 那七个词已经和 App 内天光卡、
/// 桌面「天光」组件对齐过，"同一个时段两个名字"是最难查的一类文案 bug。
private struct DaylightIslandLeading: View {

    let state: DaylightActivityAttributes.ContentState

    var body: some View {
        let sky = Theme.sky(SunClock.phase(at: Date()))
        HStack(spacing: 4) {
            if let kind = WeatherKind.from(code: state.weatherCode) {
                Image(systemName: DaylightSymbol.of(kind))
                    .font(.system(size: DaylightMetric.islandLabelSize, weight: .semibold))
                    .foregroundStyle(sky.edge)
            }
            Text(SunClock.phase(at: Date()).label)
                .font(.system(size: DaylightMetric.islandLabelSize, weight: .semibold))
                .foregroundStyle(sky.ink)
                .lineLimit(1)
        }
    }
}

/// 展开区右侧：气温 + 天气文案。两者各自 nil 就各自不画（不写"未知"占位）。
private struct DaylightIslandTrailing: View {

    let state: DaylightActivityAttributes.ContentState

    var body: some View {
        let sky = Theme.sky(SunClock.phase(at: Date()))
        VStack(alignment: .trailing, spacing: 1) {
            if let tempC = state.tempC {
                Text(DaylightText.temperature(tempC))
                    .font(.system(size: DaylightMetric.islandTempSize, weight: .semibold))
                    .foregroundStyle(sky.ink)
                    .monospacedDigit()
            }
            if let text = state.weatherText {
                Text(text)
                    .font(.system(size: DaylightMetric.islandDetailSize, weight: .medium))
                    .foregroundStyle(sky.inkDim)
                    .lineLimit(1)
            }
        }
    }
}

/// 展开区底部：28pt 天际线 + 进度条 + 倒计时。
///
/// 这一段之所以要画（而不是把字直接堆出来）：灵动岛展开态是用户"真的想看一眼"的状态，
/// 它该给出信息密度最低、认知成本最低的那个答案 —— 一条地平线和一个进度比三行字更快。
private struct DaylightIslandBottom: View {

    let state: DaylightActivityAttributes.ContentState

    var body: some View {
        let sky = Theme.sky(SunClock.phase(at: Date()))
        VStack(alignment: .leading, spacing: 6) {
            DaylightSkyline(sunDiameter: DaylightMetric.sunDiameter,
                            height: DaylightMetric.islandSkylineHeight)
            DaylightProgress(state: state, sky: sky, height: DaylightMetric.islandProgressHeight)
            Text(SkyPhase.countdownText(to: state.sunset, now: Date()))
                .font(.system(size: DaylightMetric.islandNoteSize, weight: .medium))
                .foregroundStyle(sky.inkDim)
                .lineLimit(1)
        }
    }
}

// MARK: - 紧凑态倒计时

/// 灵动岛紧凑态右侧的倒计时。
///
/// **构造前必须判 `sunset > now`**：`now...sunset` 在 `sunset < now` 时是一个非法闭区间，
/// `Text(timerInterval:)` 拿到它会直接崩 —— 而这张卡是可以在 App 早已关闭、系统独自
/// 重绘时走到那一刻的（日落之后 schema 还在）。所以这里退化成静态文案"已日落"。
private struct DaylightCompactCountdown: View {

    let state: DaylightActivityAttributes.ContentState

    var body: some View {
        let now = Date()
        let sky = Theme.sky(SunClock.phase(at: now))
        if state.sunset > now {
            Text(timerInterval: now...state.sunset, countsDown: true)
                .font(.system(size: DaylightMetric.countdownSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(sky.ink)
                .monospacedDigit()
        } else {
            Text("已日落")
                .font(.system(size: DaylightMetric.countdownSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(sky.ink)
                .monospacedDigit()
        }
    }
}

// MARK: - 进度条

/// 「日出 → 日落」全程的极细进度条。
///
/// 用 `ProgressView(timerInterval:countsDown:)` 交给系统推进：App 退后台之后它照样在走，
/// 这正是"卡片看着是活的"却零推送成本的来源（与 `SunEventProgress` 同一条技术选择）。
///
/// 同样要先判区间合法：`sunrise >= sunset`（脏数据 / 极夜）时改画一条静态轨道。
private struct DaylightProgress: View {

    let state: DaylightActivityAttributes.ContentState
    let sky: Theme.SkyColors
    let height: CGFloat

    var body: some View {
        Group {
            if state.sunset > state.sunrise {
                ProgressView(timerInterval: state.sunrise...state.sunset, countsDown: false) {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(sky.edge)
                .frame(height: height)
            } else {
                Capsule()
                    .fill(sky.ground)
                    .frame(height: height)
            }
        }
    }
}

// MARK: - 文案

/// 实时活动里的数字怎么写成字。
///
/// 气温刻意取整到个位：这一格只有 15pt 宽的地方，`18.4°` 会为了一个没人读的小数位
/// 把行撑宽 —— 而灵动岛的宽度是系统定死的，多一位数字就可能把左边的时段名挤截。
/// 体感本身也不关心那 0.4 度。
enum DaylightText {

    /// `18.4` → `"18°"`
    static func temperature(_ celsius: Double) -> String {
        return "\(Int(celsius.rounded()))°"
    }
}
