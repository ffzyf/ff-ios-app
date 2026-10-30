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
        let short = info["CFBundleShortVersionString"] as? String ?? "2.0.0"
        let build = info["CFBundleVersion"] as? String ?? "2"
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
