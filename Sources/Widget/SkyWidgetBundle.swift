import SwiftUI
import WidgetKit

/// Widget Extension 的入口（**全工程两个 main 属性之一**，另一个是 `Sources/App/FFWangApp.swift`）。
///
/// 为什么两个 main 能共存：它们分属两个 target（`SkyApp` 与 `SkyAppWidget`）。
/// `project.yml` 里给 `SkyApp` 的 `sources` 写了 `excludes: ["Widget"]` ——
/// 这一行是设计文档点名的 R1（漏掉就会出现两个入口 → `duplicate symbol '_main'`），
/// 改动 `project.yml` 时务必先看这一行还在不在。
///
/// 三个组件各自独立（PRD §5.3：不合并成一个可配置组件）：
/// 红石（小/中）、简报（中）、红石实时活动。
@main
struct SkyWidgetBundle: WidgetBundle {

    var body: some Widget {
        RedstoneWidget()
        BriefWidget()
        SunEventLiveActivity()
    }
}
