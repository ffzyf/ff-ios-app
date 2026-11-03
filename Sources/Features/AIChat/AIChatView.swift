import SwiftUI

/// 沉浸式 AI 聊天页（一级 Tab 第 3 格，3.28.0）。
///
/// 版式照 `sky-v4-preview.html` 第 2 屏：
/// ```
/// ┌  ‹        [ 模型名 ▾ ]        ⋯  ┐   ← 52pt，没有大标题、没有导航栏底板
/// │          …… 消息列表 ……          │
/// │  ┌──────────────────┐    ┌──┐    │
/// │  │ 问点什么…         │    │ ↑ │    │
/// │  └──────────────────┘    └──┘    │
/// └──────────────────────────────────┘
/// ```
///
/// 三条设计决定（都有理由，不是随手排的）：
///
/// 1. **顶部只有三个元素**，且**没有底板**。这是 3.16.0 天光页那条结论的延续：
///    一块玻璃会把头顶那片"极淡的天光"横着切掉一条，页面就不沉浸了。
///    聊天页的顶栏没有任何"当前在哪"的信息要交代（它就是最外层的一个 Tab），
///    所以连标题都可以不要 —— 只有"回去 / 跟谁聊 / 换一条聊"这三件事要做。
/// 2. **背景是"白纸上有颜色"，不是天光页那种"整片天"**。同一套 `Theme.sky` 色，
///    这里只用 10%~12% 的透明度铺在顶部与右上角，正文字色仍按纸面标准挑
///    （对比度不为装饰让路）。两页共用一个语汇，但**不共用强度**。
/// 3. **页面自己不碰网络**。发送 / 停止 / 重试 / 切会话 / 删会话全部交给 `AIChatStore`
///    与 `AIConversationListStore`（两个 `@MainActor` 单例）。这里只读 `@Published`、
///    只调它们的方法 —— 数据层已经把 SSE、代次、空闲超时那一堆都处理过了（见 `AIChatStore` 顶部注释）。
struct AIChatView: View {

    /// 聊天状态机（单例 + `@ObservedObject`：本页是 Tab 页，不依赖环境对象注入，
    /// 写法与 `MoreView` 观察 `SurveyStore` 一致）
    @ObservedObject private var chat = AIChatStore.shared

    /// 尺寸模型：只用来限宽（聊天是**一行行字**，最大用到 `readingWidth` 640）。
    /// 352 宽的 iPhone 上 640 不生效，iPad 上聊天气泡不会横跨 1080。
    @Environment(\.layoutMetrics) private var metrics

    /// 「返回」的去向。由 `RootView` 注入（它持有 Tab 选择的 Binding）——
    /// 页面不自己猜"上一层是谁"，组件永远不决定导航。
    private let onBack: () -> Void

    @State private var showsHistory: Bool = false
    @State private var showsModelPicker: Bool = false

    /// 空态的建议问题。
    ///
    /// 为什么是这四句：服务端会把当天天气摘要拼进 system prompt，也会读到简报与红石数据，
    /// 所以"穿什么 / 带不带伞 / 红石几场 / 总结简报"这四句是**真的答得出来**的；
    /// 换成"写一首诗"之类，用户第一次点开就会觉得这个 AI 跟 App 没关系。
    private static let suggestions: [String] = [
        "今天出门穿什么？",
        "明天要带伞吗？",
        "红石这周还有几场？",
        "帮我总结今天的简报"
    ]

    /// 显式 init：`onBack` 没有默认值（必须有去向），其余属性都有 `@State` 默认值。
    /// 手写一份也避免了"私有存储属性把 memberwise init 降级成 private"这个跨文件可见性坑
    /// （`SkyRoomView.init(brief:)` 记过同一条）。
    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 第一层：极淡天光。**不铺底色**（页面底色由 `RootView` 的 `PageBackground` 提供），
            // 所以这一层是"加色"而不是"盖住" —— 滚动光影仍然透得上来。
            AIChatBackdrop()

            VStack(spacing: 0) {
                AIChatTopBar(
                    modelLabel: chat.selectedModelLabel,
                    onBack: handleBack,
                    onPickModel: openModelPicker,
                    onOpenHistory: openHistory
                )

                loadErrorLine

                AIChatMessageList(
                    messages: chat.messages,
                    models: chat.models,
                    canRetry: chat.canRetry,
                    isLoading: chat.isLoadingConversation,
                    suggestions: Self.suggestions,
                    onSuggestion: sendSuggestion,
                    onRetry: retryLast
                )
                AIChatComposer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // 列宽：聊天正文最大 640（阅读行宽），iPad 上居中。
            // 窄屏 393 < 640 → `maxWidth` 不生效，与 iPhone 逐像素一致。
            .pageColumn(metrics.readingWidth)
        }
        // 两个半屏都用系统 sheet（`.presentationDetents`），不自绘 —— 见各自文件的注释
        .sheet(isPresented: $showsHistory) {
            AIChatHistorySheet()
        }
        .sheet(isPresented: $showsModelPicker) {
            AIModelPickerSheet()
        }
        // 模型清单：顶栏那个名字、模型面板的置灰状态都要它。
        // `loadModels()` 内部不节流，但它很便宜（一次 GET，拿清单 + auto 判据 + 配额），
        // 每次进这一页拉一次比"缓存一份可能过期的清单"更省事。
        .task {
            await chat.loadModels()
        }
    }

    // MARK: - 动作

    /// 会话加载失败的那一行。
    ///
    /// 为什么必须有：`AIChatStore.load(id:)` 失败时 `messages` 已经被清空了 —— 没有这一行，
    /// 用户点开一条历史对话看到的就是"一条空对话 + 四个建议问题"，完全不知道是网络问题
    /// （消息级失败有气泡下面那行灰字兜底，这里没有气泡可依附）。
    ///
    /// 三个条件缺一不可：
    /// · `messages.isEmpty` —— 手里还有内容时**绝不清屏**，也不与气泡自己的错误重复；
    /// · `conversationId != nil` —— 冷启动 `loadModels()` 失败时不该在空态顶上挂一条红字，
    ///   那与"这一页能不能开始聊"无关；
    /// · `lastError` 里的文案已经是人话（`AIError.userMessage`），这里只负责上屏 + 给重试。
    ///
    /// 重试复用 `load(id:)` 本身（它会重新置 nil 再拉），不另开一条请求路径。
    @ViewBuilder
    private var loadErrorLine: some View {
        if chat.messages.isEmpty, let error = chat.lastError, let id = chat.conversationId {
            HStack(spacing: 10) {
                Text(error.userMessage)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    retryLoad(id)
                } label: {
                    Text("重试")
                }
                .buttonStyle(SecondaryCTAStyle())
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, 6)
        }
    }

    private func handleBack() {
        Haptics.light()
        onBack()
    }

    private func openModelPicker() {
        Haptics.light()
        showsModelPicker = true
    }

    private func openHistory() {
        Haptics.light()
        showsHistory = true
    }

    /// 点建议问题 = 直接发送（不需要用户再按一次发送键）
    ///
    /// 触觉**不在这里再给一次**：胶囊按钮自己已经 `Haptics.light()` 了
    /// （`AIChatMessageList.suggestionChip`），两处都给会变成一次点击两下反馈 ——
    /// 手感上是一记更重的"咚"，而且是随两个文件的相对位置变化的不可控差异。
    /// 下面 `retryLast` 同理（`retryRow` 自己给）。
    private func sendSuggestion(_ text: String) {
        Task { await chat.send(text) }
    }

    private func retryLast() {
        Task { await chat.retryLast() }
    }

    /// 重拉当前这条会话（`loadErrorLine` 的「重试」）。
    ///
    /// 触觉在这里给：那个按钮是 `SecondaryCTAStyle`（纯样式，不含触觉）。
    private func retryLoad(_ id: String) {
        Haptics.light()
        Task { await chat.load(id: id) }
    }
}

// MARK: - 顶栏

/// 顶栏：返回 / 当前模型 / 「⋯」。
///
/// **没有底板**（理由见 `AIChatView` 顶部第 1 条）。两个图标按钮给 44×44 的点击热区
/// （HIG 的最小热区），视觉上却只有一个 15pt 的符号 —— 与天光页那个关闭按钮同一手法。
private struct AIChatTopBar: View {
    /// 当前模型名（`AIChatStore.selectedModelLabel`：清单没拉到之前也能显示"自动选择"）
    let modelLabel: String
    let onBack: () -> Void
    let onPickModel: () -> Void
    let onOpenHistory: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            iconButton(icon: "chevron.left", label: "返回", action: onBack)
            Spacer(minLength: 0)
            modelPill
            Spacer(minLength: 0)
            iconButton(icon: "ellipsis", label: "历史对话", action: onOpenHistory)
        }
        .padding(.horizontal, 10)
        // 52：比 44 的点击热区高 8，上下各留 4 的呼吸，同时把消息区往上顶一点点
        .frame(height: 52)
    }

    private func iconButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// 模型胶囊：白色玻璃 + 一个 9pt 的下箭头。
    ///
    /// 只有这一枚胶囊带玻璃 —— 顶栏的其余部分必须"看不见"，
    /// 用户唯一需要一眼认出的信息是"现在跟谁在聊"。
    private var modelPill: some View {
        Button {
            onPickModel()
        } label: {
            HStack(spacing: 5) {
                Text(modelLabel)
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            // 走唯一的玻璃入口（iOS 26 系统玻璃 / 18–25 手工配方，同一套 token）
            .glassSurface(.floating, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("切换模型，当前是" + modelLabel)
    }
}

// MARK: - 背景

/// 极淡的天光底。
///
/// 只借 `Theme.sky(...)` 的两个色（`top` 与地平线亮边 `edge`），用 10%~12% 铺在
/// 顶部与右上角：抬头能看见一点点天色，正文对比度完全不受影响。
///
/// **为什么按钟点算天色而不接天气**：这一层是氛围，不是天气报表。
/// 为它把 `WeatherStore` 拉进聊天页（还要处理"阴天不降 phase"那套门控）不划算 ——
/// 天光页做那件事是因为那一页**整屏都是天**，这里只有一条 10% 的渐变。
private struct AIChatBackdrop: View {

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [topTint, topTint.opacity(0.35), clearTint],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.42)
            )
            RadialGradient(
                colors: [edgeGlow, clearTint],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
        // 氛围层不吃触摸：它盖在消息区上面，一旦命中就会吞掉滚动与选中
        .allowsHitTesting(false)
    }

    /// 天色按当前钟点取（`SunClock.phase` 是纯时间函数，不读网络）
    private var sky: Theme.SkyColors {
        return Theme.sky(SunClock.phase(at: Date()))
    }

    private var topTint: Color {
        return sky.top.opacity(0.10)
    }

    private var edgeGlow: Color {
        return sky.edge.opacity(0.12)
    }

    /// 渐变透明端：也用同一个色的 0%，而不是 `Color.clear` ——
    /// 工程规矩是"透明度只出现在 token 里"，就地造 `Color.clear` 会开一个口子。
    private var clearTint: Color {
        return sky.top.opacity(0)
    }
}
