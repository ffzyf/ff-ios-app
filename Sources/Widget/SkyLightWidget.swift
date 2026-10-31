import SwiftUI
import WidgetKit

/// 天光（SkyLight）—— 独立小组件：桌面上一块**自己会换**的天色。
///
/// 用户原话："再给我单独开一个小组件……只要有变化，比如太阳落了它就自己轮换"。
/// 所以它和简报卡是**两个组件**，不是给简报加一套皮肤：
/// 简报讲"今天有什么事"，天光只讲"此刻的天光到哪一档了"。合在一起，
/// 想看简报的人会被倒计时干扰，想看天色的人得读一整段正文。
///
/// 版式照参考图（六张图版式完全一致，只有配色和文字在变）：
/// ```
/// ● 蓝调剩余                2分钟4秒
///
///      （天空渐变 + 有厚度的地平线弧 + 太阳光点）
///
/// 06:05                        18:13
/// ```
///
/// ## "自己轮换"是怎么做到的
/// 不是靠定时器，也不是靠用户手动切：`SkyLightProvider` 把所有**阶段边界时刻**
/// 连同 15 分钟网格一起排进 timeline，WidgetKit 到点就换上那一帧。
/// 七个阶段（夜间 / 晨间蓝调 / 日出 / 黄金 / 白天 / 日落 / 暮间蓝调）各自对应
/// `Theme.sky(phase)` 里逐档手调的一整套天空配色 —— 太阳一落，卡片自己就变。
///
/// ## 约束
/// - 只编译 `Sources/Widget` + `Sources/Shared`：不引用 `Typography` / `Radius` /
///   `Spacing` / `SkyCard`（那些在 DesignSystem，Widget target 里不存在）；
/// - 颜色一律 `Theme.sky(phase)`，本组件没有任何颜色字面量；
/// - 不新增 target、不改 `project.yml` —— 注册进 `SkyWidgetBundle` 即可。
struct SkyLightWidget: Widget {

    /// WidgetKit 用 kind 匹配已上桌的实例，改名等于让所有用户的小组件失效
    static let kind = WidgetTheme.SkyLight.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SkyLightWidget.kind, provider: SkyLightProvider()) { entry in
            SkyLightFace(entry: entry)
        }
        .configurationDisplayName(WidgetTheme.SkyLight.displayName)
        .description(WidgetTheme.SkyLight.description)
        // 小号放"阶段名 + 倒计时 + 地平线 + 太阳 + 两个时刻"（字号降一档、仍在安全区内）；
        // 大号是参考图的完整版式。不支持大号：把这张版式拉成 4×2 只会让天空变空。
        .supportedFamilies([.systemSmall, .systemMedium])
        // 关掉系统默认边距：天空与地面必须铺到卡片四边，否则外围会留一圈底色，
        // 看起来像"卡里又嵌了一张卡"。内边距由 `SkyLightFace` 自己给。
        .contentMarginsDisabled()
    }
}
