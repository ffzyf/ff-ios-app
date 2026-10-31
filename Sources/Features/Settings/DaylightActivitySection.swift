import ActivityKit
import SwiftUI

/// 设置页的「天光」组（方案 §1.5）。
///
/// 结构与 `LiveActivitySection` **逐行对齐**：
/// 同 `Spacing.cardPadding` / 同 `Spacing.listItemMinHeight` /
/// 同 `glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))`。
///
/// 默认**关闭**（新增的常驻型活动，不替用户做主；`defaults.bool(forKey:)`
/// 天然返回 false，不需要写 `object(forKey:) == nil` 分支）。
///
/// ## 能力降级（iPad）
///
/// 与 `LiveActivitySection` 同一套做法：`ActivityAuthorizationInfo().areActivitiesEnabled`
/// 在属性声明处读（不在 `onAppear` 里补），`Toggle.disabled`，副标题换文案，
/// `.lineLimit(2)`，**行高不变**（`minHeight: Spacing.listItemMinHeight`）。
struct DaylightActivitySection: View {

    /// 与 `DaylightSettings.storageKey` 同一个键；默认关闭
    ///
    /// 默认关闭是刻意的：新增的常驻型实时活动，不替用户做主开一个可能
    /// "每天 8 小时挂在锁屏上"的东西。`@AppStorage` 读不存在的键时
    /// `Bool` 天然返回 `false`，所以这里不需要写 `object(forKey:) == nil` 的分支。
    @AppStorage(DaylightSettings.storageKey) private var isEnabled: Bool = false

    /// 前台/后台切换时重读能力：用户可能刚在系统设置里把实时活动关掉或打开
    @Environment(\.scenePhase) private var scenePhase

    /// 能力判定结果。**初值直接在声明处读**，不在 `onAppear` 里补 ——
    /// 否则首帧会先画出一个可点的开关、第二帧再跳成灰的，那一下闪烁比降级本身更可疑。
    @State private var activitiesEnabled: Bool = ActivityAuthorizationInfo().areActivitiesEnabled

    /// 显式空 init：`@AppStorage` 是 private 存储属性，避免 memberwise init 被降级
    /// （`scripts/check-signatures.py` 规则 4 会报）。
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
            Image(systemName: "sun.max.fill")
                .font(.system(size: 15, weight: .medium))
                // 能力不可用时图标一并退到中性色：否则会出现"灰开关 + 亮色图标"的矛盾态
                .foregroundStyle(isEnabled && activitiesEnabled ? Theme.sky(.day).edge : Theme.textTertiary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("天光实时活动")
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
                .tint(Theme.sky(.day).edge)
                // 置灰而不是隐藏（与 `LiveActivitySection` 同一条纪律）。
                // 注意：这也意味着"用户在系统设置里关了实时活动"的 iPhone 会看到同一个
                // 灰开关 —— 这是接受过的取舍（设计文档 §10 问题 2），因为区分不了，
                // 而一个点了没反应的开关比一句解释更糟。
                .disabled(!activitiesEnabled)
                .accessibilityLabel("天光实时活动")
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: Spacing.listItemMinHeight)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
        .onChange(of: isEnabled) { _, newValue in
            Haptics.light()
            if !newValue {
                // 关掉即收尾：不等下一次 60 秒评估（与红石同一纪律）
                DaylightActivityCoordinator.shared.endAll()
            }
        }
    }

    /// 第一段说明：可用时说"开启后会怎样"，不可用时说"这台设备上没有这件事"。
    ///
    /// 为什么降级态必须换文案：上面那个开关已经是灰的、副标题也已经说了"不支持"，
    /// 这里再写"开启后会在锁屏与灵动岛出现天光"，等于在一句"不支持"后面接一句
    /// "开启后就有" —— 同一块里自相矛盾，用户会以为是自己没找对开关。
    ///
    /// 为什么只换第一段：第二段（"与红石互斥"）在降级态是错的
    /// （不能用实时活动，谈什么互斥）—— 所以第二段在两种态下共用同一句？
    /// 不，降级态也仍然有"为什么没有"的解释成本。这里的第二段写的是互斥规则，
    /// 降级态的替代路径是「桌面天光小组件」—— 与红石那块一样指向已存在的
    /// `SkyLightWidget`，落点真实。
    private var detailParagraph: String {
        guard activitiesEnabled else {
            return "此设备没有锁屏实时活动，桌面添加「天光」小组件是一样的效果。"
        }
        return "白天会在锁屏与灵动岛显示此刻的太阳位置、天色与天气。日落或 8 小时后自动消失，回到 App 会重新出现。"
    }

    /// 副标题：可用时说"能做什么"，不可用时说"为什么不能用 + 还有什么能用"
    private var subtitle: String {
        guard activitiesEnabled else {
            return "此设备不支持锁屏实时活动，可用桌面小组件"
        }
        return "锁屏与灵动岛显示此刻的天光"
    }
}
