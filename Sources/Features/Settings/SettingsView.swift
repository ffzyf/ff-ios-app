import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 设置 / 关于（PRD §3.6），以 sheet 形式从概览右上角的齿轮打开。
///
/// 刻意保持「四组静态信息」的体量：本版无账号、无同步、无推送开关，
/// 唯一会改本地状态的动作只有「清空缓存」，所以没有 ViewModel —— 多一层只为搬运两个字符串不值得。
/// 域名一律取自 `API` 常量，页面里不出现任何协议前缀字面量（T09 静态审查会 grep 这一条）。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cacheText: String = "—"
    @State private var toast: String?

    init() {}

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground(glow: false)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                    header
                    group("外观") { AppearanceSection() }
                    // 批次 4：红石实时活动开关（桌面小组件不需要开关，随时可用）
                    group("红石") { LiveActivitySection() }
                    // 批次 3：问卷管理（登录 / 退出）。单例观察，不依赖环境对象注入
                    group("问卷管理") { AccountSection() }
                    group("版本") { versionRow }
                    group("数据来源") { sourceRows }
                    group("缓存") { cacheRow }
                    group("关于") { SettingsAboutCard() }
                    SettingsFooterLine()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.page)
                .padding(.top, 12)
                .padding(.bottom, Spacing.page)
                // 表单列宽 640（§3.7）：设置行是"图标 + 标题 …… 值"，行越宽，标题与值之间
                // 那条空越多、扫读越累。窄屏 393 < 640 → 完全无副作用。
                .pageColumn(Layout.formMaxWidth)
            }
            .scrollIndicators(.hidden)
            if let toast = toast {
                SettingsToast(text: toast)
            }
        }
        .onAppear {
            refreshCacheSize()
        }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(Motion.glassOut) {
                toast = nil
            }
        }
    }

    // MARK: - 骨架

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("设置")
                    .font(Typography.titleL)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                Text("关于这个 App 的一切")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            Button(action: {
                dismiss()
            }) {
                Text("完成")
            }
            .buttonStyle(PrimaryCTAStyle())
            // Esc 关闭（§7.1）：这是本页唯一的"关闭"钮，也是模态的落点。
            // 与 `ArticleDetailView` 的返回钮分工明确 —— 那个给 ⌘[，这里给 Esc，互不抢。
            .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            content()
        }
    }

    // MARK: - 各组内容

    private var versionRow: some View {
        GlassListRow(
            icon: "app.badge",
            title: "当前版本",
            detail: appVersion,
            showsChevron: false
        ) {
            // 版本号没有可点的动作，留空实现即可（不弹假提示）
        }
    }

    @ViewBuilder
    private var sourceRows: some View {
        VStack(spacing: 8) {
            GlassListRow(
                icon: "globe",
                title: "博客内容",
                detail: displayHost(API.blogHost),
                showsChevron: false
            ) {
                copyToPasteboard(API.blogHost)
            }
            GlassListRow(
                icon: "cloud",
                title: "光遇版本与简报",
                detail: displayHost(API.briefHost),
                showsChevron: false
            ) {
                copyToPasteboard(API.briefHost)
            }
            Text("点一下域名可以复制。App 只读这些数据，不会改动任何一篇内容。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)
        }
    }

    private var cacheRow: some View {
        GlassListRow(
            icon: "trash",
            title: "清空缓存",
            detail: cacheText,
            showsChevron: false
        ) {
            clearCache()
        }
    }

    // MARK: - 数据

    private var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        // 读不到就给「—」而不是写死一个版本号：写死的话每次升版都要记得回来改这一行，
        // 漏一次就会在设置页显示一个过期的旧版本，比显示「—」更容易误导。
        let short = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    /// 列表里只显示域名（`API` 常量带协议前缀，用户不需要看那一截）
    private func displayHost(_ raw: String) -> String {
        return URL(string: raw)?.host ?? raw
    }

    // MARK: - 动作

    private func refreshCacheSize() {
        let bytes = URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
        cacheText = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func copyToPasteboard(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #endif
        Haptics.success()
        withAnimation(Motion.glassIn) {
            toast = "已复制 \(value)"
        }
    }

    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        refreshCacheSize()
        Haptics.success()
        withAnimation(Motion.glassIn) {
            toast = "缓存已清空"
        }
    }
}
