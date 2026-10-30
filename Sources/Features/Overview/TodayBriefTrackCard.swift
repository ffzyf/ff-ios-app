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
struct TodayBriefTrackCard: View {

    let snapshot: BriefSnapshot?
    private let onOpenBrief: () -> Void

    init(snapshot: BriefSnapshot?, onOpenBrief: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onOpenBrief = onOpenBrief
    }

    var body: some View {
        // 1 秒粒度：倒计时里的「秒」要跳字（参考图就是这个观感）
        TimelineView(.periodic(from: .now, by: 1)) { context in
            card(now: context.date)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture {
            Haptics.light()
            onOpenBrief()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开今日简报全文")
    }

    private func card(now: Date) -> some View {
        let phase = SunClock.phase(at: now)
        let sky = Theme.sky(phase)

        return SkyCard(
            phase: phase,
            now: now,
            sunriseText: sunText(snapshot?.sunrise, isSunrise: true, now: now),
            sunsetText: sunText(snapshot?.sunset, isSunrise: false, now: now)
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
                    inkDim: sky.inkDim
                )
            }
        }
    }

    // MARK: - 正文

    /// 服务端 `body` 切成「首句 + 补充行」。切不出来就退到农历 / 生日 / 一句提示。
    private var bodyParts: (headline: String, lines: [String]) {
        var lines: [String] = []

        // 宜忌摘要：简报站原文里最有信息量的一行，且天然适合压在地平线上方
        var ritual: [String] = []
        if let yi = snapshot?.yi, !yi.isEmpty {
            ritual.append("宜 " + yi.prefix(2).joined(separator: "、"))
        }
        if let ji = snapshot?.ji, !ji.isEmpty {
            ritual.append("忌 " + ji.prefix(1).joined(separator: "、"))
        }
        if !ritual.isEmpty {
            lines.append(ritual.joined(separator: " · "))
        }

        guard let raw = snapshot?.body?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            // 正文还没生成：不编内容，只说今天是什么日子
            let fallback = snapshot?.lunar ?? snapshot?.birthday ?? "简报还没生成"
            return ("今日简报", [fallback])
        }

        // 拆首句：中文句读 + 换行都算
        let separators = CharacterSet(charactersIn: "。！？\n")
        if let range = raw.rangeOfCharacter(from: separators) {
            let head = String(raw[raw.startIndex..<range.upperBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(raw[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                lines.insert(tail, at: 0)
            }
            return (head, Array(lines.prefix(2)))
        }
        return (raw, Array(lines.prefix(1)))
    }

    // MARK: - 文案

    private var dateLine: String {
        let title = Formatters.dayTitle(dayKey)
        let weekday = Formatters.weekdayLabel(dayKey: dayKey)
        if let lunar = snapshot?.lunar, !lunar.isEmpty {
            return title + " " + weekday + " · " + lunar
        }
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
