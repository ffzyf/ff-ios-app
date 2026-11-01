import ActivityKit
import SwiftUI

/// 设置页的「天光」组（设计文档 §1.5；3.10.0 重做为**状态跟随型按钮**）。
///
/// ## 这一行不再是开关，而是「监控 / 切换」二合一
///
/// 3.8.0~3.9.0 的那一版是纯 Toggle：`@AppStorage` 记"用户的意图"，
/// Toggle 拨到哪边就是哪边 —— 哪怕活动其实已经被红石挤掉、被系统收掉、窗口已经过期，
/// 开关仍然闭着眼说"开着"。用户看到的字与屏幕上的事实分叉，就会以为"它坏了"。
///
/// 3.10.0 起（用户反馈：灵动岛到底显没显示，在设置里看不见）：
/// - **副标题实时跟随 `DaylightActivityCoordinator.isIslandActive`**：
///   「灵动岛与锁屏显示中」/「未显示」，红石占用时明确写「红石活动占用中」（按钮禁用）；
/// - **右侧是一个按钮**：显示中 → 文案「关闭」（动作 = 记住关闭 + `endAll()`）；
///   未显示 → 文案「开启」（动作 = 记住开启 + `startNow()`）。
///   注意动作里仍要**写存储键**：不写的话 60 秒 tick 会按旧意图把活动重新拉起来（或再次收掉），
///   "关了又自己回来"比旧版 Toggle 更糟。写键 + 动作合在同一处，语义才闭环；
/// - **`.task` + scenePhase 回前台时 `refreshActivityState()`**：前台回来状态要跟上
///   （系统 / 红石在后台动过活动，App 不刷新就读旧态）。
///
/// 结构与 `LiveActivitySection`（红石，仍是真开关）**逐行对齐**（同间距、同玻璃底、同行高）：
/// 两个相邻行的形状必须一致，一个 48pt 一个 52pt，用户只会觉得"这个页面做得糙"。
struct DaylightActivitySection: View {

    /// 与 `DaylightSettings.storageKey` 同一个键。**默认关闭**（天光是常驻型活动，
    /// 不替用户做主）。注意：它只表达"用户的意图"，**不驱动按钮的显示状态** ——
    /// 显示状态只看 `coordinator.isIslandActive`（见文件头）。
    @AppStorage(DaylightSettings.storageKey) private var isEnabled: Bool = false

    /// 活动状态的唯一来源（观察单例：`isIslandActive` 变化即重算副标题与按钮文案）
    @ObservedObject private var coordinator = DaylightActivityCoordinator.shared

    /// 前台/后台切换时重读能力 + 刷新活动状态
    @Environment(\.scenePhase) private var scenePhase

    /// 能力判定结果。**初值直接在声明处读**，不在 `onAppear` 里补 ——
    /// 否则首帧会先画出一个可点的按钮、第二帧再跳成灰的，那一下闪烁比降级本身更可疑
    @State private var activitiesEnabled: Bool = ActivityAuthorizationInfo().areActivitiesEnabled

    /// 切换动作是否在跑（防连点：动作是同步的，但 endAll 的收尾是异步的，
    /// 连点会在系统还没摘完旧活动时又发一个相反动作）
    @State private var isToggling: Bool = false

    /// 显式空 init：`@AppStorage` / `@State` 是 private 存储属性，避免 memberwise init 被降级
    init() {}

    var body: some View {
        VStack(spacing: 8) {
            actionRow

            Text(detailParagraph)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)

            Text("与红石实时活动同时只会显示红石那一个；红石结束后天光会自动回来。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)
        }
        // 回前台：能力与活动状态都要跟上（系统设置里可能刚关/开了实时活动，
        // 红石 / 系统也可能在后台动过天光活动）
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
            if enabled != activitiesEnabled {
                activitiesEnabled = enabled
            }
            coordinator.refreshActivityState()
        }
        // 首次出现也刷一次：进设置页之前活动状态可能已经变了（60 秒 tick 已兜一层，
        // 这里是即时性兜底）
        .task {
            coordinator.refreshActivityState()
        }
    }

    // MARK: - 行

    private var actionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 15, weight: .medium))
                // 能力不可用 / 未显示时图标退到中性色：青柠图标配「未显示」，会读成"已经生效了"
                .foregroundStyle(coordinator.isIslandActive && activitiesEnabled ? Theme.limeInk : Theme.textTertiary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("天光灵动岛")
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    // 两行上限：降级文案比原文长，允许它最多折两行 ——
                    // **行高不能跟着变**，`.frame(minHeight:)` 在下面钉住了
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            toggleButton
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, 10)
        // 行高与「红石」组那一行完全相同：无论行文折几行，这一行的盒子高度不变
        .frame(minHeight: Spacing.listItemMinHeight)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
    }

    /// 右侧的单个按钮：显示中 → 「关闭」；未显示 → 「开启」。
    ///
    /// 置灰的三种情况：动作在跑（防连点）、系统能力不可用、红石占用中
    ///（占用时 Coordinator 的 startNow 也会拒，但按钮先禁用更诚实）。
    private var toggleButton: some View {
        Button {
            applyToggle()
        } label: {
            Text(buttonTitle)
                .font(Typography.footnoteMedium)
                .foregroundStyle(Theme.onLime)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background { Capsule().fill(Theme.lime) }
                .overlay { Capsule().strokeBorder(Theme.glassStrokeTop, lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!canTap)
        // 置灰而不是隐藏：iPad 上实时活动不可用，但这一行仍要解释"为什么不能用 +
        // 还有什么能用"。同理这里不判 `widthClass`（Slide Over 里 iPad 也是 compact）
        .opacity(canTap ? 1 : 0.4)
        .accessibilityLabel(buttonTitle)
    }

    // MARK: - 动作

    private var canTap: Bool {
        return activitiesEnabled && !isToggling && !DaylightActivityCoordinator.isRockOccupying()
    }

    private var buttonTitle: String {
        return coordinator.isIslandActive ? "关闭" : "开启"
    }

    /// 按下按钮：写意图键 + 执行对应动作，最后刷新一次状态。
    ///
    /// 为什么动作里要写存储键（文件头已述）：60 秒 tick 只认存储键。
    /// `endAll` / `startNow` 内部都会 `refreshActivityState()`，这里不必再刷。
    private func applyToggle() {
        Haptics.light()
        isToggling = true
        if coordinator.isIslandActive {
            isEnabled = false
            DaylightActivityCoordinator.shared.endAll()
        } else {
            isEnabled = true
            DaylightActivityCoordinator.shared.startNow()
        }
        isToggling = false
    }

    // MARK: - 文案

    /// 第一段说明：可用时说"开启后会怎样"，不可用时说"这台设备上没有这件事"，
    /// **两段行数一致**（iPhone 上都是 2 行）——避免"降级态比正常态高出 16pt"这种
    /// 会被当成 bug 的差异。
    private var detailParagraph: String {
        guard activitiesEnabled else {
            return "此设备没有锁屏实时活动，桌面添加「天光」小组件是一样的效果。"
        }
        return "开启后立刻出现在锁屏与灵动岛：此刻的太阳位置、天色与天气。日落或 8 小时后自动消失，回到 App 会重新出现。"
    }

    /// 副标题：**实时状态**（不是存储里的意图）。优先级：能力缺失 > 红石占用 > 实际显示状态。
    private var subtitle: String {
        guard activitiesEnabled else {
            return "此设备不支持锁屏实时活动，可用桌面小组件"
        }
        if DaylightActivityCoordinator.isRockOccupying() {
            return "红石活动占用中"
        }
        return coordinator.isIslandActive ? "灵动岛与锁屏显示中" : "未显示"
    }
}
