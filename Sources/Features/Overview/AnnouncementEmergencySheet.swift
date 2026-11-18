import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 紧急公告弹窗（5.4.0）。
///
/// ## 它和 `AnnouncementSheet` 为什么不能合并
///
/// 普通公告是"顺便告诉你"，紧急公告是"停一下，看这里"。这个差别不是加了点红色就能表达的，
/// 它连着三条彼此独立、都会和普通弹窗打架的规则：
///
/// 1. **颜色不听主题的**。整套颜色由服务端给的 hex 派生（见 `AnnouncementPalette`），
///    固定不随外观/换肤变化 —— 而 `AnnouncementSheet` 每一处都是 `Theme.*` token。
/// 2. **只能点按钮关**。普通公告随便划走；紧急公告如果也能划走，它和普通公告就只差一个颜色，
///    运营写"必须看到"这四个字就没有着落了。
/// 3. **恒为整屏**。普通弹窗半屏起步（`.fraction(0.56)`）是为了不压住首页；
///    紧急公告压住首页正是它的目的。
///
/// ## 为什么必须是 `.fullScreenCover`（5.4.1 修）
///
/// 5.4.0 用的是 sheet + `.presentationDetents([.large])` + `.interactiveDismissDisabled(true)`。
/// 那套 modifiers 在真机上有两个问题：
/// · `.large` 在 iPhone 上**顶部留一条缝**（露出首页的一角），在 iPad 上是**居中卡片** ——
///   两种都不是"压住首页"，用户第一眼看到的是"一个很大的 sheet"，不是"一屏公告"。
/// · "关不掉"靠的是 `interactiveDismissDisabled`，那是 sheet 的概念，整屏形态下根本不该存在。
///
/// 换成 `.fullScreenCover` 之后，**"只能点按钮"由呈现方式本身保证**：
/// fullScreenCover 天然没有下滑手势、也没有点背景关闭，不需要 `interactiveDismissDisabled`
/// 这种补丁式声明。同一句设计意图从"禁止某个手势"变成"压根没有那个手势"，更不容易退化。
/// 整屏也不需要圆角（四角就是屏幕角），所以 `.presentationCornerRadius` 一并去掉。
///
/// 硬塞进 `AnnouncementSheet` 意味着那个文件的每一行都要长一个 `if isEmergency` 分支，
/// 而两条分支的颜色体系、关闭策略、模态种类全都不同 —— 那不是一个视图的两种状态，是两个视图。
///
/// ## 克制
/// · 只出现在**极端场景**（服务中断、数据迁移、必须立刻升级）。它只能点按钮关闭，所以
///   每多发一条都在消耗用户的耐心 —— 这是后台二次确认弹窗存在的原因。
/// · 触觉 `.medium`（比普通公告同档）：不是"有消息"，是"注意"。
/// · 已读记忆与横幅、普通弹窗**共用 `announcement.dismissed`**：同一条公告在三条通道里
///   是同一件事，分开记就会出现"点掉了又被弹一次"。
struct AnnouncementEmergencySheet: View {

    let announcement: RemoteAnnouncement
    let revision: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 图标 / 文案的入场状态。放 State 而不是在 `onAppear` 里直接改视图：
    /// reduced-motion 时也要能走到终态（不缩放，但元素必须出现）。
    @State private var appeared = false

    /// 整套配色。`announcement.color` 为 nil / 非法时内部回落默认红，这里不用判空。
    private var palette: AnnouncementPalette {
        AnnouncementPalette(hex: announcement.color)
    }

    var body: some View {
        GeometryReader { proxy in
            // 安全区**手动**折进全屏坐标：根层 `.ignoresSafeArea()` 之后，子树读到的
            // insets 会变成 0，所以必须在**外面**这一层量（同 `SkyRoomView` 的做法）。
            let insets = proxy.safeAreaInsets

            ZStack(alignment: .top) {
                background

                VStack(spacing: 0) {
                    content
                    footer
                }
                // 背景铺满整屏，文字与按钮留在系统条之内：底部按钮压进 Home Indicator 区
                // 会和"上滑回桌面"抢手势 —— 那是把一个视觉问题换成一个操作问题。
                .padding(.top, insets.top)
                .padding(.bottom, insets.bottom)
            }
            // 真正"整屏"的那一半：渐变铺到状态栏与 Home Indicator 之外，
            // 四角就是屏幕角（fullScreenCover 没有卡片圆角这回事，也不需要 `Radius.sheet`）。
            .ignoresSafeArea()
        }
        // 强制深色：紧急公告的配色是与系统外观**无关**的一套，但系统控件（滚动条、
        // 点按高亮、可能的文本选择）仍然会去读 colorScheme。压成 dark 才不会有
        // "浅色系统下一块亮底的浅色滚动条"那种穿帮。
        .environment(\.colorScheme, .dark)
        .onAppear {
            // 与普通弹窗同为 `.medium`：`Haptics` 只有 light / medium / success / error 四档，
            // 后两档是"结果"（成功 / 失败），公告不是结果。紧急公告的重量感该由
            // "整屏 + 只能点按钮 + 不跟主题"来表达，而不是把震动调到通知级 —— 那是假的严重。
            Haptics.medium()
            appeared = true
        }
    }

    // MARK: - 背景

    /// 两层：主色渐变（deep → base）铺满，再压一层同色径向光晕。
    ///
    /// 光晕用 `palette.glow`（base 的 45% 透明度）而不是给元素加阴影：
    /// 阴影在深色渐变上会变成一圈脏边，光晕才是"这块色在发光"。
    private var background: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [palette.deep, palette.base],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [palette.glow, palette.glow.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.08),
                startRadius: 0,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
        // 背景层不吃手势：ZStack 里它铺满全屏，会挡在 ScrollView 下面一层倒无所谓，
        // 但显式关掉更保险（少了 `.allowsHitTesting` 一旦层级调整就会变成一块隐形挡板）。
        .allowsHitTesting(false)
    }

    // MARK: - 内容

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                levelBadge
                symbol
                copy
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.page + 4)
            .padding(.top, 26)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        // 正文短时不要让内容居中再留一大片空白：从顶部排下来，按钮区自然贴底，
        // 读起来是"一张通知"，而不是"一个被拉高的空层"
        .scrollBounceBehavior(.basedOnSize)
    }

    /// 顶部小标签：「紧急公告」。
    ///
    /// 这一条是整个弹窗里唯一"解释自己是什么"的元素 —— 用户在半秒内要判断
    /// "这是不是垃圾信息"，一颗警示三角 + 白描边胶囊比任何文案都直接。
    private var levelBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
            Text("紧急公告")
                .font(Typography.eyebrow)
                // 眉题要"更小更宽"才不会被当成元信息读走（中文没有大写变形，只能靠字距）
                .tracking(Typography.trackingEyebrow)
        }
        .foregroundStyle(palette.labelInk)
        .padding(.horizontal, 10)
        // 固定 28：它比一行 eyebrow 高，但低于任何可点区域 —— 这是"标签"不是"按钮"
        .frame(height: 28)
        .overlay {
            Capsule().strokeBorder(palette.hairline, lineWidth: 1)
        }
        .opacity(appeared || reduceMotion ? 1 : 0)
        .animation(reduceMotion ? nil : Motion.notice, value: appeared)
        .accessibilityHidden(true)
    }

    /// 圆底图标 + 外圈柔光（手法与 `AnnouncementSheet.symbol` 相同，只换了色源）。
    ///
    /// 白底 + `palette.deep` 图标，而不是"底色 + 白图标"：紧急公告的背景本身就是那一块浓色，
    /// 图标圆必须**从背景里跳出来**，近白的面是唯一稳的对比。图标色用 deep 而不是纯黑，
    /// 是为了让"按钮 / 图标"这两处同族色互相呼应。
    private var symbol: some View {
        ZStack {
            Circle()
                .fill(palette.glow)
                .frame(width: 96, height: 96)
                .blur(radius: 20)

            Circle()
                .fill(palette.ink)
                .frame(width: 58, height: 58)
                .overlay {
                    Circle().strokeBorder(palette.hairline, lineWidth: 1)
                }

            Image(systemName: announcement.symbolName)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(palette.deep)
        }
        .scaleEffect(appeared || reduceMotion ? 1 : 0.86)
        .opacity(appeared || reduceMotion ? 1 : 0)
        // reduced-motion 下给 nil：元素落到终态，不做缩放
        .animation(reduceMotion ? nil : Motion.notice, value: appeared)
        .accessibilityHidden(true)
    }

    private var copy: some View {
        VStack(spacing: 10) {
            if announcement.title.isEmpty == false {
                Text(announcement.title)
                    .font(Typography.titleL)
                    .tracking(Typography.trackingLarge)
                    // 纯白：这块底色是服务端指定的，`Theme.textPrimary` 在浅色外观下会变成近黑，
                    // 压在深红上直接读不出来
                    .foregroundStyle(palette.titleInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if announcement.body.isEmpty == false {
                Text(announcement.body)
                    .font(Typography.callout)
                    .foregroundStyle(palette.bodyInk)
                    // 15pt 正文要放得开才读得下去（同普通弹窗的那条 leading 规则）
                    .lineSpacing(Typography.lineSpacing(fontSize: 15, multiple: 1.65))
                    .multilineTextAlignment(.center)
                    // 不被外层压扁：让 ScrollView 变长，而不是把最后一行吃掉
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(appeared || reduceMotion ? 1 : 0)
        .animation(reduceMotion ? nil : Motion.notice.delay(0.04), value: appeared)
    }

    // MARK: - 按钮

    /// 固定贴底、不随正文滚动 —— 关不掉一条公告、还得先滑到底才能找到按钮，
    /// 那是把"不可关闭"变成"看不见出口"。
    ///
    /// 有链接：主按钮去链接、次按钮「我已了解」；
    /// 没链接：只剩主按钮（文案由 `primaryActionTitle` 给，默认「知道了」）。
    /// 不硬凑第二个按钮 —— 那个位置放"取消"会让人以为"知道了"是别的意思。
    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: primaryAction) {
                HStack(spacing: 8) {
                    if announcement.hasLink {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(announcement.primaryActionTitle)
                }
            }
            .buttonStyle(EmergencyPrimaryButtonStyle(palette: palette))
            .accessibilityHint(announcement.hasLink ? "打开链接并关闭这条公告" : "关闭这条公告")

            if announcement.hasLink {
                Button(action: markRead) {
                    Text("我已了解")
                }
                .buttonStyle(EmergencyGhostButtonStyle(palette: palette))
            }
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, 12)
        .padding(.bottom, Spacing.page)
    }

    // MARK: - 动作

    private func primaryAction() {
        Haptics.light()
        // 先记已读再跳：跳到 Safari 之后用户不会再回来点关闭，顺序反过来的话这条公告下次还会弹
        // （与 `AnnouncementSheet.primaryAction` 同一条纪律）。
        markReadQuietly()
        guard let raw = announcement.url, let url = URL(string: raw) else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #endif
    }

    private func markRead() {
        Haptics.light()
        markReadQuietly()
    }

    /// 落盘当前 revision + 关层，不带触觉（触觉由调用点决定：主按钮与次按钮各给一次 `.light`）。
    private func markReadQuietly() {
        AnnouncementMemory.markRead(revision)
        dismiss()
    }
}

// MARK: - 按钮样式

/// 主按钮：近白实底 + `palette.onInk` 文字。
///
/// 尺寸对齐 `PrimaryCTAStyle`（字号 / 内距 / 全宽），但**不复用**它 ——
/// 那个样式是青柠实底，会把"这一层不跟 App 主题走"这句话当场推翻。
/// 光晕用 `palette.glow`：白按钮压在深红上会显得"贴上去"，一圈同色光把它托起来。
private struct EmergencyPrimaryButtonStyle: ButtonStyle {

    let palette: AnnouncementPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.footnoteMedium)
            .foregroundStyle(palette.onInk)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background {
                Capsule().fill(palette.ink)
            }
            .shadow(color: palette.glow, radius: 16, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// 次按钮：透明底 + 白 35% 描边胶囊，文字白 90%。
///
/// 不做玻璃材质：`.glassSurface` 会去采样背后的模糊，而这里的背景是一块纯色渐变，
/// 模糊出来与不模糊一模一样 —— 多一层材质只是多一次离屏渲染。
private struct EmergencyGhostButtonStyle: ButtonStyle {

    let palette: AnnouncementPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.footnoteMedium)
            .foregroundStyle(palette.ghostInk)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .overlay {
                Capsule().strokeBorder(palette.ghostStroke, lineWidth: 1)
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
