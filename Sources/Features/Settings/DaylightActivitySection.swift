import ActivityKit
import SwiftUI

/// 设置页的「天光」组（设计文档 §1.5）。
///
/// 结构与 `LiveActivitySection` **逐行对齐**（同间距、同玻璃底、同行高、同 `.lineLimit(2)`）：
/// 两个开关在同一个页面里上下相邻，形状必须一致 —— 一个 48pt 高一个 52pt 高，
/// 用户不会说"行高不一致"，只会觉得"这个页面做得糙"。那里的注释已经把理由写完，这里不抄第二遍。
///
/// 与红石的三处差别，都是"要让用户看得懂"的那一类：
/// 1. **默认关闭**（`@AppStorage` 初值 false）：天光是**常驻型**活动，白天一直占着
///    灵动岛 / 锁屏，不替用户做主；红石是事件型的，默认开启才合理；
/// 2. 多第三段说明"与红石同时只显示红石那一个"：天光会**自己消失**（被红石挤掉），
///    不给这句话，用户只会以为它坏了 —— 这是两种活动最容易被误判的区别；
/// 3. 降级态的替代方案指向桌面「天光」小组件：那个组件不依赖实时活动，落点是真实的。
struct DaylightActivitySection: View {

    /// 与 `DaylightSettings.storageKey` 同一个键；**默认关闭**（理由见类型注释）
    @AppStorage(DaylightSettings.storageKey) private var isEnabled: Bool = false

    /// 前台/后台切换时重读能力：用户可能刚在系统设置里把实时活动关掉或打开
    @Environment(\.scenePhase) private var scenePhase

    /// 能力判定结果。**初值直接在声明处读**，不在 `onAppear` 里补 ——
    /// 否则首帧会先画出一个可点的开关、第二帧再跳成灰的，那一下闪烁比降级本身更可疑
    @State private var activitiesEnabled: Bool = ActivityAuthorizationInfo().areActivitiesEnabled

    /// 显式空 init：`@AppStorage` / `@State` 是 private 存储属性，避免 memberwise init 被降级
    init() {}

    var body: some View {
        VStack(spacing: 8) {
            toggleRow

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
        .onChange(of: scenePhase) { _, phase in
            // 只在回到前台时读，且**值真变才写** `@State`：写同样的值也会多一次 body 重算，
            // 而这里没有任何东西需要跟着重算（与 `LayoutMetricsScope` 同一条纪律）
            guard phase == .active else { return }
            let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
            if enabled != activitiesEnabled {
                activitiesEnabled = enabled
            }
        }
    }

    // MARK: - 开关行

    private var toggleRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 15, weight: .medium))
                // 能力不可用时图标一并退到中性色：否则会出现"灰开关 + 青柠图标"的矛盾态
                .foregroundStyle(isEnabled && activitiesEnabled ? Theme.limeInk : Theme.textTertiary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("天光实时活动")
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

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .tint(Theme.lime)
                // 置灰而不是隐藏：iPad 上实时活动不可用，但这一行仍要解释"为什么不能用 +
                // 还有什么能用"。同理这里不判 `widthClass`（Slide Over 里 iPad 也是 compact）
                .disabled(!activitiesEnabled)
                .accessibilityLabel("天光实时活动")
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, 10)
        // 行高与「红石」组那一行完全相同：无论行文折几行，这一行的盒子高度不变
        .frame(minHeight: Spacing.listItemMinHeight)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
        .onChange(of: isEnabled) { _, newValue in
            Haptics.light()
            if !newValue {
                // 关掉即收尾：不等下一次 60 秒评估（与红石同一纪律）
                DaylightActivityCoordinator.shared.endAll()
            }
            // 打开时不开活动：交给协调器的下一次前台 tick（≤60 秒）按守卫链判定 ——
            // 夜里、日落后、红石占用中都体面拒绝，Coordinator 那里才有这些判断，
            // 这里硬开一次会绕过它们（而 <10 分钟那一条正是为了防止"开了等于没开"）
        }
    }

    /// 第一段说明：可用时说"开启后会怎样"，不可用时说"这台设备上没有这件事"，
    /// **两段行数一致**（iPhone 上都是 2 行）——避免"降级态比正常态高出 16pt"这种
    /// 会被当成 bug 的差异。
    private var detailParagraph: String {
        guard activitiesEnabled else {
            return "此设备没有锁屏实时活动，桌面添加「天光」小组件是一样的效果。"
        }
        return "白天会在锁屏与灵动岛显示此刻的太阳位置、天色与天气。日落或 8 小时后自动消失，回到 App 会重新出现。"
    }

    /// 副标题：可用时说"能做什么"，不可用时说"为什么不能用 + 还有什么能用"
    private var subtitle: String {
        guard !activitiesEnabled else {
            return "锁屏与灵动岛显示此刻的天光"
        }
        return "此设备不支持锁屏实时活动，可用桌面小组件"
    }
}
