import SwiftUI
import WidgetKit

/// 红石桌面小组件（任务 1「太阳轨迹」重制版：小号 + 中号）。
///
/// 视觉语言（设计文档 §5.1 六条特征）：
/// 1. 整卡渐变背景（按时段选 `TrackGradient` 配方，颜色即信息）；
/// 2. 平滑弧线贯穿下部（约 55% 卡高），已走段亮实线、未走段同色压低不透明度；
/// 3. 发光节点：当前时刻位置，小实心圆 + 径向光晕；
/// 4. 底部两行：↘倒计时 / ↗地图名；
/// 5. 中部大号数字（28pt rounded）+ 彩色图标；
/// 6. 顶部一行：地图名 · 倍率。
///
/// 弧线语义（设计文档 §5.1.1 裁定）：红石 widget 的弧线 = 当天时间轴
/// （progress = 当天已过比例），节点 = 此刻位置；若此刻有进行中红石，节点与 tint 转 lime。
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
    }
}

/// 小号 / 中号共用的视图（按 `widgetFamily` 分派）。
struct RedstoneWidgetView: View {

    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    private let entry: RedstoneEntry

    init(entry: RedstoneEntry) {
        self.entry = entry
    }

    // 这一帧的配方 / 进度：背景渐变按配方，弧线 progress 用「当天已过比例」现算
    private var key: TrackGradient.Key { TrackGradient.forRedstone(phase: entry.phase) }
    private var gradient: [Color] { TrackGradient.gradient(for: key, scheme: colorScheme) }
    private var tint: Color { TrackGradient.arcTint(for: key, scheme: colorScheme) }
    private var progress: CGFloat { ArcGeometry.dayProgress() }

    var body: some View {
        GeometryReader { geo in
            let g = ArcGeometry(width: geo.size.width, height: geo.size.height)
            ZStack(alignment: .topLeading) {
                // 弧线 + 发光节点（透明底，叠在渐变之上）
                TrackCardBackdrop(geometry: g, progress: progress, tint: tint)
                // 文字内容（透明底）
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(WidgetTheme.padding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 整卡渐变背景（取代旧的纯色 Theme.bgBase）
        .containerBackground(for: .widget) {
            WidgetTheme.containerBackground(gradient: gradient)
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

    // MARK: - 小号（C3）

    @ViewBuilder
    private var smallContent: some View {
        if !entry.hasData {
            emptyBlock
        } else {
            VStack(alignment: .leading, spacing: WidgetTheme.rowGap) {
                headerRow
                Spacer(minLength: 0)
                bigNumber
                bottomRows
            }
        }
    }

    // MARK: - 中号（C4）

    @ViewBuilder
    private var mediumContent: some View {
        if !entry.hasData {
            emptyBlock
        } else {
            HStack(alignment: .top, spacing: WidgetTheme.blockGap) {
                // 左半：与红石小号一致（地图名 · 倍率 · 下一场 · 底部两行）
                VStack(alignment: .leading, spacing: WidgetTheme.rowGap) {
                    headerRow
                    Spacer(minLength: 0)
                    bigNumber
                    bottomRows
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if entry.todayOccurrences.isEmpty == false {
                    // 右半：今日剩余场次列表（≤3）
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(width: 1)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        todayBadge
                        ForEach(Array(entry.todayOccurrences.prefix(3)), id: \.id) { occ in
                            sessionRow(occ)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 顶部一行：地图名 · 倍率

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 4) {
            Text(focusMap)
                .font(WidgetTheme.headerTitle)
                .foregroundStyle(TrackGradient.foreground(for: key))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let rate = entry.focus?.rate {
                rateBadge(rate)
            }
            Spacer(minLength: 4)
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
                    .fill(TrackGradient.arcTint(for: key, scheme: colorScheme))
            }
    }

    // MARK: - 中部大字

    @ViewBuilder
    private var bigNumber: some View {
        if entry.phase.isOngoing {
            // 进行中：大字显示「进行中」，节点已是 lime
            Text("进行中")
                .font(WidgetTheme.bigTime)
                .foregroundStyle(TrackGradient.foreground(for: key))
                .minimumScaleFactor(0.7)
        } else if let time = entry.focus?.time {
            Text(time)
                .font(WidgetTheme.bigTime)
                .foregroundStyle(TrackGradient.foreground(for: key))
                .monospacedDigit()
        } else {
            EmptyView()
        }
    }

    // MARK: - 底部两行：↘倒计时 / ↗地图名

    @ViewBuilder
    private var bottomRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            // ↘ 倒计时（系统自绘走时，零刷新）
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.right")
                    .font(WidgetTheme.placeIcon)
                    .foregroundStyle(tint)
                countdownText
                Spacer(minLength: 0)
            }
            // ↗ 地图名（落地/去向）
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right")
                    .font(WidgetTheme.placeIcon)
                    .foregroundStyle(tint)
                Text(focusMap)
                    .font(WidgetTheme.statusSecondary)
                    .foregroundStyle(TrackGradient.foreground(for: key))
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
            // 进行中：显示剩余分钟（节点已是 lime）
            if let focus = entry.focus {
                Text(remainingText(to: focus.endAt))
                    .font(WidgetTheme.countdown)
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
        case .upcoming:
            if let focus = entry.focus, focus.startAt > Date() {
                // 未来场次：系统自绘倒计时（零刷新）。Range 非法（startAt<=now）会崩，先判一次
                Text("还有 ")
                    .font(WidgetTheme.countdown)
                    .foregroundStyle(TrackGradient.foreground(for: key).opacity(0.7))
                + Text(timerInterval: Date()...focus.startAt, countsDown: true)
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
                .foregroundStyle(TrackGradient.foreground(for: key).opacity(0.7))
        case .notGenerated:
            Text("暂无排期")
                .font(WidgetTheme.countdown)
                .foregroundStyle(TrackGradient.foreground(for: key).opacity(0.7))
        }
    }

    /// 进行中剩余分钟（向上取整，至少 1）
    private func remainingText(to endAt: Date) -> String {
        let remain = max(1, Int((endAt.timeIntervalSince(Date()) / 60).rounded(.up)))
        return "剩 \(remain) 分"
    }

    /// 进行中倒计时用 tint；其余用前景（避免 lime 在浅色下当字色读不清——lint 规则4）
    private var trackTintOrForeground: Color {
        entry.phase.isOngoing ? tint : TrackGradient.foreground(for: key)
    }

    // MARK: - 中号右半：今日场次

    @ViewBuilder
    private var todayBadge: some View {
        HStack(spacing: 4) {
            Text(entry.needsCheck ? "待核对" : "今日 \(entry.todayCount) 场")
                .font(WidgetTheme.meta)
                .foregroundStyle(entry.needsCheck ? Theme.statusWarn : TrackGradient.foreground(for: key).opacity(0.7))
            Spacer(minLength: 0)
        }
    }

    private func sessionRow(_ occ: Occurrence) -> some View {
        let isPast = occ.endAt <= entry.date
        return HStack(spacing: 4) {
            Text(occ.time)
                .font(WidgetTheme.rowTime)
                .foregroundStyle(TrackGradient.foreground(for: key))
            Text(occ.map)
                .font(WidgetTheme.rowText)
                .foregroundStyle(TrackGradient.foreground(for: key).opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 2)
            if let rate = occ.rate {
                Text(String(format: "%.1f×", rate))
                    .font(WidgetTheme.meta)
                    .foregroundStyle(TrackGradient.foreground(for: key).opacity(0.6))
            }
        }
        .opacity(isPast ? 0.3 : 1) // 已过场次 30% 灰（PRD §5.3）
    }

    // MARK: - 空态

    @ViewBuilder
    private var emptyBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("暂无排期")
                .font(WidgetTheme.mapName)
                .foregroundStyle(TrackGradient.foreground(for: key))
            Text("打开 App 刷新一次")
                .font(WidgetTheme.meta)
                .foregroundStyle(TrackGradient.foreground(for: key).opacity(0.6))
            Spacer(minLength: 0)
        }
        .padding(WidgetTheme.padding)
    }

    // MARK: - 工具

    private var focusMap: String {
        let map = entry.focus?.map ?? ""
        return (!map.isEmpty && map != "待确认") ? map : "待确认"
    }
}
