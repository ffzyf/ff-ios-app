import Foundation
import SwiftUI
import WidgetKit

/// 简报桌面小组件（V3.3：与 App 内简报卡同一套「天际线」语言）。
///
/// 用户原话："小组件样式只在 App 下面看见了，小组件还没有" —— 上一版这张卡还是
/// 「浅蓝底 + 一条弧线 + 一堆 emoji 小字」，而 App 内的简报卡早就改成了随当地时间变色的
/// 天空 + 地平线 + 地面。这次把小组件补齐到同一套语言。
///
/// 版式（systemMedium 338×158，四块各就各位，没有元素"飘"在天上）：
/// ```
/// ┌─────────────────────────────────────┐
/// │ 10月31日 周六              [简报]    │  ← 顶行：日期 + 胶囊标签
/// │ 每日简报                             │  ← 标题（20pt bold）
/// │ 今天的第一句简报正文，最多两行……      │  ← 正文，压在天空区
/// │ ～～～～～～ 地平线 ～～～～～～       │  ← 天色在这里由亮转暗
/// │ 宜 打猎、散步 · 忌 店铺开业  06:44 17:33 │  ← 地面区：注脚 + 日出日落
/// └─────────────────────────────────────┘
/// ```
///
/// 三条不能破的规矩：
/// 1. **没有的字段整行不画**（宜忌为空就不画注脚、日出算不出就不画时刻），
///    不显示 `--`、不显示"未知"，更不编一句"今日宜出行"；
/// 2. 整卡可点，落到 `skyapp://brief`（深链三处契约见 `WidgetDeepLink`）；
/// 3. 天色只走 `Theme.sky(phase)`，Widget 里一个颜色字面量都没有。
struct BriefWidget: Widget {

    static let kind = "BriefWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: BriefWidget.kind, provider: BriefProvider()) { entry in
            BriefWidgetView(entry: entry)
        }
        .configurationDisplayName("今日简报")
        .description("每天一份：日期、首句，以及宜忌与日出日落。")
        .supportedFamilies([.systemMedium])
        // 关掉系统默认内容边距：这张卡的天空要**通到卡片四边**（和 App 内那张卡一样），
        // 默认的 16pt 边距会在天空外面留一圈底色，地平线就不贴边了。
        // 边距改由 `BriefWidgetView` 自己给（14 / 12），值比默认更紧凑，适合 158pt 高的画布。
        .contentMarginsDisabled()
    }
}

/// 简报小组件视图
struct BriefWidgetView: View {

    private let entry: BriefEntry

    init(entry: BriefEntry) {
        self.entry = entry
    }

    /// 这一帧（entry.date）属于哪一档天色。
    ///
    /// 为什么用 `entry.date` 而不是 `Date()`：entry 的 `date` 就是"这一条被渲染的时刻"，
    /// 它是 Timeline 预渲染的；渲染时现取 `Date()` 会让预渲染的帧与真实显示错位
    /// （典型症状：卡片上的天色比桌面上其它小组件慢一拍）。
    private var phase: SkyPhase {
        return SunClock.phase(at: entry.date)
    }

    /// 此刻的天空五段色（物理色，不随 App 深浅外观变）
    private var sky: Theme.SkyColors {
        return Theme.sky(phase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            titleRow
                .padding(.top, 6)
            bodyRow
                .padding(.top, 4)
            // 唯一的弹性留白：把地面区那一行钉在卡片底部（地平线以下），
            // 中间所有间距都用固定 PT —— 内容多少不会把正文推过地平线。
            Spacer(minLength: 0)
            groundRow
        }
        .padding(.horizontal, WidgetTheme.skySidePadding)
        .padding(.vertical, WidgetTheme.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 整卡可点：点一下跳进 App 的简报页（冷启动 / 热启动都生效，见 RootView.onOpenURL）
        .widgetURL(WidgetDeepLink.brief)
        .containerBackground(for: .widget) {
            // `date:` 是 V3.4 的「实时太阳」—— 天空里那颗太阳按 `entry.date` 算位置，
            // 所以预渲染的那一帧和卡片上的时间永远是同一个时刻（见 `SunClock.sunMark`）。
            WidgetSkyBackdrop(phase: phase,
                              crestY: WidgetTheme.skyCrestY,
                              edgeY: WidgetTheme.skyEdgeY,
                              date: entry.date)
        }
    }

    // MARK: - 顶行：日期 · 星期 · 胶囊标签

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text(entry.dateText)
                .font(WidgetTheme.skyDate)
                .foregroundStyle(sky.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if !entry.weekdayText.isEmpty {
                Text(entry.weekdayText)
                    .font(WidgetTheme.statusSecondary)
                    .foregroundStyle(sky.inkDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // 胶囊标签：面用天色 token（edge），字用 ink —— 深色天空与白天亮天空上都读得清。
            // 这里不许用 `Theme.lime` 当面：青柠是品牌色，压在橙红色的日落天空上会打架。
            Text("简报")
                .font(WidgetTheme.label)
                .foregroundStyle(sky.ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background {
                    Capsule().fill(sky.edge.opacity(0.22))
                }
                .overlay {
                    Capsule().strokeBorder(sky.edge.opacity(0.50), lineWidth: 0.7)
                }
        }
    }

    // MARK: - 标题

    private var titleRow: some View {
        Text("每日简报")
            .font(WidgetTheme.briefBig)
            .foregroundStyle(sky.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 正文（压在天空区，最多 2 行）

    @ViewBuilder
    private var bodyRow: some View {
        if let text = bodyText {
            Text(text)
                .font(WidgetTheme.briefBody)
                .foregroundStyle(sky.inkDim)
                .lineLimit(2)
                .lineSpacing(1.5)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // 早上简报还没生成是**正常业务状态**，不是错误：说清楚"还没有"，不吓人、不编内容
            Text("今天还没有简报")
                .font(WidgetTheme.briefBody)
                .foregroundStyle(sky.inkDim)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 首句正文。
    ///
    /// 服务端 `body` 不是纯正文，而是带 emoji 小标题的分段文本（`🗓 每日简报` /
    /// `🎁 距离生日还有 253 天` / 正文若干段）。直接取第一行会把"栏目头"当正文显示，
    /// 所以先按行拆开、滤掉栏目头，剩下的第一行才是"今天的第一句"。
    /// 这段启发式与 App 内 `TodayBriefTrackCard.bodyParts` 同一套判据（emoji 开头 / 过短无句读）。
    private var bodyText: String? {
        let rows = entry.paragraphs
            .joined(separator: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !Self.isHeading($0) }
        return rows.first
    }

    /// 判断某一行是不是"栏目头"：emoji 开头，或短到不可能是一句话
    private static func isHeading(_ line: String) -> Bool {
        if let scalar = line.unicodeScalars.first, scalar.properties.isEmojiPresentation {
            return true
        }
        let hasPunctuation = line.contains("，") || line.contains("。")
            || line.contains("！") || line.contains("？") || line.contains("、")
        return line.count <= 6 && !hasPunctuation
    }

    // MARK: - 地面区：注脚 + 日出日落

    /// 地平线以下那一行。
    ///
    /// 左侧是宜忌（`BriefEntry.ritualText`，没数据就整段不画），
    /// 右侧是日出 / 日落（服务端值优先，缺了用 `SunClock` 现算，两头都没有就不画）。
    /// 两段都空时这一行虽然存在但什么都不显示 —— 比画一行 `-- --` 诚实。
    private var groundRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let note = entry.ritualText {
                Text(note)
                    .font(WidgetTheme.skyNote)
                    .foregroundStyle(sky.inkDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
            }

            Spacer(minLength: 4)

            if let rise = sunTexts.rise {
                Text(rise)
                    .font(WidgetTheme.sunTime)
                    .foregroundStyle(sky.inkDim)
                    .monospacedDigit()
            }
            if let set = sunTexts.set {
                Text(set)
                    .font(WidgetTheme.sunTime)
                    .foregroundStyle(sky.inkDim)
                    .monospacedDigit()
                    .padding(.leading, 2)
            }
        }
    }

    /// 日出 / 日落文案（服务端值优先，缺了回落 `SunClock`，两头都没有就是 nil）
    private var sunTexts: (rise: String?, set: String?) {
        return entry.sunTexts()
    }
}
