import SwiftUI

/// 流水列表的一行：左边分类 + 备注，右边带符号的金额，支持左滑删除。
///
/// 为什么手写左滑而不是 `.swipeActions`：本页是 `ScrollView + GlassCard` 结构（与全工程一致），
/// 而 `.swipeActions` 只在 `List` 里生效 —— 在 `ScrollView` 里塞 `List` 会导致滚动嵌套打架。
/// 所以这里用 `DragGesture` 自己实现：
/// - 拖拽只横向生效（`abs(dx) > abs(dy)` 才锁存），竖向手势原样交给外层滚动；
/// - 删除按钮**滑入**而不是垫在行下面 —— 行背景是透的玻璃，垫在下面的按钮在深色下会透出来；
/// - 一次只开一行：开合状态通过 `Binding` 提到 `LedgerSection`，点开第二行时第一行自动收起。
struct LedgerRow: View {

    /// 这一笔账
    let entry: LedgerEntry
    /// 是否处于「已滑开」状态（由父视图持有，保证同时只有一行是开的）
    @Binding var isOpen: Bool
    /// 点整行：进入编辑
    let onTap: () -> Void
    /// 点删除
    let onDelete: () -> Void

    /// 删除按钮占的宽度
    private static let actionWidth: CGFloat = 68
    /// 拖拽过程中的临时位移（手势结束即归零，真正的状态在 `isOpen`）
    @State private var dragOffset: CGFloat = 0
    /// 本次手势是否已判定为横向（一次手势只判定一次，避免中途抖动改变意图）
    @State private var isHorizontalDrag: Bool = false

    var body: some View {
        ZStack(alignment: .trailing) {
            content
                .offset(x: offset)
                .simultaneousGesture(dragGesture)

            deleteButton
                .frame(width: Self.actionWidth)
                .offset(x: Self.actionWidth + offset)
        }
        .clipped()
    }

    // MARK: - 行内容

    private var content: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.category)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if entry.note.isEmpty == false {
                    Text(entry.note)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(LedgerMoney.formatSigned(cents: entry.signedCents))
                .font(LedgerType.rowValue)
                .foregroundStyle(LedgerInk.signed(entry.signedCents))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if isOpen {
                // 已经滑开时，点一下先收回去（与系统列表行为一致），不要直接跳进编辑
                withAnimation(Motion.press) { isOpen = false }
            } else {
                onTap()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - 删除按钮

    private var deleteButton: some View {
        Button {
            Haptics.light()
            withAnimation(Motion.press) { isOpen = false }
            onDelete()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.badgeRedInk)
                .frame(width: 52, height: 30)
                .background { Capsule().fill(Theme.badgeRed) }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("删除这笔")
    }

    // MARK: - 手势

    /// 当前位移：`isOpen` 给出基准，加上拖拽的临时位移，夹在 `[-actionWidth, 0]`
    private var offset: CGFloat {
        let base: CGFloat = isOpen ? -Self.actionWidth : 0
        return min(0, max(-Self.actionWidth, base + dragOffset))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if !isHorizontalDrag {
                    // 竖向手势不接管：外层 ScrollView 该滚就滚
                    guard abs(dx) > abs(dy) else { return }
                    isHorizontalDrag = true
                }
                let base: CGFloat = isOpen ? -Self.actionWidth : 0
                dragOffset = min(0, max(-Self.actionWidth, base + dx))
            }
            .onEnded { value in
                let wasHorizontal = isHorizontalDrag
                isHorizontalDrag = false
                guard wasHorizontal else {
                    dragOffset = 0
                    return
                }
                let base: CGFloat = isOpen ? -Self.actionWidth : 0
                let settled = base + value.translation.width
                let shouldOpen = settled < -Self.actionWidth / 2
                withAnimation(Motion.press) {
                    isOpen = shouldOpen
                    dragOffset = 0
                }
            }
    }

    // MARK: - 无障碍

    private var accessibilityText: String {
        var parts: [String] = [entry.kind.title, entry.category]
        parts.append(LedgerMoney.formatSigned(cents: entry.signedCents))
        if entry.note.isEmpty == false {
            parts.append(entry.note)
        }
        return parts.joined(separator: "，")
    }
}
