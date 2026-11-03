import Foundation
import SwiftUI

/// 能见度 → 大气浑浊度（0 = 通透，1 = 浓雾）。
///
/// 为什么单独一个类型：App 的天光页、天光小组件、简报卡三处都要按同一个口径变暗变灰，
/// 各写一份阈值，迟早出现"App 里雾蒙蒙、桌面组件还是通透蓝天"。
///
/// ## 物理口径（不是感觉，是实测值）
///
/// 能见度（visibility）是**水平方向**"能看多远"，单位米。雾 / 霾天能见度低，
/// 阳光被气溶胶散射，天空整体发灰发白、霞光的饱和度被冲掉，远山看不见。
/// 于是「能见度低 ≈ 大气浑浊度高 ≈ 画面要起雾 + 掉饱和 + 削弱太阳辉光」。
///
/// Open-Meteo 的 `visibility` 字段下限约 200 米、上限约 24140 米，所以本文件的
/// 分段线性表就以这两端为锚点：24000 米以上视为完全通透，200 米以下视为浓雾。
///
/// ## 三条使用纪律
///
/// 1. **只输出 0…1 的一个数**：具体"雾层多不透明、饱和掉多少、辉光削多少"由各渲染层
///    自己乘系数 —— 这样同一份浑浊度在 400pt 的小组件和全屏的天光页上都成立；
/// 2. **不做兜底**：`visibilityMeters == nil` 时**不**假设 24km（那会让雾天显示成通透天），
///    只用天气类型给一个保守底值（见 `level(visibilityMeters:kind:)`）；
/// 3. **不 import UIKit**：本文件与 Widget target 共用，只依赖 `SwiftUI` 的 `Color`
///    与 `Shared/UI/ColorBlend.swift` 的 `Color.blend`。
///
/// ## 3.27.0：「渲染」与「判定」是两个入口，不许混用
///
/// - `level(visibilityMeters:kind:)`（**渲染**）：`kind == nil` 时返回 **0**。
///   不知道天气就不起雾 —— "不知道"和"雾天"是两回事。
/// - `observedLevel(visibilityMeters:kind:)`（**判定**）：允许只凭能见度给值。
///   `SkyViewing` 用它把观测翻成"此刻天好不好看"，那里能见度本身就是依据。
///
/// 为什么要分成两个而不是加个 `Bool` 参数：一个布尔在调用点读作 `haze(x, y, true)`，
/// 三个月后没人说得清那个 `true` 是"允许只凭能见度"还是"允许兜底成晴天"。
/// 两个名字各说一件事，调用点自解释。
enum SkyHaze {

    // MARK: - 浑浊度

    /// 能见度（米）+ 天气类型 → 浑浊度 0…1。**渲染层用这一个**。
    ///
    /// ## `kind == nil`（天气未知）时恒为 0
    ///
    /// 这是 3.27.0 补上的一条：能见度与天气类型走的是**两条不同的上游**
    /// （`VisibilityProbe` 直连 Open-Meteo；天气走 `/api/app/weather`）。天气那一发
    /// 超时 / `ok == false` / 后端没给 `code` 时它给不出 `kind`，而能见度那一发可能照样回来。
    /// 旧实现于是只凭能见度就把 `haze` 推到 0.2…0.56：**画面上没有任何天气图形
    /// （云、雨、雾带一个都没画），整片天却被压成灰白** —— 用户在小组件上看到的就是
    /// 卡片写着"多云"、屏上却像大雾。同一个病在 App 内天光页也有一份。
    ///
    /// **"不知道"和"阴天"是两回事**：要变灰，得有"这是阴 / 雾 / 雨"的依据。
    /// 只有能见度、没有天气类型时，"看不清远处"也可能是晴天的霾 ——
    /// 拿它当雾画，等于替用户猜了一个天气（这条纪律与 `WeatherKind.from(code:)`
    /// 拒绝兜底成晴天是同一条）。
    ///
    /// - Parameters:
    ///   - visibilityMeters: 水平能见度（米）。nil = 没有数据（不是 0、也不是 24km）
    ///   - kind: 天气类型。nil = 不知道什么天 → **本函数返回 0**
    /// - Returns: 0…1 的浑浊度
    static func level(visibilityMeters: Double?, kind: WeatherKind?) -> Double {
        // 不知道天气 → 不改画面。判断放在最前面（早于任何曲线计算），
        // 这样"缺数据"在代码里就是一条 return，不是一个藏在 max() 里的巧合。
        guard let kind else { return 0 }
        return observedLevel(visibilityMeters: visibilityMeters, kind: kind)
    }

    /// 能见度（米）+ 天气类型 → 浑浊度 0…1。**只给"把观测翻成判定"的地方用**。
    ///
    /// 与 `level` 的唯一区别：`kind == nil` 时**允许只凭能见度**给值。
    /// 目前只有 `SkyViewing.verdict` 一个调用者 —— 它回答的是"此刻天好不好看"
    /// （决定黄金时刻要不要降级、星星要不要撒），而能见度低本身就是"不好看"的
    /// 直接观测，不需要先知道天气代码。
    ///
    /// **渲染层不要用它**：那会把"天气没拿到"画成"阴天灰"，正是 3.27.0 要修的东西。
    ///
    /// 两者都有时取 `max`：雾天即使上游数据说"能见度 10km"，画面也不该通透 ——
    /// 观测点与用户所在位置常常差着几公里，雾的边界又极不规则。宁可雾重一点，
    /// 也不要出现"App 说有大雾、天空却一片澄澈"这种自相矛盾。
    ///
    /// **降水天先夹一个上限再进曲线**（3.25.0）：见 `ceiling(for:)` 与
    /// `effectiveVisibility(_:kind:)` —— 雨幕的消光不会被气象站的水平能见度反映，
    /// 不夹这一下，大雨天会拿到 10km 的观测值，`max(curve, base)` 于是只剩 `.rain` 的 0.30，
    /// 画面依旧通透，用户的原话就是「下雨时看起来还是太透」。
    ///
    /// - Parameters:
    ///   - visibilityMeters: 水平能见度（米）。nil = 没有数据（不是 0、也不是 24km）
    ///   - kind: 天气类型。`WeatherKind.from(code:)` 认不出代码时也是 nil
    /// - Returns: 0…1 的浑浊度；两项都缺时返回 0（没有依据就不改画面）
    static func observedLevel(visibilityMeters: Double?, kind: WeatherKind?) -> Double {
        let fallback = kind.map { baseLevel(for: $0) } ?? 0
        guard let meters = visibilityMeters, meters.isFinite else { return fallback }
        let effective = effectiveVisibility(meters, kind: kind)
        return max(curveLevel(effective), fallback)
    }

    /// 降水能见度上限（米）：进曲线**之前**先把 `meters` 夹到它。
    ///
    /// ## 为什么需要这一张表（不是"为了好看调参"）
    ///
    /// 上游（和风 / 气象站）的 `visibility` 是**站点观测的水平能见度**，它描述的是
    /// 「大气本身有多浑」，而雨幕造成的看不清是**几何遮挡** —— 雨滴是实体，
    /// 它挡光、挡视线的机理和雾滴的气溶胶散射不是一回事，站点那套观测里根本没有这一项。
    /// 所以同一场中雨，站里照样报 10km（因为它测的是"雾不雾"），而人站在雨里只能看 2~3km。
    ///
    /// 于是 `max(curveLevel(10_000) = 0.20, baseLevel(.rain) = 0.30)` 得到 0.30 ——
    /// 天空只掉一点点饱和、雾层几乎不出现，雨丝的粒子层孤零零地贴在通透的天上，
    /// 这正是"下雨时天光卡看起来还是太透"的根因。把被上游低估的那部分补回来的唯一办法，
    /// 就是承认"有降水时能见度不可能好于某一档"，先把 `meters` 夹到那一档再进曲线。
    ///
    /// ## 取值依据（一眼可核）
    ///
    /// | 降水类型 | 上限 | 现实参照 |
    /// |---|---|---|
    /// | 毛毛雨 | 6 km | 雨滴极小、数密度低，损失最轻；6 km → 曲线 0.36，才看得出"有点糊" |
    /// | 雨 | 5 km | 中雨的能见度量级；大雨更差，但 `kind` 分不出量级，取一个保守中值 |
    /// | 雪 | 3 km | 雪片比雨滴大一个量级，同样的降水率挡得更多 |
    /// | 雷雨 | 2.5 km | 雨幕最密 + 云底最低，是这四档里最差的 |
    ///
    /// 注意这张表给的是**上限**（`min`），不是设定值：观测值比它还差时（真·暴雨 1km）
    /// 原样进曲线，我们只补"被低估"的那一段，绝不像素级改写上游已经更差的情况。
    ///
    /// - Parameter kind: 天气类型；非降水（晴 / 多云 / 阴 / 雾）返回 nil = 不夹
    private static func ceiling(for kind: WeatherKind) -> Double? {
        switch kind {
        case .drizzle:
            // 毛毛雨：雨滴极小、数密度低，能见度损失最轻的一档。
            //
            // 为什么是 **6 km**（3.26.0 从 8 km 下调）：8 km 落在曲线 0.28 上，而
            // `baseLevel(.drizzle) = 0.24` —— `max(curve, base)` 之后只差 0.04，等于
            // 这一档**根本没有效果**（毛毛雨天调不调这条上限，画面一模一样）。
            // 6 km 对应曲线的 0.36 锚点，比底值高 0.12，毛毛雨才看得出"天有点糊"。
            //
            // 为什么不是更狠的 5 km：`kind` 只给了"毛毛雨"这一个类型（61 号代码），
            // 分不出轻重；5 km 已经是 `.rain` 的上限，会把小毛毛雨当成中雨压浑。
            // 所以取**能让这一档产生可见差异的保守上限**。
            return 6_000
        case .rain:
            // 雨：中雨的能见度量级（`kind` 分不出小 / 中 / 大，取保守中值）
            return 5_000
        case .snow:
            // 雪：雪片直径比雨滴大一个量级，同降水率下挡得更多
            return 3_000
        case .thunder:
            // 雷雨：雨幕最密、云底最低，四档里最差
            return 2_500
        case .clear, .partly, .overcast, .fog:
            // 雾**不夹**：雾的能见度就是站点直接测的那个量，它就是这条曲线的本职。
            // 晴 / 多云 / 阴根本没有降水，没有任何理由动它们的观测值。
            return nil
        }
    }

    /// 夹上下限之后真正进曲线的能见度（米）。
    ///
    /// 单独抽成一个函数是为了让 `level` 里那两行读起来就是一句话：
    /// 「先夹到降水上限，再进曲线，最后和天气类型的底值取大」。
    private static func effectiveVisibility(_ meters: Double, kind: WeatherKind?) -> Double {
        guard let kind = kind, let bound = ceiling(for: kind) else { return meters }
        return Swift.min(meters, bound)
    }

    /// 雾层的颜色：白天 / 黄昏用近白，夜里用冷灰。
    ///
    /// 做法是把**地平线那一档天色**往墨色（`sky.ink`，近白 `#F5F8FF`）里提 65%：
    ///
    /// - 白天 / 黄昏的 horizon 是暖橙 / 亮蓝，提亮之后就是"被雾冲淡的近白"；
    /// - 夜里的 horizon 是冷蓝 `#101A2C`，提亮之后是一片**冷灰**，而不是一块发光板 ——
    ///   这正是夜雾该有的样子：能见度差、整体压暗。
    ///
    /// **注意**：夜里那层雾不能用 `.plusLighter` 混合（深色天上提亮 = 一块发光的白板），
    /// 调用方要换成普通混合 + 降低 alpha（见 `SkyRoomView.scene(...)`）。
    ///
    /// - Parameter sky: 当前天色档位的六个 token
    /// - Returns: 不透明的雾色（调用方自己乘 `opacity`）
    static func tint(sky: Theme.SkyColors) -> Color {
        return Color.blend(sky.horizon, sky.ink, 0.65)
    }

    // MARK: - 能见度曲线（分段线性）

    /// 锚点表：`meters` 从大到小排列，`level` 随之单调上升。
    ///
    /// 每一档都写清楚，是因为这张表就是"观感"本身：
    ///
    /// | 能见度 | 浑浊度 | 现实对应 |
    /// |---|---|---|
    /// | ≥ 24000 m | 0.00 | 高原 / 极干燥空气，通透到能看见远山轮廓 |
    /// | 16000 m | 0.10 | 优良：霞光完整，只有极远处略灰 |
    /// | 10000 m | 0.20 | 良好：地平线开始有一层薄霾 |
    /// | 6000 m | 0.36 | 轻度霾：霞光饱和度明显下降 |
    /// | 3000 m | 0.56 | 中度霾 / 轻雾：远山化掉，太阳只剩一个盘 |
    /// | 1500 m | 0.74 | 雾：辉光基本消失，天空一片灰白 |
    /// | 600 m | 0.88 | 浓雾：只能看见近处 |
    /// | ≤ 200 m | 1.00 | 能见度下限（Open-Meteo 的下边界） |
    private static let curve: [(meters: Double, level: Double)] = [
        (meters: 24_000, level: 0.00),
        (meters: 16_000, level: 0.10),
        (meters: 10_000, level: 0.20),
        (meters: 6_000, level: 0.36),
        (meters: 3_000, level: 0.56),
        (meters: 1_500, level: 0.74),
        (meters: 600, level: 0.88),
        (meters: 200, level: 1.00)
    ]

    /// 能见度（米）→ 浑浊度：在锚点之间做线性插值，两端夹紧。
    private static func curveLevel(_ meters: Double) -> Double {
        guard let clearest = curve.first, let foggiest = curve.last else { return 0 }
        // 比最通透那档还能见得更远：就是通透
        if meters >= clearest.meters { return clearest.level }
        // 比最浓那档还差：就是满格（不往 1 以上插值，渲染层只需要 0…1）
        if meters <= foggiest.meters { return foggiest.level }

        for index in 1..<curve.count {
            let upper = curve[index - 1]   // 能见度更高、雾更淡的一档
            let lower = curve[index]       // 能见度更低、雾更重的一档
            guard meters >= lower.meters else { continue }
            let span = upper.meters - lower.meters
            guard span > 0 else { return lower.level }
            let t = (meters - lower.meters) / span   // 0 = 浓的那一档，1 = 淡的那一档
            return lower.level + (upper.level - lower.level) * t
        }
        return foggiest.level
    }

    // MARK: - 天气类型的保守底值

    /// 没有能见度数据时，按天气类型给一个**保守**底值（宁可雾重，不要通透）。
    ///
    /// 这些数字不是拍脑袋：雾 0.85 是"看不见远处"的定义本身；雨雪在 0.30~0.35
    /// 是雨幕 / 雪幕对能见度的实际影响量级；阴天 0.16 是云底那一层灰；
    /// 晴 0 与多云 0.04 是"基本不动画面"。
    ///
    /// 为什么不给 rain 更高的值：雨天的能见度损失主要体现在**降水粒子**上，
    /// 而天光页不画雨丝（那是天气组件的事）—— 这一层只负责大气浑浊度。
    ///
    /// 3.25.0 起这一档**不再是雨天的天花板**：真正把雨天"压浑"的是 `ceiling(for:)` 那张
    /// 降水能见度上限表（雨 5km → 曲线 0.42）。底值只是"连能见度都没有"时的保守兜底，
    /// 所以这里一个数都没动 —— 动了它，没有能见度数据的那一半帧反而会突然变浑。
    private static func baseLevel(for kind: WeatherKind) -> Double {
        switch kind {
        case .fog:
            return 0.85
        case .thunder:
            return 0.32
        case .rain:
            return 0.30
        case .snow:
            return 0.35
        case .drizzle:
            return 0.24
        case .overcast:
            return 0.16
        case .partly:
            return 0.04
        case .clear:
            return 0
        }
    }
}
