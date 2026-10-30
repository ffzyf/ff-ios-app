import SwiftUI

/// 收益工作站（V3.2 新增，替换原来的「文章」Tab 位）。
///
/// 网页端（`creator-earnings-tracker.pages.dev`）的收益统计搬到这里：总额 / 三态拆分 /
/// 本月新增 / 平台占比 / 活动流水。**只读** —— 加记账、改活动仍在网页端，
/// 因为那些都要键盘长输入，塞进手机反而更难用（与问卷工作台的分工一致）。
///
/// 未登录时给登录引导页（不是弹窗）：`EarningsAuth` 要管理密码，弹窗一关就得重来。
struct EarningsView: View {

    @ObservedObject private var auth = EarningsAuth.shared
    @ObservedObject private var store = EarningsStore.shared

    @State private var password: String = ""
    @State private var loginError: String?
    @State private var isSubmitting: Bool = false
    @FocusState private var isPasswordFocused: Bool

    let scrollPosition: Binding<ScrollPosition>

    init(scrollPosition: Binding<ScrollPosition>) {
        self.scrollPosition = scrollPosition
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                header

                if auth.isLoggedIn {
                    if let summary = store.summary {
                        heroCard(summary: summary)
                        if summary.platformBreakdown.isEmpty == false {
                            breakdownCard(summary: summary)
                        }
                        if store.platforms.isEmpty == false {
                            platformCard
                        }
                        if store.activities.isEmpty == false {
                            activityCard
                        }
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

    // MARK: - 总览

    private func heroCard(summary: EarningsSummary) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("总计")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textTertiary)
                    Text(EarningsMoney.formatCents(summary.total))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }

                HStack(spacing: 0) {
                    statCell(title: "待发", cents: summary.pending, tint: Theme.statusWarn)
                    dividerLine
                    statCell(title: "已收未结", cents: summary.receivedUnclosed, tint: Theme.statusOk)
                    dividerLine
                    statCell(title: "已结", cents: summary.closed, tint: Theme.textSecondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.limeInk)
                    Text("本月新增 " + EarningsMoney.formatCents(summary.monthAdded))
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Text("\(summary.activityCount) 个活动 · \(summary.platformCount) 个平台")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(Spacing.cardPadding)
        }
    }

    private func statCell(title: String, cents: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(EarningsMoney.formatCents(cents))
                .font(Typography.titleS)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: 1, height: 30)
            .padding(.horizontal, 4)
    }

    // MARK: - 平台占比

    private func breakdownCard(summary: EarningsSummary) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("平台占比", icon: "chart.pie")

                ForEach(summary.platformBreakdown) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(item.name)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(EarningsMoney.formatCents(item.amount))
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .monospacedDigit()
                        }
                        // 占比条：分母用 total，避免依赖 ratio 的口径（服务端给的是百分数还是小数，
                        // 这里不猜；金额是确定的，自己算比值最稳）
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Theme.glassFill)
                                    .frame(height: 6)
                                Capsule()
                                    .fill(Theme.chartBar)
                                    .frame(width: barWidth(total: summary.total, amount: item.amount, full: geo.size.width), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .padding(Spacing.cardPadding)
        }
    }

    private func barWidth(total: Int, amount: Int, full: CGFloat) -> CGFloat {
        guard total > 0, amount > 0 else { return 0 }
        let ratio = min(1, Double(amount) / Double(total))
        return max(3, full * ratio)
    }

    // MARK: - 平台明细

    private var platformCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("平台明细", icon: "square.stack.3d.up")
                ForEach(store.platforms) { platform in
                    HStack(spacing: 10) {
                        Text(platform.name)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("待发 " + EarningsMoney.formatCents(platform.pendingCents))
                                .font(Typography.captionXS)
                                .foregroundStyle(Theme.statusWarn)
                                .monospacedDigit()
                            Text("已收 " + EarningsMoney.formatCents(platform.receivedCents))
                                .font(Typography.captionXS)
                                .foregroundStyle(Theme.textTertiary)
                                .monospacedDigit()
                        }
                        Text("\(platform.acts) 场")
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            .padding(Spacing.cardPadding)
        }
    }

    // MARK: - 活动流水

    private var activityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("最近活动", icon: "list.bullet.rectangle")
                ForEach(store.activities.prefix(12)) { activity in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(activity.name)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(activity.platform + " · " + EarningsClock.format(ms: activity.time))
                                .font(Typography.captionXS)
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(EarningsMoney.formatCents(activity.totalCents))
                                .font(Typography.caption)
                                .foregroundStyle(Theme.textPrimary)
                                .monospacedDigit()
                            Text(activity.isClosed ? "已结" : "进行中")
                                .font(Typography.captionXS)
                                .foregroundStyle(activity.isClosed ? Theme.textTertiary : Theme.statusOk)
                        }
                    }
                    if activity.id != store.activities.prefix(12).last?.id {
                        Rectangle()
                            .fill(Theme.divider)
                            .frame(height: 1)
                    }
                }
            }
            .padding(Spacing.cardPadding)
        }
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
        Text("App 里只读：新增记账、编辑活动仍在网页端。")
            .font(Typography.captionXS)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 4)
    }

    private func sectionTitle(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
    }
}
