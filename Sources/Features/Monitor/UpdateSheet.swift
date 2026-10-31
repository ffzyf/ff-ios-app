import SwiftUI

/// 云控更新的更新层（设计文档 §4.6）。
///
/// ## 为什么必须是 sheet 而不是 alert
/// 更新说明是**多行**文本（真实说明 5–10 行，里面就是 `\n`）。`alert` 的 message 区在 iOS 上
/// 会被压到约 4 行且**不可滚动** —— 用户看不到"这次改了什么"就被劝着点安装，那是在骗他点。
/// sheet 里套 `ScrollView`，说明想多长就多长，而且长说明**不会**把两个按钮挤出屏幕
/// （按钮在滚动内容之外，永远可点、永远能关）。
///
/// 两条不能破的底线：
/// · **必须能关掉**：右上角关闭 + 底部「稍后」，两个都走同一个 dismiss；
/// · **不做强制更新**：自己的 App，用户说"稍后"就该能继续用，不拦启动。
///   （但 3.9.0 起远程配置 `minBuild` 可触发强制更新，见下文 `isForced` 例外。）
///
/// 3.9.0 的例外：远程配置给了 `minBuild` 且本机 build 低于它时（`UpdateStore.isForced`），
/// 本层退让成"不可关闭"—— 隐藏「稍后」、关闭按钮置灰、下滑手势一并禁掉，
/// 并加一行「此版本必须更新」。这是唯一合法的强制形态：**只拦弹层，不拦启动**，
/// 用户仍能正常用 App 的其它功能。
struct UpdateSheet: View {

    /// 要展示的版本。由 `.sheet(item:)` 传入，所以**非可选** —— 层内不需要再判空
    let release: AppRelease

    @ObservedObject private var store = UpdateStore.shared
    @Environment(\.dismiss) private var dismiss

    init(release: AppRelease) {
        self.release = release
    }

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground(glow: false)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                    header
                    releaseCard
                    actions
                    if store.needsInstallGuide {
                        fallbackNote
                    }
                    footNote
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.page)
                .padding(.top, 12)
                .padding(.bottom, Spacing.page)
            }
            .scrollIndicators(.hidden)
        }
        // 强更（3.9.0）：下滑手势与右上角关闭同进退 —— 只拦其中一个，用户会从另一条路溜出去，
        // "必须更新"就成了空话。三条出口（右上角 ×、「稍后」、下滑）同时封死才算数。
        .interactiveDismissDisabled(store.isForced)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("发现新版本")
                    .font(Typography.titleL)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                Text("FF大王 · 云控更新")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                // 强更标记（3.9.0）：单独一行红字，而不是塞进副标题 ——
                // "必须"与"云控更新"是两件事，混在一行会被读成修饰语
                if store.isForced {
                    Text("此版本必须更新")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.statusError)
                }
            }
            Spacer(minLength: 8)
            // 右上角关闭。与「稍后」是同一个 dismiss —— 区别只是不记「稍后」记忆键。
            // 强更时不可用（置灰而不是隐藏：位置还在，用户知道这里本可以关，
            // 是"这版不让关"而不是"界面缺了个按钮"）
            IconGlassButton(icon: "xmark", size: 36) {
                dismiss()
            }
            .disabled(store.isForced)
            .opacity(store.isForced ? 0.4 : 1)
            .accessibilityLabel("关闭")
        }
    }

    // MARK: - 版本卡

    private var releaseCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(release.version)
                        .font(Typography.versionLarge)
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    StatusPill(kind: .newVersion, text: "build " + String(release.build))
                }

                // 包大小与发布时间：拿不到就整行不给（不写「未知」）
                if !metaText.isEmpty {
                    Text(metaText)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }

                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)

                notesBlock
            }
            .padding(Spacing.cardPadding)
        }
    }

    private var metaText: String {
        var parts: [String] = []
        let size = release.sizeText
        if !size.isEmpty { parts.append(size) }
        let published = release.publishedText
        if !published.isEmpty { parts.append(published) }
        return parts.joined(separator: " · ")
    }

    /// 更新说明。`notes` 里的 `\n` 由 `Text` 自己折行，`fixedSize` 保证一个都不被压掉
    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("更新说明")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            Text(notesText)
                .font(Typography.footnote)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                // 竖直方向不参与压缩：宁可让外层 ScrollView 变长，也不让说明被截断
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 说明为空时给一句人话，而不是留一片空白让用户以为没加载出来
    private var notesText: String {
        let trimmed = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "这次没有写更新说明。" : trimmed
    }

    // MARK: - 按钮

    private var actions: some View {
        VStack(spacing: 10) {
            // 文案不提"全能签"：它是**实现细节**，用户只关心"装上新版"。
            // 装了全能签走全能签、没装走安装引导页，都是这一个按钮把事情办完；
            // 把渠道写进按钮，没装的人会以为这个按钮跟自己无关，直接略过 ——
            // 而它恰恰是唯一能保证把新版装上的入口。
            Button(action: {
                Haptics.light()
                store.install()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("安装新版本")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCTAStyle())
            .accessibilityLabel("安装新版本")
            .accessibilityHint("唤起全能签下载并安装这个版本")

            // 强更（3.9.0）：隐藏「稍后」而不是置灰 —— 强制场景里它永远不可点，
            // 留一个灰按钮只会让人反复去点
            if store.isForced == false {
                Button(action: {
                    Haptics.light()
                    // 关掉 + 记住这个发布：与右上角关闭同一个 dismiss，只是多记一笔
                    store.snooze()
                }) {
                    Text("稍后")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryCTAStyle())
                .accessibilityLabel("稍后")
            }
        }
    }

    /// 兜底提示：设备上没有全能签（或它没接住这次跳转）时，给一条还能走通的路
    private var fallbackNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("没检测到全能签。可以先看安装引导页，里面有完整的安装步骤。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)
            CapsuleGlassButton(title: "打开安装引导页", icon: "safari") {
                store.openInstallGuide()
            }
        }
    }

    /// 责任边界写清楚：我们只递 ipa，签名与信任是全能签那边的活
    private var footNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("我们只负责把 ipa 交到全能签手里：证书、重签都由全能签完成。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.6))
            Text("装完打不开的话，多半是描述文件还没信任：系统设置 → 通用 → VPN 与设备管理 里信任一次。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.6))
        }
        .padding(.horizontal, 4)
    }
}
