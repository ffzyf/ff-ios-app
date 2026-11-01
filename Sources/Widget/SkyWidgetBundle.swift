import SwiftUI
import WidgetKit

/// Widget Extension 的入口（**全工程两个 main 属性之一**，另一个是主 App 的入口文件）。
///
/// 为什么两个 main 能共存：它们分属两个 target（`SkyApp` 与 `SkyAppWidget`）。
/// `project.yml` 里给 `SkyApp` 的 `sources` 写了 `excludes: ["Widget"]` ——
/// 这一行是设计文档点名的 R1（漏掉就会出现两个入口 → `duplicate symbol '_main'`），
/// 改动 `project.yml` 时务必先看这一行还在不在。
///
/// 八个组件各自独立（PRD §5.3：不合并成一个可配置组件）：
/// 红石（小）、简报（小/中/大）、红石实时活动、天光（小/中/大 + 锁屏 accessory）、
/// 天光实时活动，以及 3.10.0 的三张天气卡：日弧（小/中 + accessoryRect/Inline）、
/// 月相（小 + accessory 三形态，纯本地天文计算）、风（小 + accessoryRect/Inline）。
///
/// 天光是 V3.5 的新组件，独立于简报：它只画"此刻的天光"，七个阶段各自一套天空配色，
/// 靠 timeline 里排好的阶段边界帧自己轮换（见 `SkyLightWidget` 文件头）。
///
/// 天光实时活动（3.8.0）与红石实时活动**互斥、红石优先**，
/// 让位规则不在这个 target 里 —— Widget 只负责画，
/// `Sources/Services/DaylightActivityCoordinator` 才决定它什么时候出现。
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
