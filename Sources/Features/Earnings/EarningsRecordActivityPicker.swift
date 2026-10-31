import SwiftUI

/// 活动选择（记账的第一层结构：**活动 → entry**）。
///
/// 网站版的模型是两层：先有活动（`activity`），记账是把 entry 挂到某个活动下面。
/// 所以这里的「活动」不是可选的标签，而是记账的前提 —— 没有活动就没有地方挂 entry
/// （服务端 `POST /api/app/earnings/entry` 的 `activityId` 必填）。
///
/// 展示方式**按平台分组**，与网页端一致：
/// 平台是小标题，标题下是这一平台的活动胶囊。平台顺序由
/// `EarningsPlatformPreset.ordered(from:)` 给出（固定 5 个在前、自定义按首次出现），
/// 与服务端聚合口径同序 —— 否则同一个账号在两侧看到的排列会不一样。
struct EarningsRecordActivityPicker: View {

    let activities: [EarningsActivity]
    @Binding var selectedId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            if activities.isEmpty {
                EarningsRecordNoActivityHint()
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: Spacing.gridUnit) {
                        // 平台名做小标题（不是可点项：平台本身不可选，选的永远是活动）
                        Text(group.platform)
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.gridUnit) {
                                ForEach(group.activities) { activity in
                                    EarningsRecordChip(
                                        title: activity.name,
                                        subtitle: EarningsMoney.formatCents(activity.totalCents),
                                        selected: activity.id == selectedId
                                    ) {
                                        selectedId = activity.id
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .onAppear(perform: selectFirstIfNeeded)
        .onChange(of: activities.count) { _, _ in
            // 活动被网页端删掉 / App 刚建了一个时，别把一个已不存在的 id 留在选中态
            selectFirstIfNeeded()
        }
    }

    /// 按平台分好组的活动（空平台不分组；组内保持服务端顺序）
    ///
    /// 用一个小 struct 而不是元组：`ForEach` 需要 `Identifiable`（或可用的 keyPath），
    /// 而 Swift 的 keyPath 不支持元组成员 —— 元组写法在这里编不过。
    private struct PlatformGroup: Identifiable {
        let platform: String
        let activities: [EarningsActivity]
        var id: String { platform }
    }

    private var groups: [PlatformGroup] {
        return EarningsPlatformPreset.ordered(from: activities)
            .map { name in
                PlatformGroup(
                    platform: name,
                    activities: EarningsPlatformPreset.activities(activities, in: name)
                )
            }
            .filter { $0.activities.isEmpty == false }
    }

    /// 默认选中第一个活动，并清理失效的选中项
    private func selectFirstIfNeeded() {
        if let selectedId, activities.contains(where: { $0.id == selectedId }) {
            return
        }
        selectedId = activities.first?.id
    }
}

/// 「没有活动」时的提示：**不给记账表单**，只说清楚下一步。
///
/// 现在 App 自己就能建活动（`POST /api/app/earnings/activity`），所以这里的出路不再是
/// "去网页端"，而是"就在下面的新建活动表单里建一个"。
struct EarningsRecordNoActivityHint: View {

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.gridUnit) {
            HStack(spacing: Spacing.gridUnit) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.statusWarn)
                Text("还没有任何活动")
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            Text("先在下面建一个活动，再往里记钱。每一笔都得挂在某个活动下面（活动 → 条目）。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.smallCardPadding)
        .background {
            RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                .fill(Theme.surfaceTint1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 归属平台选择（新建活动表单里的那一行胶囊）。
///
/// 三个来源，顺序固定：
/// 1. 固定 5 个平台（`EarningsPlatformPreset.fixed`，与网页端 `FIXED` 同序）；
/// 2. 账号里已经出现过的自定义平台（按首次出现，与 `EarningsPlatformPreset.ordered` 一致）；
/// 3. 最后一个「新平台」胶囊 —— 选中后由上层展开一行输入框（≤12 字）。
///
/// 为什么不做一个"平台管理页"：平台不是独立实体，服务端没有平台表。
/// 平台是跟着活动走的：填一个新名字，就等于新建了一个平台。
struct EarningsRecordPlatformPicker: View {

    @Binding var text: String
    /// 可选平台（固定 + 已存在的自定义，顺序由 `EarningsPlatformPreset.ordered` 给出）
    let options: [String]

    /// 「新平台」哨兵值。web 端用的是 `'__new'`，这里沿用同一个字符串（不在活动名里出现）
    static let newPlatformToken = "__new__"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.gridUnit) {
                ForEach(options, id: \.self) { platform in
                    EarningsRecordChip(title: platform, selected: platform == text) {
                        text = platform
                    }
                }
                EarningsRecordChip(title: "新平台", selected: text == Self.newPlatformToken) {
                    text = Self.newPlatformToken
                }
            }
            .padding(.vertical, 2)
        }
    }
}
