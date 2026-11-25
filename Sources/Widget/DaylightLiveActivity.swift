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
        // 底色 / 前景色也要过天气门控（3.23.0 补漏）。
        //
        // 3.22.0 只给**卡面**接了门控，底色这一行还是裸 `SunClock.phase(at: Date())`：
        // overcast + golden 的早晨，卡面文字已经按「白天」写了，锁屏底色仍然是金橙 ——
        // 同一张卡上出现两个天色，比单点误差更显眼。判定与卡面共用
        // `daylightSky(...)`（一条派生、两处消费），不各算一遍。
        //
        // 这段注释原来写在 content 闭包里，旁边就是 `let sky = ...` + `return` ——
        // 而 `ActivityConfiguration(for:content:dynamicIsland:)` 的**两个闭包都是
        // `@ViewBuilder`**：局部 `let` 是允许的（同 target 的 `SunEventLiveActivity` 就靠这个），
        // 但**显式 `return` 是硬错** —— 报错原文 `cannot use explicit 'return' statement in
        // the body of result builder 'ViewBuilder'`，而 `Content` 泛型参数也因此推不出来
        // （`generic parameter 'Content' could not be inferred`）。3.23.0 就是同时踩了这两条。
        // 现在"算天色 + 上底色"收进 `DaylightLockScreenTinted`，两个闭包体里只剩视图表达式。
        ActivityConfiguration(for: DaylightActivityAttributes.self) { context in
            DaylightLockScreenTinted(state: context.state)
        } dynamicIsland: { context in
            // HIG「Live Activities」横屏受限宽度规范：compact / minimal 要能塞进 28pt 圆圈。
            // Apple 给两条路：① 读 `isDynamicIslandLimitedInWidth` 分流；② 用短缩写或图形
            // 表达代替完整字符串。这里选 ②：
            // · 该环境值在 Apple 文档标注 **iOS 27.0+（preliminary）**，本项目 iOS 26 SDK
            //   里根本不存在这个符号 —— `#available` 只解决运行期、救不了编译期符号缺失，
            //   硬写就是一轮 20 分钟白等编译失败。故不引入。
            // · 改用"天然就短"的设计：leading 是单个太阳符号（图形表达），trailing 是走秒数字
            //   或 `12h32m` 短文案（见 `DaylightCompactCountdown.compactText` + 缩放）。
            //   两者在任何宽度下都不截断，受限宽度下系统无需再裁剪。
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
                // 图形表达：单个太阳地平线符号，本就 fit 28pt，无需按宽度换图。
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: DaylightMetric.compactIconSize, weight: .semibold))
                    // 固定亮色，不读随深浅变化的 textPrimary：灵动岛永远是黑底
                    // 3.23.0：这一支也要过天气门控，与卡面、底色读同一个 `daylightSky`。
                    // 只需一个 `edge`，就地调纯函数 —— 闭包体保持单表达式，不引入 `return`
                    .foregroundStyle(daylightSky(context.state, now: Date()).edge)
            } compactTrailing: {
                // 短缩写：与展开区同一个 `entry.deadline` 语义，长文案压成 `12h32m`。
                DaylightCompactCountdown(state: context.state)
            } minimal: {
                // HIG 建议 minimal 显示更新信息而非纯 logo；但 minimal 是 28pt 极限形态，
                // 唯一要保证的是"一眼认出是哪个 App"。这里的太阳符号 + `daylightSky().edge`
                // 动态色（6 档天色各自变化）已经是"随状态更新的信息"，再加 1–2 字符数字
                // 会与图标争抢 28pt 内的空间、反而牺牲识别度。故保留图标 + 动态色，不塞数字。
                Image(systemName: "sun.max.fill")
                    .font(.system(size: DaylightMetric.compactIconSize, weight: .semibold))
                    .foregroundStyle(daylightSky(context.state, now: Date()).edge)
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

    /// 灵动岛展开区：阶段名 / 倒计时字号。
    /// HIG「Live Activities」要求关键信息大而醒目（medium 字重以上、能在瞥一眼间读清），
    /// 13pt 在小尺寸下偏弱；提到 15pt 与锁屏卡 `lockHeaderSize` 同档，两处层级统一。
    static let islandHeaderSize: CGFloat = 15
    /// 灵动岛展开区：日出 / 日落字号。同理从 12 提到 14（比阶段名收一档，仍清晰可辨）。
    static let islandSunTimeSize: CGFloat = 14
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

/// 这一刻的天气判定（锁屏卡 / 灵动岛 / 底色**共用一份**）。
///
/// 3.22.0：时段过天气门控（与 App / 小组件同一个 `SkyViewing`）。
///
/// 这里只有天气**代码**（`ContentState` 没带云量），但 `WeatherKind` 本身已经
/// 蕴含了量级：`overcast` 就是厚云、`partly` 就是半片天、`rain` 就是雨幕。
/// 够判「这一刻天边有没有金色」了 —— 判不够精确的代价只是偶尔多说一句，
/// 而不判的代价是锁屏卡片上写着"黄金时刻"、人站在阴天里。
///
/// 抽成函数是为了让"同一个观测只解释一次"：卡面（换词）与底色（配色）若各算一遍，
/// 一处改了阈值，另一处就悄无声息地漂了 —— 那正是这次回归的成因。
private func daylightVerdict(_ state: DaylightActivityAttributes.ContentState) -> SkyViewing.Verdict? {
    return SkyViewing.verdict(kind: WeatherKind.from(code: state.weatherCode),
                              cloud: nil,
                              visibilityMeters: nil)
}

/// 这一刻的天色档位（**已过天气门控**）。底色 / 图标用它，卡面造 entry 也用它。
private func daylightPhase(_ state: DaylightActivityAttributes.ContentState,
                           now: Date) -> SkyPhase {
    return SunClock.phase(at: now).effective(viewing: daylightVerdict(state))
}

/// 这一刻的六 token 天色。给"只想要一档天色"的地方（底色 / 图标）用 ——
/// `Theme.sky(_:)` 的入参必须是过完 `SkyViewing.effective` 的 phase，
/// 裸 `SunClock.phase(at:)` 会在阴天的黄金时刻画出金橙底色。
private func daylightSky(_ state: DaylightActivityAttributes.ContentState,
                         now: Date) -> Theme.SkyColors {
    return Theme.sky(daylightPhase(state, now: now))
}

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
    // 判定存进 entry（而不是只用来降级）：渲染层要说的话是
    // `entry.phase.label(viewing: entry.viewing)`，两个真值来源合一。
    let viewing = daylightVerdict(state)
    let phase = SunClock.phase(at: now).effective(viewing: viewing)
    return SkyLightEntry(
        date: now,
        phase: phase,
        viewing: viewing,
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
    /// 字号（锁屏卡 15 / 展开区 15 / 紧凑态 12）
    let size: CGFloat
    let color: Color
    /// 极简文案：灵动岛受限宽度（横屏 / 28pt 圆圈）下把「12小时32分钟」压成「12h32m」。
    /// 只影响 ≥1 小时的静态文案；<1 小时的 `timerInterval` 走秒文案本来就短，不受影响。
    /// 默认 false —— 锁屏卡 / 展开区显示原中文文案，逐字不变。
    var compactText: Bool = false

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
                    // 合法性守卫（deadline > now）已在上方判过，这里只换文案形态。
                    // 短文案由 SkyPhase.countdownText 的结果就地压缩，不改算法本体：
                    // 锁屏卡读同一份 countdownText，算法一动两处都漂。
                    Text(compactText ? Self.abbreviate(entry.countdownText ?? "")
                                     : (entry.countdownText ?? ""))
                        .font(.system(size: size, weight: .semibold, design: compactText ? .monospaced : .default))
                        .foregroundStyle(color)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(compactText ? 0.6 : 0.7)
                }
            }
            // deadline == nil / 已过点：整格不画（宁可空着，不画一个假数字）
        }
    }

    /// 把 `12小时32分钟` / `49分钟30秒` 压成 `12h32m` / `49m30s`，
    /// 给紧凑态 52×36pt 的窄槽用。纯字符串变换，不碰 `SkyPhase.countdownText` 算法。
    private static func abbreviate(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "小时", with: "h")
            .replacingOccurrences(of: "分钟", with: "m")
            .replacingOccurrences(of: "秒", with: "s")
    }
}

// MARK: - 锁屏视图

/// 锁屏卡 + 天色底色。
///
/// 为什么要有这一层：`ActivityConfiguration(for:content:dynamicIsland:)` 的 content 闭包
/// 是 `@ViewBuilder` —— 局部 `let` 允许，**显式 `return` 不允许**（3.23.0 写了
/// `return DaylightLockScreenView(...)`，连带 `Content` 泛型参数推不出来）。
/// 而底色这件事需要先算出一份 `sky`、再连点两个 modifier：把它收进一个 View，
/// 闭包体就退化成一个视图表达式，"算天色 + 上底色"也只有这一个入口。
///
/// `activityBackgroundTint` / `activitySystemActionForegroundColor` 只有在 `View` 上才成立，
/// 所以这一层的存在是结构性的，不是多余包装。
private struct DaylightLockScreenTinted: View {

    let state: DaylightActivityAttributes.ContentState

    var body: some View {
        let sky = daylightSky(state, now: Date())
        DaylightLockScreenView(state: state)
            // 锁屏卡的底色跟着天色走（与红石那套 TrackGradient 是两套配方，不复用）
            .activityBackgroundTint(sky.top)
            .activitySystemActionForegroundColor(sky.ink)
    }
}

/// 锁屏天光卡：整片天空铺满，文字浮在上下两角。
///
/// 布局刻意只有左上（圆点 + 阶段名 / 倒计时）与左下 / 右下（日出 / 日落）三坨：
/// 中间整片留给天空 —— 这张卡要传达的是"此刻天怎么样"。
/// 日期与天气在参考图里没有，3.8.1 起不再画。
/// 5.1.2 / R3 核对：本卡显示的是**日出 / 日落**（`state.sunrise` / `state.sunset`），
/// **不含红石场次时间**（没有 `Occurrence.startAt/endAt`）。按「没有数据就说没有，
/// 绝不编造时间」的纪律，这里不调用 `RedstoneTimeText.endOnly`；R5 调试面板对本组件
/// 的「结束时间」态登记为「不适用」并置灰，不硬塞一个时间。
///
/// 5.1.2 / R5：本 View 已是 `internal` 独立锁屏 Face，调试面板可直接构造
/// `DaylightActivityAttributes.ContentState` 预览，不需要复制实现。
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

            // 词与配色是两件事：`entry.phase` 决定配色，「蓝调剩余」这种承诺颜色的词
            // 还要再过一次门控 —— 阴天不降 phase（天色仍是蓝灰，色相对），只换词。
            // 传的是 entry 里存的**观测**（`entry.viewing`），不是预先算好的词：
            // 词永远由 `phase × viewing` 现场算出来，少一个真值来源就少一处漂移。
            Text(entry.phase.label(viewing: entry.viewing))
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
/// 时段名用现成的 `SkyPhase.label(viewing:)` 七档文案，不自造 —— 那七个词已经和 App 内天光卡、
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

            // 与锁屏卡同一句话、同一份判定（`entry.viewing`）—— 两处说法不一致
            // 是"同一时段两个名字"，最难查的那类文案 bug
            Text(entry.phase.label(viewing: entry.viewing))
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
        DaylightPhaseCountdown(entry: entry,
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

/// 灵动岛紧凑态右侧的倒计时 —— 与展开区、锁屏卡**同一个语义**：距下一阶段起点
/// （`entry.deadline`）。HIG 要求紧凑 / 展开的信息可预测地对应：过去紧凑态数「距日落」、
/// 展开态数「距下一阶段」，用户看到两个不同的数（8:55:02 vs 36:22），这是明确的合规缺陷。
///
/// 实现上直接复用 `DaylightPhaseCountdown`，不复制倒计时逻辑 —— 三处从此同一真值来源。
/// 合法性守卫也随组件一起复用：`deadline > now` 才构造 `Text(timerInterval:)`，
/// 非法时整格不画，绝不把非法区间交给它会崩的初始化器。
/// 紧凑态空间只有 52×36pt，故传 `compactText: true`：≥1 小时走 `12h32m` 短文案 + 更小的
/// `minimumScaleFactor`，<1 小时仍是走秒数字。`SkyPhase.countdownText` 算法本体未改。
private struct DaylightCompactCountdown: View {

    let state: DaylightActivityAttributes.ContentState

    var body: some View {
        let now = Date()
        let entry = daylightSkyEntry(state: state, now: now)
        // 紧凑态只取 `ink`（字色），但它同样是"天色"，一样要过门控 ——
        // 与卡面、底色读同一个 `daylightSky`，不各算一遍。
        let sky = daylightSky(state, now: now)
        DaylightPhaseCountdown(entry: entry,
                               size: DaylightMetric.countdownSize,
                               color: sky.ink,
                               compactText: true)
    }
}
