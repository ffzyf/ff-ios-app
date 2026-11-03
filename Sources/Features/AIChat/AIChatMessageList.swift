import SwiftUI

/// 聊天气泡列表。
///
/// 分工：本视图**只画**，不碰状态机 —— 发消息 / 停止 / 重试都在 `AIChatStore` 里。
/// 所以它只收"值 + 两个回调"，没有自己的 `@State`（除了光标那一点视觉状态），
/// 也就没有"界面状态与 Store 状态打架"的可能。
///
/// 版式（照效果图第 2 屏）：
/// · 用户消息**靠右**、浅色气泡（`Theme.lime` 12% 面 + 18% 描边）；
/// · 助手消息**靠左**、无边框、只有极轻底色（`Theme.surfaceTint1`），正文可选中复制；
/// · 每条上面一行 11pt 的说话人（用户是「你」，助手是模型名）；
/// · 空态 = 一句引导 + 四个建议问题，点了直接发。
struct AIChatMessageList: View {

    /// 当前会话的全部消息（旧 → 新，与屏幕顺序一致）
    let messages: [AIChatMessage]

    /// 模型清单：只用来把 `deepseek-chat` 翻译成「DeepSeek」（见 `AIModelNaming`）
    let models: [AIModelOption]

    /// 最后一条是不是失败了（`AIChatStore.canRetry`）。为真时列表底部出现「重试」
    let canRetry: Bool

    /// 正在拉某条历史会话（`AIChatStore.isLoadingConversation`）。
    ///
    /// 为真且还没有消息时画骨架，而不是先闪一下"今天想聊点什么？"——
    /// 那个空态与"这条对话是空的"长得一模一样，用户会以为点错了或者历史被清空了。
    /// 有默认值：不加这个参数的老调用点仍然编得过（本页只有一个调用点）。
    var isLoading: Bool = false

    /// 空态的建议问题
    let suggestions: [String]

    let onSuggestion: (String) -> Void
    let onRetry: () -> Void

    /// 到底部的锚点。用常量而不是 UUID：每次重算都一样，`scrollTo` 才找得到它。
    private static let bottomAnchor: String = "ai-chat-bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    content

                    // 1pt 锚点：流式输出时最后一条消息**还在长高**，滚到"最后一条"
                    // 会差半行；滚到一个永远在最底的小方块才贴得住。
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                .padding(.horizontal, Spacing.page)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            // 往下拖列表时顺手收键盘：聊天页 90% 的时间在"看"，键盘挡掉半屏很烦
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            // 流式：只有最后一条的正文在变，长度是最便宜的观察量
            .onChange(of: tailTextLength) { _, _ in
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    // MARK: - 内容分发

    @ViewBuilder
    private var content: some View {
        if messages.isEmpty {
            // 先判"在拉"再判"空"：`load(id:)` 会把 messages 立刻清空后才发请求，
            // 这两三帧里如果走空态，屏幕上就是"一条空对话 + 四个建议问题"闪一下
            if isLoading {
                loadingState
            } else {
                emptyState
            }
        } else {
            ForEach(messages) { message in
                AIChatBubble(
                    message: message,
                    modelLabel: AIModelNaming.label(message.model, models: models)
                )
                .id(message.id)
            }

            if canRetry {
                retryRow
            }
        }
    }

    /// 最后一条的正文长度（流式时每来一段 delta 就变一次）
    private var tailTextLength: Int {
        return messages.last?.text.count ?? 0
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(Motion.press) {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        } else {
            // 流式每一次 delta 都不要动画：那是每秒十几次的调用，
            // 给每次滚动加一条 spring 只会让画面像在水里。
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    // MARK: - 骨架（拉历史会话的几百毫秒）

    /// 两问两答的骨架，形状照着真实气泡（左窄右宽）——收缩时不跳。
    /// 圆角走 `Radius.smallCard`（14），比气泡的 18 略方：骨架不该比真内容更"讲究"。
    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 16) {
            SkeletonBlock(width: 96, height: 11)

            HStack(spacing: 0) {
                Spacer(minLength: 44)
                SkeletonBlock(width: 180, height: 40, cornerRadius: Radius.smallCard)
            }

            SkeletonBlock(width: 84, height: 11)
            SkeletonBlock(height: 76, cornerRadius: Radius.smallCard)

            SkeletonBlock(width: 84, height: 11)
            SkeletonBlock(height: 52, cornerRadius: Radius.smallCard)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("今天想聊点什么？")
                    .font(Typography.titleM)
                    .foregroundStyle(Theme.textPrimary)
                Text("天气、红石场次、今天的简报都能问，回答里会带上当天的数据。")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Spacing.gridUnit) {
                ForEach(suggestions, id: \.self) { item in
                    suggestionChip(item)
                }
            }
        }
        // 顶部给一点距离：空态贴在顶栏下面会显得"没加载出来"
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 建议问题：整行可点，右侧一个小箭头。
    ///
    /// 用 `glassStatic`（不采样背景的廉价玻璃）而不是真玻璃：这里是 4 张并列的小卡，
    /// 真玻璃逐张采样背景在低端机上是可见的开销，而它们本来就不是"浮在内容之上"的元素。
    private func suggestionChip(_ text: String) -> some View {
        Button {
            Haptics.light()
            onSuggestion(text)
        } label: {
            HStack(spacing: 8) {
                Text(text)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.limeInk)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .glassStatic(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 重试

    /// 失败 / 被停止之后的那一个按钮。
    ///
    /// 灰字（"这条没写完…"）在气泡下面由 `AIChatBubble` 负责 —— 它属于**那条消息**；
    /// 这里只放动作，因为重试作用于"最后一轮"，不是任意一条。
    private var retryRow: some View {
        Button {
            Haptics.light()
            onRetry()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                Text("重试")
                    .font(Typography.footnoteMedium)
            }
            .foregroundStyle(Theme.limeInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassSurface(.floating, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .padding(.leading, 4)
    }
}

// MARK: - 单条消息

/// 一条消息。四件事：说话人、气泡、流式光标、错误那一行灰字。
private struct AIChatBubble: View {
    let message: AIChatMessage
    /// 助手消息的说话人（用户消息不用它）
    let modelLabel: String?

    var body: some View {
        VStack(alignment: stackAlignment, spacing: 5) {
            speaker
            row

            // 失败 / 被停止之后的一行灰字。放在气泡**下面**（而不是里面）：
            // 它说的是"这条为什么没长完整"，不是这条消息的内容。
            if let errorText = visibleErrorText {
                Text(errorText)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    // MARK: - 派生

    private var isUser: Bool {
        return message.role == .user
    }

    private var stackAlignment: HorizontalAlignment {
        return isUser ? .trailing : .leading
    }

    private var frameAlignment: Alignment {
        return isUser ? .trailing : .leading
    }

    /// 流式期间不显示上一轮的错误（重试 / 重发时 status 会先回到 `.streaming`，
    /// 而 errorText 要等收尾才清，中间那一瞬不该闪一行旧错误）
    private var visibleErrorText: String? {
        guard message.status != .streaming else { return nil }
        guard let text = message.errorText else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - 说话人

    @ViewBuilder
    private var speaker: some View {
        if isUser {
            Text("你")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
        } else if let modelLabel = modelLabel {
            // 只写模型名，不写"已用天气数据"之类的断言 —— 那件事服务端没告诉我们，
            // 界面上写出来就是在替它背书。
            Text(modelLabel)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - 气泡

    @ViewBuilder
    private var row: some View {
        if isUser {
            HStack(spacing: 0) {
                // 至少留 44：用户的短消息不该贴到屏幕另一头，
                // 那条留白正是"这是我说的话"最直接的形状
                Spacer(minLength: 44)
                userBubble
            }
        } else {
            HStack(spacing: 0) {
                assistantBubble
                Spacer(minLength: 20)
            }
        }
    }

    /// 用户气泡：浅色（青柠 12% 面），不是深色块。
    ///
    /// 效果图里用户气泡是深墨色的；这里改成浅色是这条沉浸式页的整体选择：
    /// 整页只有"白纸 + 一点天色 + 一点青柠"，一块深墨会把页面重心拽到用户自己身上，
    /// 而这页真正要读的是助手的回答。深色留给"实心 CTA"（发送键）那一档。
    private var userBubble: some View {
        Text(message.text)
            .font(Typography.bodySmall)
            .foregroundStyle(Theme.textPrimary)
            .lineSpacing(Typography.lineSpacing(fontSize: 16, multiple: 1.6))
            .multilineTextAlignment(.leading)
            // 长按可以选中复制（用户经常要把一段建议发到别处）
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.lime.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.lime.opacity(0.18), lineWidth: 1)
            }
    }

    /// 助手气泡：无边框 + 极轻底色。流式时正文尾部挂一个光标。
    private var assistantBubble: some View {
        HStack(alignment: .bottom, spacing: 4) {
            assistantText
            if message.status == .streaming {
                StreamingCursor()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surfaceTint1)
        }
    }

    @ViewBuilder
    private var assistantText: some View {
        if message.text.isEmpty && message.status == .streaming {
            // 空正文 + 流式 = 还在等首个 token。给一句"正在想…"比一个孤立的光标好懂
            Text("正在想…")
                .font(Typography.bodySmall)
                .foregroundStyle(Theme.textTertiary)
        } else if message.text.isEmpty && message.status == .cancelled {
            // 一个字都还没收到就被停下（用户点停止 / 切会话）：不留一个空方块。
            // 这里**不能**沿用"正在想…"——那个状态已经结束了，继续显示就是在撒谎。
            Text("已停止。")
                .font(Typography.bodySmall)
                .foregroundStyle(Theme.textTertiary)
        } else {
            Text(message.text)
                .font(Typography.bodySmall)
                .foregroundStyle(Theme.textBody)
                .lineSpacing(Typography.lineSpacing(fontSize: 16, multiple: 1.7))
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 流式光标

/// 流式光标：两态切换（不透明 ↔ 淡），只动 `opacity`。
///
/// 为什么不用 `TimelineView` / `phaseAnimator`：光标**不许带动任何布局**。
/// 气泡宽度每来一段 delta 都要重算一次，光标再去推着改尺寸就是每秒十几次重排。
/// 一个 `.animation(_:value:)` 把 `opacity` 在 1 与 0.15 之间来回就够"眨"了。
///
/// `reduceMotion` 打开时它**不眨**、保持常亮 —— 前庭敏感的用户要的仍然是
/// "这里还在写"这个信息，闪烁是装饰，不是语义。
private struct StreamingCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible: Bool = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Theme.limeInk)
            .frame(width: 8, height: 15)
            .opacity(visible ? 1.0 : 0.15)
            // 传 `Animation?` 而不是在调用处写三元 —— `nil` 放在三元里让编译器去猜
            // Optional 的类型，是最容易报"type of expression is ambiguous"的写法之一
            .animation(blinkAnimation, value: visible)
            .onAppear {
                guard !reduceMotion else { return }
                // 只改一次值，`repeatForever` 自己去循环（不需要 Timer、不需要 onReceive）
                visible = false
            }
            .accessibilityHidden(true)
    }

    /// 0.5 秒一次来回：与系统键盘的光标节奏一致，不会读成"卡了一下"。
    /// `reduceMotion` 时返回 nil（= 不挂动画，光标保持常亮）
    private var blinkAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)
    }
}

// MARK: - 模型名

/// 服务端模型 id → 界面上的人话。
///
/// 三处说的是同一件事实（这段字是谁写的）：聊天气泡上面那行、历史列表的副标题、
/// 首页穿搭卡的脚注。三份 `switch` 迟早会有一份漏掉新增的模型，所以只留一份。
/// 本批不许新建文件，因此挂在第一个需要它的文件末尾。
///
/// 查询顺序：**先查服务端清单**（它换了 id、加了模型都不用改代码）→ 已知 id 兜底 →
/// 原样返回 id。宁可露出 `deepseek-chat`，也不要猜一个错的名字。
enum AIModelNaming {

    static func label(_ raw: String?, models: [AIModelOption]) -> String? {
        guard let raw = raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let match = models.first(where: { $0.id == trimmed }) {
            let label = match.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty { return label }
        }

        switch trimmed {
        case "auto":
            return "自动选择"
        case "deepseek-chat", "deepseek-reasoner":
            return "DeepSeek"
        case "hunyuan-standard", "hunyuan-turbo", "hunyuan-pro":
            return "腾讯混元"
        default:
            return trimmed
        }
    }
}
