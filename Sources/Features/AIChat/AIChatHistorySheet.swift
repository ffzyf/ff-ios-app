import SwiftUI

/// 历史对话半屏（顶栏「⋯」打开）。
///
/// **用系统 sheet + `.presentationDetents([.medium, .large])`，不自绘半屏。**
/// 自绘要自己接拖拽手势、自己处理"滚动到顶再下拉才收起"、自己画遮罩与圆角 ——
/// 而这一层没有任何系统做不到的诉求（一组列表 + 一个搜索框 + 一个新建按钮）。
/// 选一种做法就用到底，绝不做两套（两套的圆角、拖拽惯性、返回手势迟早会出现分歧）。
///
/// 数据全部来自两个单例（写法同 `MoreView` / `OverviewView`），所以这个 sheet
/// **没有任何入参**：少一层参数，就少一处"传错了也不报错"。
/// 删会话走 `AIChatStore.delete(id:)` —— 它自己转给列表 Store（唯一真相源），
/// 并在"删的正好是当前这条"时清空聊天页；这里不重复实现一遍 `DELETE`。
struct AIChatHistorySheet: View {

    @ObservedObject private var chat = AIChatStore.shared
    @ObservedObject private var list = AIConversationListStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField
            deleteFailureLine
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 与「关于」同款：不采样滚动光影的静态页背景（sheet 里没有滚动光影的生产者）
        .background {
            PageBackground(glow: false)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // 每次打开都刷一次：这个请求很便宜，而"刚聊完打开历史却没看到那条"是更难受的错
        .task {
            await list.load()
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("对话")
                .font(Typography.titleL)
                .tracking(Typography.trackingLarge)
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 8)

            // 「＋ 新对话」只清本地状态，不建服务端空壳（会话是第一轮 chat 末帧才建的，
            // 否则历史列表里会堆一串"打开过但没说话"的空行 —— 见 `newConversation()` 的注释）
            CapsuleGlassButton(title: "新对话", icon: "plus") {
                startNewConversation()
            }
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    // MARK: - 搜索

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            // 绑定 Store 的 `query`（不是本地 `@State`）：过滤逻辑与分组都在 Store 里，
            // 界面只负责把用户打的字放进去
            TextField("搜索对话", text: $list.query)
                .font(Typography.footnote)
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.limeInk)
                .submitLabel(.search)

            if !list.query.isEmpty {
                Button {
                    list.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surfaceTint2)
        }
        .padding(.horizontal, Spacing.page)
        .padding(.bottom, 10)
    }

    // MARK: - 错误（删除失败 / 刷新失败但手里还有数据）

    @ViewBuilder
    private var deleteFailureLine: some View {
        if !list.isEmpty, let error = list.lastError {
            Text(error.userMessage)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, 6)
        }
    }

    // MARK: - 内容分发

    @ViewBuilder
    private var content: some View {
        if list.isEmpty {
            emptyContent
        } else if list.visible.isEmpty {
            // 「搜不到」与「还没聊过」是两种空态，文案必须分开：
            // 混用会让用户以为自己把历史清空了
            EmptyStateView(
                icon: "magnifyingglass",
                title: "没搜到",
                message: "换个词试试，或者新建一条对话。"
            )
        } else {
            conversationList
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if list.isLoading {
            loadingRows
        } else if let error = list.lastError {
            ErrorStateView(
                icon: "wifi.slash",
                title: "历史没拿到",
                message: error.userMessage,
                onRetry: reload
            )
        } else {
            EmptyStateView(
                icon: "bubble.left.and.bubble.right",
                title: "还没有对话",
                message: "问一句试试，聊过的都会留在这里。"
            )
        }
    }

    /// 骨架：与真实行同高（7pt 圆点 + 两行字），收起时不跳
    private var loadingRows: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 10) {
                    SkeletonBlock(width: 7, height: 7, cornerRadius: 3.5)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(height: 14)
                        SkeletonBlock(width: 180, height: 11)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, 8)
    }

    /// 按「今天 / 更早」分组。分组本身是 Store 算好的（`AIConversationGroup`），
    /// 这里只负责画 —— 分组规则一旦写进 View，`body` 里就会长出 `if` 和 `let`。
    private var conversationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(list.grouped) { group in
                    Text(group.title)
                        .font(Typography.eyebrow)
                        .tracking(Typography.trackingEyebrow)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 6)

                    ForEach(group.items) { conversation in
                        row(for: conversation, isToday: group.id == "today")
                    }
                }
            }
            .padding(.horizontal, Spacing.cardPadding)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - 一行

    /// 一行 = 标题 + 预览（含模型与条数）+ 右侧时间；当前这条左侧有绿点 + 淡青柠底。
    ///
    /// 删除用**长按（contextMenu）**而不是左滑：这一层不是 `List`，
    /// 自绘左滑要自己接 `DragGesture` 并处理与纵向滚动的冲突，
    /// 而长按菜单是系统自带的破坏性操作入口（带红色、带 VoiceOver 语义），零风险。
    private func row(for conversation: AIConversation, isToday: Bool) -> some View {
        Button {
            Haptics.light()
            open(conversation)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    // 当前会话的标记：用实心点而不是整行高亮 —— 整行高亮会把右侧时间压得看不清。
                    // 非当前项画一个透明圆（而不是 `if` 掉它）：有它才有一致的 7pt 缩进，
                    // `if` 会让当前行的标题比其它行右移 7pt。
                    .fill(isCurrent(conversation) ? Theme.lime : Color.clear)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 3) {
                    Text(conversation.displayTitle)
                        .font(Typography.callout)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(detailText(conversation))
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(timeText(conversation, isToday: isToday))
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent(conversation) ? Theme.lime.opacity(0.09) : Color.clear)
            }
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button(role: .destructive) {
                remove(conversation)
            } label: {
                Label("删除对话", systemImage: "trash")
            }
        }
        .hoverEffect(.highlight)
    }

    // MARK: - 派生

    private func isCurrent(_ conversation: AIConversation) -> Bool {
        guard let current = chat.conversationId else { return false }
        return current == conversation.id
    }

    /// 副标题：**模型 → 条数 → 预览**。
    ///
    /// 顺序按"一行只放得下一条信息时先给谁"排：模型决定这条回答的口径，
    /// 条数说明聊了多久，预览才是内容（而标题已经是从内容里摘的）。
    private func detailText(_ conversation: AIConversation) -> String {
        var parts: [String] = []

        if let model = AIModelNaming.label(conversation.lastModel, models: chat.models) {
            parts.append(model)
        }
        if conversation.messageCount > 0 {
            parts.append("\(conversation.messageCount) 条")
        }

        let preview = conversation.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty {
            parts.append(preview)
        }

        if parts.isEmpty { return "空对话" }
        return parts.joined(separator: " · ")
    }

    /// 「今天」那组显示钟点，更早的显示日期。
    ///
    /// 判据用分组 id（Store 已经按 `startOfDay` 分好了），不再自己 `isDateInToday` ——
    /// 两处判据迟早会漂成"分到今天就组、时间却显示昨天"。
    private func timeText(_ conversation: AIConversation, isToday: Bool) -> String {
        if isToday {
            return Formatters.timeHHmm(conversation.updatedAt)
        }
        return Formatters.absoluteCN(conversation.updatedAt)
    }

    // MARK: - 动作

    private func open(_ conversation: AIConversation) {
        // 先关半屏、再换会话：换会话会把整屏消息替换掉，若 sheet 还盖着，
        // 用户会先看到"半屏下面的内容变了"再等它收起 —— 顺序反了就是一次可见的跳字
        dismiss()
        Task { await chat.load(id: conversation.id) }
    }

    private func startNewConversation() {
        chat.newConversation()
        dismiss()
    }

    private func remove(_ conversation: AIConversation) {
        Haptics.light()
        Task { await chat.delete(id: conversation.id) }
    }

    private func reload() {
        Task { await list.load() }
    }
}
