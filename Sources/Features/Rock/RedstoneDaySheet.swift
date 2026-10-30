import SwiftUI

/// 当日场次浮层（P04 的「—」行：点日历某天弹出）。
///
/// 为什么用固定高度的 `presentationDetents([.height(...)])` 而不是 `.medium` / `.large`：
/// 一天最多 3 场，内容高度是可算的。给一个刚好包住内容的高度，用户一眼看完、不用再把浮层往上拖；
/// 而 `.medium` 会留一半空白，看起来像"内容没加载完"。
///
/// 高度按「基础 + 待确认徽标 + 备注」三段算，最后夹在 220–520 之间：
/// 夹上下限是为了极端数据（备注 200 字）不至于把浮层顶到全屏 —— 超出的部分在浮层里滚动。
struct RedstoneDaySheet: View {
    let day: RedstoneDay

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                mapRow
                timeCapsules
                if !day.note.isEmpty {
                    noteBlock
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Formatters.dayTitleWithWeekday(dayKey: day.date))
                .font(Typography.titleM)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            if day.needsCheck {
                NeedsCheckBadge()
            }
            typeBadge
        }
    }

    /// 类型徽标：红石 / 黑石（颜色与日历格里的点一致，跨页面形成同一套语言）
    private var typeBadge: some View {
        let style = RockMarkStyle.of(day)
        return HStack(spacing: 4) {
            Circle()
                .fill(style.color)
                .frame(width: 6, height: 6)
            Text(style.label)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background { Capsule().fill(Theme.surfaceTint2) }
        .overlay { Capsule().strokeBorder(Theme.divider, lineWidth: 1) }
    }

    // MARK: - 地图 / 倍率

    private var mapRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "map")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.limeInk)
            Text(day.map)
                .font(Typography.bodySmall)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            RateBadge(rate: day.rate)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.smallCardPadding)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                .fill(Theme.surfaceTint1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        }
    }

    // MARK: - 三个时刻胶囊

    private var timeCapsules: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("落地时刻（北京时间）")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            if day.times.isEmpty {
                // 服务端 warning 里那种"有排期但缺时刻"的日子：明确说没有时刻，不画假胶囊
                Text("这天还没有场次时刻。")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                HStack(spacing: 8) {
                    ForEach(day.times, id: \.self) { time in
                        timeCapsule(time)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func timeCapsule(_ time: String) -> some View {
        Text(time)
            .font(Typography.versionValue)
            .foregroundStyle(Theme.textPrimary)
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background { Capsule().fill(Theme.surfaceTint3) }
            .overlay { Capsule().strokeBorder(Theme.glassStrokeTop, lineWidth: 1) }
    }

    // MARK: - 备注

    private var noteBlock: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(day.note)
                .font(Typography.footnote)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.5))
        }
    }

    // MARK: - 高度

    /// 基础 196：头部 + 地图行 + 时刻标题 + 胶囊 + 上下留白。
    /// 待确认徽标不额外加高（它和标题同一行），备注按两行算 58pt。
    private var detentHeight: CGFloat {
        var height: CGFloat = 196
        if day.times.isEmpty { height += 8 }
        if !day.note.isEmpty { height += 58 }
        return min(520, max(220, height))
    }
}
