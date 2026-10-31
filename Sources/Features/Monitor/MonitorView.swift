import SwiftUI

/// 推送监控（PRD P12，「更多 → 推送监控」全屏页）。
///
/// 页面结构（自上而下，不可重排）：
/// ① 玻璃返回钮 + 标题；② 「立即检查」主按钮（检查中转圈、冷却中按秒提示）；
/// ③ 两张版本卡（国服 / 国际服）；④ 这个 App 自己的更新检查；
/// ⑤ 底部推送时段说明。
///
/// 三条数据纪律：
/// · **不需要登录**：`/api/app/monitor` 是匿名只读接口，页面没有登录引导；
/// · 检查失败**不清空**卡片：卡片继续显示上次成功的版本号与时间，只把检查行改成失败文案；
/// · 取不到的字段整行不渲染（时段说明拿不到就整块消失），绝不写「未知」。
struct MonitorView: View {
    @ObservedObject private var store = MonitorStore.shared
    @Environment(\.dismiss) private var dismiss
    /// 尺寸模型（设计文档 §4.9）：国服 / 国际服本来就是**对照**信息 ——
    /// iPad 上把两张卡并排，比的才是"哪个服更新"，隔着上下两屏只能靠记忆。
    @Environment(\.layoutMetrics) private var metrics

    /// 两张版本卡并排时的列定义（canvas 1080 → 各 528 = (1080 − 24) / 2）
    private var cardColumns: [GridItem] {
        return Array(repeating: GridItem(.flexible(), spacing: Layout.gridGutter), count: 2)
    }

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
                    // 3.8.0：这个 App 自己的更新检查。**独立于上面那个「立即检查」** ——
                    // 那个按钮打的是服务端巡检接口、会给所有 Bark 订阅者群发通知，
                    // 这里只是匿名只读一次 `/api/app/version`（设计文档 §4.7）
                    AppUpdateSection()
                    windowNote
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.page)
                .padding(.top, 8)
                .padding(.bottom, Spacing.page)
                // 列宽：单列时 720（窄屏 393 → `maxWidth` 不生效，与今天逐像素一致），
                // 多列时是画布 1080（左右各 57）—— 两张 528 的卡只有放得下才谈得上"对照"。
                // 不用 `formMaxWidth 640`：640 在 1194 上会让两张卡各 308，"版本号 …… 时间"
                // 之间的空白和卡一样宽，比竖排还难读。
                .pageColumn(metrics.gridPageWidth)
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
        // 进监控页补一次更新检查（6 小时闸门：连着进出不会重复打接口）。
        // 单独一个 `.task` 而不是塞进上面那个：两者的取消时机不该绑在一起
        // —— 页面切走时监控请求被取消，不该顺带把更新检查也一起取消掉。
        .task {
            await UpdateStore.shared.checkIfNeeded()
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
            if store.apps.isEmpty {
                // 接口通了但没有任何服的数据：如实说，不画两张空卡
                EmptyStateView(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "还没有版本记录。",
                    message: "服务端第一次巡检成功后，这里会出现国服与国际服的版本号。"
                )
            } else {
                cardContainer {
                    ForEach(store.apps) { app in
                        VersionStatusCard(app: app, now: Date())
                    }
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

    /// 版本卡的容器：**窄档竖排 / 宽档并排**，两种形态共用同一份内容。
    ///
    /// 抽成一个 `@ViewBuilder` 函数而不是在两个地方各写一遍 `if`：
    /// 真实卡片与骨架必须落在同一个容器里，否则加载完成时页面会从"1080 宽的一条"跳成
    /// "两张 528 的卡"（正是这个文件里"骨架与真实卡同高同距"那条注释要避免的跳动）。
    @ViewBuilder
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if metrics.gridColumns > 1 {
            LazyVGrid(columns: cardColumns, alignment: .leading, spacing: Layout.gridGutter) {
                content()
            }
        } else {
            VStack(spacing: Spacing.cardGap) {
                content()
            }
        }
    }

    /// 骨架：一张卡三行，与真实卡片同高同距，避免加载完成时页面整体跳动
    private var skeletonCards: some View {
        cardContainer {
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
