import SwiftUI

/// 底部输入框：多行自适应（1…5 行）+ 发送 / 停止。
///
/// 三件事刻意交给 `AIChatStore` 而不是自己拿 `@State`：
/// · `draft` 由 Store 持有 —— 这样"发送成功即清空""切会话即清空"只有一个入口
///   （两处各存一份，就会出现"切了会话，输入框里还挂着上一句的半截问题"）；
/// · `canSend` / `isStreaming` 是 Store 的状态机投影，界面不自己推；
/// · 停止是**同步**方法：按下去要立刻看到按钮变回"发送"，不能等一个 `await`。
///
/// 高度：`lineLimit(1...5)` + `minHeight 44`。1 行时与圆形发送键等高（44），
/// 5 行之后内部滚动 —— 再多就会把消息区挤掉半屏，而聊天页的主角是消息。
struct AIChatComposer: View {

    @ObservedObject private var chat = AIChatStore.shared

    /// 键盘焦点：切会话 / 发送完成后不强抢焦点，只在用户点了输入框时才亮光标。
    /// 不用 `@FocusState` 自动聚焦的理由：一进 AI Tab 就弹键盘，会把空态那四个
    /// 建议问题压掉一半，而用户多半是想先看看能问什么。
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            field
            sendButton
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, 6)
        // 底部 10：Tab 栏已经由 `RootView` 的 `safeAreaInset` 让开，
        // 这里只留"输入框与栏之间"的那一点呼吸
        .padding(.bottom, 10)
    }

    // MARK: - 输入框

    private var field: some View {
        TextField("", text: $chat.draft, axis: .vertical)
            .font(Typography.bodySmall)
            .foregroundStyle(Theme.textPrimary)
            // 光标色跟着品牌走（默认是系统蓝，会在青柠页面里很跳）
            .tint(Theme.limeInk)
            .lineLimit(1...5)
            .focused($focused)
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .frame(minHeight: 44, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.glassStaticFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                placeholder
            }
    }

    /// 占位文案自己画。
    ///
    /// 不用 `TextField("问点什么…")` 的 prompt：`axis: .vertical` 下 prompt 与自定义内距
    /// （15/11）对不齐，多行时还会跟着换行漂。这里与正文用同一个 `chat.draft.isEmpty`
    /// 判断，两处状态只有一个来源。
    @ViewBuilder
    private var placeholder: some View {
        if chat.draft.isEmpty {
            Text("问点什么…")
                .font(Typography.bodySmall)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 15)
                // 不能吃点击：它盖在输入框上，否则点"占位文字"不会聚焦
                .allowsHitTesting(false)
        }
    }

    // MARK: - 发送 / 停止

    private var sendButton: some View {
        Button {
            handleTap()
        } label: {
            Image(systemName: chat.isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
                .background {
                    Circle().fill(backgroundColor)
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        // 没内容、也不在流式 → 整个按钮不可点（而不是变灰可点）
        .disabled(!chat.isStreaming && !chat.canSend)
        .accessibilityLabel(chat.isStreaming ? "停止生成" : "发送")
    }

    /// 三态：流式中（中性）/ 可发送（青柠实心）/ 没内容（中性淡）
    private var backgroundColor: Color {
        if chat.isStreaming { return Theme.surfaceTint4 }
        return chat.canSend ? Theme.lime : Theme.surfaceTint3
    }

    private var iconColor: Color {
        if chat.isStreaming { return Theme.textSecondary }
        return chat.canSend ? Theme.onLime : Theme.textTertiary
    }

    private func handleTap() {
        if chat.isStreaming {
            Haptics.light()
            // 同步：按下去立刻变回"发送"（`stop()` 自己保留已收到的半截文本）
            chat.stop()
            return
        }

        guard chat.canSend else { return }
        Haptics.light()

        // 先把内容取出来：`send(_:)` 内部会把 `draft` 清空，
        // 而 `Task` 真正开始执行时读到的可能已经是空的
        let text = chat.draft
        Task { await chat.send(text) }
    }
}
