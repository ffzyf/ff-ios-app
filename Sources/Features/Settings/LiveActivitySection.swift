import ActivityKit
import SwiftUI

/// 设置页的「红石」组（PRD P14 第 ② 项）。
///
/// 一个开关 + 两句说明：
/// · 开关落盘用 `@AppStorage`（键名与 `LiveActivityCoordinator` 共用一个常量，
///   避免"设置里关了、Coordinator 还在读旧值"这种最难查的分歧）；
/// · 关掉时立刻 `endAll()`，不等下一次评估 —— 用户关了就该马上从锁屏消失。
///
/// 为什么不做「跳系统设置」按钮：`UIApplication.openSettingsURLString` 打开的是**本 App** 的设置页，
/// 而实时活动/小组件的总开关在"设置 → 通知"与"长按桌面"里，跳过去也未必直达，
/// 写一个跳不到地方的按钮比写一句话更糟。
///
/// ## 能力降级（设计文档 §6）
///
/// 实时活动在 iPad 上不可用（无灵动岛，iPadOS 不支持锁屏实时活动）。但**没有任何公开 API
/// 能表达"这台设备支持实时活动"** —— 唯一可用的是 `ActivityAuthorizationInfo().areActivitiesEnabled`，
/// 而它在两种情况下都是 `false`：
/// ① 设备本身不支持（iPad）；② 用户在系统设置里把实时活动关掉了（iPhone）。
/// 这两件事在代码里无法区分，所以只能共用同一套降级表现。
///
/// 表现上**不整块隐藏**，理由很具体：整块消失会让设置页少一组、页面高度突变，
/// 用户会以为"设置项丢了"；而同高的降级行既解释了原因，又把布局保住了。
/// 也因此这里不判 `widthClass`（iPad 在 Slide Over 里是 compact，用宽度判会在
/// Slide Over 里显示一个点了没反应的开关 —— 正是要避免的那类错误）。
struct LiveActivitySection: View {

    /// 与 `SunEventSettings.storageKey` 同一个键；默认开启
    @AppStorage(SunEventSettings.storageKey) private var isEnabled: Bool = true

    /// 前台/后台切换时重读能力：用户可能刚在系统设置里把实时活动关掉或打开
    @Environment(\.scenePhase) private var scenePhase

    /// 能力判定结果。**初值直接在声明处读**，不在 `onAppear` 里补 ——
    /// 否则首帧会先画出一个可点的开关、第二帧再跳成灰的，那一下闪烁比降级本身更可疑。
    @State private var activitiesEnabled: Bool = ActivityAuthorizationInfo().areActivitiesEnabled

    /// 显式空 init：`@AppStorage` 是 private 存储属性，避免 memberwise init 被降级
    init() {}

    var body: some View {
        VStack(spacing: 8) {
            toggleRow

            Text(detailParagraph)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)

            Text("桌面小组件在桌面长按 → 编辑 → 添加，与这个开关无关，随时可用。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)
        }
        .onChange(of: scenePhase) { _, phase in
            // 只在回到前台时读，且**值真变才写** `@State`（与 `LayoutMetricsScope` 同一条纪律：
            // 写同样的值也会多一次 body 重算，而这里没有任何东西需要跟着重算）。
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
            Image(systemName: "moon.stars")
                .font(.system(size: 15, weight: .medium))
                // 能力不可用时图标一并退到中性色：否则会出现"灰开关 + 青柠图标"的矛盾态
                .foregroundStyle(isEnabled && activitiesEnabled ? Theme.limeInk : Theme.textTertiary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("红石实时活动")
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    // 两行上限：降级文案比原文长，允许它最多折两行（不再无限折），
                    // 换行也不会把这块顶成"一行说明"以外的第三种形状。
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .tint(Theme.lime)
                // 置灰而不是隐藏（§6）。注意：这也意味着"用户在系统设置里关了实时活动"
                // 的 iPhone 会看到同一个灰开关 —— 这是接受过的取舍（设计文档 §10 问题 2），
                // 因为区分不了，而一个点了没反应的开关比一句解释更糟。
                .disabled(!activitiesEnabled)
                .accessibilityLabel("红石实时活动")
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: Spacing.listItemMinHeight)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
        .onChange(of: isEnabled) { _, newValue in
            Haptics.light()
            if !newValue {
                // 关掉即收尾：不等下一次 60 秒评估
                LiveActivityCoordinator.shared.endAll()
            }
        }
    }

    /// 第一段说明：可用时说"开启后会怎样"，不可用时说"这台设备上没有这件事"。
    ///
    /// 为什么降级态必须换文案：上面那个开关已经是灰的、副标题也已经说了"不支持"，
    /// 这里再写"开启后会在锁屏与灵动岛出现倒计时"，等于在一句"不支持"后面接一句
    /// "开启后就有" —— 同一块里自相矛盾，用户会以为是自己没找对开关。
    ///
    /// 为什么只换第一段：第二段（桌面小组件加不了靠长按桌面）在降级态**恰好是对的**，
    /// 它本来就是"不能用实时活动时还能用什么"的答案，换掉反而丢掉了唯一可行的替代路径。
    ///
    /// 为什么行数要和原文一样（iPhone 上都是 2 行）：这块高度决定了设置页的高度，
    /// 文案多一行会让降级态的页面比正常态长出 16pt —— 一个"设备不同、页面高不同"的差异
    /// 比文案本身更容易被当成 bug。
    private var detailParagraph: String {
        guard activitiesEnabled else {
            return "此设备不支持锁屏与灵动岛的实时活动，用桌面小组件看下一场倒计时即可。"
        }
        return "开启后，场次落地前 20 分钟会在锁屏与灵动岛出现倒计时，落地后 52 分钟自动消失。22:30 之后的场次不提醒。"
    }

    /// 副标题：可用时说"能做什么"，不可用时说"为什么不能用 + 还有什么能用"
    private var subtitle: String {
        guard !activitiesEnabled else {
            return "锁屏与灵动岛显示下一场倒计时"
        }
        return "此设备不支持锁屏实时活动，可用桌面小组件"
    }
}
