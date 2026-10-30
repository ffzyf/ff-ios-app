import SwiftUI
import WidgetKit

/// 红石桌面小组件（PRD §5.3：小号 + 中号）。
///
/// 字段规格逐条照做：
/// 小号 4 行 —— 「红石」标签 + 倍率徽标 / 地图名（最多 2 行）/ 场次时刻（大字）/ 倒计时；
/// 中号 —— 左半与小号完全一致（地图名完整显示），右半今日剩余场次列表（≤3 行，已过场次 30% 灰），
/// 右上「今日 3 场」或「待核对」徽标。
///
/// 两条不能破的约束：
/// 1. **倒计时交给系统画**：`Text(timerInterval:countsDown:)` 秒级走时，但一次刷新都不花；
/// 2. **没有数据就说没有**：`hasData == false` 时只画「暂无排期」，
///    绝不出现 `00:00` 或凭空编造的地图（PRD 验收第 4 条）。
struct RedstoneWidget: Widget {

    /// WidgetKit 用 kind 匹配已上桌的实例，改名等于让所有用户的小组件失效
    static let kind = "RedstoneWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RedstoneWidget.kind, provider: RedstoneProvider()) { entry in
            RedstoneWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetTheme.containerBackground()
                }
        }
        .configurationDisplayName("红石")
        .description("下一场红石的时刻、地图与倍率，倒计时自动走时。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// 小号 / 中号共用的视图（按 `widgetFamily` 分派）。
struct RedstoneWidgetView: View {

    @Environment(\.widgetFamily) private var family
    private let entry: RedstoneEntry

    init(entry: RedstoneEntry) {
        self.entry = entry
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumLayout
            default:
                smallLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(WidgetTheme.padding)
    }

    // MARK: - 小号

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: WidgetTheme.rowGap) {
            headerRow
            if entry.focus != nil {
                mapText(lineLimit: 2)
                timeText(font: WidgetTheme.bigTime)
                countdownRow
            } else {
                emptyText
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 中号

    private var mediumLayout: some View {
        HStack(alignment: .top, spacing: WidgetTheme.blockGap) {
            VStack(alignment: .leading, spacing: WidgetTheme.rowGap) {
                headerRow
                if entry.focus != nil {
                    mapText(lineLimit: 2)
                    timeText(font: WidgetTheme.mediumTime)
                    countdownRow
                } else {
                    emptyText
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if entry.hasData {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 4) {
                    remainingList
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 行部件

    /// 第一行：「红石」标签 + 右侧倍率徽标（中号时右上角再补一个「今日 N 场 / 待核对」）
    private var headerRow: some View {
        HStack(spacing: 4) {
            Text("红石")
                .font(WidgetTheme.label)
                .foregroundStyle(Theme.textTertiary)

            Spacer(minLength: 4)

            if let rate = entry.focus?.rate {
                rateBadge(rate)
            }
        }
    }

    /// 倍率徽标：`Theme.lime` 只做面，字用 `Theme.onLime`（浅色下也读得清）
    private func rateBadge(_ rate: Double) -> some View {
        Text(String(format: "%.1f×", rate))
            .font(WidgetTheme.label)
            .foregroundStyle(Theme.onLime)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.lime)
            }
    }

    /// 地图名。`待确认` 时用次级色，表示"这行不是确定信息"
    private func mapText(lineLimit: Int) -> some View {
        let map = entry.focus?.map ?? ""
        let isConfirmed = !map.isEmpty && map != "待确认"
        return Text(isConfirmed ? map : "待确认")
            .font(WidgetTheme.mapName)
            .foregroundStyle(isConfirmed ? Theme.textPrimary : Theme.textSecondary)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.8)
    }

    /// 场次时刻（大字）
    private func timeText(font: Font) -> some View {
        Text(entry.focus?.time ?? "--:--")
            .font(font)
            .foregroundStyle(Theme.textPrimary)
            .monospacedDigit()
    }

    /// 倒计时行：系统自绘走时，零刷新成本
    @ViewBuilder
    private var countdownRow: some View {
        if let focus = entry.focus {
            HStack(spacing: 4) {
                switch entry.phase {
                case .ongoing:
                    Text("进行中")
                        .font(WidgetTheme.countdown)
                        .foregroundStyle(Theme.limeInk)
                    countdown(from: entry.date, to: focus.endAt, tint: Theme.limeInk)
                case .upcoming:
                    Text("还有")
                        .font(WidgetTheme.countdown)
                        .foregroundStyle(Theme.textTertiary)
                    countdown(from: entry.date, to: focus.startAt, tint: Theme.textSecondary)
                case .endedToday:
                    Text("今日已结束")
                        .font(WidgetTheme.countdown)
                        .foregroundStyle(Theme.textTertiary)
                case .notGenerated:
                    Text("暂无排期")
                        .font(WidgetTheme.countdown)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// `Text(timerInterval:countsDown:)` 需要合法区间；`from >= to` 时退回静态文案，
    /// 否则运行期会直接崩在 Range 构造上。
    @ViewBuilder
    private func countdown(from: Date, to: Date, tint: Color) -> some View {
        if to > from {
            Text(timerInterval: from...to, countsDown: true)
                .font(WidgetTheme.countdown)
                .foregroundStyle(tint)
                .monospacedDigit()
                .multilineTextAlignment(.leading)
        } else {
            Text("00:00")
                .font(WidgetTheme.countdown)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }

    /// 中号右半：今日剩余场次（≤3 行），已过场次 30% 灰
    ///
    /// 已过的场次也画出来（而不是从列表里删掉）：用户看的是「今天还有哪几场」，
    /// 删掉之后列表会在一天里不断变短，反而看不清节奏。
    private var remainingList: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(entry.needsCheck ? "待核对" : "今日 \(entry.todayCount) 场")
                    .font(WidgetTheme.meta)
                    .foregroundStyle(entry.needsCheck ? Theme.statusWarn : Theme.textTertiary)
                Spacer(minLength: 0)
            }

            if entry.todayOccurrences.isEmpty {
                Text("今日无场次")
                    .font(WidgetTheme.rowText)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(Array(entry.todayOccurrences.prefix(3)), id: \.id) { occurrence in
                    row(for: occurrence)
                }
            }
        }
    }

    private func row(for occurrence: Occurrence) -> some View {
        let isPast = occurrence.endAt <= entry.date
        return HStack(spacing: 4) {
            Text(occurrence.time)
                .font(WidgetTheme.rowTime)
                .foregroundStyle(Theme.textPrimary)
            Text(occurrence.map)
                .font(WidgetTheme.rowText)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            if let rate = occurrence.rate {
                Text(String(format: "%.1f×", rate))
                    .font(WidgetTheme.meta)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        // 已过场次 30% 灰（PRD §5.3 明确要求）
        .opacity(isPast ? 0.3 : 1)
    }

    /// 空态。两种「没有下一场」必须说成两句不同的话：
    /// · 从来没拿到排期（`hasData == false`）→ 「暂无排期」；
    /// · 拿到了排期但本月已无未来场次（`phase == .notGenerated` 且 hasData）→ 「本月场次已结束」。
    /// 合成一句会让 11 月 30 日晚上打开桌面的人以为小组件坏了。
    private var emptyText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.hasData ? "本月场次已结束" : "暂无排期")
                .font(WidgetTheme.mapName)
                .foregroundStyle(Theme.textSecondary)
            Text(entry.hasData ? "下月排期生成后自动更新" : "打开 App 刷新一次")
                .font(WidgetTheme.meta)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
