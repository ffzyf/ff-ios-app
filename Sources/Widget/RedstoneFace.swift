import SwiftUI
import WidgetKit

// MARK: - 版式常量

/// 红石卡面的**唯一量纲来源**：字号 / 间距 / 弧与节点的几何。
///
/// 为什么集中在一个 enum 而不是散在视图里：小组件画布只有 158pt（小号）与 338pt（中号）两档，
/// 字号差 1pt 就会挤成一团或者虚掉，间距差 1pt 就会让弧压到字。这些数只有摆在一起才调得动；
/// `RedstoneWidget.swift` 因此只剩"装配"，一个数字都不带。
///
/// 单位说明：字号用 `Font`，长度一律 pt。
enum RedstoneMetric {

    // MARK: 字号

    /// 13pt semibold：地图全名（`暮土·失落方舟`，含点位）
    static let mapName = Font.system(size: 13, weight: .semibold)
    /// 34pt rounded bold：主时刻（`23:08`）—— 卡面上唯一的大数字
    static let time = Font.system(size: 34, weight: .bold, design: .rounded)
    /// 10pt 等宽：弧两端的时间（`11:08` / `23:08`），等宽才和弧的端点对得齐
    static let endpoint = Font.system(size: 10, weight: .medium, design: .monospaced)
    /// 11pt 等宽：倒计时。系统每帧重绘秒数，等宽才不会左右跳
    static let countdown = Font.system(size: 11, weight: .semibold, design: .monospaced)
    /// 10pt：倒计时前的箭头图标、主时刻旁的「进行中 / 次日」
    static let tag = Font.system(size: 10, weight: .semibold)
    /// 10pt bold：倍率胶囊上的字
    static let rate = Font.system(size: 10, weight: .bold)
    /// 10pt：中号右栏小标题（`今日 3 场`）
    static let sectionTitle = Font.system(size: 10, weight: .semibold)
    /// 11pt 等宽：中号右栏的时刻
    static let rowTime = Font.system(size: 11, weight: .semibold, design: .monospaced)
    /// 10pt：中号右栏的倍率
    static let rowRate = Font.system(size: 10, weight: .medium)
    /// 13pt semibold：空态标题
    static let emptyTitle = Font.system(size: 13, weight: .semibold)
    /// 10pt：空态说明
    static let emptyNote = Font.system(size: 10, weight: .regular)

    // MARK: 间距

    /// 小号内边距（方形画布更窄，收到 13pt 免得顶到圆角）
    static let smallPadding: CGFloat = 13
    /// 中号内边距
    static let mediumPadding: CGFloat = 14
    /// 标题行 → 主时刻
    static let gapHeaderTime: CGFloat = 8
    /// 主时刻 → 时间轴弧。**硬要求 ≥ 10pt**：弧永远不许压字
    static let gapTimeArc: CGFloat = 10
    /// 弧（含两端时刻）→ 倒计时
    static let gapArcCountdown: CGFloat = 6
    /// 弧本体 → 两端时刻
    static let gapArcEndpoint: CGFloat = 2
    /// 左栏 / 竖线 / 右栏之间的横向留白（竖线各占一半）
    static let columnGap: CGFloat = 12
    /// 中号竖分割线宽度（0.5pt：桌面上是"一道发丝"，不是一条边）
    static let dividerWidth: CGFloat = 0.5
    /// 中号右栏宽度（场次表：时刻 + 倍率两列）
    static let sideColumnWidth: CGFloat = 106
    /// 中号右栏行距
    static let rowGap: CGFloat = 5

    // MARK: 时间轴弧

    /// 弧带高度（弧顶到两端的高差全部收在这个框里，框外一行字都不许进）
    static let arcHeight: CGFloat = 22
    /// 弧顶位置（占弧带高度）。与 `HorizonEdge` 的 crestY 同义
    static let arcCrestY: CGFloat = 0.06
    /// 弧两端位置（占弧带高度）。1.0 = 两端落在弧带底边，两端时刻正好在下面一行
    static let arcEdgeY: CGFloat = 1.0
    /// 雾化层线宽：Widget 里没有 blur，"柔"靠"更粗 + 更淡"伪造
    static let arcHazeWidth: CGFloat = 3.2
    /// 弧本体线宽
    static let arcCoreWidth: CGFloat = 1.2
    /// 雾化层不透明度
    static let arcHazeAlpha: Double = 0.16
    /// 本体不透明度
    static let arcCoreAlpha: Double = 0.62

    // MARK: 节点与光点

    /// 每个今日场次的节点直径
    static let nodeDiameter: CGFloat = 3
    /// 已过场次节点的透明度（未过的为 1）
    static let nodePastAlpha: Double = 0.35
    /// 当前场次光点直径
    static let dotDiameter: CGFloat = 5
    /// 光点外那圈环的线宽
    static let dotRingWidth: CGFloat = 1
    /// 环离开光点本体的间隙（环要能看见，就得离开本体一点）
    static let dotRingGap: CGFloat = 1.5
    /// 光晕直径（RadialGradient 的外径）
    static let dotGlowDiameter: CGFloat = 20
    /// 光晕最中心的不透明度（向外迅速衰减到 0）
    static let dotGlowAlpha: Double = 0.32
    /// 节点离弧两端的最小距离（占弧长比例）：圆有直径，贴到端点会被卡片边裁掉一半
    static let nodeEdgeInset: CGFloat = 0.06

    // MARK: 顶部地图圆点

    /// 地图圆点直径：取该地图天色的 `edge`（每一档里最亮、最有色相的那支）
    static let mapDotDiameter: CGFloat = 5
    /// 圆点外面那圈环的直径（比本体大 3pt：浅色外观下纯白点会消失，靠这圈留住它）
    static let mapDotRingDiameter: CGFloat = 8
    /// 圆点环的线宽
    static let mapDotRingWidth: CGFloat = 1
}

// MARK: - 卡面

/// 红石卡面（小号 158×158 / 中号 338×158）。
///
/// 版式（照用户给的参考图重排 —— 深色底 + 一条弧 + 一个大数字 + 两端极值 + 一个光点）：
/// ```
/// ┌──────────────────────────────┬──────────┐
/// │ ◉ 暮土·失落方舟     [2.5×]   │ 今日 3 场│
/// │                              │ 11:08 2.5│
/// │ 23:08                        │ 17:08 2.5│
/// │  ╭────────●────────╮         │ 23:08 2.5│
/// │ 11:08            23:08       │          │
/// │ ↘ 还有 39:27                 │          │
/// └──────────────────────────────┴──────────┘
/// ```
/// 中号的右栏是小号没有的（158pt 见方放不下，硬塞就是现在"挤成一团"的毛病）。
///
/// 三条不能破的规矩：
/// 1. **颜色只有一个来源**：`Theme.sky(band)` 的六个 token + `Theme.trackArc` +
///    `Theme.textPrimary` + `Theme.limeDeep`；倍率胶囊是唯一的 `Theme.lime` 面。
///    本文件没有一个颜色字面量，也没有一处读 `colorScheme`（深浅由 token 自己解析）。
/// 2. **一处模糊都不用**（`blur` 一次都不调）：Widget 每帧重绘，模糊既贵又是"背景糊"的根源。
///    柔光一律用 `RadialGradient` 与"低不透明度 + 更粗的线"伪造。
/// 3. **没有数据就说没有**：`hasData == false` 或没有任何可展示场次时只写「暂无排期」，
///    绝不画假弧、假时刻、假节点。
struct RedstoneFace: View {

    @Environment(\.widgetFamily) private var family

    private let entry: RedstoneEntry

    init(entry: RedstoneEntry) {
        self.entry = entry
    }

    /// 小号：158pt 见方，只放"地图名 + 主时刻 + 弧 + 倒计时"
    private var isSmall: Bool {
        return family == .systemSmall
    }

    /// 有没有一场可画。`hasData` 为真但一条未来场次都没有（`.notGenerated`）时同样是空态 ——
    /// 那时候 `focus` 是 nil，画任何东西都是编造。
    private var hasFocus: Bool {
        return entry.focus != nil
    }

    /// 这一帧的地图意象（背景与光点共用同一份判定）
    private var band: RedstoneBackdrop.Band {
        return RedstoneBackdrop.Band(mapName: entry.focus?.map ?? "")
    }

    var body: some View {
        Group {
            if hasFocus {
                if isSmall {
                    smallCard
                } else {
                    mediumCard
                }
            } else {
                emptyCard
            }
        }
        .padding(isSmall ? RedstoneMetric.smallPadding : RedstoneMetric.mediumPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - 小号

    /// 纵向预算（内容区 132pt）：标题 16 + 8 + 主时刻 41 + 10 + 弧 22 + 2 + 两端 12 + 6 + 倒计时 14 ≈ 131
    private var smallCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.bottom, RedstoneMetric.gapHeaderTime)
            timeBlock
                .padding(.bottom, RedstoneMetric.gapTimeArc)
            trackBlock
                .padding(.bottom, RedstoneMetric.gapArcCountdown)
            countdownRow
            Spacer(minLength: 0)
        }
    }

    // MARK: - 中号

    private var mediumCard: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.bottom, RedstoneMetric.gapHeaderTime)
                timeBlock
                    .padding(.bottom, RedstoneMetric.gapTimeArc)
                trackBlock
                    .padding(.bottom, RedstoneMetric.gapArcCountdown)
                countdownRow
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 一条 0.5pt 的发丝竖线：中号唯一的"结构线"，不许更粗
            Rectangle()
                .fill(Theme.textPrimary.opacity(0.08))
                .frame(width: RedstoneMetric.dividerWidth)
                .padding(.vertical, 2)
                .padding(.horizontal, RedstoneMetric.columnGap / 2)

            sessionColumn
                .frame(width: RedstoneMetric.sideColumnWidth, alignment: .leading)
        }
    }

    // MARK: - 顶部一行：地图圆点 + 地图全名 + 倍率

    private var headerRow: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .strokeBorder(Theme.trackArc.opacity(0.55),
                                  lineWidth: RedstoneMetric.mapDotRingWidth)
                    .frame(width: RedstoneMetric.mapDotRingDiameter,
                           height: RedstoneMetric.mapDotRingDiameter)
                Circle()
                    .fill(band.dot)
                    .frame(width: RedstoneMetric.mapDotDiameter,
                           height: RedstoneMetric.mapDotDiameter)
            }
            .frame(width: RedstoneMetric.mapDotRingDiameter,
                   height: RedstoneMetric.mapDotRingDiameter)

            Text(focusMap)
                .font(RedstoneMetric.mapName)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            if let rate = entry.focus?.rate {
                rateBadge(rate)
            }
        }
    }

    /// 倍率胶囊：`Theme.lime` 做面 + `Theme.onLime` 做字 —— 全项目唯一允许 lime 的用法
    private func rateBadge(_ rate: Double) -> some View {
        Text(String(format: "%.1f×", rate))
            .font(RedstoneMetric.rate)
            .foregroundStyle(Theme.onLime)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.lime)
            }
    }

    // MARK: - 主时刻

    /// 大数字永远是**这一场的时刻**（进行中也照写，右侧多一个「进行中」小标）。
    /// 时刻是这张卡的第一信息，任何状态下都不许被替换成一句话。
    private var timeBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.focus?.time ?? "")
                .font(RedstoneMetric.time)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if entry.phase.isOngoing {
                Text("进行中")
                    .font(RedstoneMetric.tag)
                    .foregroundStyle(Theme.trackArc)
                    .lineLimit(1)
            } else if let prefix = dayPrefix {
                Text(prefix)
                    .font(RedstoneMetric.tag)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    /// 这一场不在今天时给个日期前缀（`次日` / `周五`）。
    ///
    /// 为什么必须有：`endedToday` 阶段展示的是**明天（甚至周五）**那一场，
    /// 只写 `07:08` 会被读成"今天还有一场 07:08"，那是误导。
    private var dayPrefix: String? {
        guard let focus = entry.focus else { return nil }
        let today = RedstoneClock.dayKey(entry.date)
        guard focus.date != today else { return nil }
        if focus.date == RedstoneClock.nextDayKey(today) {
            return "次日"
        }
        let weekday = Formatters.weekdayLabel(dayKey: focus.date)
        return weekday.isEmpty ? nil : weekday
    }

    // MARK: - 时间轴弧

    /// 弧 + 两端时刻。
    ///
    /// 今日**不足两场**时整块不画：一道没有首末极值的弧就是假数据
    /// （用户要的是"两端各一个时间"，只有一场时两端是同一个数，只会让人以为出错了）。
    @ViewBuilder
    private var trackBlock: some View {
        let occurrences = entry.todayOccurrences
        if occurrences.count >= 2 {
            VStack(alignment: .leading, spacing: 0) {
                RedstoneTrack(entry: entry, occurrences: occurrences)
                    .frame(height: RedstoneMetric.arcHeight)
                endpointRow(occurrences)
                    .padding(.top, RedstoneMetric.gapArcEndpoint)
            }
        }
    }

    /// 弧的两端：首场 / 末场时刻（参考图里"两端各一个时间"的那两个）
    private func endpointRow(_ occurrences: [Occurrence]) -> some View {
        HStack(spacing: 0) {
            Text(occurrences.first?.time ?? "")
                .font(RedstoneMetric.endpoint)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(occurrences.last?.time ?? "")
                .font(RedstoneMetric.endpoint)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .lineLimit(1)
        }
    }

    // MARK: - 倒计时

    private var countdownRow: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.down.right")
                .font(RedstoneMetric.tag)
                .foregroundStyle(Theme.trackArc)
            countdownText
            Spacer(minLength: 0)
        }
    }

    /// 倒计时文案。未来场次一律交给 `Text(timerInterval:countsDown:)` 让系统自绘：
    /// 秒级在走，但**零刷新成本**（Widget 里不能起 Timer，进程随时被挂起）。
    @ViewBuilder
    private var countdownText: some View {
        if let focus = entry.focus {
            switch entry.phase {
            case .ongoing:
                if focus.endAt > entry.date {
                    timerLabel(text: "还剩", from: entry.date, to: focus.endAt)
                }
            case .upcoming:
                if focus.startAt > entry.date {
                    timerLabel(text: "还有", from: entry.date, to: focus.startAt)
                }
            case .endedToday:
                caption("今日已结束")
            case .notGenerated:
                caption("暂无后续场次")
            }
        }
    }

    /// `还剩 12:34` / `还有 39:27`：前半句是普通文字，后半句是系统自绘计时器。
    ///
    /// 无中文前缀 —— `Text(timerInterval:)` 只输出 `mm:ss`（`showsHours: false` 时），
    /// 中文单位交给前面那句"还有/还剩"承载，正好是参考图的读法。
    private func timerLabel(text: String, from start: Date, to end: Date) -> some View {
        HStack(spacing: 3) {
            caption(text)
            Text(timerInterval: start...end, countsDown: true, showsHours: false)
                .font(RedstoneMetric.countdown)
                .foregroundStyle(Theme.trackArc)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(RedstoneMetric.countdown)
            .foregroundStyle(Theme.textPrimary.opacity(0.62))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    // MARK: - 中号右栏：今日场次表

    private var sessionColumn: some View {
        VStack(alignment: .leading, spacing: RedstoneMetric.rowGap) {
            Text(sessionTitleText)
                .font(RedstoneMetric.sectionTitle)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .lineLimit(1)

            ForEach(Array(entry.todayOccurrences.prefix(3)), id: \.id) { occ in
                sessionRow(occ)
            }

            Spacer(minLength: 0)
        }
    }

    /// 右栏小标题：待核对时优先报"待核对"（那份数据可信度低，比场次数更重要）
    private var sessionTitleText: String {
        if entry.needsCheck {
            return "待核对"
        }
        return "今日 " + String(entry.todayCount) + " 场"
    }

    /// 一行场次：时刻 + 倍率。当前那一场的时刻用 `trackArc` 挑出来（与弧上的光点同一个色）
    private func sessionRow(_ occ: Occurrence) -> some View {
        let isPast = occ.endAt <= entry.date
        let isFocus = occ.id == entry.focus?.id

        return HStack(spacing: 4) {
            Text(occ.time)
                .font(RedstoneMetric.rowTime)
                .foregroundStyle(isFocus ? Theme.trackArc : Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let rate = occ.rate {
                Text(String(format: "%.1f×", rate))
                    .font(RedstoneMetric.rowRate)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .opacity(isPast ? 0.4 : 1)
    }

    // MARK: - 空态

    /// 空态只写两行字：不画弧、不画节点、不出现 `00:00` 或任何地图名
    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("暂无排期")
                .font(RedstoneMetric.emptyTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text("打开 App 刷新一次")
                .font(RedstoneMetric.emptyNote)
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 工具

    /// 地图全名（`暮土·失落方舟`）。空串 / `待确认` 一律显示「待确认」，绝不编一个地名出来
    private var focusMap: String {
        let raw = entry.focus?.map ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!trimmed.isEmpty && trimmed != "待确认") ? trimmed : "待确认"
    }
}

// MARK: - 时间轴弧

/// 今日时间轴弧：一条横贯卡片的弧 + 每个场次一个节点 + 当前场次一个光点。
///
/// 几何直接复用 Shared 的 `HorizonEdge`（App 内简报卡、天光组件用的是同一条二次贝塞尔）：
/// 一条曲线只该有一个实现，重画一遍必然会和别处漂开。节点位置用**同一条曲线的参数方程**
/// 反算（见 `point(at:in:)`），所以节点严格落在弧上，不靠目测对齐。
///
/// 全程不调模糊：光点的柔边来自 `RadialGradient`，弧的柔度来自"更粗 + 更淡"的雾化层。
struct RedstoneTrack: View {

    private let entry: RedstoneEntry
    /// 今日场次（升序，至少两条 —— 调用方已保证）
    private let occurrences: [Occurrence]

    init(entry: RedstoneEntry, occurrences: [Occurrence]) {
        self.entry = entry
        self.occurrences = occurrences
    }

    /// 光点用的地图主色（与顶部圆点同一支 token）
    private var band: RedstoneBackdrop.Band {
        return RedstoneBackdrop.Band(mapName: entry.focus?.map ?? "")
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // 雾化层：替掉 blur 的那一层（更粗、更淡）
                HorizonEdge(crestY: RedstoneMetric.arcCrestY, edgeY: RedstoneMetric.arcEdgeY)
                    .stroke(Theme.trackArc.opacity(RedstoneMetric.arcHazeAlpha),
                            lineWidth: RedstoneMetric.arcHazeWidth)

                // 弧本体
                HorizonEdge(crestY: RedstoneMetric.arcCrestY, edgeY: RedstoneMetric.arcEdgeY)
                    .stroke(Theme.trackArc.opacity(RedstoneMetric.arcCoreAlpha),
                            lineWidth: RedstoneMetric.arcCoreWidth)

                // 场次节点：已过的暗、未过的亮、当前那场换成光点
                ForEach(occurrences, id: \.id) { occ in
                    marker(for: occ, in: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    // MARK: - 节点

    @ViewBuilder
    private func marker(for occ: Occurrence, in size: CGSize) -> some View {
        let point = RedstoneTrack.point(at: progress(of: occ), in: size)

        if occ.id == entry.focus?.id {
            glowDot(at: point)
        } else {
            node(at: point, past: occ.endAt <= entry.date)
        }
    }

    /// 普通场次节点：3pt 圆点。已过的压到 0.35（未过的满亮度）
    private func node(at point: CGPoint, past: Bool) -> some View {
        return Circle()
            .fill(Theme.trackArc.opacity(past ? RedstoneMetric.nodePastAlpha : 1))
            .frame(width: RedstoneMetric.nodeDiameter, height: RedstoneMetric.nodeDiameter)
            .position(x: point.x, y: point.y)
    }

    /// 当前场次光点：5pt 本体（地图主色）+ 一圈细环 + 一层 `RadialGradient` 光晕。
    ///
    /// 本体取 `sky.edge`（该地图天色里最亮的那支，也就是"地图主色"）；外环取 `trackArc`
    /// （动态 token）—— 浅色外观下近白本体压在白卡上会消失，这圈环负责把它留住。
    private func glowDot(at point: CGPoint) -> some View {
        let ringDiameter = RedstoneMetric.dotDiameter + RedstoneMetric.dotRingGap * 2

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Theme.trackArc.opacity(RedstoneMetric.dotGlowAlpha),
                            Theme.trackArc.opacity(0)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: RedstoneMetric.dotGlowDiameter / 2
                    )
                )
                .frame(width: RedstoneMetric.dotGlowDiameter,
                       height: RedstoneMetric.dotGlowDiameter)

            Circle()
                .strokeBorder(Theme.trackArc.opacity(0.75),
                              lineWidth: RedstoneMetric.dotRingWidth)
                .frame(width: ringDiameter, height: ringDiameter)

            Circle()
                .fill(band.dot)
                .frame(width: RedstoneMetric.dotDiameter,
                       height: RedstoneMetric.dotDiameter)
        }
        .frame(width: RedstoneMetric.dotGlowDiameter,
               height: RedstoneMetric.dotGlowDiameter)
        .position(x: point.x, y: point.y)
    }

    // MARK: - 几何

    /// 这一场在弧上的参数位置（0 = 今日首场，1 = 今日末场）。
    ///
    /// 为什么不按"现在几点"算：Widget 的帧是 30 分钟一格，按钟点算的话光点会在两帧之间
    /// 停住不动、然后跳一格，反而更像卡住了；按场次算则"光点永远落在真实的那一场上"，
    /// 与卡片上的大数字、右栏里被挑亮的那一行严格一致。只有一场时退到弧心（中点）。
    private func progress(of occ: Occurrence) -> CGFloat {
        guard let first = occurrences.first, let last = occurrences.last else { return 0.5 }
        let span = last.startAt.timeIntervalSince(first.startAt)
        guard span > 0 else { return 0.5 }
        let raw = occ.startAt.timeIntervalSince(first.startAt) / span
        // 首末两场不能顶到弧的两端点上：节点是个有直径的圆，落在 0 / 1 时会被卡片边裁掉一半，
        // 也会和下面的两端时刻贴在一起。往内收 6% 后，"首场/末场"仍然是那两个点，只是留了呼吸。
        let inset = RedstoneMetric.nodeEdgeInset
        let clamped = CGFloat(min(max(raw, 0), 1))
        return inset + (1 - 2 * inset) * clamped
    }

    /// 弧上参数 `t` 处的点 —— 与 `HorizonEdge` 的控制点公式逐字一致：
    /// `controlY = h · (2·crestY − edgeY)`，二次贝塞尔在 `t` 处的 y 由此展开。
    /// 这样节点和弧是"同一个函数"，不会有"看着差一点点"的对齐问题。
    static func point(at t: CGFloat, in size: CGSize) -> CGPoint {
        let edgeY = size.height * RedstoneMetric.arcEdgeY
        let controlY = size.height * (2 * RedstoneMetric.arcCrestY - RedstoneMetric.arcEdgeY)
        let inverse = 1 - t
        let y = inverse * inverse * edgeY
            + 2 * inverse * t * controlY
            + t * t * edgeY
        return CGPoint(x: size.width * t, y: y)
    }
}

// MARK: - 背景

/// 红石卡片的背景：**一张干净的渐变** + 一团气 + 一组极简剪影。
///
/// ## 为什么推倒重来
///
/// 旧做法是把一整块「剪影 + 云海 + 12pt 模糊」铺满卡片（`WidgetGameBackdrop`）。中号尚可，
/// 小号 158pt 见方下三层云叠在一起就是一团糊 —— 用户的原话是"背景糊"。
/// 参考图给的答案相反：**底色是一段渐变，信息交给几何（弧 / 点 / 两端标签）**。
///
/// 所以这里只留四样东西，一个都不多：
/// 1. 地图天色渐变（`Theme.sky` 的 top → horizon → ground，三档）；
/// 2. 一层「纱」（`Theme.bgBase` 的 `.opacity()`）：深色下压暗、浅色下提亮，
///    同一行代码同时保证白字/黑字都立得住 —— 因此这里**不判 `colorScheme`**；
/// 3. 一团极淡的气（每张地图一处，位置与色相就是"气质"本身）；
/// 4. 底部一组 1–3 个剪影（`Theme.textPrimary.opacity(0.16~0.20)`，
///    与旧版暮土/禁阁的剪影同一套做法：深浅外观下自动反向，永远压不坏文字）。
///
/// **全程零模糊**：画布上最大的一笔是 `LinearGradient` 与 `RadialGradient`，都是 GPU 合成。
///
/// 六张地图的档位（七档天色里挑，一个新 hex 都没造）：
/// | 地图 | 档 | 纱 | 那口气 | 剪影 |
/// |---|---|---|---|---|
/// | 云野 | `day` | 0.58 | `edge` 左上天光 | 两座浮岛 |
/// | 雨林 | `blueDusk` | 0.66 | `limeDeep` 贴地湿雾 | 两根高瘦树影 |
/// | 霞谷 | `sunset` | 0.50 | `edge` 谷底暖光 | 两道错开的山脊 |
/// | 暮土 | `blueDusk` | 0.76 | `top` 贴地绯红残光 | 两根断石柱 |
/// | 禁阁 | `blueDawn` | 0.62 | `edge` 顶部冷光 | 一座细塔 |
/// | 伊甸 | `night` | 0.18 | `edge` 地平线冷光 | 两块尖石 |
/// | 认不出 | 旧版静态夜（`trackTop/trackBottom`） | — | — | 无 |
struct RedstoneBackdrop: View {

    private let band: Band

    /// `mapName` 形如 `"暮土·失落方舟"`；只看 `·` 之前的地名，点位名不参与配色。
    init(mapName: String = "") {
        self.band = Band(mapName: mapName)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                skyGradient
                veil
                accent(size: size)
                silhouettes(width: size.width, height: size.height)
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }

    // MARK: - ① 底色

    /// 地图天色：三档渐变（top → horizon → ground）。
    ///
    /// 认不出的地图 / 空态退回 `trackTop → trackBottom`（旧版静态夜，逐像素不变）：
    /// 退化必须是"仍然好看"，不是"白卡"。
    @ViewBuilder
    private var skyGradient: some View {
        if band == .unknown {
            LinearGradient(colors: [Theme.trackTop, Theme.trackBottom],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        } else {
            let sky = band.sky
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: sky.top, location: 0),
                    .init(color: sky.horizon, location: 0.60),
                    .init(color: sky.ground, location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - ② 纱

    /// 压向 `Theme.bgBase` 的一层渐变纱。
    ///
    /// `bgBase` 深色近黑、浅色米白，所以这一个数同时决定"白字能不能读"和"深字能不能读"。
    /// 越亮的天色档压得越狠（云野 0.58），本来就暗的放得松（伊甸 0.18，要留住夜色）。
    @ViewBuilder
    private var veil: some View {
        if band != .unknown {
            LinearGradient(
                colors: [
                    Theme.bgBase.opacity(band.veil * 0.66),
                    Theme.bgBase.opacity(band.veil)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - ③ 那口气

    /// 每张地图一团气：亮雾 / 湿气 / 暖光 / 冷光。位置与色相就是"气质"本身
    @ViewBuilder
    private func accent(size: CGSize) -> some View {
        if let glow = band.glow {
            RadialGradient(
                gradient: Gradient(colors: [
                    glow.color.opacity(glow.alpha),
                    glow.color.opacity(0)
                ]),
                center: glow.center,
                startRadius: 0,
                endRadius: max(size.width, size.height) * glow.radius
            )
        }
    }

    // MARK: - ④ 剪影

    /// 剪影全部收在右下角一条 20pt 高的带子里。
    ///
    /// 为什么卡在这个位置：卡片左下是倒计时、右上是倍率、中间是大数字与弧 ——
    /// 只有右下角这块永远空着。剪影一进文字区就会把 11pt 的字吃掉（旧版的病）。
    @ViewBuilder
    private func silhouettes(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            switch band {
            case .cloudSea:
                islands(width: w, height: h)
            case .rainForest:
                trees(width: w, height: h)
            case .canyon:
                ridges(width: w, height: h)
            case .ruins:
                pillars(width: w, height: h)
            case .tower:
                towers(width: w, height: h)
            case .void:
                spikes(width: w, height: h)
            case .unknown:
                EmptyView()
            }
        }
    }

    /// 云野：两座浮岛（扁椭圆 + 略高的位置 = "浮着"）
    private func islands(width w: CGFloat, height h: CGFloat) -> some View {
        let rock = Theme.textPrimary.opacity(0.16)
        return ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(rock)
                .frame(width: w * 0.22, height: h * 0.055)
                .position(x: w * 0.68, y: h * 0.878)
            Ellipse()
                .fill(rock)
                .frame(width: w * 0.14, height: h * 0.038)
                .position(x: w * 0.90, y: h * 0.848)
        }
    }

    /// 雨林：两根高瘦树影。绿只能由品牌 `limeDeep` 补（`Theme.sky` 七档里没有绿色天空）
    private func trees(width w: CGFloat, height h: CGFloat) -> some View {
        let trunk = Theme.limeDeep.opacity(0.26)
        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(trunk)
                .frame(width: max(2, w * 0.022), height: h * 0.16)
                .position(x: w * 0.66, y: h - h * 0.08)
            Capsule()
                .fill(trunk)
                .frame(width: max(2, w * 0.018), height: h * 0.11)
                .position(x: w * 0.80, y: h - h * 0.055)
        }
    }

    /// 霞谷：两道错开的山脊（峰顶左右偏，才不像"两个等腰三角形"）
    private func ridges(width w: CGFloat, height h: CGFloat) -> some View {
        let stone = Theme.textPrimary.opacity(0.16)
        return ZStack(alignment: .topLeading) {
            RedstoneSpike(apexX: 0.34)
                .fill(stone)
                .frame(width: w * 0.26, height: h * 0.14)
                .position(x: w * 0.72, y: h - h * 0.07)
            RedstoneSpike(apexX: 0.62)
                .fill(stone)
                .frame(width: w * 0.16, height: h * 0.09)
                .position(x: w * 0.93, y: h - h * 0.045)
        }
    }

    /// 暮土：两根断裂石柱（微微倾斜，"这里曾经是座城"）
    private func pillars(width w: CGFloat, height h: CGFloat) -> some View {
        let stone = Theme.textPrimary.opacity(0.18)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(stone)
                .frame(width: max(2, w * 0.030), height: h * 0.15)
                .rotationEffect(.degrees(-3))
                .position(x: w * 0.70, y: h - h * 0.075)
            Rectangle()
                .fill(stone)
                .frame(width: max(2, w * 0.024), height: h * 0.10)
                .rotationEffect(.degrees(4))
                .position(x: w * 0.86, y: h - h * 0.05)
        }
    }

    /// 禁阁：一座细塔 + 塔尖（窄到极致才像"阁"而不是"楼"）
    private func towers(width w: CGFloat, height h: CGFloat) -> some View {
        let stone = Theme.textPrimary.opacity(0.20)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(stone)
                .frame(width: max(1.5, w * 0.016), height: h * 0.17)
                .position(x: w * 0.80, y: h - h * 0.085)
            Capsule()
                .fill(stone)
                .frame(width: max(1, w * 0.008), height: h * 0.05)
                .position(x: w * 0.80, y: h - h * 0.195)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(stone)
                .frame(width: max(1.5, w * 0.012), height: h * 0.12)
                .position(x: w * 0.92, y: h - h * 0.06)
        }
    }

    /// 伊甸：两块尖利乱石（峰顶横向偏移各不相同）
    private func spikes(width w: CGFloat, height h: CGFloat) -> some View {
        let stone = Theme.textPrimary.opacity(0.16)
        return ZStack(alignment: .topLeading) {
            RedstoneSpike(apexX: 0.30)
                .fill(stone)
                .frame(width: w * 0.24, height: h * 0.14)
                .position(x: w * 0.70, y: h - h * 0.07)
            RedstoneSpike(apexX: 0.62)
                .fill(stone)
                .frame(width: w * 0.18, height: h * 0.10)
                .position(x: w * 0.92, y: h - h * 0.05)
        }
    }
}

// MARK: - 地图档位

extension RedstoneBackdrop {

    /// 一张卡的「地图意象」= 从七档天色里挑一档 + 一个纱的浓度 + 一团气 + 一组剪影。
    ///
    /// 地图名的切分复用 `WidgetGameBackdrop.MapScene.family(of:)`：三种分隔符（`·` / `・` / `•`）
    /// 的容错只该有一份实现 —— 那套剪影背景不再当底图用了，但这份"地名归一"仍然是对的。
    enum Band: Equatable {

        /// 云野
        case cloudSea
        /// 雨林
        case rainForest
        /// 霞谷
        case canyon
        /// 暮土
        case ruins
        /// 禁阁
        case tower
        /// 伊甸
        case void
        /// 认不出（空串 / `待确认` / 将来新增的地图）→ 旧版静态夜
        case unknown

        /// 从数据里的地图名认出意象。`"暮土·失落方舟"` → `.ruins`
        init(mapName: String) {
            switch WidgetGameBackdrop.MapScene.family(of: mapName) {
            case "云野": self = .cloudSea
            case "雨林": self = .rainForest
            case "霞谷": self = .canyon
            case "暮土": self = .ruins
            case "禁阁": self = .tower
            case "伊甸": self = .void
            default: self = .unknown
            }
        }

        /// 底色取 `Theme.sky` 的哪一档。
        ///
        /// 六张能一眼分辨靠的是"档 + 纱 + 气"三件一起：雨林与暮土同为 `blueDusk`，
        /// 但一个压 0.66 配绿雾、一个压 0.76 配绯红残光；禁阁走 `blueDawn`（冷靛），
        /// 伊甸走 `night`（近黑）—— 六张里没有两张是同一组参数。
        var phase: SkyPhase {
            switch self {
            case .cloudSea: return .day
            case .rainForest: return .blueDusk
            case .canyon: return .sunset
            case .ruins: return .blueDusk
            case .tower: return .blueDawn
            case .void: return .night
            case .unknown: return .night
            }
        }

        /// 这一档的六个 token（top / horizon / ground / edge / ink / inkDim）
        var sky: Theme.SkyColors {
            return Theme.sky(phase)
        }

        /// 地图主色 = 该档天色里最亮、最有色相的 `edge`（顶部圆点与弧上光点都用它）
        var dot: Color {
            return sky.edge
        }

        /// 纱的浓度：压向 `Theme.bgBase` 的比例
        var veil: Double {
            switch self {
            case .cloudSea: return 0.58
            case .rainForest: return 0.66
            case .canyon: return 0.50
            case .ruins: return 0.76
            case .tower: return 0.62
            case .void: return 0.18
            case .unknown: return 0
            }
        }

        /// 那团气：颜色 + 峰值不透明度 + 位置 + 半径（占卡片长边的比例）。
        /// 认不出的地图返回 nil（旧版静态夜没有这层）
        var glow: (color: Color, alpha: Double, center: UnitPoint, radius: CGFloat)? {
            switch self {
            case .cloudSea:
                // 云海反着光，光从左上漫下来
                return (sky.edge, 0.22, UnitPoint(x: 0.28, y: 0.14), 0.80)
            case .rainForest:
                // 湿气沉在底部（七档天色里没有绿，绿由品牌 limeDeep 补，只做雾不承载文字）
                return (Theme.limeDeep, 0.26, UnitPoint(x: 0.50, y: 0.94), 0.90)
            case .canyon:
                // 两侧山脊之间那道落日
                return (sky.edge, 0.24, UnitPoint(x: 0.50, y: 0.50), 0.70)
            case .ruins:
                // 荒土上贴地的绯红残光（`blueDusk` 的 top 就是那层暗红）
                return (sky.top, 0.26, UnitPoint(x: 0.66, y: 0.92), 0.85)
            case .tower:
                // 冷紫天光从正上方压下来，塔影因此是逆光的
                return (sky.edge, 0.20, UnitPoint(x: 0.50, y: 0.08), 0.75)
            case .void:
                // 地平线上最后一点冷光（伊甸的颜色靠"近黑 + 冷光"区分，不靠红）
                return (sky.edge, 0.24, UnitPoint(x: 0.50, y: 0.90), 0.80)
            case .unknown:
                return nil
            }
        }
    }
}

// MARK: - 剪影形状

/// 可调峰顶的三角剪影（山脊 / 尖石）。
///
/// `apexX` 让峰顶左右偏：三个等腰三角形排在一起会像栅栏，错开才像地貌。
/// 只画上边两条斜线，底边落在 frame 底边（所有剪影都是"从地面长出来"）。
struct RedstoneSpike: Shape {

    /// 峰顶横向位置（0…1，相对自身宽度）
    var apexX: CGFloat = 0.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * apexX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
