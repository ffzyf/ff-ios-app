import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 公告横幅（3.9.0，热更通道的主要载体）。
///
/// 挂在 `OverviewView` 顶部、第一张卡之前：`RemoteConfigStore` 的
/// `values.announcement` 为 nil 时**整条不渲染**（首页版式回退到与 3.8.x 完全一致）。
///
/// ## 为什么关闭记忆存 revision
/// 落盘键 `announcement.dismissed` 存的是**当时那条公告的 revision**（不是固定 1/0）：
/// 运营保存一次配置 revision 就 +1，新旧值不等 → 横幅自动重新出现。
/// 存布尔值的话，同一条公告改个字也无法再次触达 —— 横幅就成了"只能用一次"的通道。
///
/// ## 样式纪律
/// 颜色全走 Theme token、圆角与描边走 `glassSurface(.card)` + `Radius.smallCard`
/// （与监控页行卡同一条体系），行高钉在 `listItemMinHeight` —— 不新造一套卡片样式。
struct AnnouncementBanner: View {

    /// 要展示的公告内容
    let announcement: RemoteAnnouncement
    /// 当前配置的 revision（关闭记忆挂在它上面）
    let revision: Int

    /// 「这条公告点过 ×」的落盘键，值 = 点掉时的 revision
    private static let dismissedKey = "announcement.dismissed"

    /// 进页面时读一次落盘值。本次会话内点 × 后由 `close()` 同步更新，
    /// 不用 observes 外部 store —— 关闭是纯本地行为，不该惊动别的页面。
    @State private var dismissedRevision: Int

    init(announcement: RemoteAnnouncement, revision: Int) {
        self.announcement = announcement
        self.revision = revision
        _dismissedRevision = State(
            initialValue: UserDefaults.standard.integer(forKey: Self.dismissedKey)
        )
    }

    var body: some View {
        // revision 相同 = 用户已经点掉过这条：整条不渲染，不占任何版面
        if dismissedRevision != revision {
            content
        }
    }

    // MARK: - 内容

    /// 有 url 时整条可点（外部链接），没有就只是静态展示 —— 分支换的是"套不套 Button"，
    /// 行内容是同一个 `row`，不会出现"可点版和不可点版长得不一样"。
    @ViewBuilder
    private var content: some View {
        if hasLink {
            Button(action: openLink) {
                row
                    .contentShape(RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 10) {
            // 圆点：公告的"这不是普通卡片"信号。lime 只作面（fill），不碰文字色铁律
            Circle()
                .fill(Theme.lime)
                .frame(width: 6, height: 6)
                // 与标题第一行光学对齐（caption 字高约 14pt，圆点居中偏移约 4pt）
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                if announcement.title.isEmpty == false {
                    Text(announcement.title)
                        .font(Typography.footnoteMedium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                if announcement.body.isEmpty == false {
                    Text(announcement.body)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                        // 最多 2 行：横幅是路过时扫一眼的东西，不是阅读区
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            // 右侧小 ×。嵌在可点行内，必须显式给 `.plain`，否则继承外层按压样式出现双高亮
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭公告")
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, 10)
        // 与设置页 / 列表行同一行高纪律：内容再短，这一条也不塌成细条
        .frame(minHeight: Spacing.listItemMinHeight)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
    }

    // MARK: - 动作

    /// 外部链接打开方式与工程现役形态一致（`UIApplication.shared.open`，同 `UpdateInstaller`）
    private func openLink() {
        Haptics.light()
        guard let raw = announcement.url, let url = URL(string: raw) else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #endif
    }

    /// 关闭：落盘当前 revision + 本地状态同步。新 revision 发布后自动重新出现。
    private func close() {
        Haptics.light()
        UserDefaults.standard.set(revision, forKey: Self.dismissedKey)
        dismissedRevision = revision
    }

    // MARK: - 派生

    /// 有合法可点的链接才整条可点：`url` 存在但拼不成 URL 时按"没有链接"处理
    private var hasLink: Bool {
        guard let raw = announcement.url, raw.isEmpty == false else { return false }
        return URL(string: raw) != nil
    }
}
