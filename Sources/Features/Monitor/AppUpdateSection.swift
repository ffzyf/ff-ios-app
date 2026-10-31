import SwiftUI

/// 监控页里的「这个 App 自己有没有新版本」那一行（设计文档 §4.7）。
///
/// ## 为什么不并进 `VersionStatusCard`
/// 那张卡讲的是**光遇国服 / 国际服**的版本（`MonitorAppVersion`），跟"这个 App 有没有新版"
/// 是两件事。混进同一张卡就会出现"卡片右上角写着有新版本，其实是光遇的"这种致命歧义 ——
/// 这个工程里 `StatusPillKind.newVersion` 的绿胶囊已经承载了"光遇有新版本"的语义，不能再挤。
/// 所以：那张卡**一个字段都不加**，这里是独立的一行。
///
/// ## 与「立即检查」按钮的区别（两者都在这一页、都叫"检查"）
/// · 「立即检查」→ 打 `POST /api/app/monitor/check`，会触发**服务端巡检并向所有 Bark 订阅者群发通知**；
/// · 「检查更新」→ 只读 `GET /api/app/version`，不触发任何推送。
/// 把它复用成"看看 App 有没有新版"，等于用户随手一点就给全站订阅者推一条通知。
/// 所以这一行自带说明文案，且**不复用**那个按钮的任何状态。
struct AppUpdateSection: View {

    @ObservedObject private var store = UpdateStore.shared

    /// 60 秒限频拦截时的瞬时反馈（3.9.0）。nil = 不显示；
    /// 正常发起的「正在检查…」由状态机（`subtitle`）接管，不经过这里。
    @State private var flashFeedback: String?

    /// 显式空 init：`@ObservedObject` 是 private 存储属性，
    /// 否则自动生成的 memberwise init 会被降级成 private，跨文件构造编译不过。
    init() {}

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(iconTint)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("这个 App")
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    // 两行上限：文案比原标题长，但**行高不变**（下面 `minHeight` 钉住了）
                    .lineLimit(2)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, 10)
        // 行高与设置页 / 列表行那几条一致：无论文案折几行，这一行的盒子高度不变
        .frame(minHeight: Spacing.listItemMinHeight)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
    }

    // MARK: - 右侧

    @ViewBuilder
    private var trailing: some View {
        switch store.state {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .tint(Theme.limeInk)
        case .available:
            CapsuleGlassButton(title: "查看更新", icon: "arrow.down.circle.fill") {
                store.present()
            }
        case .failed:
            // 失败不写闸门时间，所以这里是真重试，不受 6 小时限制
            CapsuleGlassButton(title: "重试", icon: "arrow.clockwise") {
                Task { await store.check(force: true) }
            }
        case .idle, .upToDate:
            CapsuleGlassButton(title: "检查更新", icon: "arrow.clockwise") {
                // 真·立即检测（3.9.0）：跳过 6 小时闸门，只受 60 秒客户端限频。
                // 限频拦截时给 2 秒瞬时反馈；正常发起的「正在检查…」由状态机接管。
                Task { await runCheckNow() }
            }
            .disabled(!store.canCheckNow)
            .opacity(store.canCheckNow ? 1 : 0.55)
        }
    }

    // MARK: - 文案

    private var icon: String {
        switch store.state {
        case .idle: return "clock"
        case .checking: return "arrow.clockwise"
        case .upToDate: return "checkmark.circle"
        case .available: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var iconTint: Color {
        switch store.state {
        case .available: return Theme.limeInk
        case .failed: return Theme.statusError
        case .idle, .checking, .upToDate: return Theme.textTertiary
        }
    }

    /// 第二行：当前版本 + 最近检查时间。四种状态各有各的说法，绝不用一条「—」糊过去
    private var subtitle: String {
        // 限频拦截的瞬时反馈最优先：它比"N 分钟前检查过"更像是对这次点击的直接回答
        if let flash = flashFeedback {
            return flash
        }
        let current = "当前 " + store.currentVersionText
        switch store.state {
        case .available(let release):
            return current + " · v" + release.version + " 可用"
        case .failed:
            return current + " · 暂时检查不了更新"
        case .checking:
            return current + " · 正在检查…"
        case .idle, .upToDate:
            guard let checked = store.lastCheckedAt else {
                return current + " · 还没有检查过"
            }
            return current + " · " + Formatters.relative(checked) + "检查过"
        }
    }

    // MARK: - 立即检测

    /// 发起真·立即检测；被 60 秒限频拦下时闪一条「刚检查过，稍等一分钟」（2 秒后清空）。
    private func runCheckNow() async {
        let started = await store.checkNow()
        guard started == false else { return }
        flashFeedback = "刚检查过，稍等一分钟"
        do {
            try await Task.sleep(for: .seconds(2))
        } catch {
            // 视图销毁会取消 sleep，此时不该再碰状态
            return
        }
        // 只清自己写的这条：期间用户可能又点了检查、状态机文案已经接管
        if flashFeedback == "刚检查过，稍等一分钟" {
            flashFeedback = nil
        }
    }
}
