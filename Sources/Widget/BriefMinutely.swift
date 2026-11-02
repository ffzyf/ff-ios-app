import SwiftUI

// MARK: - 未来两小时降水（简报卡）
//
// 用户原话："我大部分的降水啥的都是从……小组件里面看到更全面一些……放进简报"。
// 于是中号 / 大号底部多一条 24 格的柱状图，小号只留一行结论。
//
// ## 为什么是"预排帧"而不是"定时拉"（这一节决定下面所有实现）
//
// 小组件**不能每 5 分钟联网**：WidgetKit 给每个组件的刷新预算是一天 40~70 次，
// 5 分钟一拉是 288 次，系统会直接忽略（不是排队，是丢掉）。能做到的是：
// **一次请求拿回未来两小时 24 格，把它们排成 5 分钟一帧的时间线，到点系统自己换帧**。
// 天光卡现在就是这么做的（一轮约 103 帧、全是预渲染、不发请求）。
//
// 所以本文件里：
// · 没有 `Timer`、没有 `TimelineView(.periodic)` —— 在 Widget 里它们不会按期望的频率跑；
// · 没有 `withAnimation` —— Widget 进程里没有动画时钟，写了也是死代码；
// · "图在往前推"完全靠**每一帧丢弃已经过去的格子**（`t < entry.date` 画成底纹）。
//   这是预排帧唯一能产生"动画感"的手段，也是这张图唯一的动。
//
// ## 与 App 内那张卡的关系
//
// 阈值只有一套：`wetThreshold = 0.05`（mm / 5min），与后端 `mapMinutely`、
// `MinutelyRain.isWet`、App 内 `SkyRoomMinutelyCard` 完全一致。这里**不另立**一套，
// 否则会出现「文字说无降水、柱子却一片」这种自相矛盾。
//
// ## 服务端那句 `summary` 不能当现状重绘（3.26.0 修掉的 P0）
//
// `summary` 是「23 分钟后雨停」这样的**相对句**，它的原点只有一个：**取数那一刻**。
// 而上面这套预排帧把同一份 `minutely` 发给了时间窗内的**每一帧**（最长 115 分钟）——
// 17:55 取的那句话会一路画到 19:50，那时雨早停了 87 分钟。小号又只显示这一行，
// 于是它成为桌面上最容易被读到的一句假话，和「把不知道说成没有」是同一类错。
//
// 所以本文件的每一条判据、每一句文案都**以帧自己的 `date` 为原点重算**：
// · 新鲜（≤ `summaryFreshWindow`）时仍用 `summary` —— 它人写的、最自然，此刻也准确；
// · 过期后改说**绝对时刻**（`HH:mm 有雨` / `预计 HH:mm 转小` / 到 HH:mm 仍有雨），
//   任何一个时刻被读到都不会歧义。
// · 「未来两小时无降水」这句结论也**只看 `date` 之后**的格子 —— 这样它永远成立。

/// 分钟级降水在 Widget 侧的两件工具事：**时间窗**（哪些帧带数据）与**判据**（下没下）。
///
/// 为什么把时间窗单独抽出来：`MinutelyRain.Point.t` 是 **ISO8601 字符串**
/// （和风原文直出，可能带也可能不带秒、一定带 `+08:00`），而 entry 的 `date` 是 `Date`。
/// 比较之前必须先解析 —— 解析器只允许有一处，散在 View 里迟早出现两份口径。
enum BriefMinutely {

    /// 一「湿格」的门槛：0.05 mm / 5min。
    ///
    /// 与 `MinutelyRain.isWet` 的兜底、后端 `mapMinutely`、App 内那张卡的注释同源。
    /// **不要**改成 0.01：那会让毛毛雨的尾巴也被算成"在下"，
    /// 而服务端已经用 0.05 把 summary 改写成「未来两小时无降水」了。
    static let wetThreshold: Double = 0.05

    /// 无降水时那一行小字。**不是**错误文案：它只在"这一帧之后的格子全干"时出现
    /// （见 `ahead(_:at:)` 的 `.dry`），那是一个确定的结论。
    static let dryText = "未来两小时无降水"

    /// 服务端 `summary` 的**有效期**：**6 分钟**。
    ///
    /// `summary` 是一句以**取数时刻**为原点的相对话（「23 分钟后雨停」），而同一份 `minutely`
    /// 会被 `BriefProvider` 发给时间窗内的每一帧（最长 115 分钟）。不设闸门，17:55 取的那句话
    /// 会一路画到 19:50 —— 那时雨早停了 87 分钟。
    ///
    /// ## 这句话的误差**恒等于 age**，所以阈值必须小于句子里的数
    ///
    /// `summary` 里的相对量是按签发时刻算的，帧一往前推，误差就整份加在 age 上。
    /// 和风最常吐的两个数是「3 分钟后雨停」「5 分钟后雨停」——**阈值比句子里的数还大时，
    /// 那句话必然已经过期**。例如雨在 17:55–18:00，`summary` 说「5 分钟后雨停」，
    /// 到 18:05 的帧（age = 10 分钟）它还在说「5 分钟后雨停」，而雨其实已经停了 5 分钟 ——
    /// 用将来时描述一件已经发生的事，比不说更糟。
    ///
    /// ## 为什么是 6 分钟
    ///
    /// 和风分钟降水 **5 分钟一格**，后台**每 5 分钟**刷一次 KV。6 分钟 = 一次刷新周期
    /// （5 分钟）+ 1 分钟网络余量，语义是「**最多容忍一代旧数据**」：上一轮刷新拿到的那份
    /// 仍然可以上屏，再往前一代就不行。
    ///
    /// 12 分钟错在哪：它容忍**两代**旧数据（2 × 5 分钟 + 余量），而 summary 里最常见的
    /// 相对量就是 3 分钟、5 分钟 —— 容忍度已经超过句子本身描述的时间跨度，那句话在任何
    /// age > 5 分钟却仍"新鲜"的帧上都是假的。**不要**为了"多留一会儿那句话"把它调大。
    ///
    /// ## 过期后为什么不干脆隐藏
    ///
    /// 保留「过期改说绝对时刻」这个正确内核即可：`absoluteLabel` 从 `points` 现算，
    /// 每帧自证时刻，永远不会过期。真去隐藏，小号在 115 分钟窗口里只有 6 分钟有字，
    /// 95% 的时间空着 —— 而空白会被读成「没有降水信息」，那是另一种谎。
    static let summaryFreshWindow: TimeInterval = 6 * 60

    /// 未来两小时的时间窗。
    ///
    /// `stamps` 直接取 `points` 自己的时刻，不再额外铺一条 5 分钟网格：
    /// 上游给的就是 5 分钟一格，照抄它的时刻，帧与数据**逐格对齐**（少一层"网格起点该从哪算"
    /// 的猜测）。万一某一格的时刻解析失败，那一格不参与帧表 —— 但窗口的起止仍由
    /// 首末两个**能解析**的时刻决定，柱状图不会因为一格坏数据整块消失。
    struct Window {
        /// 首个 points 时刻
        let start: Date
        /// 最后一个 points 时刻
        let end: Date
        /// 要去重进 timeline 的帧时刻（升序）
        let stamps: [Date]

        /// 这一帧落不落在窗口内 —— 落在里面的帧才带 `minutely`。
        ///
        /// 为什么窗口外的帧要传 nil 而不是继续带同一份数据：timeline 铺 24 小时，
        /// 两小时后的帧若还拿着这份降水，柱状图会把**两个小时前**的预报当成"未来两小时"画，
        /// 而那时它已经全部变成"过去"了 —— 一张全灰的图比不画更糟。
        func covers(_ date: Date) -> Bool {
            return date >= start && date <= end
        }
    }

    /// 从响应里解出时间窗；没有可用数据时返回 nil（= 整块不画，不是"无降水"）。
    ///
    /// `ok == false` 也算没有数据：和风的分钟降水源自雷达外推，**境外坐标直接无数据**，
    /// 那种情况必须整块不画 —— 把"没有这项服务"渲染成「未来两小时无降水」是一句假承诺。
    static func window(of rain: MinutelyRain?) -> Window? {
        guard let rain = rain, rain.ok else { return nil }
        guard let points = rain.points, points.count >= 2 else { return nil }

        var times: [Date] = []
        times.reserveCapacity(points.count)
        for point in points {
            guard let time = Formatters.weatherLocalTime(point.t) else { continue }
            times.append(time)
        }
        guard times.count >= 2 else { return nil }
        times.sort()

        guard let start = times.first, let end = times.last else { return nil }
        // 上游异常防护：正常窗口就是 2 小时。远长于它说明数据不是"未来两小时"，
        // 与其画一张 6 小时的图（时间刻度全错），不如整块不画。
        let limit = WidgetTimeline.briefMinutelyHorizon + WidgetTimeline.briefMinutelyStep
        guard end.timeIntervalSince(start) <= limit else { return nil }

        return Window(start: start, end: end, stamps: times)
    }

    /// 解析后的格子表（时刻 + 该 5 分钟的降水量），按时刻升序。
    ///
    /// 下面四个判定（还挂着 `date` 的格子、第一格湿格、连续湿格的终点、空态）都要同一份
    /// 解析结果。每处各写一遍 `Formatters.weatherLocalTime` 就是四份口径 ——
    /// 口径一分散，「文字说没雨、柱子一片」这种自相矛盾就会从缝里长出来。
    static func grids(_ rain: MinutelyRain) -> [(date: Date, p: Double)] {
        guard let points = rain.points else { return [] }
        var result: [(date: Date, p: Double)] = []
        result.reserveCapacity(points.count)
        for point in points {
            guard let time = Formatters.weatherLocalTime(point.t) else { continue }
            result.append((date: time, p: point.p))
        }
        result.sort { $0.date < $1.date }
        return result
    }

    /// 这一格是否**还挂着** `date`：一格覆盖它自己的 5 分钟（区间 `[t, t + 5min)`）。
    ///
    /// 为什么用区间而不是 `t >= date`：`entry.date` 是 timeline 的帧时刻，几乎从不正好
    /// 压在格边界上（系统换帧有秒级延迟）。用 `t >= date` 会把"正在下的那一格"漏掉，
    /// 读成「现在没在下、23 分钟后有雨」—— 那正是这次要修的那种谎。
    private static func covers(_ grid: Date, _ date: Date) -> Bool {
        return grid.addingTimeInterval(WidgetTimeline.briefMinutelyStep) > date
    }

    /// 从 `date` 起**仍然有效或还没到**的格子（含 `date` 所在那一格），升序。
    static func upcomingGrids(_ rain: MinutelyRain, from date: Date) -> [(date: Date, p: Double)] {
        return grids(rain).filter { covers($0.date, date) }
    }

    /// 从某一帧往后看，未来是「有雨 / 全干 / 看不出」。
    ///
    /// 为什么要有三档而不是 Bool：把「没有数据」和「确实不下」并成一个 `false`，
    /// 就会在境外坐标（和风无雷达外推）上写出一句「未来两小时无降水」——
    /// 那是拿不知道冒充结论。
    enum Ahead: Equatable {
        /// 之后（含当前格）还有湿格
        case wet
        /// 之后的格子全干 —— 一个**确定的结论**，可以说出口
        case dry
        /// 一格都解析不出来 —— 那是「没有数据」，绝不说成「无降水」
        case unknown
    }

    /// **空态判定的唯一入口**。
    ///
    /// 为什么不用 `rain.wet` / `rain.isWet`：那是"以签发时刻为原点的两小时里有没有雨"。
    /// 一帧画在签发后第 100 分钟时，那场雨早就停了，而 `wet` 仍然是 `true`；
    /// 反过来（签发时没雨、窗口内一直没雨）也一样。只有按 `date` **之后**的 `points` 判，
    /// 「未来两小时无降水」这句话在任何一帧上才都成立。
    static func ahead(_ rain: MinutelyRain, at date: Date) -> Ahead {
        let upcoming = upcomingGrids(rain, from: date)
        guard !upcoming.isEmpty else { return .unknown }
        return upcoming.contains { $0.p >= wetThreshold } ? .wet : .dry
    }

    /// 这一帧之后（含当前格）第一格"真下"的时刻；之后全干 / 无数据返回 nil。
    ///
    /// 用于「雨在靠近」的预兆层：它问的是"还差多久下"，必须以**这一帧**为原点 ——
    /// 沿用签发时刻的第一格湿格，那可能是 80 分钟前的过去，预兆层于是永远不出现。
    static func firstWetDate(_ rain: MinutelyRain, from date: Date) -> Date? {
        return upcomingGrids(rain, from: date).first { $0.p >= wetThreshold }?.date
    }

    /// 柱状图归一化用的最大值：优先服务端 `peak`，其次本组最大值，兜底 0.5。
    ///
    /// 为什么不用 `MinutelyRain.scaleMax`：那个只看 `points`，不看 `peak`。
    /// `peak` 是服务端算好的峰值（同一批数据、同一套判据），有它就该以它为准 ——
    /// 否则一旦某一格的 `p` 因四舍五入被抹平，柱子会突然被拉满。
    /// 下限 0.5 与 App 内那张卡一致：全是毛毛雨时柱子也要撑得起来。
    static func scaleMax(_ rain: MinutelyRain) -> Double {
        let peak = rain.peak ?? (rain.points?.map(\.p).max() ?? 0)
        guard peak.isFinite, peak > 0 else { return 0.5 }
        return max(0.5, peak)
    }

    /// 降水负载（0.35…1.6）：给粒子层的"密度 / 落速"用，1 = 没有 minutely 时的基准。
    ///
    /// 1.0 mm / 5min ≈ 12 mm/h（中雨）作为"满格的一半"，
    /// 2.0 mm / 5min ≈ 24 mm/h（大雨）算满。峰值缺失时返回 1（= 不改动现有画法），
    /// 绝不用 0 当"没数据"：那会让雨突然变稀，看起来像 bug。
    static func load(_ rain: MinutelyRain?) -> Double {
        guard let rain = rain, rain.isWet else { return 1 }
        let peak = rain.peak ?? (rain.points?.map(\.p).max() ?? 0)
        guard peak.isFinite, peak > 0 else { return 1 }
        return min(max(peak / BriefMetrics.minutelyPeakFull, 0.35), 1.6)
    }

    // MARK: - 那一行结论（小号正文 / 中号空态共用）

    /// 这一帧该显示的那一行结论；`nil` = 整行不画（信息不足，绝不编）。
    ///
    /// 两层按**新鲜度**分流（这就是本文件修的那个 P0）：
    /// · 帧时刻距签发 ≤ `summaryFreshWindow` → 用服务端 `summary`：它是人写的、最自然，
    ///   而且此刻仍然准确，"23 分钟后雨停"比"19:12 转小"更接近人想听的话；
    /// · 更旧 → `summary` 已经是过去时，改说**从 `points` 现算的绝对时刻**。
    ///
    /// 为什么不干脆过期就隐藏：窗口 115 分钟里只有 6 分钟新鲜，隐藏等于让小号在 95% 的
    /// 时间里空着 —— 而空白会被读成"没有降水信息"，那是另一种谎。
    ///
    /// - Parameters:
    ///   - rain: 这一帧携带的分钟降水（只在时间窗内非 nil）
    ///   - date: **这一帧的渲染时刻**，即 `entry.date`。不是 `Date()` ——
    ///     预渲染帧被系统延后展示时，现取当前时间会让新鲜度判定整体错位。
    /// - Returns: 一行文案；`nil` 表示连时间窗都解不出（= 没有任何可说的依据）
    static func label(_ rain: MinutelyRain, at date: Date) -> String? {
        // 时间窗是"这份数据到底签发过没有"的唯一凭据：连窗都解不出就没有任何话可说
        guard let window = window(of: rain) else { return nil }

        let age = date.timeIntervalSince(window.start)
        if age <= summaryFreshWindow,
           let summary = rain.summary,
           !summary.isEmpty {
            return summary
        }
        return absoluteLabel(rain, at: date)
    }

    /// 过期后的文案：**只用 `points` 自己算，任何一帧都自证时刻**。
    ///
    /// | 这一帧的处境 | 文案 | 为什么这么说 |
    /// |---|---|---|
    /// | 当前格是湿的，之后会转干 | `预计 HH:mm 转小` | 此刻确实在下，用户要知道的是"几点好" |
    /// | 当前格是湿的，一直湿到窗口末 | `到 HH:mm 仍有雨` | 不知道几点停，就老实说"至少到那时" |
    /// | 当前格是干的，之后有湿格 | `HH:mm 有雨` | 现在不下，用户要知道的是"几点下" |
    /// | 之后全干 | `未来两小时无降水` | 确定结论，而且**只在真的全干时**说 |
    ///
    /// 所有措辞都是**绝对时刻**，绝不出现「分钟后」/「稍后」：相对词会随帧漂，
    /// 而这一行从签发一直挂到窗口结束，漂一次就是一句假话。
    static func absoluteLabel(_ rain: MinutelyRain, at date: Date) -> String? {
        let upcoming = upcomingGrids(rain, from: date)
        // 一格都解析不出来 = 没有数据（不是"不下"）：整行不画
        guard !upcoming.isEmpty else { return nil }
        guard let firstWet = upcoming.firstIndex(where: { $0.p >= wetThreshold }) else {
            return dryText
        }
        // `upcoming[0].date <= date` 说明 `date` 正落在这一格里 → 此刻在下
        if firstWet == 0, upcoming[0].date <= date {
            if let dry = upcoming.first(where: { $0.p < wetThreshold }) {
                return "预计 \(Formatters.timeHHmm(dry.date)) 转小"
            }
            if let last = upcoming.last {
                let until = last.date.addingTimeInterval(WidgetTimeline.briefMinutelyStep)
                return "到 \(Formatters.timeHHmm(until)) 仍有雨"
            }
        }
        return "\(Formatters.timeHHmm(upcoming[firstWet].date)) 有雨"
    }
}

// MARK: - 中号 / 大号：24 格柱状图

/// 底部那条 24 格的降水柱。
///
/// 三档状态，逐档语义不同（**别合并**）：
///
/// | 状态 | 画什么 |
/// |---|---|
/// | `rain == nil`（没拿到） | 整块不画 —— 由调用方判空，本组件根本不创建 |
/// | 这一帧之后全干（`.dry`） | 一行小字「未来两小时无降水」—— 这是一个**结论**，不是缺数据 |
/// | 这一帧之后有湿格（`.wet`） | 24 根柱子；已经过去的格子退化成一截极淡的底纹 |
///
/// 三档由 `BriefMinutely.ahead(_:at:)` 判 —— **不是** `rain.wet`。理由见那边的注释：
/// `wet` 以签发时刻为原点，一帧画在第 100 分钟时它讲的是 100 分钟前的事。
///
/// 柱子按 `p / scaleMax` 归一化。过去的格子不画成柱子而是画成 2pt 底纹，
/// 于是每换一帧（5 分钟）就有一根柱子塌成底纹 —— 图"往前推"，这是预排帧能做出
/// 推进感的唯一手段（Widget 里没有持续动画）。
struct BriefMinutelyBars: View {

    let rain: MinutelyRain
    /// 这一帧的时刻。**必须是 `entry.date`**，不能是 `Date()`：
    /// 预渲染帧被系统延后展示时，现取当前时间会让"哪一格已经过去"整体错位。
    let date: Date
    /// 柱区高度（pt）
    let height: CGFloat
    /// 墨色（跟随纸面档位，由 `BriefFace` 那唯一一处 colorScheme 决定）
    let ink: Color
    /// 一行字用的字号（无降水时那句结论）
    let font: Font

    var body: some View {
        // 只看 `date` 之后：柱图本身早就按每根柱子自己的 `t` 画了，
        // 这里要改的只是**空态判定**（文字那一支）。
        switch BriefMinutely.ahead(rain, at: date) {
        case .wet:
            chart
        case .dry:
            dryLabel
        case .unknown:
            // 一格都解析不出来 = 没有可用数据（不是"不下"）：整块不画。
            // 在这种情况下写「未来两小时无降水」就是拿不知道冒充结论。
            EmptyView()
        }
    }

    /// 全干时的结论。字号 / 透明度与 App 内那张卡同一档（`minutelyDryTextAlpha`）。
    private var dryLabel: some View {
        Text(BriefMinutely.dryText)
            .font(font)
            .foregroundStyle(ink.opacity(BriefMetrics.minutelyDryTextAlpha))
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(BriefMinutely.dryText)
    }

    /// 24 根柱子等距排开。
    ///
    /// 为什么用 `Capsule` 一列而不是 `Canvas`：24 个纯色圆角小矩形交给合成层，
    /// 比每帧重绘一次画布便宜，而且它天然跟着墨色走（Widget 每小时都要重画一次，
    /// 这里的成本要按"一年 8760 次"算）。
    private var chart: some View {
        let points = rain.points ?? []
        let scale = BriefMinutely.scaleMax(rain)
        return HStack(alignment: .bottom, spacing: BriefMetrics.minutelyBarGap) {
            ForEach(Array(points.enumerated()), id: \.offset) { pair in
                bar(point: pair.element, scale: scale)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityLabel("未来两小时降水强度")
    }

    /// 一根柱子。
    ///
    /// 三个不透明度代表三种语义：过去（底纹，最淡）/ 湿格（正字）/ 未来干格（几乎只剩基线）。
    /// 未来干格也要画一截，否则"雨还没到的那些格"会是一段空白，
    /// 读者会以为图没画完（而不是"这段时间不下"）。
    private func bar(point: MinutelyRain.Point, scale: Double) -> some View {
        let time = Formatters.weatherLocalTime(point.t)
        let isPast = time.map { $0 < date } ?? false
        let isWet = point.p >= BriefMinutely.wetThreshold
        let ratio = scale > 0 ? min(max(point.p / scale, 0), 1) : 0
        let wetHeight = max(BriefMetrics.minutelyBarMinHeight, height * CGFloat(ratio))
        let barHeight = isPast
            ? BriefMetrics.minutelyPastHeight
            : (isWet ? wetHeight : BriefMetrics.minutelyBarMinHeight)
        let alpha = isPast
            ? BriefMetrics.minutelyPastAlpha
            : (isWet ? BriefMetrics.minutelyBarAlpha : BriefMetrics.minutelyDryAlpha)

        return Capsule(style: .continuous)
            .fill(ink.opacity(alpha))
            .frame(maxWidth: .infinity)
            .frame(height: barHeight)
    }
}

// MARK: - 小号：一行结论

/// 小号只有 158×158，一张 24 格的图会把正文与轨迹全挤掉 —— 所以小号只放**结论**。
///
/// 一句话回答"要不要现在出门"，柱状图要读者自己算 —— 这也是为什么这一行必须永远准确：
/// 小号**只有**这一行，读错了没有任何别的元素能纠正它。
///
/// ## 文案不能直接用服务端 `summary`（3.26.0 P0）
/// `summary` 的原点是**取数那一刻**（「23 分钟后雨停」），而同一份 `minutely` 会发给
/// 时间窗内的每一帧。直接上屏 = 17:55 那句话一直画到 19:50（那时雨早停了 87 分钟）。
/// 于是分流全部交给 `BriefMinutely.label(_:at:)`：新鲜时用 `summary`，过期后改说
/// 从 `points` 现算的**绝对时刻**。View 层不许自己判 `rain.wet` 或读 `rain.summary`，
/// 否则小号 / 中号会各说一套。
struct BriefMinutelySummary: View {

    let rain: MinutelyRain
    /// 这一帧的渲染时刻（**`entry.date`**）。服务端那句话准不准，只有拿这一帧自己的
    /// 时刻去比才知道 —— 用 `Date()` 会让预渲染帧在被系统延后展示时整体错位。
    let date: Date
    let font: Font
    let ink: Color

    /// 这一帧要说的话；nil = 整行不画（一格数据都解不出来时不编内容）
    private var text: String? {
        return BriefMinutely.label(rain, at: date)
    }

    var body: some View {
        if let text = text {
            Text(text)
                .font(font)
                .foregroundStyle(ink.opacity(BriefMetrics.minutelySummaryAlpha))
                .lineLimit(1)
                // 显式收尾截断：小号只有一行、字号又是按屏幕缩放的，
                // 靠默认值在不同系统语言 / 动态字号下不一定还是 `.tail`
                .truncationMode(.tail)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(text)
        }
    }
}
