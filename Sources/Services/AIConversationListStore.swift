import Combine
import Foundation

// MARK: - 分组

/// 历史列表里的一段（"今天" / "更早"）。
///
/// 为什么用"一段"而不是二维数组：`ForEach` 要 `Identifiable`，而 section 的标题、
/// 空段要不要出现这些判断一旦塞进 View，就会在 `body` 里长出 `if` 与 `let` ——
/// 那是 SwiftUI 最容易被写坏的地方。分组逻辑放 Store，View 只负责画。
struct AIConversationGroup: Identifiable, Equatable {

    /// `"today"` / `"earlier"`，只用于列表 diff
    let id: String

    /// 「今天」「更早」
    let title: String

    let items: [AIConversation]
}

// MARK: - 历史列表

/// 历史对话的唯一状态源：列表 / 搜索 / 分组 / 删除 / 新建空会话。
///
/// 与 `AIChatStore` 分工：
/// · 本类只管"有哪些会话"（列表这一层）；
/// · 单条会话里有什么消息，由 `AIChatStore.load(id:)` 负责。
///
/// 所以聊天页删会话时调的是本类 —— 删完列表就地少一行，这才是唯一真相源该做的事。
/// 反过来让聊天页自己写一份 `DELETE`，历史列表就得靠"下次打开再拉"来发现删过了，
/// 中间那段时间用户还能看到一条明明删掉的会话。
@MainActor
final class AIConversationListStore: ObservableObject {

    /// 全 App 唯一实例（写法同 `WeatherStore.shared` / `AIChatStore.shared`）
    static let shared = AIConversationListStore()

    // MARK: - 状态

    /// 全部会话（按 `updatedAt` 倒序）
    @Published private(set) var conversations: [AIConversation] = []

    /// 首页在飞（骨架态）
    @Published private(set) var isLoading = false

    /// 下一页在飞（底部小转圈）
    @Published private(set) var isLoadingMore = false

    /// 服务端还有下一页
    @Published private(set) var hasMore = false

    /// 最近一次失败（`.cancelled` 不写这里）
    @Published private(set) var lastError: AIError?

    /// 搜索词。**本地过滤**，不打接口 —— 契约里没有 search 参数，
    /// 而索引一次最多回来 120 条，本地 `contains` 比一次往返快得多。
    @Published var query: String = ""

    /// 下一页游标
    private var nextCursor: String?

    private let client: APIClient

    // MARK: - 初始化

    init(client: APIClient = .shared) {
        self.client = client
    }

    // MARK: - 派生

    /// 列表是否真的空（不是"搜索没结果"）。空态文案要区分这两件事
    var isEmpty: Bool {
        conversations.isEmpty
    }

    /// 过滤后的列表。搜索词为空时就是全量
    var visible: [AIConversation] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return conversations }
        return conversations.filter { conversation in
            conversation.title.lowercased().contains(keyword)
                || conversation.preview.lowercased().contains(keyword)
        }
    }

    /// 直接给 `List` 用的两段（今天 / 更早）。搜索时也照样分组 ——
    /// 搜出来的结果如果只有一条，"更早"下面那一行标题反而帮用户定位
    var grouped: [AIConversationGroup] {
        return Self.group(visible, now: Date())
    }

    /// 搜索没有结果（用来区分"还没聊过"和"搜不到"两种空态）
    var isSearchEmpty: Bool {
        !conversations.isEmpty && visible.isEmpty
    }

    // MARK: - 加载

    /// 拉第一页。
    ///
    /// 不做时间节流：这个请求很便宜（服务端读一次索引分片，最多 120 条），
    /// 而"我刚聊完打开历史却没看到那条"是更难受的错。每次打开半屏都刷一次。
    ///
    /// - Parameter force: 保留参数语义（`false` 时已有数据就跳过），
    ///   给"页面刚出现先看缓存"这类调用留口子；默认 `true`。
    func load(force: Bool = true) async {
        guard !isLoading else { return }
        if !force, !conversations.isEmpty { return }

        isLoading = true
        defer { isLoading = false }

        do {
            guard let url = API.aiConversations() else {
                throw AIError.server("地址拼错了。")
            }
            let request = API.aiRequest(url: url, method: "GET", token: AIKeychain.token())
            let response = try await client.send(request, as: AIConversationsResponse.self)
            guard response.ok else {
                throw AIError.server("历史列表没拿到，晚点再看。")
            }
            // 服务端已按时间倒序。这里再排一次，是为了将来索引分片顺序变了也不会乱
            conversations = response.conversations.sorted { $0.updatedAt > $1.updatedAt }
            hasMore = response.hasMore ?? false
            nextCursor = response.nextCursor
            lastError = nil
        } catch {
            lastError = AIFailure.from(error)
        }
    }

    /// 拉下一页（列表滚到底时调）
    func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMore else { return }
        let cursor = nextCursor
        guard let cursor = cursor, !cursor.isEmpty else {
            // 服务端说还有、却没给游标：当作到底，别用空游标反复打同一个请求
            hasMore = false
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            guard let url = API.aiConversations(cursor: cursor) else {
                throw AIError.server("地址拼错了。")
            }
            let request = API.aiRequest(url: url, method: "GET", token: AIKeychain.token())
            let response = try await client.send(request, as: AIConversationsResponse.self)
            guard response.ok else {
                throw AIError.server("更多历史没拿到，晚点再看。")
            }

            // 去重：翻页期间有新会话写入时，两页可能重叠。按 id 合并才不会出现重复行
            var known = Set(conversations.map { $0.id })
            var merged = conversations
            for item in response.conversations where !known.contains(item.id) {
                known.insert(item.id)
                merged.append(item)
            }
            conversations = merged.sorted { $0.updatedAt > $1.updatedAt }
            hasMore = response.hasMore ?? false
            nextCursor = response.nextCursor
            lastError = nil
        } catch {
            lastError = AIFailure.from(error)
        }
    }

    // MARK: - 删除

    /// 删一条会话。
    ///
    /// 乐观删除 + 失败回滚：列表立刻少一行（这是用户唯一能看到的结果），
    /// 失败了再把快照摆回去并挂错误 —— 反过来（先转圈、等 300ms 再删）更"正确"，
    /// 但删一条聊天记录这件事，慢半拍本身就是一种坏体验。
    ///
    /// - Returns: 服务端确认删掉了才 `true`
    @discardableResult
    func delete(id: String) async -> Bool {
        let target = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return false }

        guard let url = API.aiConversation(id: target) else {
            lastError = .server("地址拼错了。")
            return false
        }

        let snapshot = conversations
        conversations.removeAll { $0.id == target }

        do {
            let request = API.aiRequest(url: url, method: "DELETE", token: AIKeychain.token())
            let response = try await client.send(request, as: AIConversationDeleteResponse.self)
            guard response.ok else {
                throw AIError.server("这条对话没删掉，再试一次。")
            }
            lastError = nil
            return true
        } catch {
            conversations = snapshot
            lastError = AIFailure.from(error)
            return false
        }
    }

    // MARK: - 新建空会话

    /// 新建一条空会话（`POST /api/ai/conversation`）。
    ///
    /// 日常聊天**不需要**它：第一轮 `chat` 的末帧会隐式建会话并回 `convId`。
    /// 它是给"先建空壳、再逐轮写"的形态留的口子（历史列表里主动点「新建」时用）。
    /// 建出来的会话 `messageCount == 0`，插到列表最前面。
    ///
    /// - Parameter title: 标题；nil / 空串交给服务端用首条用户消息兜底
    /// - Returns: 成功时返回新会话，失败返回 nil（错误挂在 `lastError`）
    func create(title: String? = nil) async -> AIConversation? {
        guard let url = API.aiConversationCreate() else {
            lastError = .server("地址拼错了。")
            return nil
        }

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = (trimmedTitle?.isEmpty ?? true) ? nil : trimmedTitle

        do {
            let body = try JSONEncoder().encode(AIConversationCreateRequest(title: payload))
            let request = API.aiRequest(url: url,
                                        method: "POST",
                                        token: AIKeychain.token(),
                                        body: body)
            let response = try await client.send(request, as: AIConversationCreateResponse.self)
            guard response.ok, let conversation = response.conversation else {
                throw AIError.server("新对话没建起来，稍后再试。")
            }
            conversations.insert(conversation, at: 0)
            lastError = nil
            return conversation
        } catch {
            lastError = AIFailure.from(error)
            return nil
        }
    }

    // MARK: - 分组（纯函数，方便自检）

    /// 按"今天 / 更早"切两段。
    ///
    /// 判据用 `startOfDay` 而不是 `Calendar.isDateInToday`：后者在设备时钟略快
    /// （或跨时区旅行）时会把"刚发的消息"判成明天/昨天，于是它从"今天"里消失 ——
    /// 而用户看到的是"我刚聊的对话不见了"。用 `>= startOfDay` 只分一次界，更稳。
    static func group(_ items: [AIConversation], now: Date) -> [AIConversationGroup] {
        let startOfToday = Calendar.current.startOfDay(for: now)
        var today: [AIConversation] = []
        var earlier: [AIConversation] = []
        for item in items {
            if item.updatedAt >= startOfToday {
                today.append(item)
            } else {
                earlier.append(item)
            }
        }
        var groups: [AIConversationGroup] = []
        if !today.isEmpty {
            groups.append(AIConversationGroup(id: "today", title: "今天", items: today))
        }
        if !earlier.isEmpty {
            groups.append(AIConversationGroup(id: "earlier", title: "更早", items: earlier))
        }
        return groups
    }
}
