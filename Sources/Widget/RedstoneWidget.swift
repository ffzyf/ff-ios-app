import SwiftUI
import WidgetKit

/// 红石桌面小组件（V3.11：**小 / 中 / 大三档**，三套版式，见 `RedstoneFace.swift`）。
///
/// 这个文件从"画整张卡"退回到**只做装配**，是刻意的：
/// 上一版把版式、底色、剪影、云海全堆在这里，改一处字号要翻 300 行，
/// 而卡面里 90% 的东西（弧 / 节点 / 光点）现在都在 `RedstoneFace` 里，
/// 与"组件注册信息"无关。留在本文件的只有三样：
///
/// 1. **kind 与 supportedFamilies**：`kind` 是 WidgetKit 匹配已上桌实例的键，
///    改名等于让所有用户的小组件失效。3.11.0 起恢复 `.systemMedium` 并新增
///    `.systemLarge` —— 用户原话"红石的小组件咋只有一个"（V3.7 曾按另一条反馈
///    只留正方形）。三个尺寸是**三套版式**，不是把正方形拉宽拉高：
///    中号横排（左倒计时 / 右收益·规律·今日）、大号上方 hero + 下方本周排期，
///    分档由 `RedstoneFace` 里的 `@Environment(\.widgetFamily)` 决定（DESIGN-RULES §3）；
/// 2. **刷新策略的接入口**：`RedstoneProvider`（在 `WidgetProvider.swift`，只读不改）；
/// 3. **整卡点击目标**：`WidgetDeepLink.rock`（`RootView.onOpenURL` 那头解析同一个 URL）。
///
/// 视觉上三条不能破的约束（沿用旧版，且都是"用户能看见"的）：
/// - 倒计时交给系统画：`Text(timerInterval:countsDown:)` 秒级走时但零刷新成本；
/// - 没有数据就说没有：空窗期整卡切换为天光卡面（见 `RedstoneWidgetView`），
///   RedstoneFace 内部的空态 / 收官文案只作为兜底，绝不出现 00:00 或假地图名；
/// - **本月过完了就说收官**：排期有、只是这个月的都过完了，同样交给天光面 ——
///   用户不需要一张"挂着红石但什么都没有"的卡（3.8.1 用户反馈）。
struct RedstoneWidget: Widget {

    /// WidgetKit 用 kind 匹配已上桌的实例，改名等于让所有用户的小组件失效
    static let kind = "RedstoneWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RedstoneWidget.kind, provider: RedstoneProvider()) { entry in
            RedstoneWidgetView(entry: entry)
        }
        .configurationDisplayName("红石")
        .description("下一场红石的时刻、地图与倍率，倒计时自动走时。")
        // 三个尺寸，一套数据三种版式（`RedstoneFace.body` 按 family 分派）：
        // - 小号 158×158：地图名 + 主时刻 + 时间轴弧 + 倒计时（版式一字未改）；
        // - 中号 338×158：左栏 30pt 主时刻与倒计时，右栏收益 / 规律 / 今日场次
        //   （"今天还有几场"从中号退役后曾挤回小号倒计时行，现在回到它该在的地方）；
        // - 大号 338×354：52pt hero 主时刻 + 本周排期 3–4 行（`RedstoneEntry.weekRows`）。
        // 空窗期（无场次 / 本月收官）三档都整卡换成天光面，见 `RedstoneWidgetView`。
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
///
/// ## 空窗期整卡换天光面（3.8.1）
///
/// 用户原话："如果说这几天是红石的空窗期它应该显示其他的内容啊不应该一直挂个红石"。
/// 所以 `focus == nil`（暂无排期 / 本月已收官）的日子，整卡切换为天光卡面
/// （`SkyLightFace`，吃 Provider 顺带算好的 `entry.daylight`，见 `RedstoneEntry`），
/// 深链也跟着换成 `WidgetDeepLink.sky` —— 卡上说的已经是天光，点进去就该是天光页
/// （3.11.0 起全工程的天光 / 日弧 / 月相 / 风 四张卡统一指向沉浸式天光页 `SkyRoomView`）。
/// **同日有场次则一切不变**：红石卡面 + `skyapp://rock`。
struct RedstoneWidgetView: View {

    private let entry: RedstoneEntry

    init(entry: RedstoneEntry) {
        self.entry = entry
    }

    var body: some View {
        Group {
            if entry.focus == nil, let daylight = entry.daylight {
                SkyLightFace(entry: daylight)
                    // 卡面是天光，点击目标跟着换成天光页（不是简报表）。
                    // 与 `SkyLightFace` 内部那条 `.widgetURL(WidgetDeepLink.sky)` 值相同、
                    // 互为兜底：将来谁改了一处，另一处仍是同一个落点。
                    .widgetURL(WidgetDeepLink.sky)
            } else {
                RedstoneFace(entry: entry)
                    // 整卡可点：点一下跳进 App 的红石页（冷启动 / 热启动都生效，见 RootView.onOpenURL）
                    .widgetURL(WidgetDeepLink.rock)
                    .containerBackground(for: .widget) {
                        // 背景跟着**当前场次的地图**走（不是"今天第一场"，也不是"日历里的地图"）：
                        // 卡片上大字写的是哪一场，背景就该是哪一场 —— 否则用户会看到"暮土"配着云野的天。
                        // 空态 / 待确认时 mapName 是空串，背景自动退化成默认夜（见 RedstoneBackdrop）；
                        // 收官态 focus 为 nil，同样走默认夜（不拿"本月上一场"的地图去配一个没有场的日子）。
                        RedstoneBackdrop(mapName: entry.focus?.map ?? "")
                    }
            }
        }
    }
}
