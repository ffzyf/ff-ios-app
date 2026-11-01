import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 设置（PRD §3.6），以 sheet 形式从概览右上角的齿轮打开。
///
/// 3.10.0 起的原则：**设置只留可操作项**（开关、选择、动作），说明性 / 只读内容
/// （版本展示、数据来源、边界说明）已全部挪到「更多 → 关于」（`MoreAboutSheet`）——
/// 同一句话在两处各写一份，迟早有一份过期。
///
/// 刻意保持薄：本版无账号、无同步、无推送开关，会改本地状态的动作只有
/// 「清空缓存」与各组的开关/登录，所以没有 ViewModel —— 多一层只为搬运两个字符串不值得。
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
                    // 3.7.0：天气用设备定位（默认关闭，见 LocationStore 的类型注释）
                    group("天气") { WeatherLocationSection() }
                    // 批次 4：红石实时活动开关（桌面小组件不需要开关，随时可用）
                    group("红石") { LiveActivitySection() }
                    // 3.8.0：天光实时活动（3.10.0 起是"状态跟随"按钮，见 DaylightActivitySection）
                    group("天光") { DaylightActivitySection() }
                    // 批次 3：问卷管理（登录 / 退出）。单例观察，不依赖环境对象注入
                    group("问卷管理") { AccountSection() }
                    group("缓存") { cacheRow }
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
                // 副标题跟着页面职责改：这里只剩开关与动作，只读信息在「关于」
                Text("开关与动作都在这里；版本与数据来源见「更多 → 关于」")
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

    // MARK: - 动作

    private func refreshCacheSize() {
        let bytes = URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
        cacheText = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
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
