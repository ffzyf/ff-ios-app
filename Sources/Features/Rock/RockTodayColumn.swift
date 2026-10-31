import SwiftUI

/// 红石页宽档副列的「今日场次」（2026-10-31 iPad 版式重做新增）。
///
/// **为什么需要这一组**（设计文档 §4.2）：副列原来只有「下一场 68 + 分布 92 + 规律 88 ≈ 312」，
/// 而主列（分区标题 40 + 月历卡）有 430–480 —— 右下角常年空出一块 146×368 的洞。
/// 修法不是往副列"塞东西凑高"，而是补一组**今天真实存在、但只在弹层里能看到**的数据：
/// 今天每个场次的时刻 + 地点 + 倍率。数据早就有了（`RedstoneDay.times` / `.map` / `.rate`），
/// 侧栏常驻 = 少一次点击（原来要先在月历上点今天那一格，才会弹出同样的清单）。
///
/// 三条约束：
/// 1. 纯展示组件：不读 Store、不发请求，`day` 由调用方挑好传进来（与 `RedstoneMonthGrid` 同款约定）；
/// 2. **取不到就整块不渲染**（`day == nil` 或 `times` 为空）—— 宁可让副列短一截、由 `Spacer` 把
///    「规律」压到底，也不画一张"今天没有场次"的空卡（那就又变回"塞东西凑高"了）；
/// 3. 每行 44pt（= iOS 最小点击目标，也是 3×44 + 标题 40 = 172 的来历），
///    与「更多」的列表行同一档 —— 行高不是随手取的数，是全站"一行有多高"的唯一答案。
struct RockTodayColumn: View {

    /// 今天那一条。`nil` = 这个月还没加载 / 今天没有排期 → 整块不渲染
    private let day: RedstoneDay?

    /// 单行高度（44 = 点击目标下限；三行 + 标题恰好 172，与 hero 侧栏的 172 同数）
    private let rowHeight: CGFloat = 44

    /// 显式 init：只有一个入参也要写，保持与其它纯展示组件（`RedstoneMonthGrid` /
    /// `NextEventBar`）一致的构造形态 —— 以后加私有常量时不用再回来补。
    init(day: RedstoneDay?) {
        self.day = day
    }

    var body: some View {
        if let day, day.times.isEmpty == false {
            // `SectionHeader` 自带 12pt 下距，所以外层用 `spacing: 0` 就是"标题 + 12 + 卡"
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "今日场次")
                GlassCard(level: .card) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(day.times.enumerated()), id: \.offset) { pair in
                            row(time: pair.element, day: day)
                            // 分割线只画在行与行之间：末行下面再画一条就是"卡里多一道杠"
                            if pair.offset < day.times.count - 1 {
                                Rectangle()
                                    .fill(Theme.divider)
                                    .frame(height: 1)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.cardPadding)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - 一行

    /// 一行 = 时刻 + 地点 + 倍率。
    ///
    /// 地点用 `day.map` 的**全名**（`霞谷·圆梦村`）而不是月历格子里的短名（`圆梦村`）：
    /// 月历一格只有 88pt 宽、必须缩，而这一栏有 344pt，没有任何理由再裁一次地名。
    /// 全名也让「霞谷的 11:08」和「霞谷的 17:08」在同一栏里能一眼分开。
    private func row(time: String, day: RedstoneDay) -> some View {
        HStack(spacing: 10) {
            Text(time)
                .font(Typography.footnoteMedium)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)

            Text(day.map)
                .font(Typography.footnote)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // 倍率取不到（`map == 待确认`）时 `RateBadge` 自己什么都不画 —— 不写「—」
            RateBadge(rate: day.rate)
        }
        .frame(minHeight: rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(day.map + "，" + time + (RedstoneRules.rateText(day.rate).map { "，" + $0 } ?? ""))
    }
}
