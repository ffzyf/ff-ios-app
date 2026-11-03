import SwiftUI
import Foundation

/// 概览页的「每日简报」卡 —— V3.2 改成**天际线**（照参考图）。
///
/// 版式：
/// ```
/// ┌──────────────────────────────────┐
/// │ ● 日出                     2分钟4秒 │  ← 时段 + 倒计时（天色自己算）
/// │ 10月31日 周六 · 农历九月十二        │
/// │ 今天风速偏大，记得添件外套…          │  ← 简报正文（服务端 body 的首句/续文）
/// │ 宜 晒被、散步 · 已推送 07:03        │
/// │                                  │
/// │ ╭──────── 地平线 ────────╮        │  ← 弧线以下转暗色地面
/// │ 06:05                    18:13    │
/// └──────────────────────────────────┘
/// ```
///
/// 天色按**当地时间**在七档之间切换（`SunClock`），所以同一张卡早上是橙、白天是蓝、
/// 傍晚是红、夜里是深靛 —— 不需要用户手动换。
///
/// 正文只给 1 句 + 1 行补充：卡片不是阅读页，全文点进简报 Tab 看。
///
/// ## 3.11.0：点击目标改成"天光页"
///
/// 用户原话："概览-第二个小组件可以点击今日"。所以整卡点击不再切到简报 Tab，
/// 而是全屏打开沉浸式天光页（`SkyRoomView`）—— 这张卡本来就是一整片天空，
/// 点进去看到"更大的同一片天"才是它该有的去向；简报全文仍可从 Tab 栏进。
struct TodayBriefTrackCard: View {

    /// 首页这张是 `.medium`（窄档 168 / 宽档仍是 168，宽档靠外层 `maxHeight: .infinity` 拉到 172）
    @Environment(\.layoutMetrics) private var metrics

    let snapshot: BriefSnapshot?
    /// 点击整卡 → 打开天光页。由 `OverviewView` 注入（页面自己持有弹出状态，
    /// 卡片只发信号 —— 组件永远不决定"要用什么方式呈现下一页"）。
    private let onOpenSky: () -> Void

    init(snapshot: BriefSnapshot?, onOpenSky: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onOpenSky = onOpenSky
    }

    var body: some View {
        // 1 秒粒度：倒计时里的「秒」要跳字（参考图就是这个观感）
        TimelineView(.periodic(from: .now, by: 1)) { context in
            card(now: context.date)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture {
            Haptics.light()
            onOpenSky()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开今日天光")
        // 伪 3D 倾斜挂最外层（§3.4：不能塞进 SkyCard 内部），iPad 生效、iPhone 完全不挂载
        .cardTilt(cornerRadius: Radius.card)
    }

    private func card(now: Date) -> some View {
        // 3.22.0：与天光页同一套门控 —— 这张卡的右上角也写着「黄金时刻」，
        // 只修天光页的话，用户回到首页还是看到同一句话。天气读单例：
        // 本卡没有自己的天气数据源，而 `WeatherStore` 是全 App 唯一那一份实况。
        //
        // 判定只算一次、两处用：`phase` 要吃它（黄金时刻 → 白天），
        // 左上角那个词还要吃它（阴天的「蓝调剩余」→「入夜剩余」）。分开各调一次
        // `verdict(...)` 也没错，但那等于让同一次观测被解释两遍 ——
        // 一处改了阈值，另一个出口就悄悄漂了。
        let viewing = SkyViewing.verdict(of: WeatherStore.shared.current)
        let phase = SunClock.phase(at: now).effective(viewing: viewing)
        let sky = Theme.sky(phase)

        return SkyCard(
            phase: phase,
            now: now,
            sunriseText: sunText(snapshot?.sunrise, isSunrise: true, now: now),
            sunsetText: sunText(snapshot?.sunset, isSunrise: false, now: now),
            // 词在这里定型：判定只有 `SkyViewing.swift` 一处，`SkyCard` 只负责画。
            // 卡片自己持有 `viewing` 就等于持有"我该怎么判"的知识 —— 下一个调用方
            // 忘了传，就会静默退回那句承诺颜色的假话。
            phaseLabel: phase.label(viewing: viewing),
            note: ritualText,
            // 首页的是**摘要卡**（168），简报页才是 hero —— 同一份数据两页分饰两角，
            // 不能是"一样高的两张卡"（设计报告 §4.3）。
            // 宽档这里仍是 168（`CardTier.medium.wideHeight` 没动）：它在 Row A 右栏里是
            // 192pt 高的那一格，多出来的高度由 `maxHeight: .infinity` 拉伸，不是靠改 `minHeight`。
            minHeight: metrics.cardHeight(.medium)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(dateLine)
                        .font(Typography.captionXS)
                        .foregroundStyle(sky.inkDim)
                        .monospacedDigit()
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(pushText)
                        .font(Typography.captionXS)
                        .foregroundStyle(sky.inkDim)
                        .lineLimit(1)
                }

                SkyCardBody(
                    title: bodyParts.headline,
                    lines: bodyParts.lines,
                    ink: sky.ink,
                    inkDim: sky.inkDim,
                    // 卡内最大字号 ≥20pt（设计报告 R6）：17pt 的小卡撑不起"这是今天的正事"
                    titleFont: Typography.titleM,
                    // 续文只给**一行**（3.27.0 修「和红石卡不等高」）。
                    //
                    // 这张卡的版式本来就是「1 句 + 1 行补充」（见文件头的版式图），
                    // 可 12pt 正文在 321pt 的可用宽里常常把那一行折成两行 ——
                    // 卡片自然高度从约 144 涨到 181，而它上面的红石卡是 168，
                    // 用户要的"跟下面那个天气一样大"当天就失效。
                    //
                    // 为什么不改成"卡片跟着长高"：那一对卡的等高是**栅格给的**
                    // （两张都是 `.medium` = 168），让其中一张跟着内容浮动，
                    // 等于把版式交回给"这一天的简报长不长"这种每天都会变的东西。
                    // 摘要卡不是阅读页：多出来的半句在简报 Tab 里读全文。
                    bodyLineLimit: 1
                )
            }
        }
    }

    // MARK: - 正文

    /// 宜 / 忌：放在地平线以下的那行注脚。
    ///
    /// 简报站原文里信息密度最高的一行，但它属于"历书"，不是正文 ——
    /// 塞进天空区会被地平线亮边切开，所以走 SkyCard 的 `note` 位。
    private var ritualText: String? {
        var parts: [String] = []
        if let lunar = snapshot?.lunar, !lunar.isEmpty {
            parts.append(lunar)
        }
        if let yi = snapshot?.yi, !yi.isEmpty {
            parts.append("宜 " + yi.prefix(2).joined(separator: "、"))
        }
        if let ji = snapshot?.ji, !ji.isEmpty {
            parts.append("忌 " + ji.prefix(1).joined(separator: "、"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 服务端 `body` 切成「首句 + 一行续文」。
    ///
    /// **坑**：`body` 不是纯正文，而是带 emoji 小标题的分段文本 ——
    /// 形如 `🗓 每日简报` / `🎁 距离生日还有 252 天` / 正文若干段。
    /// 直接取第一句会拿到"栏目头"当标题（上一版卡片上就出现了这两行）。
    /// 所以先按行过滤掉栏目头，剩下的才是真正要展示的内容。
    ///
    /// 只给一行续文是硬约束：天空区到地平线只有这么多高度，多一行就会压线。
    private var bodyParts: (headline: String, lines: [String]) {
        guard let raw = snapshot?.body?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            let fallback = snapshot?.lunar ?? "简报还没生成"
            return ("今日简报", [fallback])
        }

        let rows = raw.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !Self.isHeading($0) }

        guard let first = rows.first else {
            return ("今日简报", [snapshot?.lunar ?? "简报还没生成"])
        }

        // 首行本身可能还带着两句，按句读切开，第二句降级为续文
        let separators = CharacterSet(charactersIn: "。！？")
        var headline = first
        var tail: String?
        if let range = first.rangeOfCharacter(from: separators) {
            headline = String(first[first.startIndex..<range.upperBound])
            let rest = String(first[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { tail = rest }
        }

        var lines: [String] = []
        if let tail { lines.append(tail) }
        if lines.isEmpty {
            for row in rows.dropFirst() where lines.count < 1 {
                lines.append(row)
            }
            if lines.isEmpty, let next = rows.dropFirst().first {
                lines.append(next)
            }
        }
        return (headline, Array(lines.prefix(1)))
    }

    /// 判断某一行是不是"栏目头"：emoji 开头，或短到不可能是一句话
    private static func isHeading(_ line: String) -> Bool {
        if let scalar = line.unicodeScalars.first, scalar.properties.isEmojiPresentation {
            return true
        }
        // 短、且没有任何句读 → 当标题处理（"每日简报" 会命中，"早安。" 不会）
        let hasPunctuation = line.contains("，") || line.contains("。")
            || line.contains("！") || line.contains("？") || line.contains("、")
        return line.count <= 6 && !hasPunctuation
    }

    // MARK: - 文案

    private var dateLine: String {
        let title = Formatters.dayTitle(dayKey)
        let weekday = Formatters.weekdayLabel(dayKey: dayKey)
        return title + " " + weekday
    }

    /// 日出 / 日落：优先用服务端给的值（它按当地算过，比 App 自己算的更准），
    /// 缺了才回落到 `SunClock`
    private func sunText(_ raw: String?, isSunrise: Bool, now: Date) -> String {
        if let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }
        guard let times = SunClock.times(on: now) else { return "—" }
        return Formatters.timeHHmm(isSunrise ? times.sunrise : times.sunset)
    }

    /// 推送状态：推送过给时刻，没推送过明确说没推送（不写"未知"）
    private var pushText: String {
        guard let snapshot else { return "还没有简报" }
        if snapshot.pushedToday {
            if let pushedAt = snapshot.pushedAt {
                return "已推送 " + Formatters.timeHHmm(pushedAt)
            }
            return "已推送"
        }
        return "今日未推送"
    }

    /// 简报的日期键：服务端给的优先，缺省用「今天（北京）」
    private var dayKey: String {
        if let date = snapshot?.date, !date.isEmpty {
            return date
        }
        return RedstoneClock.dayKey(Date())
    }
}
