import SwiftUI

/// 推送监控（PRD P12，「更多 → 推送监控」全屏页）。
///
/// 页面结构（自上而下，不可重排）：
/// ① 玻璃返回钮 + 标题；② 「立即检查」主按钮（检查中转圈、冷却中按秒提示）；
/// ③ 两张版本卡（国服 / 国际服）；④ 底部推送时段说明。
///
/// 三条数据纪律：
/// · **不需要登录**：`/api/app/monitor` 是匿名只读接口，页面没有登录引导；
/// · 检查失败**不清空**卡片：卡片继续显示上次成功的版本号与时间，只把检查行改成失败文案；
/// · 取不到的字段整行不渲染（时段说明拿不到就整块消失），绝不写「未知」。
struct MonitorView: View {
    @ObservedObject private var store = MonitorStore.shared
    @Environment(\.dismiss) private var dismiss

    /// 显式空 init：`@ObservedObject` 是 private 存储属性，
    /// 编译器会把自动生成的 memberwise init 降级成 private，跨文件 `MonitorView()` 就调不到。
    init() {}

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground(glow: false)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                    header
                    checkButton
                    cards
                    windowNote
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.page)
                .padding(.top, 8)
                .padding(.bottom, Spacing.page)
                // 表单列宽 640（§3.7 / §3.1 总表）：两张版本卡 + 一段说明，拉宽只会让
                // "版本号 …… 时间"之间空出一大截。窄屏无副作用。
                .pageColumn(Layout.formMaxWidth)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await store.load(force: true)
            }
        }
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
        .task {
            // 先给缓存（观感上"立刻有内容"），再发请求
            await store.loadFromCacheIfNeeded()
            await store.load()
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // ⌘[ 返回（§7.1）。与文章详情的返回钮同一个键，用户只需要记一次。
                // 键交给 `IconGlassButton` 内部那颗 `Button` 注册 —— 挂在包装 View 上不保证生效。
                IconGlassButton(icon: "chevron.left", size: 36, shortcut: "[") {
                    dismiss()
                }
                .accessibilityLabel("返回")

                VStack(alignment: .leading, spacing: 2) {
                    Text("推送监控")
                        .font(Typography.titleL)
                        .tracking(Typography.trackingLarge)
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 副标题：优先说「最近检查」，完全没有数据时说明为什么空着
    private var subtitle: String {
        if let checked = store.latestCheckedAt {
            return "最近检查 " + Formatters.relative(checked)
        }
        if store.state.error != nil { return "暂时取不到监控状态" }
        return "版本巡检由服务端定时执行"
    }

    // MARK: - 立即检查

    private var checkButton: some View {
        Button(action: {
            Haptics.light()
            Task { await store.checkNow() }
        }) {
            HStack(spacing: 8) {
                if store.isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.onLime)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.onLime)
                }
                Text(checkButtonTitle)
                    .font(Typography.footnoteMedium)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryCTAStyle())
        .disabled(!store.canCheck)
        // 禁用态压暗但**不隐藏**：用户要能看见"为什么现在点不了"
        .opacity(store.canCheck ? 1 : 0.55)
        .accessibilityLabel(checkButtonTitle)
        .accessibilityHint("手动触发一次服务端版本巡检，60 秒内只能检查一次")
    }

    private var checkButtonTitle: String {
        if store.isChecking { return "检查中…" }
        if store.cooldownSeconds > 0 { return "\(store.cooldownSeconds) 秒后可再检查" }
        return "立即检查"
    }

    // MARK: - 版本卡

    @ViewBuilder
    private var cards: some View {
        if store.state.hasContent {
            VStack(spacing: Spacing.cardGap) {
                ForEach(store.apps) { app in
                    VersionStatusCard(app: app, now: Date())
                }
                if store.apps.isEmpty {
                    // 接口通了但没有任何服的数据：如实说，不画两张空卡
                    EmptyStateView(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "还没有版本记录。",
                        message: "服务端第一次巡检成功后，这里会出现国服与国际服的版本号。"
                    )
                }
            }
        } else if let error = store.state.error {
            ErrorStateView(
                icon: error.icon,
                title: error.title,
                message: error.hint,
                onRetry: {
                    Task { await store.load(force: true) }
                }
            )
        } else {
            skeletonCards
        }
    }

    /// 骨架：一张卡三行，与真实卡片同高同距，避免加载完成时页面整体跳动
    private var skeletonCards: some View {
        VStack(spacing: Spacing.cardGap) {
            ForEach(0..<2, id: \.self) { _ in
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonBlock(width: 52, height: 11)
                        SkeletonBlock(width: 120, height: 24)
                        SkeletonBlock(width: 84, height: 11)
                        Rectangle()
                            .fill(Theme.divider)
                            .frame(height: 1)
                        SkeletonBlock(width: 140, height: 11)
                    }
                    .padding(Spacing.cardPadding)
                }
            }
        }
    }

    // MARK: - 底部时段说明

    /// 时段说明整块来自服务端 `pushWindow`。取不到就**整块不渲染**（不写「时段未知」）
    @ViewBuilder
    private var windowNote: some View {
        let text = store.pushWindowText
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("推送时段")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                Text(text)
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                Text("手动检查有 60 秒限频；巡检的失败重试与合并推送都由服务端负责。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
            }
            .padding(.horizontal, 4)
        }
    }
}
