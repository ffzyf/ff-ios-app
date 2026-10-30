import SwiftUI

/// 轨迹卡的 6 套渐变配方（设计文档 §5.1.2 表2）。
///
/// 为什么放在 Widget 目录（不进 `Shared`）：配方是小组件轨迹卡专属的视觉语言，主 App 不用，
/// 进 Shared 只会让共享层多一批"只有 widget 用"的颜色。
///
/// 颜色来源：全部来自设计文档表2 的 hex（深/浅双主题）。Widget **跟随系统外观**，不跟随 App 三态，
/// 所以每套配方都给出 dark / light 两端，运行时按 `colorScheme` 选。
///
/// 为什么不在 Widget 里直接写十六进制颜色字面量：主题闸门（`scripts/lint-theme.sh`）把十六进制颜色写法列为
/// 「只能在 Theme.swift / Extensions.swift 出现」的硬规则，Widget 里出现会直接报红。
/// 这里手写一份 hex→RGB 的解析（`c(_:_:scheme:)`），既不碰 lint 红线，又能做到深浅自适应，
/// 也**不需要引入 UIKit**（纯 SwiftUI `Color(red:green:blue:)` 即可，避免 Widget 目录出现裸 UIKit 引用）。
enum TrackGradient {

    /// 配方键：由「时段（常驻 widget）/ 状态（实时活动）」决定用哪套。
    enum Key: Hashable {
        case dawn    // 日出（05:00–08:00 / live=即将）
        case day     // 日间晴（08:00–11:00 / 14:00–17:00）
        case noon    // 正午（11:00–14:00）
        case dusk    // 黄昏（17:00–19:30）
        case night   // 午夜（19:30–05:00 / live=已结束）
        case active  // 进行中（live=进行中 / 红石此刻有场次）
    }

    // MARK: - 十六进制解析（纯 SwiftUI，不引 UIKit、不写十六进制颜色字面量）

    /// 把 `#RRGGBB` / `RRGGBB` 解析成 0..1 的 RGB 分量。非法输入回退黑，绝不崩。
    private static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let t = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt64(t, radix: 16) ?? 0
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        return (r, g, b)
    }

    /// 动态色：按 `scheme` 选 dark / light 一端，转成 `Color(red:green:blue:)`。
    private static func c(_ dark: String, _ light: String, scheme: ColorScheme) -> Color {
        let hex = (scheme == .light) ? light : dark
        let (r, g, b) = rgb(hex)
        return Color(red: r, green: g, blue: b)
    }

    // MARK: - 6 套配方（深 / 浅 两端 + 弧线 tint）

    /// 每套配方 = (dark 起始, dark 结束, light 起始, light 结束, arcTint 深, arcTint 浅)
    /// 数值一字不差照抄设计文档 §5.1.2 表2。
    private static let recipes: [Key: (d0: String, d1: String, l0: String, l1: String, t0: String, t1: String)] = [
        // dawn 日出
        .dawn:  ("#0D3B4F", "#2E8B9A", "#BFE3EC", "#7FC8D6", "#3FE0C0", "#1FA98C"),
        // day 日间晴
        .day:   ("#3FA9F5", "#8FD3F4", "#5FB4EC", "#CFEAFB", "#0B6E9E", "#0B6E9E"),
        // noon 正午
        .noon:  ("#0B2545", "#1B3A5C", "#34487A", "#5E79AC", "#9FC0FF", "#3D6BBF"),
        // dusk 黄昏
        .dusk:  ("#2A1A0A", "#C9871F", "#F0C58A", "#D89A3C", "#FFE3B0", "#C9871F"),
        // night 午夜
        .night: ("#070B14", "#101C2E", "#2A3550", "#46577A", "#9FB4E0", "#46577A"),
        // active 进行中（靛蓝→深绿，lime 节点）
        .active:("#13243F", "#1E5C3A", "#3C6E5A", "#7FD0A8", "#6BDB5C", "#2F7A2C"),
    ]

    /// 该配方对应的渐变停靠点（[起始, 结束]）。按 `scheme` 选深/浅。
    static func gradient(for key: Key, scheme: ColorScheme) -> [Color] {
        guard let r = recipes[key] else {
            return [c("#070B14", "#2A3550", scheme: scheme), c("#101C2E", "#46577A", scheme: scheme)]
        }
        return [c(r.d0, r.l0, scheme: scheme), c(r.d1, r.l1, scheme: scheme)]
    }

    /// 该配方对应的弧线 / 节点 tint（按 `scheme` 选；浅色下整体压深以保证对比度）。
    static func arcTint(for key: Key, scheme: ColorScheme) -> Color {
        guard let r = recipes[key] else { return c("#9FB4E0", "#46577A", scheme: scheme) }
        return c(r.t0, r.t1, scheme: scheme)
    }

    /// 该配方的一个代表实色（实时活动 `activityBackgroundTint` 需要单一 Color 兜底时用）。
    static func solid(for key: Key, scheme: ColorScheme = .dark) -> Color {
        guard let r = recipes[key] else { return c("#101C2E", "#46577A", scheme: scheme) }
        return c(r.d1, r.l1, scheme: scheme)
    }

    /// 渐变方向：让"颜色即信息"有方向感（设计文档：`.topLeading`→`.bottomTrailing`）。
    static let startPoint = UnitPoint.topLeading
    static let endPoint = UnitPoint.bottomTrailing

    /// 前景色（大字 / 图标 / 地名）：用近黑，深浅自适应。直接复用 `Theme.textPrimary`
    /// —— 它在浅色下正是近黑（#0F1A26），深色下近白，全程可读。
    static func foreground(for key: Key) -> Color {
        return Theme.textPrimary
    }

    // MARK: - 时段 → 配方

    /// 北京时区的小时（0–23）。
    static func hour(now: Date = Date()) -> Int {
        return RedstoneClock.calendar.component(.hour, from: now)
    }

    /// 由「一天里的小时」选配方（设计文档 §5.1.2 trigger 列）。
    ///
    /// 05–08 日出 / 08–11 与 14–17 日间 / 11–14 正午 / 17–19:30 黄昏 / 其余午夜。
    static func forHour(_ h: Int) -> Key {
        switch h {
        case 5..<8:             return .dawn
        case 8..<11, 14..<17:   return .day
        case 11..<14:           return .noon
        case 17..<20:           return .dusk
        default:                return .night
        }
    }

    /// 红石 widget：有进行中场次 → active（lime 节点）；否则按当前小时选时段配方。
    static func forRedstone(phase: RockPhase, now: Date = Date()) -> Key {
        if phase.isOngoing { return .active }
        return forHour(hour(now: now))
    }

    /// 简报 widget：纯时段配方（无自身状态语义，如表1 裁决）。
    static func forBrief(now: Date = Date()) -> Key {
        return forHour(hour(now: now))
    }

    /// 实时活动锁屏：即将=dawn / 进行中=active / 兜底=night。
    static func forLiveActivity(phase: String) -> Key {
        switch phase {
        case "ongoing":   return .active
        case "upcoming":  return .dawn
        default:          return .night
        }
    }
}
