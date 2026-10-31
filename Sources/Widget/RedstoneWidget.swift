import SwiftUI
import WidgetKit

/// 红石桌面小组件（V3.6：卡面与背景整体重做，见 `RedstoneFace.swift`）。
///
/// 这个文件从"画整张卡"退回到**只做装配**，是刻意的：
/// 上一版把版式、底色、剪影、云海全堆在这里，改一处字号要翻 300 行，
/// 而卡面里 90% 的东西（弧 / 节点 / 光点 / 中号场次表）现在都在 `RedstoneFace` 里，
/// 与"组件注册信息"无关。留在本文件的只有三样：
///
/// 1. **kind 与 supportedFamilies**：`kind` 是 WidgetKit 匹配已上桌实例的键，
///    改名等于让所有用户的小组件失效；支持小号与中号两档（中号才有场次表）；
/// 2. **刷新策略的接入口**：`RedstoneProvider`（在 `WidgetProvider.swift`，只读不改）；
/// 3. **整卡点击目标**：`WidgetDeepLink.rock`（`RootView.onOpenURL` 那头解析同一个 URL）。
///
/// 视觉上两条不能破的约束（沿用旧版，且都是"用户能看见"的）：
/// - 倒计时交给系统画：`Text(timerInterval:countsDown:)` 秒级走时但零刷新成本；
/// - 没有数据就说没有：空态只写「暂无排期」，绝不出现 00:00 或假地图名。
struct RedstoneWidget: Widget {

    /// WidgetKit 用 kind 匹配已上桌的实例，改名等于让所有用户的小组件失效
    static let kind = "RedstoneWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RedstoneWidget.kind, provider: RedstoneProvider()) { entry in
            RedstoneWidgetView(entry: entry)
        }
        .configurationDisplayName("红石")
        .description("下一场红石的时刻、地图与倍率，倒计时自动走时。")
        .supportedFamilies([.systemSmall, .systemMedium])
        // 与其它组件一致地关掉系统内容边距：底色渐变必须铺到卡片四边，
        // 默认 16pt 边距会在渐变外围留一圈系统底色，看着像"卡里嵌了一张小卡"。
        .contentMarginsDisabled()
    }
}

/// 小组件入口视图：把 entry 交给卡面，挂上深链与整卡背景。
///
/// 为什么 `containerBackground` 不在 `RedstoneFace` 里做：卡面负责"内容"，
/// 背景要铺满**整个画布**（不受卡面内边距影响），两者职责不同；
/// 而且 `.widgetURL` / `.containerBackground` 属于"组件"这一层，卡面应该是
/// 可以在预览里单独摆出来的纯视图。
struct RedstoneWidgetView: View {

    private let entry: RedstoneEntry

    init(entry: RedstoneEntry) {
        self.entry = entry
    }

    var body: some View {
        RedstoneFace(entry: entry)
            // 整卡可点：点一下跳进 App 的红石页（冷启动 / 热启动都生效，见 RootView.onOpenURL）
            .widgetURL(WidgetDeepLink.rock)
            .containerBackground(for: .widget) {
                // 背景跟着**当前场次的地图**走（不是"今天第一场"，也不是"日历里的地图"）：
                // 卡片上大字写的是哪一场，背景就该是哪一场 —— 否则用户会看到"暮土"配着云野的天。
                // 空态 / 待确认时 mapName 是空串，背景自动退化成默认夜（见 RedstoneBackdrop）。
                RedstoneBackdrop(mapName: entry.focus?.map ?? "")
            }
    }
}
