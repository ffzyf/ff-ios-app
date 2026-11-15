import Foundation

// MARK: - Timeline 时间刻度（App / Widget 双 target 共用）

/// 5.1.2 · T03：`enum WidgetTimeline` 从 `Sources/Widget/WidgetProvider.swift` **纯平移**到这里。
///
/// ## 为什么必须下沉
/// `project.yml` 把整个 `Sources/Widget` 排除在主 App target 之外，又以独立 `path:` 条目
/// 显式引入 `*Face` 渲染层（R5 调试面板要「App 进程内复用渲染层」）。而
/// `BriefFace`（分钟降水柱的 5 分钟槽位）与 `BriefMinutely`（时间窗防胀、最后一根柱的
/// 推进量）都要读这几个刻度常量 —— 它们原先只在 Provider 文件里，主 App 编译因此报
/// `cannot find 'WidgetTimeline' in scope`。
///
/// 这个 enum 是**纯常量 + 纯函数**（只依赖 Foundation 的 `Date` / `TimeInterval`），
/// 没有任何 Widget-only 类型（`BriefCachePayload` / `WidgetTheme` / `SunTimesOverride`），
/// 所以可以整段下沉到 Shared —— 两个 target 引用**同一份**刻度，不会出现两套帧距。
///
/// ## 抽取纪律
/// 一个字都没改：注释、常量名、常量值、`stamps` 的防死循环写法与原文逐字一致。
/// `WidgetProvider.swift` 只删掉这个 enum，其余（解码器 / 快照 / 请求层 / Provider）原样保留。

/// Timeline 的「时间刻度」工具。
///
/// 为什么要按刻度铺 entry，而不是"只给一条、靠 `.atEnd` 反复重取"：
/// 简报卡的天色由 `SkyPhase` 的七档决定（夜 / 蓝调 / 日出 / 黄金 / 白天 / 日落 / 蓝调），
/// 档与档之间**没有插值** —— 想让天空"随时间自然过渡"，唯一的办法是让 entry 跟着时间走，
/// 让系统到点自己换上下一帧。Timeline 里的多个 entry 是**预渲染帧**，
/// 不消耗刷新预算（预算算的是「重新跑一次 getTimeline、又发一轮网络请求」），
/// 所以这里是"多帧、少请求"：简报卡一轮约 48 帧（1 小时网格 + 未来两小时的 5 分钟网格），
/// 但真正发请求的是每两小时那一次。
enum WidgetTimeline {

    /// 简报卡的刻度：**60 分钟**。
    ///
    /// 为什么从 30 分钟放宽到 60 分钟（V3.7）：这张卡的底色不再随时段变色，而是跟着
    /// **当天的天气**走（一天只变一次脸），真正还在"走"的只有轨迹上那颗光点。
    /// WidgetKit 的刷新预算按"每天几十次"算，30 分钟一帧铺 24 小时就是 48 帧 ——
    /// 预算会被这种"看不出差别"的帧吃光，代价是用户在早上 8 点看不到当天的新简报。
    /// 而云要"飘"根本不需要更高频的唤醒：位移是靠**预排帧**做的（每帧的云位置由这一帧的
    /// 时刻算出来，见 `BriefFace` 的 `BriefWeatherLayer.drift`），到点系统自己换画面。
    static let briefStep: TimeInterval = 60 * 60

    /// 简报卡的视野：**24 小时**（24 帧）。到点按 `briefRefresh`（2 小时）再取一轮
    /// （含三次网络请求：简报 + 天气 + 分钟降水），一天约 12 次，
    /// 离 iOS 每天 40–70 次的预算上限还有一个量级的余量。
    ///
    /// 为什么铺满一整天而不是 12 小时：天气一天只有"白天/夜里"和"变天"这几次变化，
    /// 视野短于一天就会出现"用户在晚上 11 点看不到明天早上那一帧"的断档，
    /// 而多出来的帧全是预渲染，不发请求。
    static let briefHorizon: TimeInterval = 24 * 3600

    /// 分钟级降水的视野：**2 小时**（24 格 × 5 分钟）。
    ///
    /// 它也顺带决定简报卡的**重取间隔**（见 `briefRefresh`）：柱状图讲的是"未来两小时"，
    /// 两小时后再取一轮，图上永远有一段真实的未来 —— 而旧的那 24 帧在这一刻正好全部走完。
    static let briefMinutelyHorizon: TimeInterval = 2 * 3600

    /// 分钟级降水的刻度：**5 分钟**。
    ///
    /// 上游（和风 `/v7/minutely/5m`）就是 5 分钟一格，所以帧表直接照抄 `points` 的时刻。
    /// 这个常量真正的用处是两处**换算**：
    /// 1. `BriefMinutely.Window` 的异常防护（窗口不该远长于 2 小时）；
    /// 2. `BriefWeatherLayer.fallPhase` 把帧时刻推进到"第几个 5 分钟槽位"——
    ///    那是雨滴"在落"的唯一来源（预排帧里没有动画时钟）。
    static let briefMinutelyStep: TimeInterval = 5 * 60

    /// 简报卡重新取一轮的间隔：**2 小时**。
    ///
    /// 为什么不是 `.atEnd`：timeline 铺 24 小时，`.atEnd` 意味着**要等 24 小时**才会重取，
    /// 底部的柱状图会旧 22 小时（画的全是"过去"，一根柱子都不剩）。
    /// 2 小时一轮 = 一天 12 次，仍在 iOS 每天 40–70 次的预算里（3.25.0 前是 1 次/天）。
    static let briefRefresh: TimeInterval = 2 * 3600

    /// 红石卡的刻度：30 分钟（与简报统一 —— 两张卡并排放在桌面上，刷新节奏不该有两个脾气）
    static let rockStep: TimeInterval = 30 * 60

    /// 红石卡的视野：24 小时（红石一天只变几次，视野放长，请求更省）
    static let rockHorizon: TimeInterval = 24 * 3600

    /// 从 `now` 起按 `step` 等距铺到 `horizon`（含 `now` 本身）。
    ///
    /// 显式防死循环：`step <= 0` 直接退回单帧，游标每轮必须严格前进。
    static func stamps(now: Date, horizon: TimeInterval, step: TimeInterval) -> [Date] {
        guard step > 0, horizon > 0 else { return [now] }
        var result: [Date] = [now]
        var cursor = now.addingTimeInterval(step)
        let limit = now.addingTimeInterval(horizon)
        while cursor < limit {
            result.append(cursor)
            cursor = cursor.addingTimeInterval(step)
        }
        return result
    }
}
