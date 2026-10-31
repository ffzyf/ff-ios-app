import SwiftUI

/// 分区标题（设计报告 §5 新组件）。
///
/// 存在理由：改版前全工程 0 处 22pt 分区标题（`Typography.titleL` 只在次级页出现），
/// 一页的字阶只剩 34 / 20 / 17 / 13 / 11 —— 眼睛扫下去找不到"这是新的一组"。
/// 所以每一组都必须有一个比正文大 ≥5pt 的标题，右侧可带一个动作或一个插槽。
///
/// 两种构造：
/// · `SectionHeader(title:actionTitle:action:)` —— 纯标题（首页三组都是这个形态）；
/// · `SectionHeader(title:) { 插槽 }` —— 右侧塞任意控件（红石页的翻月器要塞进来，省掉一整行 40pt）。
///
/// 12pt 下距**由本组件自带**：调用方写成 `VStack(spacing: 0) { Header; 内容 }` 即可，
/// 不必每处再记得加间距 —— 记不住的东西迟早会漏一个页面。
///
/// 插槽用 `AnyView?` 而不是泛型 `Slot`：一个分区标题最多塞一个翻月器、一次实例化，
/// 类型擦除的代价可以忽略；换来的是最常见的 `SectionHeader(title:)` 不需要任何泛型推断，
/// 少一类只有真机编译才会暴露的推断失败。
struct SectionHeader: View {
    private let title: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let slot: AnyView?

    init(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.slot = nil
    }

    init<Slot: View>(
        title: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder slot: () -> Slot
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.slot = AnyView(slot())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(Typography.titleL)
                // ≥22pt 一律加 -0.4 字距（`Typography.trackingLarge`），与页面其它大标题同一条规则
                .tracking(Typography.trackingLarge)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let slot {
                slot
            }

            if let actionTitle, let action {
                Button {
                    Haptics.light()
                    action()
                } label: {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                            // 17pt regular：动作比标题小 5pt，才不会被读成第二个标题
                            .font(Typography.body)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    // 文字用 limeInk 而不是 lime：lime 只做面（PRD §3.2 面/字分离）
                    .foregroundStyle(Theme.limeInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title + "，" + actionTitle)
            }
        }
        .padding(.bottom, Spacing.sectionTitleGap)
    }
}
