import SwiftUI
import WidgetKit

/// 红石桌面小组件（V3.3：与首页红石卡同一套「光遇」语言）。
///
/// 版式（照参考图二重排 —— 每个元素都在固定位置，不再跟曲线抢地方）：
/// ```
/// ┌───────────────────────────────┬──────────────┐
/// │ 霞谷 · 圆梦村  [2.5×]          │ 今日 3 场     │
/// │                               │ 11:08  … 2.5×│
/// │ 23:08                         │ 17:08  … 2.5×│
/// │ ↘ 还有 39:27                  │ 23:08  … 2.5×│
/// │ ↗ 霞谷 · 圆梦村               │              │
/// └───────────────────────────────┴──────────────┘
/// ```
///
/// **为什么这张卡不用天际线**（与简报卡唯一的"故意不对称"）：红石的信息密度是简报卡的三倍
/// （大字时刻 / 倒计时 / 场次表 / 倍率）。一整块随当地时间变色的天空，白天那一档是亮蓝
/// （`#BFE4FF`），白字压上去直接不合格 —— 大字时刻会被天色压得看不清。
/// 所以红石的底是**静态的夜**：星点 + 云海 + 一团暖光（`WidgetGameBackdrop`），
/// 天色不参与信息表达，颜色的职责只有一个：让画面活着。
///
/// 两条不能破的约束（沿用旧版）：
/// 1. 倒计时交给系统画：`Text(timerInterval:countsDown:)` 秒级走时但零刷新成本；
/// 2. 没有数据就说没有：`hasData == false` 只画「暂无排期」，绝不出现 00:00 或假地图。
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
        // 与简报卡一致地关掉系统内容边距：云海与星点要铺到卡片四边，
        // 默认 16pt 边距会在云海外围留一圈底色，看着像"卡里嵌了一张小卡"。
        .contentMarginsDisabled()
    }
}

/// 小号 / 中号共用的视图（按 `widgetFamily` 分派）。
struct RedstoneWidgetView: View {

    @Environment(\.widgetFamily) private var family
    private let entry: RedstoneEntry

    init(entry: RedstoneEntry) {
        self.entry = entry
    }

    /// 进度节点 / 强调图标用的光色。
    ///
    /// 以前这里按配方 + 系统外观算（`TrackGradient.arcTint(for:scheme:)`），现在统一走
    /// `Theme.trackArc`：它是**动态 token**，深浅外观由系统自己解析，Widget 层不需要再判
    /// `colorScheme`（判了就等于在 View 层做深浅分叉，主题闸门也会拦）。
    private var tint: Color { Theme.trackArc }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            // 整卡可点：点一下跳进 App 的红石页（冷启动 / 热启动都生效，见 RootView.onOpenURL）
            .widgetURL(WidgetDeepLink.rock)
            .containerBackground(for: .widget) {
                WidgetGameBackdrop()
            }
    }

    // MARK: - 内容分派

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            mediumContent
        default:
            smallContent
        }
    }

    // MARK: - 小号

    /// 小号只放左栏（宽度不够放场次表，硬塞会挤成一团）。
    @ViewBuilder
    private var smallContent: some View {
        if !entry.hasData {
            emptyBlock
        } else {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                Spacer(minLength: 10)
                bigNumber
                Spacer(minLength: 6)
                bottomRows
            }
        }
    }

    // MARK: - 中号

    @ViewBuilder
    private var mediumContent: some View {
        if !entry.hasData {
            emptyBlock
        } else {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    Spacer(minLength: 10)
                    bigNumber
                    Spacer(minLength: 6)
                    bottomRows
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if entry.todayOccurrences.isEmpty == false {
                    Rectangle()
                        .fill(Theme.trackDivider)
                        .frame(width: 1)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 5) {
                        todayBadge
                        ForEach(Array(entry.todayOccurrences.prefix(3)), id: \.id) { occ in
                            sessionRow(occ)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 118, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 顶部一行：地图名 · 倍率

    private var headerRow: some View {
        HStack(spacing: 5) {
            Text(focusMap)
                .font(WidgetTheme.headerTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let rate = entry.focus?.rate {
                rateBadge(rate)
            }
            Spacer(minLength: 0)
        }
    }

    /// 倍率徽标：tint 只做面，字用 `Theme.onLime`（浅色下也读得清）
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

    // MARK: - 中部大字

    @ViewBuilder
    private var bigNumber: some View {
        if entry.phase.isOngoing {
            Text("进行中")
                .font(WidgetTheme.bigTime)
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.7)
        } else if let time = entry.focus?.time {
            Text(time)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        } else {
            EmptyView()
        }
    }

    // MARK: - 底部两行：↘倒计时 / ↗地图名

    private var bottomRows: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.right")
                    .font(WidgetTheme.placeIcon)
                    .foregroundStyle(tint)
                countdownText
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right")
                    .font(WidgetTheme.placeIcon)
                    .foregroundStyle(tint)
                Text(focusMap)
                    .font(WidgetTheme.statusSecondary)
                    .foregroundStyle(Theme.textPrimary.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
    }

    /// ↘ 倒计时文案：按 phase 现算（沿用旧版逻辑，字符串颜色走 tint/前景）
    @ViewBuilder
    private var countdownText: some View {
        switch entry.phase {
        case .ongoing:
            if let focus = entry.focus {
                Text(remainingText(to: focus.endAt))
                    .font(WidgetTheme.countdown)
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
        case .upcoming:
            if let focus = entry.focus, focus.startAt > entry.date {
                // 未来场次：系统自绘倒计时（零刷新）。Range 非法会崩，先判一次
                Text("还有 ")
                    .font(WidgetTheme.countdown)
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                + Text(timerInterval: entry.date...focus.startAt, countsDown: true)
                    .font(WidgetTheme.countdown)
                    .foregroundStyle(trackTintOrForeground)
                    .monospacedDigit()
            } else if let focus = entry.focus {
                Text(remainingText(to: focus.startAt))
                    .font(WidgetTheme.countdown)
                    .foregroundStyle(trackTintOrForeground)
                    .monospacedDigit()
            }
        case .endedToday:
            Text("今日已结束")
                .font(WidgetTheme.countdown)
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
        case .notGenerated:
            Text("暂无排期")
                .font(WidgetTheme.countdown)
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
        }
    }

    /// 进行中剩余分钟（向上取整，至少 1）
    private func remainingText(to endAt: Date) -> String {
        let remain = max(1, Int((endAt.timeIntervalSince(entry.date) / 60).rounded(.up)))
        return "剩 " + String(remain) + " 分"
    }

    /// 进行中倒计时用 tint；其余用前景（避免 lime 在浅色下当字色读不清）
    private var trackTintOrForeground: Color {
        entry.phase.isOngoing ? tint : Theme.textPrimary
    }

    // MARK: - 中号右半：今日场次

    private var todayBadge: some View {
        HStack(spacing: 4) {
            Text(entry.needsCheck ? "待核对" : "今日 " + String(entry.todayCount) + " 场")
            .font(WidgetTheme.meta)
            .foregroundStyle(entry.needsCheck ? Theme.statusWarn : Theme.textPrimary.opacity(0.7))
            Spacer(minLength: 0)
        }
    }

    private func sessionRow(_ occ: Occurrence) -> some View {
        let isPast = occ.endAt <= entry.date
        return HStack(spacing: 4) {
            Text(occ.time)
                .font(WidgetTheme.rowTime)
                .foregroundStyle(Theme.textPrimary)
            Text(occ.map)
                .font(WidgetTheme.rowText)
                .foregroundStyle(Theme.textPrimary.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let rate = occ.rate {
                Text(String(format: "%.1f×", rate))
                    .font(WidgetTheme.meta)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
        }
        .opacity(isPast ? 0.3 : 1) // 已过场次 30% 灰（PRD §5.3）
    }

    // MARK: - 空态

    private var emptyBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("暂无排期")
                .font(WidgetTheme.mapName)
                .foregroundStyle(Theme.textPrimary)
            Text("打开 App 刷新一次")
                .font(WidgetTheme.meta)
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
            Spacer(minLength: 0)
        }
    }

    // MARK: - 工具

    private var focusMap: String {
        let map = entry.focus?.map ?? ""
        return (!map.isEmpty && map != "待确认") ? map : "待确认"
    }
}
