import SwiftUI

/// 单平台详情弹页（A+B 混合方案的 A 面：**卡片墙**）。
///
/// 为什么把它做成弹页而不是页面内的展开卡：
/// 两列网格已经回答了"谁占多少"，再往同一屏塞一张"按平台过滤的活动列表"，
/// 平台区块会长到跟「最近活动」抢位置 —— 而这两块的内容高度都不可控（活动条数随账号变）。
/// 弹页的好处是：**平台列表永远只有 96pt 高的四张卡**，想细看才展开，
/// `.medium` 档还能让用户只露半个屏，往下拖就是 `.large`，视线不离开当前滚动位置。
///
/// ## 版面三段
/// 1. 头：● 平台名（22pt）+ 右侧活动数；下一行「待发 · 已收」（来自总览顶层 `platforms`）；
/// 2. 分割线；
/// 3. 活动行：名称 15pt + 时间 11pt / 右侧金额 17pt + 状态胶囊（待发 = `lime` 面 + `onLime` 字，
///    已收 = 中性面 + 次级字）。
///
/// 三个口径纪律：
/// 1. **金额格式化只走 `EarningsMoney.formatCents`**（全工程唯一入口，本文件不出现第二个 formatter）；
/// 2. **待发 / 已收不自己加总**：取 `EarningsPlatform.pendingCents` / `receivedCents` 两个服务端字段。
///    这份缓存里没有该平台（`aggregate == nil`）时**整行不出现**，不拿活动列表去凑一个近似值；
/// 3. **空态不画假行**：该平台没有活动就只写一句话，不给 0.00 的占位活动。
struct PlatformDetailSheet: View {

    /// 平台名（服务端原样字符串，含空格也不裁剪 —— 它同时是活动匹配的键）
    let platformName: String
    /// 该平台的服务端聚合（待发 / 已收 / 场次）。nil = 这份数据里没有（例如旧缓存）
    let aggregate: EarningsPlatform?
    /// 已按该平台过滤好的活动（由调用方用 `EarningsPlatformPreset.activities(_:in:)` 过滤）
    let activities: [EarningsActivity]

    /// 本页几何常量（嵌套类型不参与 memberwise init，故不影响下面那个显式 init）
    private enum Metrics {
        /// 品牌色圆点
        static let dot: CGFloat = 8
        /// 活动行最小高度：名称 + 时间两行文字的最小呼吸量
        static let rowMinHeight: CGFloat = 56
        /// 分割线厚度
        static let divider: CGFloat = 1
    }

    /// 显式 init（而不是靠 memberwise）两个理由：
    /// 1. 三个入参语义相近（平台名 / 平台聚合 / 活动列表），显式写出来才能在调用点强制带上标签，
    ///    `PlatformDetailSheet("抖音", nil, list)` 这种读不懂的调用根本编不过；
    /// 2. 一旦以后有人给本类型加一个 `private` 存储属性，memberwise init 会**悄悄降级成 private**，
    ///    跨文件构造就断了（`EarningsRecordSheet` 踩过这个坑）—— 显式 init 不参与那个规则。
    init(platformName: String, aggregate: EarningsPlatform?, activities: [EarningsActivity]) {
        self.platformName = platformName
        self.aggregate = aggregate
        self.activities = activities
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                divider
                if activities.isEmpty {
                    emptyState
                } else {
                    rows
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 18)
            .padding(.bottom, Spacing.sectionGap)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 头

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.gridUnit) {
                Circle()
                    .fill(Theme.Platform.of(platformName))
                    .frame(width: Metrics.dot, height: Metrics.dot)
                // 22pt：弹页标题与页面里的 `SectionHeader` 同一档，进来不会"变小一号"
                Text(platformName)
                    .font(Typography.titleL)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: Spacing.gridUnit)
                Text("\(activities.count) 个活动")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            if let aggregate {
                // 待发用 statusWarn（与三态构成条 / 旧平台明细同一语义色），已收用次级字：
                // 两个数都不是"涨跌"，所以都不借 riseRed / fallGreen
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("待发 " + EarningsMoney.formatCents(aggregate.pendingCents))
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.statusWarn)
                        .monospacedDigit()
                        .lineLimit(1)
                    Text("·")
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textTertiary)
                    Text("已收 " + EarningsMoney.formatCents(aggregate.receivedCents))
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.bottom, Spacing.cardGap)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: Metrics.divider)
    }

    // MARK: - 活动行

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(activities) { activity in
                activityRow(activity)
                if activity.id != activities.last?.id {
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(height: Metrics.divider)
                }
            }
        }
    }

    private func activityRow(_ activity: EarningsActivity) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                // 15pt：活动名是这一行的主语（与「最近活动」同一档，两处读起来是同一个东西）
                Text(activity.name)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                // 11pt 时间：同一平台下常有「9 月星图 / 10 月星图」这种只差一个月的同名活动，
                // 没有时间这一行，两行长得一模一样
                Text(EarningsClock.format(ms: activity.time))
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            // 17pt：金额与页面里其它金额同档（`titleS`）
            Text(EarningsMoney.formatCents(activity.totalCents))
                .font(Typography.titleS)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
            statusPill(isClosed: activity.isClosed)
        }
        .frame(minHeight: Metrics.rowMinHeight)
        .contentShape(Rectangle())
    }

    /// 状态胶囊。
    ///
    /// 「待发 / 已收」这组词与卡片副标题、以及头部的两个金额保持同一对词，
    /// 读的是 `EarningsActivity.isClosed`（服务端 `closedAt` 命中即已结清）。
    /// 待发是"钱还没到"——最该被看见的一档，所以用品牌色**面** + `onLime` **字**；
    /// 已收是完成态，安静即可，用中性面 + 次级字，不与待发抢注意力。
    private func statusPill(isClosed: Bool) -> some View {
        Text(isClosed ? "已收" : "待发")
            .font(Typography.captionXS)
            .foregroundStyle(isClosed ? Theme.textSecondary : Theme.onLime)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(isClosed ? Theme.surfaceTint3 : Theme.lime)
            }
            .overlay {
                Capsule().strokeBorder(Theme.divider, lineWidth: 1)
            }
            .fixedSize()
    }

    // MARK: - 空态

    /// 这个平台还没有活动：一句现象 + 一句出路，不插一行 ¥0.00 的假活动
    private var emptyState: some View {
        EmptyStateView(
            icon: "tray",
            title: "这个平台还没有活动",
            message: "记一笔时选这个平台，活动就会出现在这儿。"
        )
    }
}
