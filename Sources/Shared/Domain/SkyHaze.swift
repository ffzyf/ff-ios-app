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
enum SkyHaze {

    // MARK: - 浑浊度

    /// 能见度（米）+ 天气类型 → 浑浊度 0…1。
    ///
    /// 两者都有时取 `max`：雾天即使上游数据说"能见度 10km"，画面也不该通透 ——
    /// 观测点与用户所在位置常常差着几公里，雾的边界又极不规则。宁可雾重一点，
    /// 也不要出现"App 说有大雾、天空却一片澄澈"这种自相矛盾。
    ///
    /// - Parameters:
    ///   - visibilityMeters: 水平能见度（米）。nil = 没有数据（不是 0、也不是 24km）
    ///   - kind: 天气类型。`WeatherKind.from(code:)` 认不出代码时也是 nil
    /// - Returns: 0…1 的浑浊度；两项都缺时返回 0（没有依据就不改画面）
    static func level(visibilityMeters: Double?, kind: WeatherKind?) -> Double {
        let fallback = kind.map { baseLevel(for: $0) } ?? 0
        guard let meters = visibilityMeters, meters.isFinite else { return fallback }
        return max(curveLevel(meters), fallback)
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
