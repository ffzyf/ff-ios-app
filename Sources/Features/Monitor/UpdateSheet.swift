import SwiftUI

/// 云控更新的更新层（5.3.0 重做，原版 3.9.0）。
///
/// ## 为什么是 sheet 而不是 alert
/// 更新说明是**多行**文本（真实说明 5–10 行，里面就是 `\n`）。`alert` 的 message 区在 iOS 上
/// 会被压到约 4 行且**不可滚动** —— 用户看不到"这次改了什么"就被劝着点安装，那是在骗他点。
///
/// ## 5.3.0 改了什么（这是这次重做的全部动机）
/// 旧版把「标题 / 版本卡 / 按钮 / 兜底 / 两条免责」竖着排进一个全屏 ScrollView：
/// · 说明一长，**安装按钮就被推出屏幕** —— 想更新得先滚到底，而按钮恰恰是这层唯一的目的；
/// · 版本号只显示新的，用户看不出"我从哪升到哪"，5.2.0 到底新不新没有参照；
/// · 两条灰色免责常驻，占掉屏幕下方三分之一，把真正的操作压得没重量。
///
/// 现在：
/// 1. **按钮固定在底部**，说明区独立滚动 —— 无论说明 3 行还是 30 行，安装按钮永远在拇指下；
/// 2. **版本对比**：`5.1.3 → 5.2.0`，新版本给视觉重量，旧版本退成灰参照；
/// 3. 免责折叠成一行「安装遇到问题？」，展开才占版面；
/// 4. 半屏起步（`.medium`）+ 可上拉（`.large`）：首屏是"一件事 + 一个按钮"，长说明自己拉。
///
/// 两条不能破的底线：
/// · **必须能关掉**：右上角关闭 + 底部「稍后」，两个都走同一个 dismiss；
/// · **不做强制更新**：用户说"稍后"就该能继续用，不拦启动。
///   （3.9.0 起远程配置 `minBuild` 可触发强制更新，见 `isForced` 例外。）
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 免责区的展开状态。默认收起：装不上的时候才需要，平时那是噪音。
    @State private var showsTroubleshooting = false
    /// 图标入场（同公告层，保持两个弹层的手感一致）。
    @State private var appeared = false

    init(release: AppRelease) {
        self.release = release
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.blockGap) {
                    hero
                    versionBlock
                    notesBlock
                    if store.needsInstallGuide {
                        fallbackNote
                    }
                    troubleshooting
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.page + 4)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            actions
        }
        .background(PageBackground(glow: false))
        // 半屏起步：首屏只回答两个问题——「新在哪」「怎么装」。
        // 说明很长时上拉到底，不用在客户端量文本高度（Dynamic Type 一变就量错）。
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.sheet)
        // 强更（3.9.0）：下滑手势与右上角关闭同进退 —— 只拦其中一个，用户会从另一条路溜出去，
        // "必须更新"就成了空话。三条出口（右上角 ×、「稍后」、下滑）同时封死才算数。
        .interactiveDismissDisabled(store.isForced)
        .onAppear {
            appeared = true
        }
    }

    // MARK: - 头部

    /// 图标 + 标题 + 关闭。
    ///
    /// 标题下方那条「FF大王 · 云控更新」在 5.3.0 删掉了：它对用户零信息量，
    /// 只是把"我在用云控"这件事讲给开发者自己听。
    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            updateBadge

            VStack(alignment: .leading, spacing: 4) {
                Text("发现新版本")
                    .font(Typography.titleL)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)

                // 强更标记：单独一行红字，而不是塞进副标题 ——
                // "必须"与"有新版本"是两件事，混在一行会被读成修饰语
                if store.isForced {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("此版本必须更新")
                            .font(Typography.caption)
                    }
                    .foregroundStyle(Theme.statusError)
                } else {
                    Text("装完可以直接用，不影响现有数据")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 4)

            // 右上角关闭。与「稍后」是同一个 dismiss —— 区别只是不记「稍后」记忆键。
            // 强更时不可用（置灰而不是隐藏：位置还在，用户知道这里本可以关，
            // 是"这版不让关"而不是"界面缺了个按钮"）
            IconGlassButton(icon: "xmark", size: 32) {
                dismiss()
            }
            .disabled(store.isForced)
            .opacity(store.isForced ? 0.4 : 1)
            .accessibilityLabel("关闭")
        }
    }

    private var updateBadge: some View {
        ZStack {
            Circle()
                .fill(Theme.limeGlow)
                .frame(width: 72, height: 72)
                .blur(radius: 16)

            Circle()
                .fill(Theme.lime)
                .frame(width: 46, height: 46)
                .overlay {
                    Circle().strokeBorder(Theme.glassStrokeTop, lineWidth: 1)
                }

            Image(systemName: "arrow.down")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.onLime)
        }
        .scaleEffect(appeared || reduceMotion ? 1 : 0.86)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .animation(reduceMotion ? nil : Motion.notice, value: appeared)
        .accessibilityHidden(true)
    }

    // MARK: - 版本对比

    /// `5.1.3 → 5.2.0`。
    ///
    /// 旧版只写新版本号，用户没有任何参照 —— 5.2.0 相对自己装的 5.1.3 是大改还是补丁，
    /// 看不出来。把当前版本摆出来，这个数字才有意义。
    private var versionBlock: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let installed = store.installedVersionName {
                        Text(installed)
                            .font(Typography.versionValue)
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()

                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }

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

    // MARK: - 更新说明

    /// 说明完整显示（不折行截断）。`\n` 由 `Text` 自己折行，
    /// `fixedSize` 保证一个都不被压掉 —— 外层是 ScrollView，长就让它长。
    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("更新说明")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .textCase(.none)

            Text(notesText)
                .font(Typography.callout)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(Typography.lineSpacing(fontSize: 15, multiple: 1.6))
                // 竖直方向不参与压缩：宁可让外层 ScrollView 变长，也不让说明被截断
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    /// 说明为空时给一句人话，而不是留一片空白让用户以为没加载出来
    private var notesText: String {
        let trimmed = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "这次没有写更新说明。" : trimmed
    }

    // MARK: - 安装遇到问题（折叠）

    /// 旧版把两条免责常驻在底部，占掉屏幕下方三分之一，把"安装"这个主操作压得没重量。
    /// 现在收成一行：装不上的时候自己点开，装得上的人永远不用看见它。
    private var troubleshooting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                Haptics.selection()
                withAnimation(Motion.expand) {
                    showsTroubleshooting.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Text("安装遇到问题？")
                        .font(Typography.caption)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(showsTroubleshooting ? 180 : 0))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.textTertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showsTroubleshooting ? "收起安装说明" : "展开安装说明")

            if showsTroubleshooting {
                VStack(alignment: .leading, spacing: 6) {
                    Text("我们只负责把 ipa 交到全能签手里：证书、重签都由全能签完成。")
                    Text("装完打不开的话，多半是描述文件还没信任：系统设置 → 通用 → VPN 与设备管理 里信任一次。")
                }
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.6))
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 4)
    }

    /// 兜底提示：设备上没有全能签（或它没接住这次跳转）时，给一条还能走通的路
    private var fallbackNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("没检测到全能签。可以先看安装引导页，里面有完整的安装步骤。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            CapsuleGlassButton(title: "打开安装引导页", icon: "safari") {
                store.openInstallGuide()
            }
        }
    }

    // MARK: - 按钮（固定底部）

    /// **这一块不参与滚动** —— 说明再长，安装按钮也钉在拇指下。
    /// 旧版把它排在 ScrollView 末尾，长说明一出现就得滚到底才能点，等于把唯一的目的藏起来。
    private var actions: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

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
            .padding(.horizontal, Spacing.page)
            .padding(.top, 12)
            .padding(.bottom, Spacing.page)
        }
    }
}
