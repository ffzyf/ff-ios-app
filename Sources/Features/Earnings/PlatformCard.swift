import SwiftUI

/// 平台小卡（A+B 混合方案的 B 面：**两列概览**）。
///
/// 为什么是"两列小卡"而不是上一轮的横滑（C 方案）：
/// 横滑一次只能看到 1.5 张卡，用户永远不知道右边还有几个平台；两列网格一屏放得下 4 张，
/// 「我总共有几个平台、各自多大」是一眼的事。平台再多就自然往下排（`LazyVGrid`），不做横滑。
///
/// 卡片只承担一个职责：**回答"谁占多少"**。它刻意不列活动 ——
/// "这个平台具体是哪些活动"是另一个问题，点进来交给 `PlatformDetailSheet`（A 面）。
///
/// ## 内容四行（高度固定 96，与「本月」三张 tile 同一档）
/// 1. ● 平台名（8pt 品牌色圆点 + 13pt 名）—— **圆点只是线索，识别靠的是文字**：
///    抖音 / 快手 / 小红书三张卡都是红，只看颜色会糊成一片；
/// 2. 金额 20pt `titleM`（收入用中性主色，不用绿 —— 中国用户的收入习惯色是红/中性）；
/// 3. 「N 个活动 · 待发 ¥X」11pt 次级色；
/// 4. 3pt 细条：该平台金额 / 所有平台金额之和，品牌色填充。
///
/// 金额与"待发"文案**只用 `EarningsPlatformBreakdown.amount`**，不在卡片里做任何二次汇总
/// （口径只留在服务端那一处；卡片一旦自己加总，App 与网页端的数就会开始漂）。
struct PlatformCard: View {

    /// 卡最小高度：窄档 96（今天）、宽档 120（与 tile 同档 —— 收益页里"并排小卡"只有这一个高度）。
    /// 用 `minHeight` 而不是 `height`：金额极大时卡可以长高，不裁字。
    @Environment(\.layoutMetrics) private var metrics

    /// 该平台的金额占比单项（来自总览 `summary.platformBreakdown`）
    let item: EarningsPlatformBreakdown
    /// 所有平台金额之和 —— 细条的分母。0 时整条不画（新账号没有任何金额）
    let totalAmount: Int
    /// 该平台下的活动数（由调用方按 `store.activities` 数好传进来，卡片自己不认识 `EarningsActivity`）
    let activityCount: Int
    /// 点整卡 → 打开该平台的详情弹页
    let action: () -> Void

    /// 本卡的几何常量。
    ///
    /// 收进嵌套 `Metrics` 而不是散成三个 `private let`：`private` 存储属性会把 memberwise init
    /// 降级成 `private`，跨文件就构造不出来（`EarningsRecordSheet` 踩过这个坑）；
    /// 嵌套类型不参与 memberwise init，所以这样写既保留了默认值，也保留了 internal 的构造入口。
    ///
    /// 高度**不在**这里：它要读 `layoutMetrics`（96 窄档 / 120 宽档），静态类型读不到环境，
    /// 所以走 `metrics.cardHeight(.tile)`（与「本月」三张 tile 同一个调用，两处不会漂）。
    private enum Metrics {
        /// 占比细条厚度 3pt：只回答"谁更大"，不需要精确读数，所以比 hero 的构成条（10pt）细
        static let barHeight: CGFloat = 3
        /// 品牌色圆点直径
        static let dot: CGFloat = 8
    }

    /// 显式 init：`@Environment` 是 private 存储属性，会把自动生成的 memberwise init 降级成
    /// private，跨文件 `PlatformCard(item:totalAmount:activityCount:action:)` 就构造不了。
    /// 参数顺序保持原样（`action` 仍在最后），调用点的尾随闭包继续配到它身上。
    init(
        item: EarningsPlatformBreakdown,
        totalAmount: Int,
        activityCount: Int,
        action: @escaping () -> Void
    ) {
        self.item = item
        self.totalAmount = totalAmount
        self.activityCount = activityCount
        self.action = action
    }

    var body: some View {
        PressableGlassCard(cornerRadius: Radius.smallCard, action: action) {
            VStack(alignment: .leading, spacing: 6) {
                nameRow

                // 20pt：卡里唯一的读数。用 `titleM`（20 semibold）而不是新造一个 rounded token ——
                // 字阶表（`Typography`）本轮不动，20pt 只有这一档，`.monospacedDigit()` 补上数字对齐
                Text(EarningsMoney.formatCents(item.amount))
                    .font(Typography.titleM)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    // 两列时单卡内容宽约 150pt，「¥12,480.00」放不下就缩，绝不换行
                    .minimumScaleFactor(0.6)

                Text(subtitle)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // 把细条顶到卡底：四行内容天然比 96 矮，`Spacer` 吸收差额，
                // 于是所有卡的细条基线对齐（网格里参差的底线最显廉价）
                Spacer(minLength: 0)

                ratioBar
            }
            .padding(Spacing.smallCardPadding)
            .frame(minHeight: metrics.cardHeight(.tile), alignment: .topLeading)
        }
        // 只换 label，不加 `.accessibilityElement(children: .ignore)`：
        // 整卡本身是 `Button`（`PressableGlassCard` 里包的），读屏需要它保留"按钮"语义；
        // 把子元素忽略掉会连按钮特征一起丢掉，变成一段点了没反应的文字
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("查看该平台的活动明细")
        // 2×2 网格里一次只会歪"拖的那一张"，静止时全平，不会变成一堆歪纸（§3.3）
        .cardTilt(cornerRadius: Radius.smallCard)
    }

    // MARK: - 行 1：圆点 + 平台名

    private var nameRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.Platform.of(item.name))
                .frame(width: Metrics.dot, height: Metrics.dot)
            // 13pt：平台名是这一行的主语，且是三张红卡唯一可靠的区分线索 —— 不许被截断到只剩两个点
            Text(item.name)
                .font(Typography.footnoteMedium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    // MARK: - 行 3：活动数 · 待发

    /// 副标题。
    ///
    /// 「待发」两个字是**跟着 `EarningsPlatformBreakdown.amount` 来的**：该字段与网页端
    /// 平台占比条同源（`summary.platformBreakdown`，服务端按待发口径聚合）。
    /// 若哪天服务端改了这个口径，只需要改这一处文案 —— 金额本身一个字都不重算。
    private var subtitle: String {
        return "\(activityCount) 个活动 · 待发 " + EarningsMoney.formatCents(item.amount)
    }

    // MARK: - 行 4：占比细条

    private var ratioBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.glassFill)
                // 总和为 0（`fillWidth` 返回 0）时只留空轨，不画一段"假长度"
                if fillWidth(full: geo.size.width) > 0 {
                    Capsule()
                        .fill(Theme.Platform.of(item.name))
                        .frame(width: fillWidth(full: geo.size.width))
                }
            }
        }
        .frame(height: Metrics.barHeight)
    }

    /// 细条宽度：该平台金额 / 所有平台金额之和。
    ///
    /// 分母刻意用"各平台之和"而不是 `summary.total`：这条条回答的是"平台之间谁更大"，
    /// 属于平台内部的相对关系；用总额当分母会让所有平台加起来不足满宽（条缺一角，看着像画错了）。
    /// 最小 2pt：占比极小也要留一条可见的痕，否则用户会以为这个平台没数据。
    private func fillWidth(full: CGFloat) -> CGFloat {
        guard totalAmount > 0, item.amount > 0, full > 0 else { return 0 }
        let ratio = min(1.0, Double(item.amount) / Double(totalAmount))
        return max(2, full * CGFloat(ratio))
    }

    // MARK: - 无障碍

    /// 四行内容对读屏来说是一堆碎词，合成一句人话
    private var accessibilityText: String {
        let percent = percentText
        return item.name + "，待发 " + EarningsMoney.formatCents(item.amount)
            + "，" + "\(activityCount) 个活动" + "，占平台总额 " + percent
    }

    /// 百分比（取整）。同样从金额算，不读 `ratio` 字段 —— 口径只保留一处
    private var percentText: String {
        guard totalAmount > 0, item.amount > 0 else { return "0%" }
        let percent = Int((Double(item.amount) / Double(totalAmount) * 100).rounded())
        return "\(percent)%"
    }
}
