import SwiftUI

/// 更多（Tab 5，PRD P13）。
///
/// 四行列表：问卷工作台 / 推送监控 / 设置 / 关于。
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

    @State private var showsWorkspace: Bool = false
    @State private var showsMonitor: Bool = false
    @State private var showsSettings: Bool = false
    @State private var showsAbout: Bool = false
    /// 滚动偏移保活（B3）：由 RootView 持有字典并作为 Binding 注入。
    let scrollPosition: Binding<ScrollPosition>

    /// 显式空 init：`@State` / `@ObservedObject` 都是 private 存储属性，
    /// 会把自动生成的 memberwise init 降级成 private，跨文件 `MoreView(scrollPosition:)` 就调不到。
    init(scrollPosition: Binding<ScrollPosition>) {
        self.scrollPosition = scrollPosition
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                header

                VStack(spacing: 8) {
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

                Text("问卷工作台要管理密码；推送监控是匿名只读，不需要登录。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
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

    // MARK: - 动作

    private func openWorkspace() {
        Haptics.light()
        // 未登录也直接进工作台：它会显示登录引导页（PRD P08 要的是"引导页"而不是"弹窗"）
        showsWorkspace = true
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "3.0.0"
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
    }
}

// MARK: - 关于

/// 关于：版本、构建号、数据来源、一句边界说明。
///
/// 不写"开源库列表"（本工程零第三方依赖，写了反而像凑数）；
/// 域名一律取自 `API` / `Endpoint`，页面里不出现协议前缀字面量。
struct MoreAboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    init() {}

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground(glow: false)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                    header
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            infoRow(title: "版本", value: appVersion)
                            Rectangle().fill(Theme.divider).frame(height: 1)
                            infoRow(title: "构建号", value: buildNumber)
                            Rectangle().fill(Theme.divider).frame(height: 1)
                            infoRow(title: "博客站", value: hostOf(API.blogHost))
                            Rectangle().fill(Theme.divider).frame(height: 1)
                            infoRow(title: "简报站", value: hostOf(API.briefHost))
                            Rectangle().fill(Theme.divider).frame(height: 1)
                            infoRow(title: "问卷站", value: hostOf(API.surveyHost))
                        }
                        .padding(Spacing.cardPadding)
                    }

                    Text("问卷与推送监控都是只读入口：创建问卷、编辑题目、导出数据都留在网页端。App 不上传任何使用数据，也没有第三方统计 SDK。")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.6))
                        .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.page)
                .padding(.top, 12)
                .padding(.bottom, Spacing.page)
            }
            .scrollIndicators(.hidden)
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
        return info["CFBundleShortVersionString"] as? String ?? "3.0.0"
    }

    private var buildNumber: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return info["CFBundleVersion"] as? String ?? "3"
    }

    /// 只显示域名：协议前缀对用户没有信息量
    private func hostOf(_ raw: String) -> String {
        return URL(string: raw)?.host ?? raw
    }
}
