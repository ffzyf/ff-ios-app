import SwiftUI

/// 活动选择（记账的第一层结构：**活动 → entry**）。
///
/// 网站版的模型是两层：先有活动（`activity`），记账是把 entry 挂到某个活动下面。
/// 所以这里的「活动」不是可选的标签，而是记账的前提 —— 没有活动就没有地方挂 entry。
/// 服务端 `POST /api/app/earnings/entry` 的 `activityId` 必填。
///
/// 只显示前 12 个活动：手机上一屏能比较的范围有限，更多的活动仍在网页端管理
/// （App 里不提供建活动 / 改活动，那两件事都要长表单）。
struct EarningsRecordActivityPicker: View {

    let activities: [EarningsActivity]
    @Binding var selectedId: String?

    /// 手机上最多给几个可选活动
    private static let visibleLimit = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EarningsRecordFieldLabel(text: "活动", accessory: accessoryText)

            if activities.isEmpty {
                EarningsRecordNoActivityHint()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visibleActivities) { activity in
                            EarningsRecordChip(
                                title: activity.name,
                                subtitle: activity.platform,
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
        .onAppear(perform: selectFirstIfNeeded)
        .onChange(of: activities.count) { _, _ in
            // 活动被网页端删掉 / 新增时，别把一个已不存在的 id 留在选中态
            selectFirstIfNeeded()
        }
    }

    private var visibleActivities: [EarningsActivity] {
        return Array(activities.prefix(Self.visibleLimit))
    }

    private var accessoryText: String {
        guard activities.isEmpty == false else { return "还没有活动" }
        if activities.count > Self.visibleLimit {
            return "\(activities.count) 个 · 显示前 \(Self.visibleLimit) 个"
        }
        return "\(activities.count) 个"
    }

    /// 默认选中第一个活动，并清理失效的选中项
    private func selectFirstIfNeeded() {
        if let selectedId, activities.contains(where: { $0.id == selectedId }) {
            return
        }
        selectedId = activities.first?.id
    }
}

/// 「没有活动」时的替代内容：**不给记账表单**，只说明该去哪儿建活动。
///
/// 为什么不在 App 里建活动：建活动要填名称 / 平台 / 结算方式，是一张长表单，
/// 塞进手机反而更难用（与问卷工作台的分工一致）。这里只把出路说清楚。
struct EarningsRecordNoActivityHint: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.statusWarn)
                Text("先在网页端建一个活动")
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            Text("每一笔都得挂在某个活动下面（活动 → 条目）。网页端建好活动后回到这页下拉刷新，就能记账了。")
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
