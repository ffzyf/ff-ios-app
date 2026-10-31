import SwiftUI
import WidgetKit

// MARK: - 版式常量

/// 红石卡面的**唯一量纲来源**：字号 / 间距 / 弧与节点的几何。
///
/// 为什么集中在一个 enum 而不是散在视图里：小组件画布只有 **158pt 见方**（`.systemSmall`，
/// 中号在 V3.7 已下线，见 `RedstoneWidget.supportedFamilies`），字号差 1pt 就会挤成一团
/// 或者虚掉，间距差 1pt 就会让弧压到字。这些数只有摆在一起才调得动；
/// `RedstoneWidget.swift` 因此只剩"装配"，一个数字都不带。
///
/// 单位说明：字号用 `Font`，长度一律 pt。
enum RedstoneMetric {

    // MARK: 字号

    /// **11pt 是这套语言的字号下限**（设计语言 R2 / R7 #9）：158pt 宽里可用的字号只有
    /// 11 / 13 / 34 三档，没有任何 10pt、9pt。全文件一个 10pt 的字号声明都不留。
    /// 11pt semibold：地图全名（`暮土·失落方舟`，含点位）
    static let mapName = Font.system(size: 11, weight: .semibold)
    /// 34pt rounded bold：主时刻（`23:08`）—— 卡面上唯一的大数字
    static let time = Font.system(size: 34, weight: .bold, design: .rounded)
    /// 11pt 等宽：弧两端的时间（`11:08` / `23:08`），等宽才和弧的端点对得齐
    static let endpoint = Font.system(size: 11, weight: .medium, design: .monospaced)
    /// 11pt 等宽：倒计时。系统每帧重绘秒数，等宽才不会左右跳
    static let countdown = Font.system(size: 11, weight: .semibold, design: .monospaced)
    /// 11pt：倒计时前的箭头图标、主时刻旁的「进行中 / 次日」
    static let tag = Font.system(size: 11, weight: .semibold)
    /// 11pt semibold：右上角倍率（`2.5×`）的字。
    ///
    /// 它与 `tag` 字重字号相同，看着像重复，但语义完全不同（一个是状态标签、一个是数值），
    /// 分成两个常量是为了将来调其中一个时不会连带另一个。
    static let rate = Font.system(size: 11, weight: .semibold)
    /// 11pt：倒计时行右端的「今日 4 场」。
    ///
    /// 中号下线后，那份"今日场次表"的信息位没了 —— 但"今天还有几场"是用户真正在意的量，
    /// 所以它必须挤回小号：并进倒计时那一行的右端，是全卡唯一还剩的横向余量。
    static let sessionCount = Font.system(size: 11, weight: .medium)
    /// 13pt semibold：空态 / 收官态标题
    static let emptyTitle = Font.system(size: 13, weight: .semibold)
    /// 11pt：空态 / 收官态说明
    static let emptyNote = Font.system(size: 11, weight: .regular)

    // MARK: 间距

    /// 卡面内边距（方形画布更窄，收到 13pt 免得顶到圆角）
    static let padding: CGFloat = 13
    /// 标题行 → 主时刻（8 → 6：R5 的纵向腾挪，见 `RedstoneFace.card` 的预算注释）
    static let gapHeaderTime: CGFloat = 6
    /// 主时刻 → 时间轴弧。**硬要求 ≥ 10pt**：弧永远不许压字
    static let gapTimeArc: CGFloat = 10
    /// 弧（含两端时刻）→ 倒计时
    static let gapArcCountdown: CGFloat = 6
    /// 弧本体 → 两端时刻（2 → 1：同一行 11pt 字自己带 1pt 上留白，2pt 会读成"断开了"）
    static let gapArcEndpoint: CGFloat = 1
    /// 空态 / 收官态：标题 → 分隔线 → 说明
    static let gapEmptyBlock: CGFloat = 7
    /// 收官态那条分隔线的长度与粗细（短线：像一段标尺，不像"卡片边界"）
    static let closedRuleWidth: CGFloat = 22
    static let closedRuleHeight: CGFloat = 1

    // MARK: 时间轴弧

    /// 弧带高度（弧顶到两端的高差全部收在这个框里，框外一行字都不许进）。
    /// 24 → 22：仍是"有弯度的一段弧"（crestY 0.32 → 起伏 7pt），但把最后一笔余量省出来。
    static let arcHeight: CGFloat = 22
    /// 弧顶位置（占弧带高度）。0.32 才有"半圆"的弯度，太小会变成一条直线
    static let arcCrestY: CGFloat = 0.32
    /// 弧两端位置（占弧带高度）。1.0 = 两端落在弧带底边，两端时刻正好在下面一行
    static let arcEdgeY: CGFloat = 1.0
    /// 雾化层线宽：Widget 里没有 blur，"柔"靠"更粗 + 更淡"伪造
    static let arcHazeWidth: CGFloat = 3.2
    /// 弧本体线宽
    static let arcCoreWidth: CGFloat = 1.2
    /// 雾化层峰值不透明度（亮段处）
    static let arcHazeAlpha: Double = 0.16
    /// 雾化层谷值不透明度（亮段之外）
    static let arcHazeAlphaFloor: Double = 0.06
    /// 本体峰值不透明度（亮段处，锚在光点的 x）
    static let arcCoreAlpha: Double = 0.62
    /// 本体谷值不透明度（亮段之外）。峰值/谷值 ≈ 3.4:1，正是 R3 要求的峰谷比
    static let arcCoreAlphaFloor: Double = 0.18
    /// 亮段的扩散半径（占卡宽比例）：从光点往左右各 0.34 卡宽衰减到谷值
    static let arcGlowSpread: CGFloat = 0.34

    // MARK: 节点与光点

    /// 每个今日场次的节点直径
    static let nodeDiameter: CGFloat = 3
    /// 已过场次节点的透明度（未过的为 1）
    static let nodePastAlpha: Double = 0.30
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

    // MARK: 单场日的短线轨迹

    /// 今日只有一场时那段轨迹的长度。
    ///
    /// 为什么是 24pt：一个场次的节点只有 3pt，短线再短就读成"一个点被拉长了"；
    /// 24pt 约等于内容宽的 18%，一眼能看出"这是一条轨迹的起点"，又不会冒充整条弧。
    static let singleTrackWidth: CGFloat = 24

    // MARK: 顶部地图圆点

    /// 地图圆点直径：取该地图天色的 `edge`（每一档里最亮、最有色相的那支）
    static let mapDotDiameter: CGFloat = 6
    /// 圆点外面那圈环的直径（比本体大 3pt：浅色外观下纯白点会消失，靠这圈留住它）
    static let mapDotRingDiameter: CGFloat = 9
    /// 圆点环的线宽
    static let mapDotRingWidth: CGFloat = 1
}

// MARK: - 卡面

/// 红石卡面（**只有小号 158×158**）。
///
/// 版式（照用户给的参考图语言重排 —— 饱和渐变压底 + 顶行小字 + 中间巨大主值 +
/// 一条几何轨迹带光点 + 两端极值贴轨迹下方）：
/// ```
/// ┌──────────────────────────────┐
/// │ ● 暮土·失落方舟         2.5× │  ← 地图色点 6pt + 地图名 11pt / 倍率 11pt（无底）
/// │                              │
/// │  23:08                       │  ← 34pt rounded bold
/// │                              │
/// │  ╭────●────○────╮            │  ← 弧（今日所有场次的轨道，亮段跟着光点走）
/// │  11:08          23:08        │  ← 两端首末场次 11pt
/// │  ↘ 还有 39:27      今日 4 场 │  ← 倒计时 11pt + 今日场次数 11pt
/// └──────────────────────────────┘
/// ```
/// 158pt 见方里**只有这五组元素**：今日场次表放不下，所以它彻底不进小号
/// （中号下线时已经把这部分整段删掉，不留给死代码）。
///
/// 四条不能破的规矩：
/// 1. **颜色只有一个来源**：`Theme.sky(band)` 的六个 token + `Theme.trackArc`。
///    文字一律取 `band.sky.ink` / `band.sky.inkDim` —— 这两个是**固定**的
///    （`#F5F8FF` 及其 0.72），不随深浅外观翻转，所以压在饱和色场上也立得住；
///    用 `Theme.textPrimary` 会在浅色外观翻成深字，饱和色场上直接糊掉。
///    本文件没有一个颜色字面量，也没有一处读 `colorScheme`（深浅由 token 自己解析）。
/// 2. **一处模糊都不用**（`blur` 一次都不调）：Widget 每帧重绘，模糊既贵又是"背景糊"的根源。
///    柔光一律用 `RadialGradient` 与"低不透明度 + 更粗的线"伪造。
/// 3. **没有数据就说没有**：`.pending` 只写「暂无排期」，绝不画假弧、假时刻、假节点。
/// 4. **本月过完了就说收官**：`.closed` 写「本月红石已收官」+ 月份文案，
///    同样不画弧、不画时刻（判定与 App 首页共用 `RedstoneWindow`，见 Shared/Domain）。
struct RedstoneFace: View {

    private let entry: RedstoneEntry

    init(entry: RedstoneEntry) {
        self.entry = entry
    }

    /// 本月窗口三态：与 App 首页红石卡**同一份判定**（`Sources/Shared/Domain/RedstoneWindow.swift`）。
    ///
    /// 这里只能喂两个布尔：Widget 的 entry 里没有整月场次
    /// （`WidgetProvider.swift` 不在本次可改范围）。`focus == nil` 就等于
    /// 「没有任何进行中 / 未来的场次」—— 门面会把这两项翻成三态。
    private var windowState: RedstoneWindowState {
        return RedstoneWindow.state(hasData: entry.hasData,
                                    hasFutureOccurrence: entry.focus != nil,
                                    now: entry.date)
    }

    /// 有没有一场可画（`.live` 时必然为真，这里只是兜底：宁可写"暂无排期"也不编一场出来）
    private var hasFocus: Bool {
        return entry.focus != nil
    }

    /// 这一帧的地图意象（背景与光点共用同一份判定）
    private var band: RedstoneBackdrop.Band {
        return RedstoneBackdrop.Band(mapName: entry.focus?.map ?? "")
    }

    var body: some View {
        Group {
            switch windowState {
            case .closed:
                closedCard
            case .pending:
                pendingCard
            case .live:
                if hasFocus {
                    card
                } else {
                    pendingCard
                }
            }
        }
        .padding(RedstoneMetric.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - 正常倒计时

    /// 纵向预算（内容区 132pt，R5 上限 96% = 127pt）：
    /// 标题 14 + 6 + 主时刻 41 + 10 + 弧 22 + 1 + 两端时刻 12 + 6 + 倒计时 14 = **126 / 132 = 95.5%**，
    /// 余量 6pt。
    ///
    /// 三处收紧（`gapHeaderTime` 8→6、`gapArcEndpoint` 2→1、`arcHeight` 24→22）一共省 5pt，
    /// 正好抵掉 R2 把三处 10pt 升到 11pt 带来的每行约 1pt 增量 —— 不收紧的话是 131/132（99.2%），
    /// 只剩 1pt 余量，中文行高在不同系统版本有 ±1pt 浮动，超了就是倒计时那行被裁。
    private var card: some View {
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
                // eyebrow 的 +0.5 字距（R2）：11pt 在 158pt 卡上偏小，全靠这点字距撑开
                .tracking(0.5)
                // ink 是固定的 `#F5F8FF`，饱和色场上不随外观翻转
                .foregroundStyle(band.sky.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            if let rate = entry.focus?.rate {
                rateText(rate)
            }
        }
    }

    /// 倍率：**一行纯文字，不带任何面**（原 `rateBadge` 带 `Theme.lime` 底与 4pt 圆角，
    /// 本次去面后名字也跟着改，免得下次有人看名字又把面加回来）。
    ///
    /// 为什么去掉了原来的 `Theme.lime` 底 + 4pt 圆角：一张卡只该有**一个色场**，
    /// 一个填色胶囊会在 158pt 里造出"卡中卡"（R7 #2），而且 lime 会成为这张卡上的
    /// **第三支强调色**（天色 `sky.edge` + 轨迹 `trackArc` 已经两支，R7 #3 的上限是两支）。
    /// 现在它只是一行 11pt semibold 的字，颜色取 `trackArc`（与轨迹同一支，不引入新色），
    /// 于是卡面自绘形归 0（R6），`Theme.lime` 在这张卡上一次都不出现。
    private func rateText(_ rate: Double) -> some View {
        Text(String(format: "%.1f×", rate))
            .font(RedstoneMetric.rate)
            .foregroundStyle(Theme.trackArc)
            .lineLimit(1)
    }

    // MARK: - 主时刻

    /// 大数字永远是**这一场的时刻**（进行中也照写，右侧多一个「进行中」小标）。
    /// 时刻是这张卡的第一信息，任何状态下都不许被替换成一句话。
    private var timeBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.focus?.time ?? "")
                .font(RedstoneMetric.time)
                .foregroundStyle(band.sky.ink)
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
                    .foregroundStyle(band.sky.inkDim)
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

    /// 轨迹层 + 两端时刻。
    ///
    /// - **≥ 2 场**：整条弧 + 两端首末场次；
    /// - **刚好 1 场**：22pt 弧带保留，但只画一段 24pt 短线 + 1 个光点，两端时刻不画
    ///   （两端会是同一个数，读起来像"数据出错了"）；
    /// - **0 场**：整块不画 —— 一道没有节点的弧就是假数据。
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
        } else if occurrences.count == 1 {
            // 单场日不能让轨迹整块塌陷（否则卡面只剩"大字 + 一行倒计时"，
            // 与参考图的"时间轴 + 当下"结构对不上）
            RedstoneTrack(entry: entry, occurrences: occurrences)
                .frame(height: RedstoneMetric.arcHeight)
        }
    }

    /// 弧的两端：首场 / 末场时刻（参考图里"两端各一个时间"的那两个）。
    /// 颜色取 `inkDim`：它们与 eyebrow 同字号，靠颜色和位置分主次，不靠字号 （R2）。
    private func endpointRow(_ occurrences: [Occurrence]) -> some View {
        HStack(spacing: 0) {
            Text(occurrences.first?.time ?? "")
                .font(RedstoneMetric.endpoint)
                .foregroundStyle(band.sky.inkDim)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(occurrences.last?.time ?? "")
                .font(RedstoneMetric.endpoint)
                .foregroundStyle(band.sky.inkDim)
                .lineLimit(1)
        }
    }

    // MARK: - 倒计时（左）+ 今日场次数（右）

    private var countdownRow: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.down.right")
                .font(RedstoneMetric.tag)
                .foregroundStyle(Theme.trackArc)
            countdownText
            Spacer(minLength: 4)
            Text(todayCountText)
                .font(RedstoneMetric.sessionCount)
                // 第三层字用 inkDim（固定 0.72 白），不用 `textPrimary.opacity(0.45)`：
                // 后者会随外观翻转，且 0.45 压在压纱后的天色上只有约 2.4:1，11pt 读不清。
                // 也不用 `textSecondary`：它在浅色外观翻成深灰，同样压不住饱和色场。
                .foregroundStyle(band.sky.inkDim)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    /// 右端那行极小字：待核对时优先报"待核对"（那份数据可信度低，比场次数更重要），
    /// 否则报「今日 N 场」—— 中号下线后，这是"今天还有几场"唯一还在的地方。
    private var todayCountText: String {
        if entry.needsCheck {
            return "待核对"
        }
        return "今日 " + String(entry.todayCount) + " 场"
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
            .foregroundStyle(band.sky.inkDim)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    // MARK: - 空态（排期还没拉到）

    /// 空态只写两行字：不画弧、不画节点、不出现 `00:00` 或任何地图名。
    /// 这一态的 `band` 必然是 `.unknown`（没有场次就没有地图），天色退回静态夜，
    /// 所以 `sky.ink` / `sky.inkDim` 就是近黑底上的白字与 72% 白字。
    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("暂无排期")
                .font(RedstoneMetric.emptyTitle)
                .foregroundStyle(band.sky.ink)
                .lineLimit(1)
            Spacer(minLength: RedstoneMetric.gapEmptyBlock)
            Text("打开 App 刷新一次")
                .font(RedstoneMetric.emptyNote)
                .foregroundStyle(band.sky.inkDim)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 收官态（本月场次全过完了）

    /// 收官态：与空态同样是"没有弧、没有时刻"，但说的完全是另一件事 ——
    /// 排期是有的，只是这个月走完了。中间那条 22pt 的短线把两句文案分开，
    /// 免得 158pt 见方里只剩两块飘着的字。
    private var closedCard: some View {
        let state = windowState

        return VStack(alignment: .leading, spacing: 0) {
            Text(state.closedTitle ?? "本月红石已收官")
                .font(RedstoneMetric.emptyTitle)
                .foregroundStyle(band.sky.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Rectangle()
                .fill(Theme.trackArc.opacity(0.28))
                .frame(width: RedstoneMetric.closedRuleWidth,
                       height: RedstoneMetric.closedRuleHeight)
                .padding(.top, RedstoneMetric.gapEmptyBlock)
                .padding(.bottom, RedstoneMetric.gapEmptyBlock)

            Text(state.closedNote ?? "")
                .font(RedstoneMetric.emptyNote)
                .foregroundStyle(band.sky.inkDim)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

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
/// 两种画法，按今日场次数分派：
/// - **≥ 2 场**：整条弧（横向渐变描边，亮段跟着光点走）+ 每个场次一个节点；
/// - **1 场**：一段 24pt 的短线 + 1 个光点（没有"两端"可报，整条弧反而像假数据）。
///
/// 全程不调模糊：光点的柔边来自 `RadialGradient`，弧的柔度来自"更粗 + 更淡"的雾化层。
struct RedstoneTrack: View {

    private let entry: RedstoneEntry
    /// 今日场次（升序）。调用方可能传 0 / 1 / n 条，这里自己分派画法
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
            if occurrences.count >= 2 {
                arcTrack(in: size)
            } else {
                singleTrack(in: size)
            }
        }
    }

    // MARK: - 整条弧

    private func arcTrack(in size: CGSize) -> some View {
        let center = focusX()

        return ZStack {
            // 雾化层：替掉 blur 的那一层（更粗、更淡）。也走同一套横向渐变 ——
            // 否则"雾"比本体的亮段更平，光点周围那圈亮会被雾舔平。
            HorizonEdge(crestY: RedstoneMetric.arcCrestY, edgeY: RedstoneMetric.arcEdgeY)
                .stroke(arcStroke(color: Theme.trackArc,
                                  peak: RedstoneMetric.arcHazeAlpha,
                                  floor: RedstoneMetric.arcHazeAlphaFloor,
                                  anchor: center),
                        style: StrokeStyle(lineWidth: RedstoneMetric.arcHazeWidth,
                                           lineCap: .round,
                                           lineJoin: .round))

            // 弧本体：线端必须是 `.round`（默认是 butt，弧两端会切出两个方角）
            HorizonEdge(crestY: RedstoneMetric.arcCrestY, edgeY: RedstoneMetric.arcEdgeY)
                .stroke(arcStroke(color: Theme.trackArc,
                                  peak: RedstoneMetric.arcCoreAlpha,
                                  floor: RedstoneMetric.arcCoreAlphaFloor,
                                  anchor: center),
                        style: StrokeStyle(lineWidth: RedstoneMetric.arcCoreWidth,
                                           lineCap: .round,
                                           lineJoin: .round))

            // 场次节点：已过的暗、未过的亮、当前那场换成光点
            ForEach(occurrences, id: \.id) { occ in
                marker(for: occ, in: size)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// 弧的横向渐变描边：最亮处（`peak`）对准光点的 x，左右各 `spread` 卡宽内衰减到 `floor`。
    ///
    /// 照 `SkyLightFace.strokeStyle(_:sunX:peak:base:spread:)` 写 —— 那是全工程唯一一处
    /// 真正实现"亮段跟着光点走"的地方，再发明一套就会有两种描边语义。
    ///
    /// 为什么不用单一不透明度：一条恒定亮度的弧读作"装饰线"，一段亮一段暗才读作"轨迹"；
    /// 而且亮段随当前场次往右移，卡片每半小时的帧都在动。
    /// `LinearGradient` 的 `location` 必须单调递增，所以落在 0 / 1 上的停靠点按情况省略。
    private func arcStroke(color: Color,
                           peak: Double,
                           floor: Double,
                           anchor raw: CGFloat) -> LinearGradient {
        let center = min(max(raw, 0), 1)
        let spread = RedstoneMetric.arcGlowSpread
        let left = max(0, center - spread)
        let right = min(1, center + spread)

        var stops: [Gradient.Stop] = [.init(color: color.opacity(floor), location: 0)]
        if left > 0.001 {
            stops.append(.init(color: color.opacity(floor), location: left))
        }
        stops.append(.init(color: color.opacity(peak), location: center))
        if right < 0.999 {
            stops.append(.init(color: color.opacity(floor), location: right))
        }
        stops.append(.init(color: color.opacity(floor * 0.85), location: 1))

        return LinearGradient(gradient: Gradient(stops: stops),
                              startPoint: .leading,
                              endPoint: .trailing)
    }

    // MARK: - 单场日的短轨迹

    /// 单场日：一段 24pt 的短线（本体色）+ 一个光点，落在弧带同样的高度上。
    ///
    /// 为什么不画整条弧：两端时刻会是同一个数（`11:08` 左右各一个），读起来像"数据坏了"；
    /// 但整块不画又会塌成"只有一行字"，所以留一段短线 + 光点，轨迹这一层不缺席。
    private func singleTrack(in size: CGSize) -> some View {
        let y = size.height * RedstoneMetric.arcCrestY
        let endX = RedstoneMetric.singleTrackWidth

        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Theme.trackArc.opacity(RedstoneMetric.arcCoreAlpha))
                .frame(width: RedstoneMetric.singleTrackWidth,
                       height: RedstoneMetric.arcCoreWidth)
                .position(x: endX / 2, y: y)
            // 光点落在短线的末端：读作"轨迹从这儿开始，现在停在这一场"
            glowDot(at: CGPoint(x: endX, y: y))
        }
        .frame(width: size.width, height: size.height)
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

    /// 普通场次节点：3pt 圆点。已过的压到 0.30（未过的满亮度）
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

    /// 光点在弧上的横向位置（0…1）：亮段要"跟着当前场次走"，锚点只能是光点的 x。
    /// 找不到对应场次（`focus` 与今日场次不重叠，理论上不会发生）时退到弧心。
    private func focusX() -> CGFloat {
        guard let focusID = entry.focus?.id,
              let occ = occurrences.first(where: { $0.id == focusID }) else {
            return 0.5
        }
        return progress(of: occ)
    }

    /// 这一场在弧上的参数位置（0 = 今日首场，1 = 今日末场）。
    ///
    /// 为什么不按"现在几点"算：Widget 的帧是 30 分钟一格，按钟点算的话光点会在两帧之间
    /// 停住不动、然后跳一格，反而更像卡住了；按场次算则"光点永远落在真实的那一场上"，
    /// 与卡片上的大数字严格一致。只有一场时退到弧心（中点）。
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

/// 红石卡片的背景：**一张干净的渐变** + 一层纱 + 一团气 + 一组极简剪影。
///
/// ## 为什么推倒重来
///
/// 旧做法是把一整块「剪影 + 云海 + 12pt 模糊」铺满卡片（已删除的 `WidgetGameBackdrop`）。
/// 中号尚可，小号 158pt 见方下三层云叠在一起就是一团糊 —— 用户的原话是"背景糊"。
/// 参考图给的答案相反：**底色是一段渐变，信息交给几何（弧 / 点 / 两端标签）**。
///
/// 所以这里只剩四样东西：
/// 1. 地图天色渐变（`Theme.sky` 的 top → horizon → ground，三档）；
/// 2. 一层「纱」：**压向该档自己的 `ground`**，不是 `Theme.bgBase`。
///    为什么这一条是硬规矩：`bgBase` 浅色外观是近白米色（`#EDF1EC`），
///    0.66–0.76 的纱会把饱和色场洗成一张米白卡，直接违反"没有一张是纯白或纯灰"。
///    压向 `ground` 则只会让这一档的天色变深、不会变色相，深浅外观下都是同一块天色。
///    因此这里**不判 `colorScheme`**；
/// 3. 一团极淡的气（每张地图一处，位置与色相就是"气质"本身）。半径 ≤0.50 短边、alpha ≤0.16 ——
///    再大就成了"整卡泛光"，色场渐变会被吃掉；
/// 4. 底部一组 **1–2 个**剪影（`band.sky.ink.opacity(≤0.18)`）。
///    **剪影是故意保留的**：设计语言 R7 #8 把装饰几何判为禁止项，但用户明确要求
///    "要知道自己在哪个地图"，而剪影是这张卡上**唯一的地图标识**（天色色相只能分到
///    "暖 / 冷 / 亮 / 暗"这一级）。删掉它就退化成一张纯色卡，所以它属于**地图识别**
///    而非装饰 —— 代价是色场层从 3 层变成 4 层（R1 的上限），这一层被显式豁免。
///
/// **全程零模糊**：画布上最大的一笔是 `LinearGradient` 与 `RadialGradient`，都是 GPU 合成。
///
/// 六张地图的档位（七档天色里挑，一个新 hex 都没造）：
/// | 地图 | 档 | 纱 | 那口气 | 剪影 |
/// |---|---|---|---|---|
/// | 云野 | `day` | 0.28 | `edge` 左上柔光 | 两座浮岛 |
/// | 雨林 | `blueDusk` | 0.22 | `limeDeep` 湿雾 | 两根高瘦树影 |
/// | 霞谷 | `sunset` | 0.18 | `edge` 谷底暖光 | 两道错开的山脊 |
/// | 暮土 | `blueDusk` | 0.24 | `top` 绯红残光 | 两根断石柱 |
/// | 禁阁 | `night` | 0.20 | `edge` 顶部冷光 | 一座细塔（塔身 + 塔尖） |
/// | 伊甸 | `night` | 0.10 | `edge` 地平线冷光 | 两块尖石 |
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

    /// 地图天色：三档渐变（top → horizon → ground），角度**只有** `.top → .bottom`（180°）。
    ///
    /// 认不出的地图 / 空态退回 `trackTop → trackBottom`（旧版静态夜，逐像素不变）：
    /// 退化必须是"仍然好看"，不是"白卡"。这里同样用 180° —— 斜向渐变会在 158pt 方卡上
    /// 把左上角提亮，与"顶部一行小字"抢注意力，也会让同一套组件里出现两种角度。
    @ViewBuilder
    private var skyGradient: some View {
        if band == .unknown {
            LinearGradient(colors: [Theme.trackTop, Theme.trackBottom],
                           startPoint: .top,
                           endPoint: .bottom)
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

    /// 压向该档 `ground` 的一层渐变纱（`Theme.sky(band.phase).ground`，不是 `Theme.bgBase`）。
    ///
    /// 上限收到 0.28：0.66–0.76 的 `bgBase` 纱在浅色外观会把卡洗成米白，而 `ground`
    /// 是这一档天色自己的最暗端，压它只是让天色变沉、色相不动。越亮的天色档压得稍多
    /// （云野 0.28），本来就暗的放得松（伊甸 0.10，要留住夜色）。
    /// 上端再乘 0.66，保证"上浅下深"的方向感 —— 底部那两行 11pt 小字永远压在更深的一侧。
    @ViewBuilder
    private var veil: some View {
        if band != .unknown {
            let ground = band.sky.ground
            LinearGradient(
                colors: [
                    ground.opacity(band.veil * 0.66),
                    ground.opacity(band.veil)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - ③ 那口气

    /// 每张地图一团气：亮雾 / 湿气 / 暖光 / 冷光。位置与色相就是"气质"本身。
    ///
    /// 三停靠点（0 / 0.35 / 1）而不是两停靠点：两停靠点从中心到边缘是线性衰减，
    /// 在 79pt 半径上读起来像"一片均匀的雾"；多一个 0.35 的中间点才有"光从中心散出去"的手感。
    /// 半径与 alpha 都由 `Band.glow` 卡死（≤0.50 短边 / ≤0.16），这里不再乘任何系数。
    @ViewBuilder
    private func accent(size: CGSize) -> some View {
        if let glow = band.glow {
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: glow.color.opacity(glow.alpha), location: 0),
                    .init(color: glow.color.opacity(glow.alpha * 0.42), location: 0.35),
                    .init(color: glow.color.opacity(0), location: 1)
                ]),
                center: glow.center,
                startRadius: 0,
                endRadius: max(size.width, size.height) * glow.radius
            )
        }
    }

    // MARK: - ④ 剪影

    /// 剪影全部收在右下角一条 20pt 高的带子里，**每张地图最多两个形状**。
    ///
    /// 为什么卡在这个位置：卡片左下是倒计时、右上是倍率、中间是大数字与弧 ——
    /// 只有右下角这块永远空着。剪影一进文字区就会把 11pt 的字吃掉（旧版的病）。
    /// 为什么限两个：158pt 见方只容得下"一个意象"，第三个形状就开始像噪点。
    /// 颜色统一取 `band.sky.ink`（固定近白）而不是 `Theme.textPrimary`：后者会随外观翻转，
    /// 浅色外观下剪影变深灰，压在饱和色场上就直接消失了 —— 地图标识会跟着一起没。
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
        let rock = band.sky.ink.opacity(0.16)
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

    /// 雨林：两根高瘦树影。绿只能由品牌 `limeDeep` 补（`Theme.sky` 七档里没有绿色天空），
    /// 按附录 A 的分工，`limeDeep` 只做雾与形、不承载任何文字。
    private func trees(width w: CGFloat, height h: CGFloat) -> some View {
        let trunk = Theme.limeDeep.opacity(0.18)
        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(trunk)
                .frame(width: max(2, w * 0.022), height: h * 0.16)
                .position(x: w * 0.66, y: h - h * 0.08)
            Capsule()
                .fill(trunk)
                .frame(width: max(2, w * 0.018), height: h * 0.11)
                .position(x: w * 0.82, y: h - h * 0.055)
        }
    }

    /// 霞谷：两道错开的山脊（峰顶左右偏，才不像"两个等腰三角形"）
    private func ridges(width w: CGFloat, height h: CGFloat) -> some View {
        let stone = band.sky.ink.opacity(0.16)
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
        let stone = band.sky.ink.opacity(0.18)
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
                .position(x: w * 0.87, y: h - h * 0.05)
        }
    }

    /// 禁阁：一座细塔 —— 塔身 + 塔尖两个形状（窄到极致才像"阁"而不是"楼"）。
    ///
    /// 旧的第三个形状（右侧矮塔）在 158pt 里只是一块噪点，本次删掉。
    private func towers(width w: CGFloat, height h: CGFloat) -> some View {
        let stone = band.sky.ink.opacity(0.18)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(stone)
                .frame(width: max(1.5, w * 0.018), height: h * 0.17)
                .position(x: w * 0.82, y: h - h * 0.085)
            Capsule()
                .fill(stone)
                .frame(width: max(1, w * 0.008), height: h * 0.05)
                .position(x: w * 0.82, y: h - h * 0.195)
        }
    }

    /// 伊甸：两块尖利乱石（峰顶横向偏移各不相同）
    private func spikes(width w: CGFloat, height h: CGFloat) -> some View {
        let stone = band.sky.ink.opacity(0.16)
        return ZStack(alignment: .topLeading) {
            RedstoneSpike(apexX: 0.30)
                .fill(stone)
                .frame(width: w * 0.24, height: h * 0.14)
                .position(x: w * 0.70, y: h - h * 0.07)
            RedstoneSpike(apexX: 0.62)
                .fill(stone)
                .frame(width: w * 0.18, height: h * 0.10)
                .position(x: w * 0.93, y: h - h * 0.05)
        }
    }
}

// MARK: - 地图档位

extension RedstoneBackdrop {

    /// 一张卡的「地图意象」= 从七档天色里挑一档 + 一个纱的浓度 + 一团气 + 一组剪影。
    ///
    /// 地图名的切分复用 `MapScene.family(of:)`：三种分隔符（`·` / `・` / `•`）
    /// 的容错只该有一份实现 —— 那份"地名归一"是唯一活下来的一小块，
    /// 它服务的配色表现在**只在这里**（不再有第二份）。
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
            switch MapScene.family(of: mapName) {
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
        /// 档位按参考图给的对照（云野→`day`、雨林→`blueDusk`、霞谷→`sunset`、
        /// 暮土→`blueDusk`、禁阁→`night`、伊甸→`night`）。六张能一眼分辨靠的是
        /// "档 + 纱 + 气 + 剪影"四件一起：雨林与暮土同为 `blueDusk`，但一个压 0.22 配绿雾 + 树影、
        /// 一个压 0.24 配绯红残光 + 断柱；禁阁与伊甸同为 `night`，一个压 0.20 配顶部冷光 + 细塔、
        /// 一个压 0.10 配地平线冷光 + 乱石 —— 六张里没有两张是同一组参数。
        var phase: SkyPhase {
            switch self {
            case .cloudSea: return .day
            case .rainForest: return .blueDusk
            case .canyon: return .sunset
            case .ruins: return .blueDusk
            case .tower: return .night
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

        /// 纱的浓度：压向该档 `sky.ground` 的比例。
        ///
        /// 六档全部收在 **0.10–0.28**（原来 0.18–0.76）。上限 0.28 是硬数：
        /// 再高就会把 `day` 档的蓝白天色压成一块灰白，卡就不"饱和"了。
        /// 档与档之间仍留 0.02–0.04 的差，是为了让"哪张图"在只看底色时也能感觉出区别。
        var veil: Double {
            switch self {
            case .cloudSea: return 0.28
            case .rainForest: return 0.22
            case .canyon: return 0.18
            case .ruins: return 0.24
            case .tower: return 0.20
            case .void: return 0.10
            case .unknown: return 0
            }
        }

        /// 那团气：颜色 + 峰值不透明度 + 位置 + 半径（占卡片长边的比例）。
        ///
        /// 半径 0.50 / alpha 0.16 是 R4 的两条硬上限（背景"那口气" ≤0.50 短边 / ≤0.18）。
        /// 中心从"贴边"（旧版暮土在 `0.66, 0.92`）移到主值附近 —— 大字与轨迹都在上半部，
        /// 光贴在那儿才是"给主值打的光"；贴在卡边只会变成整卡泛光，把色场渐变吃掉。
        /// 六档中心各偏 0.02–0.06，是留给"气质"的最后一点差异（云野偏左上、暮土偏右、伊甸正上）。
        /// 认不出的地图返回 nil（旧版静态夜没有这层）
        var glow: (color: Color, alpha: Double, center: UnitPoint, radius: CGFloat)? {
            switch self {
            case .cloudSea:
                // 云海反着光，光从左上方漫下来
                return (sky.edge, 0.16, UnitPoint(x: 0.34, y: 0.26), 0.50)
            case .rainForest:
                // 湿气浮在树影之间（七档天色里没有绿，绿由品牌 limeDeep 补，只做雾不承载文字）
                return (Theme.limeDeep, 0.16, UnitPoint(x: 0.40, y: 0.34), 0.50)
            case .canyon:
                // 两侧山脊之间那道落日，正好落在主值右下
                return (sky.edge, 0.16, UnitPoint(x: 0.38, y: 0.30), 0.50)
            case .ruins:
                // 荒土上的绯红残光（`blueDusk` 的 top 就是那层暗红），偏右一点避开地图名
                return (sky.top, 0.16, UnitPoint(x: 0.42, y: 0.34), 0.50)
            case .tower:
                // 冷紫天光从上方压下来，塔影因此是逆光的
                return (sky.edge, 0.16, UnitPoint(x: 0.34, y: 0.24), 0.50)
            case .void:
                // 只有一点冷光，位置最贴主值（伊甸靠"近黑 + 冷光"区分，不靠红）
                return (sky.edge, 0.16, UnitPoint(x: 0.38, y: 0.32), 0.50)
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
