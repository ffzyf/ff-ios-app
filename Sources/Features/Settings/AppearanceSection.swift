import SwiftUI

/// 「外观」三选一（PRD §3.6 / 验收第 1 条：切换后**立即整屏生效、无需重启**）。
///
/// 为什么用 `@ObservedObject` 而不是 `@EnvironmentObject`：
/// 本组件是从概览页以 `sheet` 弹出的设置页里的一个分组，V2 的模态呈现已经出现过
/// "环境对象没继承"的历史问题（`RootView` 里对 `fullScreenCover` 显式再注入了一遍 `model`）。
/// 直接观察单例可以彻底绕开这条依赖：改值 → `AppearanceStore` 发通知 →
/// 设置页这一行立刻重画、`FFWangApp` 的 `preferredColorScheme` 同步更新。
///
/// 图标不是业务语义（不改 `AppearanceMode` 的定义），所以映射留在这里：
/// 设计系统只管长得对，Domain 只管值域。
struct AppearanceSection: View {
    @ObservedObject private var store = AppearanceStore.shared

    var body: some View {
        VStack(spacing: 8) {
            ForEach(AppearanceMode.allCases) { mode in
                row(mode)
            }
            Text("选「跟随系统」时，iOS 深浅色自动切换时 App 也会跟着变。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
                .padding(.vertical, 6)

            themePicker
        }
    }

    // MARK: - 配色

    /// 五套配色：色板 + 名称。
    ///
    /// 为什么不做成"整行单选"（跟上面深浅三档一样）：配色是**看**出来的，不是读出来的 ——
    /// 一列文字里出现五个"暮紫/暖砂"，不如直接给五枚色点。点一下即换，选中项加一圈描边。
    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("配色")
                .font(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)

            HStack(spacing: 6) {
                ForEach(Theme.Palette.all) { palette in
                    swatch(palette)
                }
            }
            .padding(.horizontal, 2)

            Text("每套配色都自带深色版本，和上面的深浅设置任意组合。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)
        }
    }

    private func swatch(_ palette: Theme.Palette) -> some View {
        let isSelected = (store.themeId == palette.id)
        return Button {
            Haptics.light()
            // 换肤是整屏变化，跟玻璃出现同一条缓动，避免硬切像闪屏
            withAnimation(Motion.glassIn) {
                store.selectTheme(palette.id)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(palette.swatch)
                        .frame(width: 30, height: 30)
                    if isSelected {
                        Circle()
                            .strokeBorder(Theme.textPrimary.opacity(0.9), lineWidth: 2)
                            .frame(width: 38, height: 38)
                    }
                }
                .frame(width: 38, height: 38)

                Text(palette.name)
                    .font(Typography.captionXS)
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(palette.name)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private func row(_ mode: AppearanceMode) -> some View {
        let isSelected = (store.mode == mode)
        return Button(action: {
            Haptics.light()
            // 用与玻璃出现同一条缓动：切换是"整屏明暗变化"，硬切会像闪屏
            withAnimation(Motion.glassIn) {
                store.mode = mode
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "inset.filled.circle" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.limeInk : Theme.textTertiary)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(Typography.callout)
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    Text(mode.detail)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)

                // 右侧图标只作提示，不承载状态（状态由左侧单选圈表达，避免两处同时"亮"）
                Image(systemName: icon(for: mode))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Spacing.cardPadding)
            .padding(.vertical, 10)
            .frame(minHeight: Spacing.listItemMinHeight, alignment: .leading)
            .background {
                // 选中项的青柠微底：`opacity` 作用在 token 外层，不破坏动态性（PRD §3.4 第 1 条的允许形式）
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                        .fill(Theme.lime.opacity(0.10))
                }
            }
            .contentShape(Rectangle())
            .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        // 单选组的选中态必须能被读屏读出来（否则三项听上去一模一样）。
        // 两次 addTraits 是并集叠加，比写数组字面量更不依赖 AccessibilityTraits 的构造器形态。
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private func icon(for mode: AppearanceMode) -> String {
        switch mode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}
