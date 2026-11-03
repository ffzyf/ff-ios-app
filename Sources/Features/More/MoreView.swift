import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 更多（Tab 5，PRD P13）。
///
/// 两组：「工具」= 收益（3.28.0 从底栏搬来）/ 问卷工作台 / 推送监控 / 检查更新；
/// 「其他」= 设置 / 关于。
///
/// 为什么是两个低频功能 + 设置 + 关于，而不是把它们塞进 Tab：
/// 问卷是"发起—回收—看结果"的批次动作，监控是"抽查一下"，都不构成每日回路；
/// 做成一级 Tab 会让未登录用户长期看到一个空壳页（PRD §2.3 的判断）。
///
/// 未登录时问卷行是「未连接」灰态：文字变灰、右侧给出状态字，点进去是登录引导页
/// （不是弹窗、不是禁用 —— 用户想连上，得给他一条路）。
struct MoreView: View {
    @ObservedObject private var auth = SurveyAuth.shared
    @ObservedObject private var store = SurveyStore.shared
    /// 批次 4：监控行的右侧状态字来自这里（有新版本 / 已是最新 / 检查失败）。
    /// 单例观察，与问卷那一行同款写法 —— 少一层环境注入，少一处运行期崩溃面。
    @ObservedObject private var monitor = MonitorStore.shared
    /// 3.10.0：「检查更新」行。观察单例让 `lastCheckSummaryText`（状态机投影）即时上屏。
    @ObservedObject private var update = UpdateStore.shared
    /// 限频时的瞬时提示（2 秒即逝）。它不是状态机的账（理由见 `UpdateStore.lastCheckSummaryText`），
    /// 所以只留在 View 的 `@State` 里，不复写 Store 的任何字段。
    @State private var rateLimitedHint: String? = nil
    /// 尺寸模型（设计文档 §4.6）：rail 档把两张状态 tile 搬到右侧 368，
    /// 四行工具列表留在主列 —— 这一页原来最"空"（内容 752 高、只占 57% 的宽度）。
    @Environment(\.layoutMetrics) private var metrics
    /// 主列实测高度（副列靠它撑高，`Spacer` 才吸得到差额；理由见 `View.measureHeight(into:)`）
    @State private var mainColumnHeight: CGFloat = 0

    @State private var showsWorkspace: Bool = false
    @State private var showsMonitor: Bool = false
    @State private var showsSettings: Bool = false
    @State private var showsAbout: Bool = false
    /// 滚动偏移保活（B3）：由 RootView 持有字典并作为 Binding 注入。
    let scrollPosition: Binding<ScrollPosition>

    /// 「收益」入口（3.28.0）。收益已从底栏移出（第 3 格让给 AI），
    /// 这一页的「工具」组里那一行是它**唯一**的入口。
    ///
    /// 为什么把切页动作做成闭包交给 `RootView`：Tab 选择那个 Binding 在根视图手里，
    /// 触觉与切页动画都挂在它的 setter 里；让本页自己造一个"直接改 tab"的通道，
    /// 就会出现"从这里进收益是硬切的、从底栏进是滑动过去的"两套手感。
    private let onOpenEarnings: () -> Void

    /// 显式 init：`@State` / `@ObservedObject` 都是 private 存储属性，
    /// 会把自动生成的 memberwise init 降级成 private，
    /// 跨文件 `MoreView(scrollPosition:onOpenEarnings:)` 就调不到。
    init(scrollPosition: Binding<ScrollPosition>, onOpenEarnings: @escaping () -> Void) {
        self.scrollPosition = scrollPosition
        self.onOpenEarnings = onOpenEarnings
    }

    var body: some View {
        ScrollView {
            // 组间 32（`sectionGapLoose`）/ 组内 8（`gridUnit`）：改版前 4 行全是 48pt 等高 + 8pt 等距，
            // 问卷 / 监控 / 设置 / 关于混在一列里，谁跟谁都读不出关系（设计报告 §4.5）
            VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
                header
                mainGroups
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
            // 列宽：rail 档 = 画布 1080 + 页边距（主 680 / 32 / 副 368），否则 720（= 今天）。
            // 窄屏 393 < 720 → 无影响。
            .pageColumn(metrics.railPageWidth)
        }
        .scrollPosition(scrollPosition)
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            PageToast(message: store.toast)
        }
        .task(id: store.toast) {
            guard store.toast != nil else { return }
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(Motion.glassOut) {
                store.clearToast()
            }
        }
        // 监控行的状态字是"顺带"信息：进页面时补一次，失败也只是右侧留白
        .task {
            await monitor.load()
        }
        // 限频提示 2 秒即逝：提示挂太久会让人以为每次点都被拦
        .task(id: rateLimitedHint) {
            guard rateLimitedHint != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            rateLimitedHint = nil
        }
        // 工作台是全屏接管：里面要看答卷明细、要填答，底部 Tab 栏不该参与
        .fullScreenCover(isPresented: $showsWorkspace) {
            SurveyWorkspaceView()
        }
        // 推送监控：批次 4 已落地为原生页（两张版本卡 + 立即检查 + 时段说明）
        .fullScreenCover(isPresented: $showsMonitor) {
            MonitorView()
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showsAbout) {
            MoreAboutSheet()
        }
    }

    // MARK: - 分组排布（单列 / rail）

    /// 窄档：两张 tile 横排 → 工具 → 其他 → 页脚（顺序与 3.7.0 一字不差）。
    /// rail 档：工具 + 其他 留主列，两张 tile 竖排搬进 368 的副列，页脚贴副列底
    /// （设计文档 §4.6：左 ≈ 328、右自然 ≈ 252 → `Spacer` 吃掉 76，两列底边齐）。
    @ViewBuilder
    private var mainGroups: some View {
        if metrics.usesRail {
            HStack(alignment: .top, spacing: Layout.columnGap) {
                mainColumn
                    .frame(maxWidth: metrics.railMainWidth)
                    .measureHeight(into: $mainColumnHeight)
                sideColumn
                    .frame(width: Layout.sideColumnWidth)
                    // `minHeight` 而不是 `height`：副列内容比主列高时不溢出卡片，
                    // 内容矮时仍然撑到主列高度 —— `Spacer` 吃差额，页脚压到底边（齐平保留）。
                    .frame(minHeight: sideColumnHeight, alignment: .top)
            }
        } else {
            statusRow
            mainColumn
            footNote
        }
    }

    /// 主列：工具 + 其他（两组的定义只有一份，两个档共用）
    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
            toolsGroup
            otherGroup
        }
    }

    /// 副列：两张状态 tile（368×120，间距 12）+ `Spacer(minLength: 32)` + 页脚说明
    ///
    /// 两张 tile 用内层 `VStack(spacing: cardGap)` 而不是两个 `Spacer`：12 是**固定间距**，
    /// `Spacer` 是"吸收剩余"，用它当间距会让两个 120 高的卡被拉开到 248 —— 那是另一种错。
    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: Spacing.cardGap) {
                surveyTile
                monitorTile
            }
            Spacer(minLength: Layout.columnGap)
            footNote
        }
    }

    /// 副列高度：量到主列才给值，首帧（0）给 `nil` = 按内容自然高
    private var sideColumnHeight: CGFloat? {
        return mainColumnHeight > 0 ? mainColumnHeight : nil
    }

    /// 窄档的两张 tile 横排。宽档不渲染这一行（它们在副列里竖排）。
    private var statusRow: some View {
        // 顶部两张 tile：把"连接状态"从行内 13pt 的一小串字，
        // 提成一组 20pt 的状态卡 —— 这一页最先该被看到的就是"连上了没有"
        HStack(spacing: Spacing.cardGap) {
            surveyTile
            monitorTile
        }
    }

    private var surveyTile: some View {
        statusTile(
            title: "问卷",
            value: auth.isLoggedIn ? "已连接" : "未连接",
            valueColor: auth.isLoggedIn ? Theme.limeInk : Theme.textTertiary,
            detail: auth.isLoggedIn ? "可进工作台" : "要管理密码"
        ) {
            openWorkspace()
        }
    }

    private var monitorTile: some View {
        statusTile(
            title: "推送监控",
            value: monitorTimeText,
            valueColor: Theme.textPrimary,
            detail: monitor.summaryText ?? "点开看明细"
        ) {
            showsMonitor = true
        }
    }

    private var toolsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "工具")
            VStack(spacing: Spacing.gridUnit) {
                // 收益（3.28.0）：底栏让位给 AI 之后搬到这里，排在「工具」组第一位 ——
                // 它是一个完整的工作站（和问卷工作台同级），不该埋进「其他」里跟设置并排
                MoreRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "收益"
                ) {
                    onOpenEarnings()
                }

                MoreRow(
                    icon: "list.bullet.rectangle.portrait",
                    title: "问卷工作台",
                    detail: auth.isLoggedIn ? "已连接" : "未连接",
                    isMuted: !auth.isLoggedIn
                ) {
                    openWorkspace()
                }

                MoreRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "推送监控",
                    // 取不到就显示 nil（右侧留白）；绝不写「未知」——
                    // 这行要么说事实（有新版本 / 已是最新 + 时间），要么什么都不说
                    detail: monitor.summaryText,
                    isMuted: monitor.summaryText == nil
                ) {
                    showsMonitor = true
                }

                MoreRow(
                    icon: "arrow.down.circle",
                    title: "检查更新",
                    // 限频提示优先（它最"新"），否则显示状态机投影（检查中… / 已是最新 / 有新版本）；
                    // idle 时右侧留白，与监控行同一口径
                    detail: rateLimitedHint ?? update.lastCheckSummaryText,
                    isMuted: (rateLimitedHint ?? update.lastCheckSummaryText) == nil
                ) {
                    checkForUpdate()
                }
            }
        }
    }

    private var otherGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "其他")
            VStack(spacing: Spacing.gridUnit) {
                MoreRow(
                    icon: "gearshape",
                    title: "设置",
                    detail: nil,
                    isMuted: false
                ) {
                    showsSettings = true
                }

                MoreRow(
                    icon: "info.circle",
                    title: "关于",
                    detail: appVersion,
                    isMuted: false
                ) {
                    showsAbout = true
                }
            }
        }
    }

    private var footNote: some View {
        Text("问卷工作台要管理密码；推送监控是匿名只读，不需要登录。")
            .font(Typography.captionXS)
            .foregroundStyle(Theme.textTertiary)
            .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
            .padding(.horizontal, 4)
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("更多")
                .font(Typography.display)
                .tracking(Typography.trackingLarge)
                .foregroundStyle(Theme.textPrimary)
            Text(auth.isLoggedIn ? "问卷已连接 · 其余都在这一页" : "只有问卷要密码，监控与设置都不用登录")
                .font(Typography.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - 顶部状态 tile

    /// 96pt 状态 tile：眉题在上、状态在下，整块可点。
    ///
    /// 为什么单开一个组件而不是复用 `MoreRow`：行的信息量是"一行字 + 一个状态字"，
    /// 而这一页第一眼要回答的是"连上了没有" —— 那需要一个 ≥20pt 的字（R6：每张卡都要有一个"大东西"）。
    private func statusTile(
        title: String,
        value: String,
        valueColor: Color,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            GlassCard {
                // 高度走 `cardHeight(.tile)`：窄档 96（今天）/ 宽档 120。
                // 96 − 24（上下内距）= 72pt 可用：眉题 13 + 状态 24 + 说明 16 + 3 条 4pt 间距 = 65，
                // 剩下的由 `Spacer` 吃掉 —— 状态字因此被压到卡的下半部，两张 tile 底线对齐。
                // 宽档 120 走同一套推导，多的 24pt 也全给 `Spacer`，所以文字位置不变、卡变高。
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: title)
                    Spacer(minLength: 0)
                    Text(value)
                        // 20pt：连接状态从行内 13pt 提上来，这一页的"大东西"
                        .font(Typography.titleM)
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(detail)
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(Spacing.smallCardPadding)
                .frame(height: metrics.cardHeight(.tile), alignment: .leading)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    /// 推送监控 tile 的大字：最近一次推送的时刻。
    ///
    /// 取不到就给「—」（与 `MonitorAppVersion.displayVersion` 同一套"没有就说没有"的做法），
    /// 不写「未知」也不编一个时间；状态字仍由 `MonitorStore.summaryText` 提供，
    /// 与「工具」组里那一行的口径完全同源。
    private var monitorTimeText: String {
        guard let last = monitor.response?.lastPushAt else { return "—" }
        return Formatters.timeHHmm(last)
    }

    // MARK: - 动作

    /// 「检查更新」行的动作（3.10.0）。
    ///
    /// 行为：`checkNow()`（3.9.0 已有的 60 秒限频入口）→ 有更新走 `present()`
    /// （弹层挂在 `FFWangApp` 的全局 `.sheet(item:)` 上，这里只管置值）；
    /// 被限频给一条 2 秒即逝的提示；已在检查中就什么都不加（副标题已经写着「检查中…」）。
    private func checkForUpdate() {
        Haptics.light()
        Task { @MainActor in
            let started = await UpdateStore.shared.checkNow()
            if started {
                // 检查完成后再看一次：有可用更新就弹层（present() 内部判 release 非空）
                if UpdateStore.shared.release != nil {
                    UpdateStore.shared.present()
                }
            } else if case .checking = UpdateStore.shared.state {
                // 上一发还在飞：副标题已经在走「检查中…」，不再叠一条提示
                return
            } else {
                // 60 秒内刚查过：瞬时提示，不复写状态机
                rateLimitedHint = "刚检查过，稍等一分钟"
            }
        }
    }

    private func openWorkspace() {
        Haptics.light()
        // 未登录也直接进工作台：它会显示登录引导页（PRD P08 要的是"引导页"而不是"弹窗"）
        showsWorkspace = true
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "—"
        return short
    }

    // 批次 4 说明：原先这里有一个 `monitorPlaceholder`（`PagePlaceholder` + 返回钮）。
    // 推送监控已换成原生页 `MonitorView`（自带返回钮与骨架/错误态），
    // 占位页在本文件内不再使用 —— 特意删掉而不是留着，避免以后有人误接线。
}

// MARK: - 一行

/// 「更多」的一行：图标 + 标题 + 右侧状态字 + 箭头。
///
/// 没有直接用 `GlassListRow`，原因只有一个：它没有"未连接"这种**灰态**。
/// 未连接是"要引导登录"的信号，标题、图标、状态字必须一起变淡，
/// 否则用户会以为点进去就有数据，然后撞上一个登录页。
struct MoreRow: View {
    let icon: String
    let title: String
    /// 右侧状态字（nil = 不显示）
    var detail: String? = nil
    /// true = 未连接 / 未启用（整行降透明度，状态字用警示前的中间色）
    var isMuted: Bool = false
    let action: () -> Void

    init(
        icon: String,
        title: String,
        detail: String? = nil,
        isMuted: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.isMuted = isMuted
        self.action = action
    }

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isMuted ? Theme.textTertiary : Theme.limeInk)
                    .frame(width: 22, alignment: .center)

                Text(title)
                    .font(Typography.callout)
                    .foregroundStyle(isMuted ? Theme.textSecondary : Theme.textPrimary)

                Spacer(minLength: 8)

                if let detail = detail {
                    Text(detail)
                        .font(Typography.footnote)
                        .foregroundStyle(isMuted ? Theme.textTertiary : Theme.limeInk)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Spacing.cardPadding)
            .frame(minHeight: Spacing.listItemMinHeight)
            .contentShape(Rectangle())
            .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        // 指针悬停高亮（设计文档 §7.2）。行本身就是一整块玻璃，`lift` 会与
        // `glassShadow` 的双层投影叠加成"跳一下"，所以只用 `highlight`。
        // iPhone 上无指针 → 完全无影响。
        .hoverEffect(.highlight)
    }
}

// MARK: - 关于

/// 关于（3.10.0 起按「软件信息 / 数据来源 / 边界说明」三组组织）。
///
/// 3.10.0 的调整：设置页按「只留可操作项」瘦身，**只读的说明性内容全部挪到这里** ——
/// 版本 / 构建号（原设置「版本」组）、三个站点域名（原「数据来源」组，点击复制的行为一并带来）、
/// 以及原设置页「关于」卡与页脚的定位 / 边界说明。设置页从此只剩开关与动作，
/// 「它是什么、数据从哪来」只在这一个地方回答，不再两处维护同一句话。
///
/// 行组件复用两套既有件：键值行用本页的 `infoRow`（纯展示），可点复制的域名行用
/// `GlassListRow`（设置页原来那行的同款组件，`showsChevron: false`）—— 不复制样式。
/// 不写"开源库列表"（本工程零第三方依赖，写了反而像凑数）；
/// 域名一律取自 `API` / `Endpoint`，页面里不出现协议前缀字面量。
struct MoreAboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// 复制成功后的瞬时提示（与设置页同款：1.8 秒即逝）
    @State private var toast: String?

    init() {}

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground(glow: false)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                    header

                    // MARK: 软件信息
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            infoRow(title: "版本", value: appVersion)
                            Rectangle().fill(Theme.divider).frame(height: 1)
                            infoRow(title: "构建号", value: buildNumber)
                        }
                        .padding(Spacing.cardPadding)
                    }

                    // MARK: 数据来源
                    VStack(alignment: .leading, spacing: 8) {
                        Text("数据来源")
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.textTertiary)
                        VStack(spacing: 8) {
                            GlassListRow(
                                icon: "globe",
                                title: "博客内容",
                                detail: hostOf(API.blogHost),
                                showsChevron: false
                            ) {
                                copyToPasteboard(API.blogHost)
                            }
                            GlassListRow(
                                icon: "cloud",
                                title: "光遇版本与简报",
                                detail: hostOf(API.briefHost),
                                showsChevron: false
                            ) {
                                copyToPasteboard(API.briefHost)
                            }
                            GlassListRow(
                                icon: "list.bullet.rectangle.portrait",
                                title: "问卷工作台",
                                detail: hostOf(API.surveyHost),
                                showsChevron: false
                            ) {
                                copyToPasteboard(API.surveyHost)
                            }
                        }
                        Text("点一下域名可以复制。App 只读这些数据，不会改动任何一篇内容。")
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.textTertiary)
                            .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                            .padding(.horizontal, 4)
                    }

                    // MARK: 边界说明（原设置页「关于」卡 + 页脚署名 + 只读边界，原句未改）
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("一个安静的阅读入口")
                                .font(Typography.titleS)
                                .foregroundStyle(Theme.textPrimary)
                            Text("只放三样东西：博客文章、光遇版本、每天一份简报。没有账号，没有推荐，没有广告位。")
                                .font(Typography.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                            Text("问卷与推送监控都是只读入口：创建问卷、编辑题目、导出数据都留在网页端。App 不上传任何使用数据，也没有第三方统计 SDK。")
                                .font(Typography.captionXS)
                                .foregroundStyle(Theme.textTertiary)
                                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.6))
                            Text("浅色和深色都做好了。在「外观」里三选一：跟随系统、始终浅色、始终深色，选了立刻生效。")
                                .font(Typography.captionXS)
                                .foregroundStyle(Theme.textTertiary)
                                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                        }
                        .padding(Spacing.cardPadding)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.page)
                .padding(.top, 12)
                .padding(.bottom, Spacing.page)
            }
            .scrollIndicators(.hidden)

            if let toast = toast {
                SettingsToast(text: toast)
            }
        }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(Motion.glassOut) {
                toast = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("关于")
                    .font(Typography.titleL)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                Text("FF大王 · 原生重写版")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            IconGlassButton(icon: "xmark", size: 36) {
                dismiss()
            }
            .accessibilityLabel("关闭")
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Typography.footnote)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(Typography.footnote)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return info["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return info["CFBundleVersion"] as? String ?? "—"
    }

    /// 只显示域名：协议前缀对用户没有信息量
    private func hostOf(_ raw: String) -> String {
        return URL(string: raw)?.host ?? raw
    }

    /// 复制域名（与设置页原「数据来源」行同一行为：复制的是完整 URL，粘贴即用）
    private func copyToPasteboard(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #endif
        Haptics.success()
        withAnimation(Motion.glassIn) {
            toast = "已复制 \(value)"
        }
    }
}
