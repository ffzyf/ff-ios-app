import SwiftUI

/// 收益工作站（V3.2 新增，替换原来的「文章」Tab 位）。
///
/// 网页端（`creator-earnings-tracker.pages.dev`）的收益统计搬到这里：总额 / 三态构成 /
/// 本月新增 / 平台占比 / 活动流水。
///
/// **能建活动、也能记一笔，但账不在本地**：App 通过 `POST /api/app/earnings/activity` 建活动、
/// 通过 `POST /api/app/earnings/entry` 往活动里追加条目（见 `EarningsRecordSheet`），
/// 与网页端读同一份 KV。改活动 / 勾「已发」仍在网页端 —— 那些要长表单，塞进手机反而更难用。
///
/// 未登录时给登录引导页（不是弹窗）：`EarningsAuth` 要管理密码，弹窗一关就得重来。
///
/// ## 版面（设计报告 §4.4 / P0-8）
///
/// 改版前的病是"一个大数字 + 一堆 12pt 小字表"：整页只有 hero 一处重量，往下全是同宽同圆角的
/// 卡片，眼睛扫不到"这是新的一组"。现在的区块顺序与重量：
///
/// 1. **hero 216pt**：眉题（总计 · 本月新增）+ 40pt `metricL` 总额 + 10pt 三态堆叠条 + 图例
///    + 右下「记一笔」入口 —— 一屏唯一的锚点；
/// 2. **「本月」+ 三张 96pt tile**：本月新增（28pt `metricM`，涨红跌绿）/ 待结算 / 活动 · 平台；
/// 3. **「平台占比」+ 明细**：占比条 6→12pt、名称 12→15pt、金额 12→17pt；
///    「明细」把原来那张独立的「平台明细」卡收进同一组（不必再为大区块付一次组距）；
/// 4. **「最近活动」+ 全部**：行高 72，名称 15pt、金额 17pt；
/// 5. 页脚 11pt 说明。
///
/// 组间一律 `Spacing.sectionGapLoose` 32、组内 `Spacing.cardGap` 12；分区标题一律走
/// `SectionHeader`（22pt + 右侧动作 + 12pt 下距），不再有自造的 12pt「假分区标题」。
struct EarningsView: View {

    @ObservedObject private var auth = EarningsAuth.shared
    @ObservedObject private var store = EarningsStore.shared

    @State private var password: String = ""
    @State private var loginError: String?
    @State private var isSubmitting: Bool = false
    /// 「记一笔」表单
    @State private var showsRecord: Bool = false
    /// 平台「明细」展开态：占比条回答"谁占多少"，明细补"待发 / 已收 / 场次"。
    /// 两件事同源（都来自 `platformBreakdown` / `platforms`），放一张卡里就不必各占一个区块。
    @State private var showsPlatformDetail: Bool = false
    /// 「最近活动」是否已展开到全部（默认 12 条，与服务端一次返回的量级匹配）
    @State private var showsAllActivities: Bool = false
    @FocusState private var isPasswordFocused: Bool

    /// hero 卡最小高度（报告 §4.4 线框图指定 216pt）。
    ///
    /// 为什么不直接用 `CardTier.hero.height`：240 是首页红石倒计时那一档（它还有 4pt 进度轨
    /// 与"三场并列"行）；收益 hero 里只有一个数字 + 一条构成条 + 一行图例，216 才是它的内容高度。
    /// 用 `minHeight` 而不是固定 `height`：数字换行或大字号时卡可以长高，不会裁字。
    private let heroMinHeight: CGFloat = 216.0
    /// 平台占比条厚度（报告 §4.4：6 → 12）。`Layout` 里只有构成条 10 与轨道 4，没有这一档，
    /// 就近声明成常量，避免在 `GeometryReader` 里再写一遍魔法数字。
    private let ratioBarHeight: CGFloat = 12.0
    /// 活动行高度（报告 §4.4：72pt）。名称 15 + 元信息 12 两行文字需要的最小呼吸量。
    private let activityRowHeight: CGFloat = 72.0
    /// 默认展示的活动条数（超过才给「全部」动作）
    private let recentActivityLimit: Int = 12

    let scrollPosition: Binding<ScrollPosition>

    init(scrollPosition: Binding<ScrollPosition>) {
        self.scrollPosition = scrollPosition
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
                header

                if auth.isLoggedIn {
                    if let summary = store.summary {
                        heroCard(summary: summary)
                        monthSection(summary: summary)
                        platformSection(summary: summary)
                        activitySection
                        footerNote
                    } else if store.isLoading {
                        loadingCard
                    } else {
                        emptyCard
                    }
                } else {
                    loginCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
        }
        .scrollPosition(scrollPosition)
        .scrollIndicators(.hidden)
        .refreshable {
            await store.load(force: true)
        }
        .task {
            // 已登录才拉：没凭证时 load() 自己会清成空态，不发请求
            await store.load()
        }
        .sheet(isPresented: $showsRecord) {
            EarningsRecordSheet()
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("收益")
                    .font(Typography.display)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if auth.isLoggedIn {
                    Button {
                        Haptics.light()
                        Task { await store.load(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background {
                                Circle().fill(Theme.glassFill)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("刷新收益")
                }
            }

            HStack(spacing: 6) {
                if let updated = store.updatedText {
                    Text(updated)
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textTertiary)
                    if store.isStale {
                        Text("· 离线数据")
                            .font(Typography.footnote)
                            .foregroundStyle(Theme.statusWarn)
                    }
                } else {
                    Text(auth.isLoggedIn ? "来自收益工作台" : "需要访问密码")
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    // MARK: - hero（一屏唯一锚点）

    private func heroCard(summary: EarningsSummary) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                // 眉题说"这是什么口径的数"：总计 + 本月新增。金额单独着色，
                // 因为 `Eyebrow` 只吃一个颜色 —— 让它整条变红，就把"总计"这个标签也染红了
                HStack(spacing: 5) {
                    Eyebrow(text: "总计 · 本月")
                    Text(monthAddedText(summary.monthAdded))
                        .font(Typography.eyebrow)
                        .tracking(Typography.trackingEyebrow)
                        .foregroundStyle(monthAddedColor(summary.monthAdded))
                        .monospacedDigit()
                        .lineLimit(1)
                    Image(systemName: summary.monthAdded >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(monthAddedColor(summary.monthAdded))
                    Spacer(minLength: 0)
                }

                Text(EarningsMoney.formatCents(summary.total))
                    .font(Typography.metricL)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                // 三态构成条：pending + receivedUnclosed + closed 就是这条条的全部，
                // "本月新增"是流量口径，刻意不参与（见 `StatCompositionBar` 注释）
                StatCompositionBar(
                    pending: summary.pending,
                    receivedUnclosed: summary.receivedUnclosed,
                    closed: summary.closed
                )

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if canRecord {
                        recordButton
                    }
                }
            }
            .padding(Spacing.cardPadding)
            .frame(minHeight: heroMinHeight, alignment: .topLeading)
        }
    }

    /// 本月新增的文案：正数带 `+`，负数交给 `EarningsMoney` 自己带 `-`（它已经带 `¥` 前缀）
    private func monthAddedText(_ cents: Int) -> String {
        let body = EarningsMoney.formatCents(abs(cents))
        return cents >= 0 ? "+" + body : "-" + body
    }

    /// 涨=红 / 跌=绿（中国习惯）。不能借 `statusError` / `statusNew`：
    /// 那是"出错了 / 有新版本"，用在金额上会被读成状态而不是趋势。
    private func monthAddedColor(_ cents: Int) -> Color {
        return cents >= 0 ? Theme.riseRed : Theme.fallGreen
    }

    /// 能不能记账：**只要登录了就给入口**。
    ///
    /// 早先这里的条件是「登录 + 至少一个活动」，因为那时建活动只能在网页端做，
    /// 没活动就等于没地方记账。现在弹页里可以建活动（`POST /api/app/earnings/activity`），
    /// 所以「一个活动都没有」恰恰是最该点进来的情况 —— 再挡住入口就等于把建活动的路也堵了。
    private var canRecord: Bool {
        return auth.isLoggedIn
    }

    /// 「记一笔」入口（hero 卡右下角）。
    private var recordButton: some View {
        Button {
            Haptics.light()
            showsRecord = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.onLime)
                Text("记一笔")
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.onLime)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background { Capsule().fill(Theme.lime) }
            .overlay { Capsule().strokeBorder(Theme.glassStrokeTop, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("记一笔收入")
    }

    // MARK: - 本月 · 三张 tile

    private func monthSection(summary: EarningsSummary) -> some View {
        // `SectionHeader` 自带 12pt 下距，所以这里用 spacing 0 而不是再加一层 cardGap
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "本月")
            HStack(spacing: Spacing.cardGap) {
                statTile(title: "本月新增") {
                    Text(monthAddedText(summary.monthAdded))
                        .font(Typography.metricM)
                        .foregroundStyle(monthAddedColor(summary.monthAdded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }

                statTile(title: "待结算") {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(summary.pendingActivityCount)")
                            .font(Typography.metricM)
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                        Text("个")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .lineLimit(1)
                }

                statTile(title: "活动 / 平台") {
                    Text("\(summary.activityCount) / \(summary.platformCount)")
                        .font(Typography.metricM)
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            }
        }
    }

    /// 96pt tile 的统一外壳：眉题在顶、数字在底（`Spacer` 把两边顶开，
    /// 三张卡的数字基线因此永远对齐，即便某张数字因缩放变窄）。
    private func statTile<Value: View>(
        title: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: title)
                Spacer(minLength: 0)
                value()
                Spacer(minLength: 0)
            }
            .padding(Spacing.smallCardPadding)
            .frame(height: CardTier.tile.height, alignment: .leading)
        }
    }

    // MARK: - 平台占比（含平台明细）

    @ViewBuilder
    private func platformSection(summary: EarningsSummary) -> some View {
        if summary.platformBreakdown.isEmpty == false {
            VStack(alignment: .leading, spacing: 0) {
                // 动作显式写在 `action:` 上（不用尾随闭包）：`SectionHeader` 还有"右侧插槽"
                // 那个泛型构造，两处都用尾随闭包会让重载解析含糊
                SectionHeader(
                    title: "平台占比",
                    actionTitle: showsPlatformDetail ? "收起" : "明细",
                    action: {
                        withAnimation(Motion.expand) {
                            showsPlatformDetail.toggle()
                        }
                    }
                )

                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.cardGap) {
                        ForEach(summary.platformBreakdown) { item in
                            breakdownRow(item: item, total: summary.total)
                        }

                        if showsPlatformDetail {
                            Rectangle()
                                .fill(Theme.divider)
                                .frame(height: 1)

                            if store.platforms.isEmpty {
                                // 明细来自响应顶层 `platforms`，与占比同源但不同字段；
                                // 只有占比、没有明细时给一句实话，不编造平台行
                                Text("平台明细要等下次总览刷新才带得回来。")
                                    .font(Typography.footnote)
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.5))
                            } else {
                                ForEach(store.platforms) { platform in
                                    platformDetailRow(platform)
                                }
                            }
                        }
                    }
                    .padding(Spacing.cardPadding)
                }
            }
        }
    }

    private func breakdownRow(item: EarningsPlatformBreakdown, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // 15pt：平台名要能被"读到"，改版前 12pt 与金额同级，撑不起"平台占比"这四个字
                Text(item.name)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                // 17pt：金额是这一行的读数
                Text(EarningsMoney.formatCents(item.amount))
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(percentText(amount: item.amount, total: total))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }

            // 占比条：分母用 total，不依赖 `ratio` 字段的口径（服务端给百分数还是小数，
            // 这里不猜；金额是确定的，自己算最稳）。条高 6 → 12（报告 §4.4）
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.glassFill)
                        .frame(height: ratioBarHeight)
                    Capsule()
                        .fill(Theme.chartBar)
                        .frame(
                            width: barWidth(total: total, amount: item.amount, full: geo.size.width),
                            height: ratioBarHeight
                        )
                }
            }
            .frame(height: ratioBarHeight)
        }
    }

    /// 单条占比宽度。最小 3pt：占比极小（0.1%）时也要留一条可见的痕，
    /// 否则用户会以为这个平台没数据。
    private func barWidth(total: Int, amount: Int, full: CGFloat) -> CGFloat {
        guard total > 0, amount > 0 else { return 0 }
        let ratio = min(1, Double(amount) / Double(total))
        return max(3, full * CGFloat(ratio))
    }

    /// 百分比文案。同样从金额算，不读 `ratio`（口径只保留一处）
    private func percentText(amount: Int, total: Int) -> String {
        guard total > 0, amount > 0 else { return "0%" }
        let percent = Int((Double(amount) / Double(total) * 100).rounded())
        return "\(percent)%"
    }

    private func platformDetailRow(_ platform: EarningsPlatform) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(platform.name)
                .font(Typography.callout)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text("\(platform.acts) 场")
                .font(Typography.caption)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text("待发 " + EarningsMoney.formatCents(platform.pendingCents))
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.statusWarn)
                    .monospacedDigit()
                Text("已收 " + EarningsMoney.formatCents(platform.receivedCents))
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
        }
    }

    // MARK: - 最近活动

    @ViewBuilder
    private var activitySection: some View {
        if store.activities.isEmpty == false {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(
                    title: "最近活动",
                    actionTitle: activitiesActionTitle,
                    action: {
                        withAnimation(Motion.expand) {
                            showsAllActivities.toggle()
                        }
                    }
                )

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleActivities) { activity in
                            activityRow(activity)
                            if activity.id != visibleActivities.last?.id {
                                Rectangle()
                                    .fill(Theme.divider)
                                    .frame(height: 1)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.cardPadding)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    /// 「全部 / 收起」——活动不足一页时不给动作：一个点了没反应的按钮比没有更糟
    private var activitiesActionTitle: String? {
        guard store.activities.count > recentActivityLimit else { return nil }
        return showsAllActivities ? "收起" : "全部"
    }

    private var visibleActivities: [EarningsActivity] {
        guard showsAllActivities == false else { return store.activities }
        return Array(store.activities.prefix(recentActivityLimit))
    }

    private func activityRow(_ activity: EarningsActivity) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                // 15pt：活动名是这一行的主语
                Text(activity.name)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(activity.platform + " · " + EarningsClock.format(ms: activity.time))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                // 17pt：金额与平台占比卡保持同一档
                Text(EarningsMoney.formatCents(activity.totalCents))
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(activity.isClosed ? "已结" : "进行中")
                    .font(Typography.caption)
                    .foregroundStyle(activity.isClosed ? Theme.textTertiary : Theme.statusOk)
            }
        }
        .frame(minHeight: activityRowHeight)
        .contentShape(Rectangle())
    }

    // MARK: - 状态页

    private var loadingCard: some View {
        GlassCard {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(Theme.lime)
                Text("正在读取收益…")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(Spacing.cardPadding)
        }
    }

    private var emptyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.errorText ?? "还没有读到收益数据")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    Haptics.light()
                    Task { await store.load(force: true) }
                } label: {
                    Text("重新读取")
                }
                .buttonStyle(PrimaryCTAStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.cardPadding)
        }
    }

    // MARK: - 登录引导

    private var loginCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("连接收益工作台")
                        .font(Typography.titleM)
                        .foregroundStyle(Theme.textPrimary)
                    Text("用网页端的访问密码登录一次，之后就免密。")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textTertiary)
                }

                SecureField("访问密码", text: $password)
                    .textContentType(.password)
                    .focused($isPasswordFocused)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                            .fill(Theme.glassFill)
                    }
                    .submitLabel(.go)
                    .onSubmit { submit() }

                if let loginError {
                    Text(loginError)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.statusError)
                }

                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small).tint(Theme.onLime)
                    } else {
                        Text("登录")
                    }
                }
                .buttonStyle(PrimaryCTAStyle())
                .disabled(isSubmitting || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("密码就是网页端 `ACCESS_PASSWORD`。App 只存一个 30 天有效的会话 Cookie 在 Keychain，退出即删。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
            }
            .padding(Spacing.cardPadding)
        }
    }

    private func submit() {
        let value = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        loginError = nil
        Haptics.light()
        Task {
            do {
                try await auth.login(password: value)
                password = ""
                isPasswordFocused = false
                await store.load(force: true)
            } catch let error as EarningsAuthError {
                loginError = error.userMessage
            } catch {
                loginError = "登录没成功，稍后再试。"
            }
            isSubmitting = false
        }
    }

    // MARK: - 页脚

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("App 里能建活动、选平台、记一笔；改活动 / 勾「已发」仍在网页端。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            if store.activities.isEmpty {
                Text("还没有活动：点 hero 卡里的「记一笔」，在里面填名称 + 平台就能建一个。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.statusWarn)
            }
        }
        .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
        .padding(.horizontal, 4)
    }
}
