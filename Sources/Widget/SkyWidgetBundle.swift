import SwiftUI
import WidgetKit

/// Widget Extension 的入口（**全工程两个 main 属性之一**，另一个是主 App 的入口文件）。
///
/// 为什么两个 main 能共存：它们分属两个 target（`SkyApp` 与 `SkyAppWidget`）。
/// `project.yml` 里给 `SkyApp` 的 `sources` 写了 `excludes: ["Widget"]` ——
/// 这一行是设计文档点名的 R1（漏掉就会出现两个入口 → `duplicate symbol '_main'`），
/// 改动 `project.yml` 时务必先看这一行还在不在。
///
/// 八个组件各自独立（PRD §5.3：不合并成一个可配置组件），尺寸表如下
///（3.12.0 全员补齐大号 —— 用户原话"每日简报大的小组件因为它大也可以显示更多内容啊，
/// 把内容显出来啊。当然其他的小组件也是以此类推"）：
///
/// | 组件 | 桌面档 | 锁屏档 |
/// |---|---|---|
/// | 红石 `RedstoneWidget` | 小 / 中 / **大**（hero 倒计时 + 本周排期） | — |
/// | 简报 `BriefWidget` | 小 / 中 / 大（大号：5 行正文 + 宜忌 chips + 加大天气块） | — |
/// | 天光 `SkyLightWidget` | 小 / 中 / 大（大号：更大的天 + 今日天气摘要） | rect / inline |
/// | 日弧 `SunArcWidget` | 小 / 中 / **大**（大号：长弧 + 今日天气一句） | rect / inline |
/// | 月相 `MoonPhaseWidget` | 小 / **大**（大号：月盘 148pt + 下次满月） | 三形态 |
/// | 风 `WindWidget` | 小 / **大**（大号：56pt 风速 + 风力刻度） | rect / inline |
/// | 红石实时活动 / 天光实时活动 | —（ActivityKit） | — |
///
/// 天光是 V3.5 的新组件，独立于简报：它只画"此刻的天光"，七个阶段各自一套天空配色，
/// 靠 timeline 里排好的阶段边界帧自己轮换（见 `SkyLightWidget` 文件头）。
///
/// 天光实时活动（3.8.0）与红石实时活动**互斥、红石优先**，
/// 让位规则不在这个 target 里 —— Widget 只负责画，
/// `Sources/Services/DaylightActivityCoordinator` 才决定它什么时候出现。
///
/// **注册表本身只增不减**：重复注册不会报错、只会让组件库出现两份；
/// 漏注册则是"这个组件彻底不存在"。所以在 `body` 里一一对应地列出来，
/// 每次改动都对着上面的表点一遍名。
@main
struct SkyWidgetBundle: WidgetBundle {

    var body: some Widget {
        RedstoneWidget()
        BriefWidget()
        SunEventLiveActivity()
        DaylightLiveActivity()
        SkyLightWidget()
        // 3.10.0 三张天气卡（参考图风格：单色系强渐变底 + 辉光 + 顶行标签/值 + 底部上下文）
        SunArcWidget()
        MoonPhaseWidget()
        WindWidget()
    }
}
