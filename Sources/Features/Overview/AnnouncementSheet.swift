import SwiftUI

/// 公告的「已读」记忆。横幅与弹窗**共用同一笔账**。
///
/// 为什么不各记各的：同一份配置在两条通道里是同一件事。分开记会出现
/// 「横幅点掉了、下次启动又被弹窗拦一次」—— 用户会觉得这个 App 不记事。
/// 落盘的是**当时的 revision**而不是布尔：服务端保存一次配置 revision +1，
/// 新旧值不等 → 公告自动重新出现；存 0/1 的话同一条公告改个字就再也触达不到。
enum AnnouncementMemory {

    /// 落盘键。与 3.9.0 横幅沿用的键名逐字相同 —— 老用户已经点掉的公告不会因为这次改版重新弹。
    static let key = "announcement.dismissed"

    /// 用户是否已经看过这个 revision。
    static func hasRead(_ revision: Int) -> Bool {
        UserDefaults.standard.integer(forKey: key) == revision
    }

    /// 记下"这个 revision 看过了"。
    static func markRead(_ revision: Int) {
        UserDefaults.standard.set(revision, forKey: key)
    }
}

/// `.sheet(item:)` 的载荷：把「公告内容 + 它属于哪个 revision」捆成一个 Identifiable。
///
/// `id` 拼上标题而不是只用 revision：同一 revision 下服务端若改了公告正文（不该发生，
/// 但并非不可能），只按 revision 做 id 会让 SwiftUI 把新内容当成同一个 item 复用，
/// 弹层里还是旧文案 —— 与 `AppRelease` 当年"同 build 重发"踩过的是同一个坑。
struct AnnouncementSheetItem: Identifiable {
    let announcement: RemoteAnnouncement
    let revision: Int

    var id: String { "\(revision)|\(announcement.title)" }
}

/// 公告弹窗（5.3.0）。
///
/// ## 为什么要有两种形态
/// 顶部横幅（`AnnouncementBanner`）是"路过时扫一眼"的东西，正文被压到 2 行 ——
/// 对"版本号更新了""活动上线了"够用，对"服务要停两小时""数据要迁移"就不够，
/// 用户看不完也记不住。这类公告需要一块能放正文、能放主按钮的地方，于是有了这一层。
///
/// 选择权交给服务端（`announcement.style`）：客户端不去猜"正文多长才算重要" ——
/// 那种启发式一旦猜错，要么把小事弹成大窗，要么把大事压成一行字。
///
/// ## 为什么是 sheet 而不是自定义居中弹窗
/// 这个工程里所有"临时浮层"都是 sheet（更新、收益记录、平台详情、AI 历史……），
/// 系统自带下滑关闭、可中断的弹簧、无障碍焦点管理。自己拿 ZStack 搭一个居中卡片，
/// 这三样都得重写一遍，而且大概率写不过系统。公告内容长度不定，sheet 还能上拉看全。
///
/// ## 克制
/// · **同一个 revision 只弹一次**：落盘键与横幅共用 `announcement.dismissed`，
///   横幅点过 × 的人也不会再被弹一次 —— 两条通道记的是同一笔账。
/// · 不阻断启动：随时可下滑关掉，关掉就是"已读"，不影响首页任何操作。
/// · 触觉只在打开时给一次 `.medium`（"这里有事，看一眼"），关闭只给 `.light`。
struct AnnouncementSheet: View {

    let announcement: RemoteAnnouncement
    let revision: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 图标和文案的入场状态。放在 State 里而不是在 `onAppear` 里直接改视图，
    /// 是为了让 reduced-motion 也能走到终态：不做缩放，但元素必须出现在场上。
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    symbol
                    copy
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.page + 4)
                .padding(.top, 28)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            // 正文短的时候不要把整块内容顶到中间再留一大片空白：
            // 从顶部排下来，按钮区自然贴底，读起来是"一张通知"而不是"一个居中的弹窗"。
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .background(PageBackground(glow: false))
        // 半屏起步、可上拉：短公告停在半屏，长公告一拉就到底，不用在客户端量内容高度
        // （量出来也会因为 Dynamic Type 变化而算错）。
        .presentationDetents([.fraction(0.56), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.sheet)
        .onAppear {
            Haptics.medium()
            appeared = true
        }
    }

    // MARK: - 图标

    /// 圆底 + 外圈柔光。柔光是 `limeGlow` 而不是给图标加阴影 ——
    /// 阴影会在浅色主题下变脏，光晕才是"这个色在发光"。
    private var symbol: some View {
        ZStack {
            Circle()
                .fill(Theme.limeGlow)
                .frame(width: 96, height: 96)
                .blur(radius: 20)

            Circle()
                .fill(Theme.lime)
                .frame(width: 58, height: 58)
                .overlay {
                    // 与全工程一致的上缘接光描边
                    Circle().strokeBorder(Theme.glassStrokeTop, lineWidth: 1)
                }

            Image(systemName: announcement.symbolName)
                .font(.system(size: 25, weight: .semibold))
                // 铁律：lime 只作面，文字/图标用 onLime 压在上面
                .foregroundStyle(Theme.onLime)
        }
        .scaleEffect(appeared || reduceMotion ? 1 : 0.86)
        .opacity(appeared || reduceMotion ? 1 : 0)
        // reduced-motion 下直接给 nil，元素落到终态、不做缩放
        .animation(reduceMotion ? nil : Motion.notice, value: appeared)
        .accessibilityHidden(true)
    }

    // MARK: - 文案

    private var copy: some View {
        VStack(spacing: 10) {
            if announcement.title.isEmpty == false {
                Text(announcement.title)
                    .font(Typography.titleL)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if announcement.body.isEmpty == false {
                Text(announcement.body)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textSecondary)
                    // 15pt 正文要放得开才读得下去（Apple 那条"leading 随字号反向走"）
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

    /// 主页面上做一件事，次按钮只负责"我已读"。
    ///
    /// 有链接时主按钮是「去看看」、次按钮是「知道了」；
    /// 没链接时只剩一个「知道了」—— 不硬凑第二个按钮，
    /// 那个位置放"取消"会让人以为"知道了"是别的意思。
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
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCTAStyle())
            .accessibilityHint(announcement.hasLink ? "打开链接并关闭这条公告" : "关闭这条公告")

            if announcement.hasLink {
                Button(action: markRead) {
                    Text("知道了")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryCTAStyle())
            }
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, 12)
        .padding(.bottom, Spacing.page)
    }

    // MARK: - 动作

    private func primaryAction() {
        Haptics.light()
        // 先记已读再跳：跳到 Safari 之后用户不会再回来点关闭，
        // 顺序反过来的话这条公告下次还会弹。
        markRead()
        guard let raw = announcement.url, let url = URL(string: raw) else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #endif
    }

    /// 落盘当前 revision + 关层。与横幅同一套记忆（`AnnouncementMemory`），
    /// 新 revision 发布后自动重新出现。
    private func markRead() {
        Haptics.light()
        AnnouncementMemory.markRead(revision)
        dismiss()
    }
}
