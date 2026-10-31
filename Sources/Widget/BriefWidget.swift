import Foundation
import SwiftUI
import WidgetKit

/// 每日简报桌面小组件（V3.6：从「天空」换成「纸面 + 轨道」；V3.7：纸面按当天天气换氛围）。
///
/// 用户原话："现在我这里有两个天际线的效果小组件。你从里面找一张好看的，重新设计一个吧，
/// 要不然两个一模一样的小组件看着有点烦" —— 上一版简报和天光（`SkyLightWidget`）
/// 都在画天空渐变 + 地平线弧 + 太阳，摆在同一屏上就是两块几乎一样的图。
/// 天光那套是用户自己挑的参考（阶段 + 倒计时），**一行不动**；改的是这张卡：
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │ 10月31日 周六                     简报   │
/// │ 每日简报                                 │
/// │ 今天的第一句正文，最多 2 行，超出截断……    │
/// │  · · · · · · · · ● · · · · · · · · ·     │ ← 点线轨迹 + 今日进度光点
/// │ 宜 打猎          忌 店铺开业   06:44 17:33│
/// └─────────────────────────────────────────┘
/// ```
///
/// V3.7 追加的一条：**卡片的氛围跟着当天的真实天气走**（用户原话"把拉到的天气对应放到
/// 对应的效果上"）—— 晴是暖褐 + 暖金光，阴是冷灰 + 三朵云，雨是深蓝 + 20 条斜雨丝，
/// 雷是近黑紫 + 一道闪电。八档见 `Theme.Weather`（氛围色）与 `BriefFace`（粒子画法）；
/// 天气数据由 `BriefProvider.getTimeline` 与简报**并发**拉取（`GET /api/app/weather`，
/// 匿名可读、不需要 App Group），拉失败就是 `nil`，卡片退回无天气形态。
///
/// 视觉全部在 `BriefFace.swift`（底色 / 字号 / 轨迹 / 天气粒子 / 兜底文案）。
/// 本文件只剩三件事：注册 kind、声明尺寸、把 entry 交给卡面 ——
/// 天气请求在 `WidgetProvider.swift` 的 `BriefProvider` 里（timeline 是 Provider 的活，
/// 不是 Widget 声明的活，别来这里找）。
///
/// 三条不能破的规矩：
/// 1. **没有的字段整行不画**（宜忌为空就不画注脚、日出算不出就不画时刻），
///    不显示 `--`、不显示"未知"，更不编一句"今日宜出行"；同理**没有天气就不画粒子**；
/// 2. 整卡可点，落到 `skyapp://brief`（深链三处契约见 `WidgetDeepLink`）；
/// 3. 颜色只走 `Theme` token，Widget 里一个颜色字面量都没有。
struct BriefWidget: Widget {

    static let kind = "BriefWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: BriefWidget.kind, provider: BriefProvider()) { entry in
            BriefFace(entry: entry)
        }
        .configurationDisplayName("每日简报")
        .description("每天一份：日期、首句，以及今日进度、宜忌与日出日落。")
        // 小号（158×158）只留「日期 + 每日简报 + 正文 1 行 + 轨迹」；
        // 中号（338×158）是完整版式，多出宜忌与日出日落。两种尺寸共用同一个卡面
        // （`BriefFace` 按 `widgetFamily` 收版式），不拆两个 View —— 拆开必然会有两套字号。
        .supportedFamilies([.systemSmall, .systemMedium])
        // 关掉系统默认内容边距：底色要**通到卡片四边**，默认的 16pt 边距会在纸面外面
        // 留一圈系统色，看起来像"卡里又嵌了一张卡"。边距改由 `BriefFace` 自己给
        // （中号 14 / 12，小号 11 / 12），比默认更紧凑，适合 158pt 高的画布。
        .contentMarginsDisabled()
    }
}
