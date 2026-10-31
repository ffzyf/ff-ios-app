import SwiftUI

/// 收益三态构成条（设计报告 §4.4 / P0-8）：一条 10pt 堆叠条 + 一行图例。
///
/// **它存在的唯一理由**：改版前"待发 / 已收未结 / 已结"是三个并排的 17pt 数字加两条竖线，
/// 看上去是"三个独立指标"；但服务端保证 `pending + receivedUnclosed + closed == total`
/// （`EarningsSummary.isConsistent`），也就是这三段本就应该拼成一条满宽的条。
/// 把恒等式画出来，用户一眼就知道"我的钱现在分几种状态、各占多少"，而不是去心算三数之比。
///
/// 三条口径纪律：
/// 1. **入参是三个 `Int` 分，不是 `EarningsSummary`**：本组件不认识金额单位，
///    也不认识摘要里的其它字段 —— 单位换算只发生在 `EarningsMoney`，这里一个 `÷100` 都没有，
///    所以「元 / 分」口径不可能在这里被第二次实现。
/// 2. **分母 = 三段之和，不是 `total`**：三段之和正是恒等式的左边。若某天服务端的 `total`
///    与三段不一致，用 `total` 当分母会让三段宽度加起来不足满宽（条缺一角），
///    读者只会以为"画错了"，而这其实是数据口径问题 —— 不该由一条条来承担。
/// 3. **"本月新增"不参与**：它是"这个月新进来多少钱"的流量口径，与三态（存量口径）不同源，
///    混进同一条堆叠条会让比例失去意义（报告 §4.4 把它单独做成一张 tile）。
struct StatCompositionBar: View {
    /// 待发（未到账）金额，单位与 `EarningsMoney` 一致（服务端整数分）
    let pending: Int
    /// 已到账未结清金额
    let receivedUnclosed: Int
    /// 已结清金额
    let closed: Int

    /// 段间缝隙：三段色相不同，但纯靠色相在深色玻璃上仍会糊在一起；
    /// 一道 2pt 的缝比给每段加描边便宜，也更像"构成"而不是"渐变"。
    private let segmentGap: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.gridUnit) {
            bar
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - 条

    private var bar: some View {
        // 只画金额 > 0 的段：0 宽度的胶囊会被圆角渲染成一个小点，看起来像"多了一个状态"
        let visible = segments.filter { $0.cents > 0 }
        let gaps = CGFloat(max(0, visible.count - 1)) * segmentGap

        return GeometryReader { geo in
            let usable = max(0, geo.size.width - gaps)
            HStack(spacing: segmentGap) {
                if visible.isEmpty {
                    // 三段全 0（新账号 / 全部结清且金额为 0）：给一条空轨，
                    // 而不是留白 —— 留白会被读成"没加载出来"
                    Capsule().fill(Theme.glassFill)
                } else {
                    ForEach(visible) { segment in
                        Capsule()
                            .fill(segment.color)
                            .frame(width: usable * ratio(of: segment.cents))
                    }
                }
            }
        }
        .frame(height: Layout.compositionBar)
    }

    /// 单段占"三段之和"的比例。总和为 0 时返回 0（此时走空轨分支）
    private func ratio(of cents: Int) -> CGFloat {
        guard totalCents > 0, cents > 0 else { return 0 }
        return CGFloat(Double(cents) / Double(totalCents))
    }

    private var totalCents: Int {
        return pending + receivedUnclosed + closed
    }

    // MARK: - 图例

    private var legend: some View {
        HStack(alignment: .top, spacing: Spacing.cardGap) {
            ForEach(segments) { segment in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 6, height: 6)
                        Text(segment.title)
                            // 12pt：图例名是"标签"，不该比金额抢眼
                            .font(Typography.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Text(EarningsMoney.formatCents(segment.cents))
                        // 13pt：金额是这一段真正的读数
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        // 三段并排在 353pt 屏上每段只有 ~100pt，
                        // 「¥12,480.00」放不下时宁可缩 20% 也不换行（换行会顶掉 hero 的高度预算）
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 三段定义

    /// 一段：名称 + 金额 + 面色。
    ///
    /// 颜色全部取现有 token，不新造：
    /// · 待发 = `statusWarnFill`（琥珀**面**）—— 与改版前三态里"待发"用的黄色同族；
    /// · 已到账未结 = `lime`（品牌**面**）—— "钱在路上"，最该被看见的一段；
    /// · 已结清 = `statusOk`（中性灰）—— 完成即安静，不跟前面两段抢注意力。
    private struct Segment: Identifiable {
        let title: String
        let cents: Int
        let color: Color
        var id: String { title }
    }

    private var segments: [Segment] {
        return [
            Segment(title: "待发", cents: pending, color: Theme.statusWarnFill),
            Segment(title: "未结", cents: receivedUnclosed, color: Theme.lime),
            Segment(title: "已结", cents: closed, color: Theme.statusOk),
        ]
    }

    // MARK: - 无障碍

    /// 堆叠条本身对读屏是无意义的色块，所以把三段读成一句话
    private var accessibilityText: String {
        let parts = segments.map { $0.title + " " + EarningsMoney.formatCents($0.cents) }
        return parts.joined(separator: "，")
    }
}
