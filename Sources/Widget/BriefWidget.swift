import SwiftUI
import WidgetKit

/// 简报桌面小组件（任务 1「太阳轨迹」重制版：中号）。
///
/// 视觉语言与红石小/中号同一套轨迹卡（设计文档 §5.1 六条特征），保证桌面两张卡视觉同源。
///
/// 弧线语义（设计文档 §5.1.1 裁定）：简报 widget 无自身时间概念 → 弧线仍画**当日时间轴**
/// （与红石同 motif），其信息价值来自「时段配色」（晨蓝/午晴/昏金/夜蓝）作安静氛围，不强行赋别的语义。
///
/// 字段（设计文档 §5.1.3 简报表）：
/// 顶部一行 `10月30日` · `周四` · `简报`；
/// 中部大字 简报首句（截断 2 行，约 20pt，因为是句子不是数字）；
/// 底部两行 `今日已推送 07:02` / `↗光遇简报`。
///
/// 没有正文（早上 7:30 前简报还没生成）时不说假话：明确写「今天还没有简报」。
struct BriefWidget: Widget {

    static let kind = "BriefWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: BriefWidget.kind, provider: BriefProvider()) { entry in
            BriefWidgetView(entry: entry)
        }
        .configurationDisplayName("今日简报")
        .description("每天一份：日期、首句，以及今天推送了没有。")
        .supportedFamilies([.systemMedium])
    }
}

/// 简报小组件视图
struct BriefWidgetView: View {

    private let entry: BriefEntry

    @Environment(\.colorScheme) private var colorScheme

    init(entry: BriefEntry) {
        self.entry = entry
    }

    // 配方 / 进度：简报按当前时段选配方，弧线用当天时间轴（与红石同源）
    private var key: TrackGradient.Key { TrackGradient.forBrief() }
    private var gradient: [Color] { TrackGradient.gradient(for: key, scheme: colorScheme) }
    private var tint: Color { TrackGradient.arcTint(for: key, scheme: colorScheme) }
    private var progress: CGFloat { ArcGeometry.dayProgress() }

    /// 简报来源名（底部 ↗ 用的站点标签，属品牌标识，非捏造的指标数据）
    private let sourceName = "光遇简报"

    var body: some View {
        GeometryReader { geo in
            let g = ArcGeometry(width: geo.size.width, height: geo.size.height)
            ZStack(alignment: .topLeading) {
                TrackCardBackdrop(geometry: g, progress: progress, tint: tint)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(WidgetTheme.padding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(for: .widget) {
            WidgetTheme.containerBackground(gradient: gradient)
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            if entry.hasData {
                bodyText
            } else {
                emptyText
            }
            Spacer(minLength: 0)
            footerRows
        }
    }

    // MARK: - 顶部一行：日期 · 星期 · 简报

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.dateText)
                .font(WidgetTheme.meta)
                .foregroundStyle(TrackGradient.foreground(for: key))
                .monospacedDigit()
            Text(entry.weekdayText)
                .font(WidgetTheme.statusSecondary)
                .foregroundStyle(TrackGradient.foreground(for: key).opacity(0.7))
            Spacer(minLength: 0)
            Text("简报")
                .font(WidgetTheme.label)
                .foregroundStyle(TrackGradient.foreground(for: key).opacity(0.7))
        }
    }

    // MARK: - 中部大字：简报首句（截断 2 行，约 20pt）

    @ViewBuilder
    private var bodyText: some View {
        if let first = entry.paragraphs.first, !first.isEmpty {
            Text(first)
                .font(WidgetTheme.briefBig)
                .foregroundStyle(TrackGradient.foreground(for: key))
                .lineLimit(2)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
        } else {
            emptyText
        }
    }

    private var emptyText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("今天还没有简报")
                .font(WidgetTheme.mapName)
                .foregroundStyle(TrackGradient.foreground(for: key))
            Text("生成后会出现在这里")
                .font(WidgetTheme.meta)
                .foregroundStyle(TrackGradient.foreground(for: key).opacity(0.6))
        }
    }

    // MARK: - 底部两行：↘今日已推送 / ↗来源

    private var footerRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            // ↘ 推送状态（有数据才画，不写「未知」）
            if let text = entry.footerText {
                HStack(spacing: 4) {
                    Image(systemName: entry.pushedToday ? "paperplane.fill" : "paperplane")
                        .font(WidgetTheme.placeIcon)
                        .foregroundStyle(entry.pushedToday ? tint : TrackGradient.foreground(for: key).opacity(0.7))
                    Text(text)
                        .font(WidgetTheme.briefFooter)
                        .foregroundStyle(entry.pushedToday ? tint : TrackGradient.foreground(for: key).opacity(0.7))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
            }
            // ↗ 来源站点
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right")
                    .font(WidgetTheme.placeIcon)
                    .foregroundStyle(tint)
                Text(sourceName)
                    .font(WidgetTheme.statusSecondary)
                    .foregroundStyle(TrackGradient.foreground(for: key).opacity(0.7))
                Spacer(minLength: 0)
            }
        }
    }
}
