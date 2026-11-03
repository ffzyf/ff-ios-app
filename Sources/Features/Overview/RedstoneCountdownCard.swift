import SwiftUI

/// 概览页置顶的红石卡（P01 / P0-4 升 Hero）。
///
/// 版式（设计报告 §4.1 hero 线框图）：
/// ```
/// ┌──────────────────────────────────────┐
/// │ 红石 · 今日                    [2.5×] │  ← Eyebrow + 倍率
/// │                                      │
/// │ 23:08                                │  ← 40pt `metricL`（今天最大的那个东西）
/// │ ↘ 还有 39:27                          │  ← 13pt
/// │ ↗ 下一场 23:08 · 霞谷 · 圆梦村         │  ← 13pt
/// │ ──────────────●──────────             │  ← 4pt 进度轨（今日第 2/3 场）
/// │ 11:08      17:08      23:08           │  ← 13pt 三场并列
/// │ 圆梦村      霞谷       霞谷            │  ← 11pt
/// └──────────────────────────────────────┘
/// ```
///
/// 三处刻意的改动：
/// 1. **纵向单栏**取代原来的"左栏 + 126pt 右栏"。右栏那张三行小表把卡压成 223pt 却只有
///    12pt 字，是"底盘大内容小"的典型；搬到底部做三场并列之后，同一份数据只用一种长相；
/// 2. **进度轨**回答"今天第几场"这个原来没说的话 —— 只有数字没有刻度，读者记不住自己在哪；
/// 3. 大数字走 `Typography.metricL`（原 inline 36pt 已删除），与收益页总额同一个 token。
///
/// **3.27.0：首页把它降到 168（`tier: .medium`）**，与下面那张天气卡等高。
/// 上面那张版式图是 240 档的画法；168 档少 72pt，取舍见 `isCompactHeight` 与
/// `liveContent(now:)` 里的间距分组 —— 必留的是大字 / 倒计时 / 进度轨，
/// 让位的是留白与"三场并列"的第二种排版（地图名不再逐场列出）。
///
/// **两种大字（3.16.0，用户："我不知道它在几点几月几号"）**：
/// ```
/// 今天还有场次（进行中 / 今天晚些）   今天已经没有了
/// 红石 · 今日                       红石 · 下一次
/// 23:08                            5 天后
/// ↘ 还有 39:27                      ↘ 周六 10:08
/// ↗ 下一场 23:08 · 霞谷 · 圆梦村      ↗ 禁阁 · 星漠水母湾
/// ```
/// 判据是 `RockPhase.hasRemainingSessionToday(now:)`（`Sources/Shared/Domain`，与小组件共用）——
/// **`.upcoming` 属于"今天还有"**，只有 `.endedToday`（下一场在明天或更远）才切成「N 天后」。
///
/// **三态**（判定在 `Shared/Domain/RedstoneWindow.swift`，与桌面小组件共用同一份）：
/// ```
/// 排期还没拉到              → 「排期还没生成」（原有逻辑，一个字都不改）
/// 本月有场次且全部已过       → 「本月红石已收官」+ 一条静态弧 + 月份文案
/// 还有进行中 / 未来场次      → 正常倒计时（原有逻辑，一个字都不改）
/// ```
/// 第二种状态是本次修的 bug：用户 10 月 31 日晚上看到「排期还没生成」，
/// 语义上完全不对 —— 排期生成过，只是这个月的都过完了。
///
/// 刷新粒度 1 秒：`39:27` 是 mm:ss，按分钟刷会僵住。只重建内容子树，
/// 卡片底盘（渐变 / 云海 / 描边）在 `TimelineView` 之外常驻。
struct RedstoneCountdownCard: View {
    @EnvironmentObject private var rock: RockStore
    /// 卡片档位只在宽档变大（240 → 344），所以高度与"大数字"都要读同一个判据 `usesWideCards`。
    @Environment(\.layoutMetrics) private var metrics

    /// 卡片高度档：首页窄档传 `.medium`（168）、宽档传 `.hero`（344），其它场景想复用可以继续降级
    private let tier: CardTier
    /// 点击整卡 → 切到红石 Tab（由 `OverviewView` 通过现有 tab binding 完成，不新建导航栈）
    private let onOpenRock: () -> Void

    init(tier: CardTier = .hero, onOpenRock: @escaping () -> Void) {
        self.tier = tier
        self.onOpenRock = onOpenRock
    }

    // MARK: - 这一档怎么排

    /// 这一档只有 168 高吗？**判据用卡高本身，不用 `tier` 名字**。
    ///
    /// 为什么不是 `tier == .medium`：真正约束排版的是"内容能拿到多少 pt"，而不是档位叫什么。
    /// 现在 `.medium` 在窄档与宽档都是 168，两者应当共用同一套紧凑排版；
    /// 反过来，哪天有人把 `.hero` 改矮或新增一档，按高度判会自动跟着走，按名字判则不会。
    ///
    /// 为什么阈值取 `CardTier.medium.height`（168）：它就是"能装下大字 + 倒计时 + 进度轨，
    /// 但装不下 240 那份宽松留白"的那条线 —— 这一档以下必须换紧凑排版，否则内容会溢出。
    private var isCompactHeight: Bool {
        return metrics.cardHeight(tier) <= CardTier.medium.height
    }

    /// 大字字号（**唯一**会随卡片高度变的字号）。
    ///
    /// - 168：`metricM`（28）—— 效果图里大字从 38 降到 32 的那种关系。40pt 的 `23:08`
    ///   在约 123pt 的可排高度里会吃掉三分之一，倒计时和进度轨就被挤到没有位置；
    /// - 宽档 hero（344）：`metricXL`（56）—— 卡片宽度翻倍、高度涨 43%，锚点必须跟着变大
    ///   （设计文档 §5.2：不放大就是"放大的空卡"）；
    /// - 窄档 hero（240）：`metricL`（40）—— 3.27.0 之前的版面，简报页等复用点。
    ///
    /// 三档全部取自 `Typography` 现有档位，不新造字号常量（本项目的字号只有这一处真源）。
    private var bigValueFont: Font {
        if isCompactHeight {
            return Typography.metricM
        }
        return metrics.usesWideCards ? Typography.metricXL : Typography.metricL
    }

    var body: some View {
        TrackCard(
            progress: ArcGeometry.dayProgress(),
            peak: 0.70,
            // 高度走 `cardHeight(_:)`：窄档首页 168（`.medium`）、宽档 344（`.hero`）。
            // 直接写 `tier.height` 会让 iPad 上继续是"放大的手机"。
            minHeight: metrics.cardHeight(tier),
            backdrop: .skyGame
        ) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if rock.hasLoadedAnyMonth {
                    cardContent(now: context.date)
                } else {
                    unavailableBlock
                }
            }
            .padding(Spacing.cardPadding)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture {
            Haptics.light()
            onOpenRock()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开红石日历")
        // 伪 3D 倾斜必须挂在最外层：旋转作用在玻璃外面，玻璃才能继续采样背后的页面背景
        .cardTilt(cornerRadius: Radius.card)
    }

    // MARK: - 有数据

    /// 按「本月窗口」三态分流。判定本身在 Shared（`RedstoneWindow`），这里只负责画。
    ///
    /// `.pending` 与 `.live` 共用同一套内容：`.pending` 时 `phase` 必然是 `.notGenerated`，
    /// `bigValue` 会写「排期还没生成」—— 那正是这边要保留的原有文案。
    @ViewBuilder
    private func cardContent(now: Date) -> some View {
        switch RedstoneWindow.state(days: rock.allLoadedDays, now: now) {
        case .closed(let month, let next):
            closedContent(month: month, next: next, now: now)
        case .pending, .live:
            liveContent(now: now)
        }
    }

    /// 有场次可等：大字 + 倒计时 + 进度轨（+ 今日场次的排期）
    ///
    /// ## 两套间距，只有间距与"场次那一行的排法"不同
    ///
    /// 内容的**顺序与组成完全一样** —— 变的是留白和底部那一组：
    /// ```
    ///                240 / 344 档            168 档
    /// 眉题             ↓                      ↓
    ///                 Spacer 12              Spacer 2
    /// 大字 40/56      ↓                      ↓ 28
    ///                 Spacer 10              Spacer 2
    /// 倒计时 + 在哪   ↓                      ↓
    ///                 Spacer 18              Spacer 2
    /// 进度轨          ↓ (下留 12)             ↓ (下留 4)
    /// 三场并列        时刻 + 地图两行          一行「时刻 · 时刻 · 时刻」
    /// ```
    ///
    /// 为什么 168 档必须换这一版：卡内真实可排高度 = 168 − 上下内边距 32 − 底盘底部让位
    /// （`TrackCard` 给 `.skyGame` 留 `arcGap × 0.6` ≈ 13）= **约 123pt**。逐项加起来：
    /// 眉题行 17（带倍率徽标）+ 大字 34 + 倒计时两行 34 + 进度轨 10 + 下留 4 + 场次一行 16
    /// ≈ **115**，三段留白的最小值 6 —— 合计 121，还剩 2pt 余量。
    /// 240 那一版按同样的算法：大字 48（40pt 行高）、场次两行 31，其余不变，
    /// 加 12/10/18 的留白 = 192，塞进 194 正好 —— 所以 240 也**不能被随便改矮**，
    /// 差的这 72pt 全是"没有留白可让"的硬内容。
    /// 取舍优先级（用户定的）：大字 / 倒计时 / 进度轨必留，"三场并列"让位。
    ///
    /// 为什么内边距仍写 16（`Spacing.cardPadding`）：168 已经贴到下限，再压内边距
    /// 会让文字离圆角太近（24 的圆角在 16 的内边距下才是同心的）。
    private func liveContent(now: Date) -> some View {
        let days = rock.allLoadedDays
        let phase = RedstoneTimeline.phase(in: days, now: now)
        let today = RedstoneTimeline.occurrences(in: days)
            .filter { $0.isOn(dayKey: RedstoneClock.dayKey(now)) }
        let compact = isCompactHeight

        return VStack(alignment: .leading, spacing: 0) {
            eyebrowRow(phase: phase, now: now)

            // Spacer 的 minLength 是"内容自然高度"的组成部分：底部高度由 TrackCard 的
            // `minHeight` 兜住，这里负责让几块内容撑到接近那个高度，
            // 免得整块内容被居中后上下各空出一大截。
            //
            // 紧凑档三段留白全给 2（不是 2/2/6）：`minLength` 只在**地方不够时**才起作用，
            // 有余量时 Spacer 会自己把空隙平分掉 —— 所以把最小值压到 2 一点视觉代价都没有，
            // 却多买了几 pt 的安全余量（这套高度是算出来的，不是量出来的，见 `liveContent` 的注释）。
            Spacer(minLength: compact ? 2 : 12)

            bigValue(phase: phase, now: now)

            Spacer(minLength: compact ? 2 : 10)

            detailLines(phase: phase, now: now)

            Spacer(minLength: compact ? 2 : 18)

            // 今日没有场次时整块不画：一条 0/0 的空轨比没有轨更让人困惑
            if today.isEmpty == false {
                RedstoneProgressTrack(
                    total: today.count,
                    index: trackIndex(today: today, now: now)
                )
                .padding(.bottom, compact ? 4 : 12)

                if compact {
                    // 168 档只画一行：三场的时刻并排，地图名让给"信息密度更高"的那一版。
                    // 不改成横滑：这张卡整卡可点（进红石页），横滑手势会和点击抢事件。
                    compactSessionRow(today: today, now: now)
                } else {
                    sessionRow(today: today, now: now)
                }
            }
        }
    }

    // MARK: - 本月已收官

    /// 收官态：**没有目标了**，所以不画倒计时、也不画"今日第 N/M 场"那条进度轨 ——
    /// 一条走到头却还在原地的轨只会让人以为卡住了。
    ///
    /// 取而代之的是一条静态弧：它画的是**这个月真实走过的场次**（首场 → 末场），
    /// 两端各一个暗节点、弧线整体压暗。比只剩一行字更不空，也一个假数据都没有。
    ///
    /// 168 档（3.27.0）：这一态原来按 240 排，固定内容就有 129pt、加留白 46pt = 175，
    /// 在 123pt 的可排高度里**必然溢出**。所以紧凑档收三处：留白 12/8/16/10 → 2/2/4/2、
    /// 说明文 `lineLimit 2 → 1`、静态弧 26 → 20。**没有删掉任何一块信息**：
    /// 首场 / 末场时刻与「本月 N 场」都还在 —— 收官态本来就只有这几句话。
    private func closedContent(month: Int, next: Int, now: Date) -> some View {
        let sessions = RedstoneWindow.monthOccurrences(days: rock.allLoadedDays, now: now)
        let state = RedstoneWindowState.closed(month: month, next: next)
        let compact = isCompactHeight

        return VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "红石 · 本月", color: Theme.trackTextDim)

            Spacer(minLength: compact ? 2 : 12)

            Text(state.closedTitle ?? "")
                .font(Typography.titleL)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: compact ? 2 : 8)

            Text(state.closedNote ?? "")
                .font(Typography.footnote)
                .foregroundStyle(Theme.trackTextDim)
                // 168 档只给一行：这句话说的是「下个月什么时候回来」，一行读得完；
                // 多给一行换来的是"弧线被挤掉"，而弧线才是这一态唯一的形状。
                .lineLimit(compact ? 1 : 2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: compact ? 4 : 16)

            if sessions.count >= 2 {
                RedstoneMonthSpentArc()
                    // 20 而不是 26：弧是"记号"，不是内容；矮 6pt 换来的是留白不至于全挤没
                    .frame(height: compact ? 20 : 26)

                HStack(spacing: 0) {
                    Text(sessions.first?.time ?? "")
                        .font(Typography.footnoteMedium)
                        .monospacedDigit()
                        .foregroundStyle(Theme.trackTextDim)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(sessions.last?.time ?? "")
                        .font(Typography.footnoteMedium)
                        .monospacedDigit()
                        .foregroundStyle(Theme.trackTextDim)
                        .lineLimit(1)
                }
                .padding(.top, 2)

                Spacer(minLength: compact ? 2 : 10)

                Text("本月 " + String(sessions.count) + " 场 · 全部已过")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.trackTextDim)
            }
        }
    }

    /// 眉题行：左边"这是什么栏目"，右边倍率 / 待核对（都是服务端给的，取不到就不画）
    private func eyebrowRow(phase: RockPhase, now: Date) -> some View {
        HStack(spacing: 6) {
            Eyebrow(text: eyebrowTitle(phase: phase, now: now), color: Theme.trackTextDim)
            Spacer(minLength: 6)
            if let rate = phase.occurrence?.rate {
                RateBadge(rate: rate)
            }
            if phase.occurrence?.needsCheck == true {
                NeedsCheckBadge()
            }
        }
    }

    /// 眉题文案：今天还有场次时这一屏讲的是「今日」；今天已经没有了，讲的就是**下一场**。
    ///
    /// 为什么必须分开写：大字这时写的是「5 天后」，如果眉题还写「红石 · 今日」，
    /// 读者会把「5 天后」读成"今天的某个时刻"。一句话的区别，语义天差地别。
    private func eyebrowTitle(phase: RockPhase, now: Date) -> String {
        switch phase {
        case .notGenerated, .ongoing, .upcoming:
            return "红石 · 今日"
        case .endedToday:
            return "红石 · 下一次"
        }
    }

    /// 大字：今天还有场次 → 焦点场次的时刻（`23:08`）；今天已经没有了 → 「5 天后」/「明天」。
    ///
    /// 两支护字**共用同一个字号**：字变少了不放大。否则同一张卡在不同时刻会跳字号
    /// （23:10 看是 40pt 的 `23:08`，23:11 看是 56pt 的「5 天后」），版式会抖。
    /// 未生成时不给任何数字。
    @ViewBuilder
    private func bigValue(phase: RockPhase, now: Date) -> some View {
        switch phase {
        case .notGenerated:
            Text("排期还没生成")
                .font(Typography.titleM)
                .foregroundStyle(Theme.textPrimary)
        default:
            if let occurrence = phase.occurrence {
                Text(headlineText(phase: phase, occurrence: occurrence, now: now))
                    // 字号三档全部在 `bigValueFont` 里（168 → 28 / 窄档 240 → 40 / 宽档 344 → 56），
                    // 判据是**卡片高度**而不是宽度 —— 理由见那个属性的注释。
                    .font(bigValueFont)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// 大字那一行的文字。
    ///
    /// - 今天还有场次（进行中 / 今天晚些）→ 时刻，`23:08`。**今天晚些的 `.upcoming` 走这一支**，
    ///   绝不能被当成"今日已结束"（判据见 `RockPhase.hasRemainingSessionToday(now:)`）；
    /// - 今天已经没有剩余场次（`.endedToday`，下一场在明天或更远）→ `5 天后` / `明天`；
    /// - 天差算不出来（日期键是脏数据）→ 退回时刻，宁可少说一句也不写「Nil 天后」。
    private func headlineText(phase: RockPhase, occurrence: Occurrence, now: Date) -> String {
        if phase.hasRemainingSessionToday(now: now) {
            return occurrence.time
        }
        return RockPhase.daysAheadLabel(occurrence, now: now) ?? occurrence.time
    }

    /// 大字下面两行：横向是"还有多久"，斜向是"下一场在哪"
    ///
    /// 「今天已无场次」时的版式换了一套（3.16.0 用户反馈："我不知道它在几点几月几号"）：
    /// ```
    /// 5 天后             ← 大字
    /// ↘ 周六 10:08       ← 哪一天的几点（原本这里是"还有 4 天 22 小时"）
    /// ↗ 禁阁 · 星漠水母湾 ← 在哪（原本这里重复一遍时刻）
    /// ```
    /// 长倒计时（「还有 4 天 22 小时」）在这一支里**不再出现**：它和大字说的是同一件事。
    private func detailLines(phase: RockPhase, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            switch phase {
            case .notGenerated:
                // 大字已经说了"排期还没生成"，这里只补一句接下来会怎样
                Text("等官方更新这月的排期。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.trackTextDim)
            default:
                if let occurrence = phase.occurrence {
                    if phase.hasRemainingSessionToday(now: now) {
                        if let detail = countdownLine(phase: phase) {
                            arrowLine(icon: "arrow.down.right", text: detail, emphasized: true)
                        }
                        arrowLine(icon: "arrow.up.right",
                                  text: placeText(phase: phase, occurrence: occurrence),
                                  emphasized: false)
                    } else {
                        // 日期用 `RockPhaseText.dayLabel`：今日 / 明日 / 周五 / 11月6日，
                        // 与顶部「下一场」条同一套口径（同一个"下一场"只该有一种叫法）。
                        arrowLine(icon: "arrow.down.right",
                                  text: RockPhaseText.dayLabel(occurrence, now: now) + " " + occurrence.time,
                                  emphasized: true)
                        arrowLine(icon: "arrow.up.right", text: occurrence.map, emphasized: false)
                    }
                }
            }
        }
    }

    /// "下一场 23:08 · 霞谷 · 圆梦村" —— 三样东西拼一行，缺哪个都不编（`map` 服务端一定有，可能是"待确认"）
    private func placeText(phase: RockPhase, occurrence: Occurrence) -> String {
        if phase.isOngoing {
            return "正在 " + occurrence.time + " · " + occurrence.map
        }
        return "下一场 " + occurrence.time + " · " + occurrence.map
    }

    /// ↘ 行：进行中给剩余分钟，否则给"还有 mm:ss"。
    ///
    /// `.endedToday` / `.notGenerated` 不在这里：前者的大字已经是「5 天后」，下行换成
    /// 「周六 10:08」（见 `detailLines`），再挂一句「还有 4 天 22 小时」就是同一件事说两遍；
    /// 后者大字已经说了"排期还没生成"。
    private func countdownLine(phase: RockPhase) -> String? {
        switch phase {
        case .ongoing(_, let minutesLeft):
            return "进行中 · 剩 " + String(minutesLeft) + " 分"
        case .upcoming(_, let seconds):
            return "还有 " + Formatters.countdown(seconds: seconds)
        case .endedToday, .notGenerated:
            return nil
        }
    }

    private func arrowLine(icon: String, text: String, emphasized: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(emphasized ? Theme.trackArc : Theme.trackTextDim)
            Text(text)
                .font(emphasized ? Typography.footnoteMedium : Typography.footnote)
                .foregroundStyle(emphasized ? Theme.textPrimary : Theme.trackTextDim)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }

    /// 底部"三场并列"：时刻（13pt）+ 地图（11pt）。
    ///
    /// 已过场次不靠 `.opacity()` 变淡，而是换成更淡的**文字 token** ——
    /// 透明度只能加在 `Theme.*` 上（PRD §3.4），换 token 同样达到"退到后面"的效果。
    private func sessionRow(today: [Occurrence], now: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(today.prefix(3))) { occurrence in
                VStack(alignment: .leading, spacing: 2) {
                    Text(occurrence.time)
                        .font(Typography.footnoteMedium)
                        .foregroundStyle(occurrence.endAt <= now ? Theme.trackTextDim : Theme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(occurrence.map)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.trackTextDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 168 档的"三场并列"：**一行时刻，地图名不画**。
    ///
    /// 为什么不是横滑（用户给的备选之一）：这张卡整卡可点（进红石页），
    /// 卡内再放一个横向滚动区就是两个手势抢同一块面积 —— 用户想点卡会划走，想滑会点开。
    /// 一行三个 `HH:mm`（13pt 等宽，每个约 34pt）在 353pt 宽的卡里绰绰有余，
    /// 而且「今天有哪几场」这个信息一点没丢，丢的只是"每一场在哪张图"——
    /// 地图信息在大字下面那句「下一场 23:08 · 霞谷 · 圆梦村」里已经有了。
    ///
    /// 已过场次仍然靠换 token 退到后面（同 `sessionRow`，不用 opacity）。
    /// 超过 3 场时补一句「等 N 场」：只画前三条不说明，会让人以为是全部。
    private func compactSessionRow(today: [Occurrence], now: Date) -> some View {
        let shown = Array(today.prefix(3))

        return HStack(spacing: 6) {
            // 用下标遍历而不是 `enumerated()`：元组的 key path（`\.element.id`）
            // Swift 不支持，写出来直接编译不过。`shown` 是 Array，下标从 0 开始，
            // 分隔点的判据就是 `index > 0`。
            ForEach(shown.indices, id: \.self) { index in
                if index > 0 {
                    Text("·")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.trackTextDim)
                }
                Text(shown[index].time)
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(shown[index].endAt <= now ? Theme.trackTextDim : Theme.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if today.count > shown.count {
                Text("等 " + String(today.count) + " 场")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.trackTextDim)
                    .lineLimit(1)
            }
        }
    }

    /// 进度轨节点落在第几场（1 起）：已结束的场次数 + 1；全部结束则停在最后一场。
    ///
    /// 用 `endAt` 而不是 `startAt` 判定"过了"：落地持续 52 分钟，
    /// 用开始时刻判会让正在落地的那一场被算成"已过"，节点就提前跳到下一场。
    private func trackIndex(today: [Occurrence], now: Date) -> Int {
        let finished = today.filter { $0.endAt <= now }.count
        return min(max(1, finished + 1), max(1, today.count))
    }

    // MARK: - 完全没有数据

    @ViewBuilder
    private var unavailableBlock: some View {
        if rock.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.trackArc)
                Text("正在看排期…")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.trackTextDim)
                Spacer(minLength: 0)
            }
        } else if let error = rock.lastError {
            VStack(alignment: .leading, spacing: 8) {
                Text(error.userMessage)
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                Button {
                    Haptics.light()
                    Task { await rock.loadSchedule(force: true) }
                } label: {
                    Text("重试")
                }
                .buttonStyle(PrimaryCTAStyle())
            }
        } else {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("暂无排期")
                        .font(Typography.titleS)
                        .foregroundStyle(Theme.textPrimary)
                    Text("去红石页看看这个月的场次。")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.trackTextDim)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.trackTextDim)
            }
        }
    }
}

// MARK: - 今日场次进度轨

/// 4pt 细轨 + 当前节点（设计报告 §4.1 hero 卡）。
///
/// 轨用 `Theme.trackArc`（这张卡自己的光轨色），节点用 `Theme.lime`（品牌色 = 当前位置），
/// 两者都是 token：深浅两套外观各自解析，View 层不判 `colorScheme`。
private struct RedstoneProgressTrack: View {
    /// 今日总场次
    let total: Int
    /// 当前是第几场（1 起）
    let index: Int

    /// 节点横向位置。
    ///
    /// 预留 9pt（节点直径）再乘比例：否则走到第 3/3 场时圆点会有一半溢出卡片右侧内边距。
    private func nodeX(width: CGFloat, ratio: CGFloat) -> CGFloat {
        let clamped = min(max(ratio, 0), 1)
        return clamped * max(width - 9, 0)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let ratio = total > 0 ? CGFloat(index) / CGFloat(total) : 0
            let x = nodeX(width: width, ratio: ratio)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.trackArc.opacity(0.28))
                    .frame(height: Layout.trackHeight)
                Capsule()
                    .fill(Theme.lime)
                    .frame(width: x + Layout.trackHeight, height: Layout.trackHeight)
                Circle()
                    .fill(Theme.lime)
                    .frame(width: 9, height: 9)
                    .offset(x: x)
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("今日第 " + String(index) + "/" + String(total) + " 场")
    }
}

// MARK: - 本月已走的静态弧

/// 收官态那条弧：**一条走完的弧**，没有光点、没有动画、没有已过未过的区别。
///
/// 为什么复用 `HorizonEdge`：它已经和简报卡、桌面组件是同一条二次贝塞尔曲线。
/// 为了一张"静态弧"再写一遍 `Path`，两条曲线迟早会在某次改版里对不上 ——
/// 一条曲线只该有一个实现。
///
/// 两端各一颗暗节点 = 本月首场 / 末场落在弧上的位置（节点本身就是"到过这里"的记号）。
/// 颜色只有 `Theme.trackArc` 一支，透明度降下来表示"已经过去了"，不引入任何新色。
private struct RedstoneMonthSpentArc: View {

    /// 弧顶（占弧带高度）
    private let crestY: CGFloat = 0.22
    /// 弧两端（占弧带高度）
    private let edgeY: CGFloat = 0.92
    /// 端点节点直径
    private let nodeDiameter: CGFloat = 3
    /// 弧本体不透明度（比"进行中"那条暗一档）
    private let arcAlpha: Double = 0.28
    /// 端点节点不透明度
    private let nodeAlpha: Double = 0.30

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                HorizonEdge(crestY: crestY, edgeY: edgeY)
                    .stroke(Theme.trackArc.opacity(arcAlpha), lineWidth: 1.2)

                Circle()
                    .fill(Theme.trackArc.opacity(nodeAlpha))
                    .frame(width: nodeDiameter, height: nodeDiameter)
                    .position(x: nodeDiameter, y: size.height * edgeY)

                Circle()
                    .fill(Theme.trackArc.opacity(nodeAlpha))
                    .frame(width: nodeDiameter, height: nodeDiameter)
                    .position(x: size.width - nodeDiameter, y: size.height * edgeY)
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }
}
