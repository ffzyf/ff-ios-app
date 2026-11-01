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
///
/// ## 天气是叠加层（V3.5）
/// 用户要的是"在它原有之上，再添加一种天气效果"，所以本文件的配置**一个字都不改**
/// （kind / displayName / supportedFamilies / contentMarginsDisabled 全部照旧）——
/// 天气不改变这张卡的形态，只改变背景层里多画了点什么：
///
/// ```
/// SkyLightProvider.getTimeline   ← 唯一一次网络请求（/api/app/weather，8 秒超时）
///        ↓ 同一个 WeatherNow 发给这一轮全部 ~103 帧（半小时内天气不会变）
/// SkyLightEntry.weather
///        ↓
/// SkyLightSky.body 的第 ③ 层（云）与第 ⑥ 层（雨 / 雪 / 雾 / 闪电）
/// ```
///
/// 拉失败或后端没给代码 → `weather == nil` → 这两层整块不画，卡片与升级前完全相同。
/// **绝不兜底成晴天**：把缺数据画成晴天，等于骗人（`WeatherKind.from(code:)` 的注释里
/// 记着这个项目已经踩过一次的坑）。
struct SkyLightWidget: Widget {

    /// WidgetKit 用 kind 匹配已上桌的实例，改名等于让所有用户的小组件失效
    static let kind = WidgetTheme.SkyLight.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SkyLightWidget.kind, provider: SkyLightProvider()) { entry in
            SkyLightFace(entry: entry)
        }
        .configurationDisplayName(WidgetTheme.SkyLight.displayName)
        .description(WidgetTheme.SkyLight.description)
        // 家族表（#8 审计，3.10.0）：
        // - systemSmall / systemMedium：既有两档（字号已按画布调校）；
        // - systemLarge：版式是"上文字 + 满屏天空 + 下时刻"的三段式，画布变高由
        //   Spacer 吸收、天空本来就以"整块天"为主体 —— Large 恰是这张卡最舒展的形态；
        // - accessoryRectangular / accessoryInline：天光加锁屏紧凑形态（参考图的
        //   "紧凑一行"），走 `SkyLightFace` 的极简分支；
        // - 不加 accessoryCircular：环形里"阶段名 + 倒计时 + 两个时刻"任何一项的
        //   可读形态都放不下，硬塞是不可读的噪点。
        .supportedFamilies([.systemSmall,
                            .systemMedium,
                            .systemLarge,
                            .accessoryRectangular,
                            .accessoryInline])
        // 关掉系统默认边距：天空与地面必须铺到卡片四边，否则外围会留一圈底色，
        // 看起来像"卡里又嵌了一张卡"。内边距由 `SkyLightFace` 自己给。
        .contentMarginsDisabled()
    }
}
