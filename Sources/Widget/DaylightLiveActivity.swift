import ActivityKit
import SwiftUI
import WidgetKit

/// 天光实时活动的锁屏 / 灵动岛界面（设计文档 §1.4；3.8.1 照「光效小组件」参考图重做）。
///
/// 与 `SunEventLiveActivity` 的关系：两个**互不相干**的实时活动，各画一套，
/// 连配色都不是一家 —— 红石用 `TrackGradient`（"事件状态"的语义色），天光用 `Theme.sky(_:)`
/// （**固定物理天色**，不随系统深浅变）。后者正好适配灵动岛永远黑底这件事：
/// 浅色模式下 `Theme.textPrimary` 是近黑，压在黑底上等于没有。
///
/// 这个文件只管画。什么时候出现、什么时候消失全在 App 侧的 `DaylightActivityCoordinator`
/// （Widget target 不编译 `Sources/Services`）。
///
/// ## 3.8.1 版式重做的来历
///
/// 旧版是"自绘天际线 + 进度条 + 日期/天气"，用户截图显示锁屏卡接近纯黑、观感差。
/// 参考图（六张，六档天色）给的是一套**极简版式**，逐像素照搬：
///
/// ```
/// ● 蓝调剩余                    2分钟4秒   ← 左上：阶段色圆点 + 阶段名 / 右上：倒计时
///      （整片天空：渐变天幕 + 地平线弧 + 弧上太阳辉光点）
/// 06:05                            18:13   ← 左下日出 / 右下日落
/// ```
///
/// 日期与天气在参考图里**没有**，本次一并去掉（信息块多了就把天空的主角地位挤没了）。
/// 天空背景层直接复用 `SkyLightFace.swift` 的 `SkyLightSky`（internal，同 target 可用）——
/// 桌面「天光」组件、锁屏卡、灵动岛展开区从此是**同一份天空**，不会各画各的。
///
/// 两条不能破的规则：
/// 1. `Text(timerInterval:)` 拿到**非法区间**（上界 < 下界）会**运行期崩**，而活动内容会在
///    另一个进程里被解码、被系统自己重绘 —— 构造前一律判 `>`，不成立就改画静态文案；
/// 2. 颜色全部走 `Theme.sky(phase)` 的六个 token；本文件没有一个颜色字面量。
struct DaylightLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DaylightActivityAttributes.self) { context in
            DaylightLockScreenView(state: context.state)
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
/// 单独一个 namespace 是为了让"改一个字号"有唯一入口：这是实时活动与桌面「天光」组件
/// 对表的数字，散在视图里就会各自漂。
private enum DaylightMetric {

    /// 锁屏卡内容的内边距
    static let lockPadding: CGFloat = 16
    /// 锁屏卡左上阶段名 / 右上倒计时的字号。
    /// 参考图的字级在锁屏卡上读作"标题"：15pt semibold 压在天空上，比旧版 13pt 的日期行
    /// 更醒目，也和底部 15pt 的时刻形成同一档的两个层级（颜色分主次：ink / inkDim）
    static let lockHeaderSize: CGFloat = 15
    /// 锁屏卡底部日出 / 日落时刻的字号（与阶段名同档，靠位置与颜色分主次）
    static let lockSunTimeSize: CGFloat = 15
    /// 锁屏卡阶段色圆点直径。比桌面组件的 5pt 大一号：锁屏卡面积大得多，
    /// 5pt 在那里是"看得见但不抢戏"，在这里只是"看不见"
    static let lockDotDiameter: CGFloat = 6

    /// 灵动岛展开区：阶段名 / 倒计时字号（展开区高度有限，比锁屏卡收一档）
    static let islandHeaderSize: CGFloat = 13
    /// 灵动岛展开区：日出 / 日落字号（时刻是次要信息，再收一档）
    static let islandSunTimeSize: CGFloat = 12
    /// 灵动岛展开区：紧凑天空高度。约展开区内容高度的一半 —— 天空是这张卡的主角，
    /// 太矮读不出"渐变天幕 + 地平线弧"，再高字就悬在半空
    static let islandSkyHeight: CGFloat = 40
    /// 灵动岛展开区：阶段色圆点直径（与桌面组件的 5pt 同档）
    static let islandDotDiameter: CGFloat = 5

    /// 灵动岛紧凑态图标
    static let compactIconSize: CGFloat = 12
    /// 灵动岛紧凑态倒计时
    static let countdownSize: CGFloat = 12
}

// MARK: - 共享的「这一刻的天光帧」

/// 由 `ContentState` 造一帧 `SkyLightEntry`（锁屏卡与灵动岛展开区共用的天空数据源）。
///
/// 天空背景层 `SkyLightSky` 吃的是 `SkyLightEntry`，而实时活动没有 Timeline、
/// 没有预渲染帧 —— 所以每次 body 求值时**现造一帧**，`date` 就是此刻。
/// 这与"太阳位置用 `Date()` 现算"是同一条哲学：活动内容会在另一个进程里被解码重绘，
/// 现算永远比烘焙准，App 被杀之后也不会冻在当初那一帧。
///
/// `weather` 恒为 nil：参考图版式里没有天气，天空也不叠天气层
/// （缺数据不猜，这里干脆不需要 —— 天气在旧版里就只是个挤在角落的小字）。
private func daylightSkyEntry(state: DaylightActivityAttributes.ContentState,
                              now: Date) -> SkyLightEntry {
    // 3.22.0：时段过天气门控（与 App / 小组件同一个 `SkyViewing`）。
    //
    // 这里只有天气**代码**（`ContentState` 没带云量），但 `WeatherKind` 本身已经
    // 蕴含了量级：`overcast` 就是厚云、`partly` 就是半片天、`rain` 就是雨幕。
    // 够判「这一刻天边有没有金色」了 —— 判不够精确的代价只是偶尔多说一句，
    // 而不判的代价是锁屏卡片上写着"黄金时刻"、人站在阴天里。
    let phase = SunClock.phase(at: now).effective(
        viewing: SkyViewing.verdict(kind: WeatherKind.from(code: state.weatherCode),
                                    cloud: nil,
                                    visibilityMeters: nil)
    )
    return SkyLightEntry(
        date: now,
        phase: phase,
        deadline: SkyLightEntry.deadline(for: now, phase: phase),
        // 日出日落用 state 里 App 写进来的值（`SunClock.times(on:)` 现算的同一套算法、
        // 同一个 ±3 分钟），但 state 里的值在 `ProgressView(timerInterval:)` 时代就是
        // 稳定锚点 —— 沿用它，卡上数字与历史行为完全一致
        sunrise: state.sunrise,
        sunset: state.sunset,
        weather: nil,
        // 锁屏实时活动不拉能见度：它由 Focus/通知触发，不该再多一次网络请求
        visibilityMeters: nil
    )
}

// MARK: - 倒计时（锁屏卡与展开区共用）

/// 「距下一阶段起点」的倒计时，参考图右上角那格。
///
/// 两种画法，按"还剩多久"分派（与 `SkyLightFace.countdown` 同一套规则）：
/// - **< 1 小时**：`Text(timerInterval:countsDown:showsHours:)` —— 系统自己走秒，零推送成本。
///   **构造前必须判 `deadline > now`**：活动内容会在另一个进程被解码重绘，
///   把非法区间交给它就是运行期崩溃；
/// - **≥ 1 小时**：静态文案（`12小时32分钟`，`SkyPhase.countdownText` 的既有规则）。
private struct DaylightPhaseCountdown: View {

    let entry: SkyLightEntry
    /// 字号（锁屏卡 15 / 展开区 13）
    let size: CGFloat
    let color: Color

    var body: some View {
        let now = entry.date
        Group {
            if let deadline = entry.deadline, deadline > now {
                if entry.needsSecondTicker {
                    Text(timerInterval: now...deadline, countsDown: true, showsHours: false)
                        .font(.system(size: size, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(entry.countdownText ?? "")
                        .font(.system(size: size, weight: .semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            // deadline == nil / 已过点：整格不画（宁可空着，不画一个假数字）
        }
    }
}

// MARK: - 锁屏视图

/// 锁屏天光卡：整片天空铺满，文字浮在上下两角。
///
/// 布局刻意只有左上（圆点 + 阶段名 / 倒计时）与左下 / 右下（日出 / 日落）三坨：
/// 中间整片留给天空 —— 这张卡要传达的是"此刻天怎么样"。
/// 日期与天气在参考图里没有，3.8.1 起不再画。
struct DaylightLockScreenView: View {

    let state: DaylightActivityAttributes.ContentState

    var body: some View {
        let now = Date()
        let entry = daylightSkyEntry(state: state, now: now)
        let sky = Theme.sky(entry.phase)
        ZStack(alignment: .topLeading) {
            // 整片天空：渐变天幕 + 地平线弧 + 太阳辉光点（与桌面「天光」组件同一份实现）
            SkyLightSky(entry: entry)

            VStack(alignment: .leading, spacing: 0) {
                header(entry: entry, sky: sky)
                Spacer(minLength: 8)
                footer(sky: sky)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, DaylightMetric.lockPadding)
            .padding(.vertical, DaylightMetric.lockPadding)
        }
    }

    // MARK: 左上：阶段色圆点 + 阶段名 / 右上：倒计时

    private func header(entry: SkyLightEntry, sky: Theme.SkyColors) -> some View {
        HStack(spacing: 6) {
            // 阶段色圆点：取这一档天空里最亮的那支 `edge`（正午近白、晨昏暖白、夜里冷蓝）
            Circle()
                .fill(sky.edge)
                .frame(width: DaylightMetric.lockDotDiameter,
                       height: DaylightMetric.lockDotDiameter)

            Text(entry.phase.label)
                .font(.system(size: DaylightMetric.lockHeaderSize, weight: .semibold))
                .foregroundStyle(sky.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            DaylightPhaseCountdown(entry: entry,
                                   size: DaylightMetric.lockHeaderSize,
                                   color: sky.inkDim)
        }
    }

    // MARK: 左下 / 右下：日出 / 日落

    /// 颜色职责与 `SkyLightFace.footer` 完全一致：日出取 `sky.edge`
    /// （每档最亮、偏暖的那支），日落取 `sky.inkDim`（压暗退后，读作"要收起来的光"）。
    private func footer(sky: Theme.SkyColors) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(Formatters.timeHHmm(state.sunrise))
                .font(.system(size: DaylightMetric.lockSunTimeSize,
                              weight: .medium,
                              design: .monospaced))
                .foregroundStyle(sky.edge)
                .monospacedDigit()
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(Formatters.timeHHmm(state.sunset))
                .font(.system(size: DaylightMetric.lockSunTimeSize,
                              weight: .medium,
                              design: .monospaced))
                .foregroundStyle(sky.inkDim)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

// MARK: - 灵动岛 · 展开区

/// 展开区左侧：阶段色圆点 + 当前时段名。
///
/// 时段名用现成的 `SkyPhase.label` 七档文案，不自造 —— 那七个词已经和 App 内天光卡、
/// 桌面「天光」组件、锁屏卡对齐过，"同一个时段两个名字"是最难查的一类文案 bug。
private struct DaylightIslandLeading: View {

    let state: DaylightActivityAttributes.ContentState

    var body: some View {
        let now = Date()
        let entry = daylightSkyEntry(state: state, now: now)
        let sky = Theme.sky(entry.phase)
        HStack(spacing: 5) {
            Circle()
                .fill(sky.edge)
                .frame(width: DaylightMetric.islandDotDiameter,
                       height: DaylightMetric.islandDotDiameter)

            Text(entry.phase.label)
                .font(.system(size: DaylightMetric.islandHeaderSize, weight: .semibold))
                .foregroundStyle(sky.ink)
                .lineLimit(1)
        }
    }
}

/// 展开区右侧：距下一阶段起点的倒计时（与锁屏卡同一格、同一套合法性守卫）。
private struct DaylightIslandTrailing: View {

    let state: DaylightActivityAttributes.ContentState

    var body: some View {
        let now = Date()
        let entry = daylightSkyEntry(state: state, now: now)
        return DaylightPhaseCountdown(entry: entry,
                                      size: DaylightMetric.islandHeaderSize,
                                      color: Theme.sky(entry.phase).inkDim)
    }
}

/// 展开区底部：40pt 紧凑天空 + 日出 / 日落。
///
/// 这一版之所以还画天空（旧版是"天际线 + 进度条 + 小字"）：灵动岛展开态是用户
/// "真的想看一眼"的状态，参考图的答案是一片干净的天 —— 一个渐变、一条弧、一个光点，
/// 比进度条加三行字的认知成本低得多。
private struct DaylightIslandBottom: View {

    let state: DaylightActivityAttributes.ContentState

    var body: some View {
        let now = Date()
        let entry = daylightSkyEntry(state: state, now: now)
        let sky = Theme.sky(entry.phase)
        VStack(alignment: .leading, spacing: 6) {
            SkyLightSky(entry: entry)
                .frame(height: DaylightMetric.islandSkyHeight)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(Formatters.timeHHmm(entry.sunrise ?? state.sunrise))
                    .font(.system(size: DaylightMetric.islandSunTimeSize,
                                  weight: .medium,
                                  design: .monospaced))
                    .foregroundStyle(sky.edge)
                    .monospacedDigit()
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(Formatters.timeHHmm(entry.sunset ?? state.sunset))
                    .font(.system(size: DaylightMetric.islandSunTimeSize,
                                  weight: .medium,
                                  design: .monospaced))
                    .foregroundStyle(sky.inkDim)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 紧凑态倒计时

/// 灵动岛紧凑态右侧的倒计时（数到日落 —— 紧凑态空间只够放一个最重要的数）。
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
