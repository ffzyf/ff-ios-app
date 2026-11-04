import Combine
import Foundation

// MARK: - 错误映射

/// 传输层错误 → `AIError`。
///
/// 为什么单独一个 enum 而不是 `AIError.init(error:)`：`AIError` 在 `Shared/Models` 里，
/// 那个目录**也会被编进小组件 target**，而 `APIError` 在 `Services/` 里 ——
/// 让 `AIError` 认识 `APIError`，小组件就编不过。所以映射放在 Services 侧。
///
/// 放在本文件而不是各 Store 里：聊天 / 历史列表 / 穿搭三个 Store 都要用它，
/// 同一套 `switch` 抄三遍，迟早改一处漏两处（比如某天补了 403 只改了一个文件）。
enum AIFailure {

    /// 把任意错误归一成 `AIError`（已经是 `AIError` 就原样返回，幂等）
    static func from(_ error: Error) -> AIError {
        if let ai = error as? AIError { return ai }
        if let api = error as? APIError {
            switch api {
            case .network:
                return .network
            case .decoding:
                return .server("数据格式对不上，先不展示了。")
            case .cancelled:
                return .cancelled
            case .server(let code, let message):
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                switch code {
                case 401, 403:
                    return .unauthorized
                case 429:
                    return .quota(trimmed)
                default:
                    return .server(trimmed)
                }
            }
        }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError, urlError.code == .cancelled { return .cancelled }
        return .network
    }
}

// MARK: - 聊天状态机

/// AI 聊天的唯一状态源。
///
/// 六件事：发消息 → 边收边贴字 → 收尾落状态；停止；重试；切会话；删会话；模型选择。
/// 写作方式与 `WeatherStore` / `SpeechStore` 一致：`@MainActor` 单例 + `@Published private(set)`
/// + 页面用 `@ObservedObject` 观察（AI 页将来是独立 Tab / 模态，不依赖环境对象注入）。
///
/// ## 四条不能破的规矩
///
/// 1. **半截不冒充完整**：只有收到服务端末帧 `{"done":true}` 才算 `.done`。
///    流被对端关掉、空闲超时、用户点停止，一律 `.cancelled` / `.failed`。
///    这不是洁癖：`.done` 的含义是"服务端已经把这轮写进 KV 了"，标错会让用户以为存上了，
///    于是关掉页面再回来发现少了半句 —— 那时已经无从解释。
/// 2. **切会话必须先掐掉在飞的流**：否则旧会话的 `delta` 会继续往新会话的消息里追加，
///    屏幕上就是"我打开了一条旧对话，它自己在打字"。实现见 `abortInFlightForSwitch()`。
/// 3. **乐观插入**：用户消息与 assistant 占位先上屏，再开流。网络那 300ms 不该是空白。
/// 4. **只许一条流**：`isStreaming` 是唯一的闸门，重试 / 再发都要过它。
///
/// ## 并发模型（一句话）
///
/// 整个类是 `@MainActor`，所以**所有状态写入都在主线程**，包括流里的每一次 `append`。
/// 流式本身不占主线程（`bytes(for:)` 的等待是挂起，不是忙等），
/// 但 `for try await line in bytes.lines` 里每个 `await` 都是回到主 actor 执行 ——
/// 于是"边收边贴"天然是线程安全的，不需要任何锁。
@MainActor
final class AIChatStore: ObservableObject {

    /// 全 App 唯一实例
    static let shared = AIChatStore()

    // MARK: - 对外状态

    /// 当前会话 id。nil = 新对话（还没被服务端建过）。
    ///
    /// 新对话的 id 是**第一轮末帧**才给的（`{"done":true,"convId":"…"}`），
    /// 所以"发送前为 nil、发送后变成 22 位串"是正常形态，不是 bug。
    @Published private(set) var conversationId: String?

    /// 当前会话的全部消息（从旧到新，与屏幕顺序一致）
    @Published private(set) var messages: [AIChatMessage] = []

    /// 有一条流在飞。UI 据此把"发送"变成"停止"
    @Published private(set) var isStreaming = false

    /// 当前选的模型：`"auto"` 或具体模型 id。**默认 auto**
    @Published private(set) var selectedModel: String = "auto"

    /// 服务端给的 auto 选择原因（末帧的 `reason`）。
    /// 界面上要显示它 —— 用户有权知道"为什么这次是 DeepSeek 答的"
    @Published private(set) var lastReason: String?

    /// 今日剩余条数。权威值来自 `GET /api/ai/models`；本机每成功一轮先 −1 做乐观提示
    @Published private(set) var quotaRemaining: Int?

    /// 输入框内容。Store 持有它，是为了"发送成功即清空""切会话即清空"只有一个入口
    @Published var draft: String = ""

    /// 可选模型清单（`GET /api/ai/models`）。空数组 = 还没拉到
    @Published private(set) var models: [AIModelOption] = []

    /// auto 这次会选中谁（`auto.picked`），与 `lastReason` 配着显示
    @Published private(set) var autoPicked: String?

    /// 最近一次失败（nil 表示没失败）。**`.cancelled` 不写这里** —— 停止不是错误
    @Published private(set) var lastError: AIError?

    /// 正在拉某条历史会话（骨架态）
    @Published private(set) var isLoadingConversation = false

    // MARK: - 常量

    /// 空闲超时（秒）：**30 秒收不到任何字节就掐断**。
    ///
    /// 语义是"空闲"，不是"整请求"：一条长回复可以流 3 分钟，但只要服务端还在发东西
    /// （哪怕只是每 10 秒一行 `: ping` 心跳），这条流就不该被断。
    /// 反过来，服务端挂了 / CF 边缘掐了连接，30 秒内必有结论，用户不用干等到天荒地老。
    ///
    /// ## 为什么不只靠 `timeoutIntervalForRequest`
    ///
    /// `URLSessionConfiguration.timeoutIntervalForRequest` 的文档语义是"等待更多数据"，
    /// 看起来正好，但它有两个问题：
    /// 1. 它是**整条连接**的一个计时器，掷到哪一层由系统决定 —— 真机上它有时表现为
    ///    "整个请求 30 秒"，那就把一条正常的长回复也砍了；
    /// 2. 它抛出来的错误和"用户点了停止"在客户端看起来一样（都是 `URLError.cancelled`），
    ///    分不清就没法给不同的收尾文案。
    ///
    /// 所以这里**自己记 `lastByteAt`**（每收到一行就刷新），由一个看门狗任务判超时，
    /// 超时时先记下 `abortReason = .idleTimeout` 再取消 —— 收尾时就能说清是"超时"还是"你停的"。
    /// session 上的 `timeoutIntervalForRequest` 仍然设 30，当第二道保险（它先触发也不亏，
    /// 反正结果是同一条 `.idleTimeout`）。
    private static let idleTimeout: TimeInterval = 30

    /// 看门狗检查间隔（秒）。5 秒一次：超时判定最多晚 5 秒，代价可忽略
    private static let idleCheckInterval: TimeInterval = 5

    /// 错误信封最多读多少字节（防止服务端异常时无限读）
    private static let maxErrorBodyBytes = 64 * 1024

    // MARK: - 私有状态

    private let client: APIClient

    /// 流式专用 session。
    ///
    /// 为什么不复用 `APIClient` 的：那个类的 `session` 是私有的，而且配了
    /// `timeoutIntervalForResource = 30`（整请求上限）—— 拿它流式，一条超过 30 秒的回复
    /// 会被硬切。这里单独一份，超时语义只服务聊天。
    private let streamSession: URLSession

    /// 在飞的流（`send` / `retryLast` 都 `await` 它的 value）
    private var streamTask: Task<Void, Never>?

    /// 空闲看门狗
    private var watchdogTask: Task<Void, Never>?

    /// 代次。**这是"切会话"那条 bug 的解药**：
    /// 每次开新流 / 停止 / 切会话都 +1；流循环里每一步都校验"我还是当前那一代吗"，
    /// 不是就直接返回，一个字段都不写。取消（`Task.cancel`）是"请求它别跑"，
    /// 代次是"就算你跑回来了也不许动状态" —— 两个都要，缺一个就有窗口期。
    private var streamGeneration: Int = 0

    /// 这一轮是**为什么**结束的（供收尾文案区分）
    ///
    /// 显式写 `: Equatable`：本文件要拿它做 `==` 比较，靠"无关联值枚举自动合成"虽然也行，
    /// 但这种隐式能力一旦被后人加上关联值就会静默编不过，不如写死。
    private enum AbortReason: Equatable {
        case none
        case userStopped
        case switchedConversation
        case idleTimeout
    }

    private var abortReason: AbortReason = .none

    /// 最后一次收到字节的时刻（看门狗判空闲超时用）
    private var lastByteAt: Date = .distantPast

    /// 用户有没有手动选过模型。`true` 时 `loadModels()` 不许用服务端的 `defaultModel` 覆盖它
    private var userPickedModel = false

    // MARK: - 初始化

    init(client: APIClient = .shared, streamSession: URLSession? = nil) {
        self.client = client
        if let streamSession = streamSession {
            self.streamSession = streamSession
        } else {
            let configuration = URLSessionConfiguration.default
            // 空闲超时的第二道保险（第一道是看门狗，见 `idleTimeout`）
            configuration.timeoutIntervalForRequest = AIChatStore.idleTimeout
            // 整请求上限放到 10 分钟：一条长回复 + 心跳可以走很久，不该被资源超时打断
            configuration.timeoutIntervalForResource = 600
            // AI 响应全部 no-store，本地缓存只会拿到一份"过期答案"
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.httpAdditionalHeaders = ["User-Agent": "FFWang/2.0 (iOS)"]
            self.streamSession = URLSession(configuration: configuration)
        }
    }

    // MARK: - 派生

    /// 能不能发：有内容、没有流在飞
    var canSend: Bool {
        !isStreaming && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 最后一条 assistant 消息是不是失败了（UI 据此显示"重试"）
    var canRetry: Bool {
        guard !isStreaming else { return false }
        guard let last = messages.last, last.role == .assistant else { return false }
        return last.status == .failed || last.status == .cancelled
    }

    /// 选中模型的显示名（"自动选择" / "DeepSeek"）。清单没拉到就用 id 顶上
    var selectedModelLabel: String {
        if let match = models.first(where: { $0.id == selectedModel }) {
            return match.label
        }
        return selectedModel == "auto" ? "自动选择" : selectedModel
    }

    // MARK: - 发送

    /// 发一句话。
    ///
    /// 顺序（每一步都有理由）：
    /// 1. trim / 空串直接返回（用户按了回车但只有空格，不该产生一条空气泡）；
    /// 2. 乐观插入用户消息 + assistant 占位；
    /// 3. 开流，`await` 到收尾。
    ///
    /// `await` 到收尾是刻意的：调用方（`.task` / 按钮的 Task）在流结束时才拿到控制权，
    /// 不需要自己订阅状态。想中途停止就调 `stop()` —— 它取消任务，`await` 立刻返回。
    func send(_ text: String) async {
        let trimmed = trim(text)
        guard !trimmed.isEmpty, !isStreaming else { return }
        draft = ""
        await startTurn(text: trimmed, appendUserBubble: true)
    }

    /// 停止当前流。
    ///
    /// **保留已收到的半截文本**（用户看到的字不能凭空消失），状态标 `.cancelled`。
    /// 同步方法：UI 点下去必须立刻看到按钮变回"发送"，不能等一个 `await`。
    ///
    /// 这里的 `streamGeneration &+= 1` 是关键：还在 `await bytes.lines` 里的那个循环
    /// 回来后会发现"我已经不是当前代次了"，于是不写任何状态（否则它会把 `.cancelled`
    /// 覆盖成 `.failed`，或者干出别的更难看的事）。
    func stop() {
        guard isStreaming else { return }
        abortReason = .userStopped
        streamGeneration &+= 1
        cancelInFlight()
        updateAssistant(status: .cancelled, errorText: nil)
        isStreaming = false
        lastError = nil
    }

    /// 重试上一条。
    ///
    /// **不重复插入用户气泡**：失败的那一轮，用户消息已经在屏幕上了，
    /// 再插一条一样的，历史里就会出现"同一句话说了两遍"。
    /// 做法是丢掉最后那条失败 / 中止的 assistant 占位（它只有半截文本，重试本来就是重写它），
    /// 再用最后一条用户消息的原文重发。
    func retryLast() async {
        guard !isStreaming else { return }
        guard let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) else { return }
        let text = trim(messages[lastUserIndex].text)
        guard !text.isEmpty else { return }

        if let last = messages.last, last.role == .assistant,
           last.status == .failed || last.status == .cancelled {
            messages.removeLast()
        }
        lastError = nil
        await startTurn(text: text, appendUserBubble: false)
    }

    /// 开一条新对话（只清本地状态，不请求服务端）。
    ///
    /// 不调 `POST /api/ai/conversation` 的理由：会话是在第一轮 `chat` 的末帧里
    /// 由服务端创建并回报 `convId` 的。先建一条空会话再写，会在历史列表里留下一堆
    /// "打开过但没说话"的空壳。
    func newConversation() {
        abortInFlightForSwitch()
        conversationId = nil
        messages = []
        lastReason = nil
        lastError = nil
        draft = ""
    }

    // MARK: - 切换 / 加载 / 删除

    /// 打开一条历史会话。
    ///
    /// 三步的顺序不能换：**先掐流 → 再换 id → 最后清消息**。
    /// 先换 id 再掐流的话，掐流的收尾动作（`updateAssistant` 找最后一条 streaming 消息）
    /// 会落到新会话的数组上；先清消息再换 id 也一样 —— 中间的任何一个乱序，
    /// 结果都是"旧会话的字写进了新会话"。
    func load(id: String) async {
        let target = trim(id)
        guard !target.isEmpty else { return }
        // 同一条会话已经在屏幕上：什么都不做。
        // 注意这里**不判** `isStreaming`：用户在历史里点到的正好是当前这条时，
        // 重拉毫无意义（服务端还没把这轮写完，拉回来的一定比屏幕上少），
        // 而顺手掐断一条正在流式输出的对话，是最让人莫名其妙的一种"点了没反应"。
        if conversationId == target, !messages.isEmpty { return }

        abortInFlightForSwitch()
        conversationId = target
        messages = []
        lastReason = nil
        lastError = nil

        guard let url = API.aiConversation(id: target) else {
            lastError = .server("地址拼错了。")
            return
        }

        isLoadingConversation = true
        defer { isLoadingConversation = false }

        do {
            let request = API.aiRequest(url: url, method: "GET", token: AIKeychain.token())
            let response = try await client.send(request, as: AIConversationDetailResponse.self)

            // 等网络这几百毫秒里，用户可能已经又切走了 —— 那就别把旧数据摆上去
            guard conversationId == target, !isStreaming else { return }
            guard response.ok else {
                throw AIError.server("这条对话没打开，可能已经被删了。")
            }
            messages = response.messages
            if let conversation = response.conversation {
                conversationId = conversation.id
                if let model = conversation.lastModel, !model.isEmpty, model != "auto",
                   !userPickedModel {
                    // 续聊时跟着这条会话上次用的模型走，比"上次在整个 App 里选的那个"更贴近
                    selectedModel = model
                }
            }
        } catch {
            guard conversationId == target else { return }
            lastError = AIFailure.from(error)
        }
    }

    /// 删掉一条会话。
    ///
    /// 真正的删除实现在 `AIConversationListStore`（它是历史列表的唯一真相源，
    /// 删完要就地少一行）。这里只负责"删的正好是当前这条 → 屏幕上清空"。
    /// 不重复写一遍 `DELETE`：两份实现迟早有一份忘了处理 404。
    func delete(id: String) async {
        let target = trim(id)
        guard !target.isEmpty else { return }
        if conversationId == target {
            newConversation()
        }
        await AIConversationListStore.shared.delete(id: target)
    }

    // MARK: - 模型

    /// 用户手动选模型（模型面板调用）。选了就不再让服务端的 `defaultModel` 覆盖
    func selectModel(_ id: String) {
        let target = trim(id)
        guard !target.isEmpty else { return }
        selectedModel = target
        userPickedModel = true
        // 换成具体模型后，上一条 auto 的"选择原因"就过期了
        if target != "auto" { lastReason = nil }
    }

    /// 拉模型清单 + auto 判据 + 今日配额（进页面 / 打开模型面板时调一次就够）
    func loadModels() async {
        guard let url = API.aiModels() else {
            lastError = .server("地址拼错了。")
            return
        }
        do {
            let request = API.aiRequest(url: url, method: "GET", token: AIKeychain.token())
            let response = try await client.send(request, as: AIModelsResponse.self)
            guard response.ok else {
                throw AIError.server("模型清单没拿到，稍后再试。")
            }
            models = response.models
            autoPicked = response.auto?.picked
            if let remaining = response.quota?.remaining {
                quotaRemaining = remaining
            }
            // 服务端建议的默认值只在"用户没主动选过"时生效：
            // 否则每次打开页面都会把用户选的混元打回 auto
            if let defaultModel = response.defaultModel, !defaultModel.isEmpty, !userPickedModel {
                selectedModel = defaultModel
            }
        } catch {
            lastError = AIFailure.from(error)
        }
    }

    // MARK: - 流：主流程

    /// 开一轮对话（`appendUserBubble == false` 时只补 assistant 占位，用于重试）
    private func startTurn(text: String, appendUserBubble: Bool) async {
        if appendUserBubble {
            messages.append(AIChatMessage(id: "local-\(UUID().uuidString)",
                                          role: .user,
                                          text: text,
                                          status: .done,
                                          createdAt: Date()))
        }
        // 占位：先上屏，然后往上贴字。`status == .streaming` 就是界面画打字光标的凭据
        messages.append(AIChatMessage(id: "local-\(UUID().uuidString)",
                                      role: .assistant,
                                      text: "",
                                      status: .streaming,
                                      model: selectedModel == "auto" ? nil : selectedModel))

        lastError = nil
        lastReason = nil
        isStreaming = true

        streamGeneration &+= 1
        let token = streamGeneration
        abortReason = .none
        lastByteAt = Date()

        // Task 继承当前 actor（本类是 @MainActor），所以闭包里的写入仍在主线程。
        // **不在这里把 streamTask 置 nil**：那个赋值会在 `await` 之后执行，
        // 有可能把"用户刚发起的新一轮"的引用擦掉，于是 `stop()` 取消了错的任务。
        // 闭包里显式 `guard let self` 而不是 `await self?.streamOnce(...)`：
        // 后者会让闭包返回 `Void?`，把 Task 推成 `Task<Void?, Never>`，与字段类型对不上。
        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.streamOnce(token: token, userText: text)
        }
        streamTask = task
        await task.value
    }

    /// 一轮流的全部收尾（成功 / 失败 / 超时 / 中止都从这里出去）
    private func streamOnce(token: Int, userText: String) async {
        // 拿到**自己这一代**的看门狗句柄，而不是收尾时去读字段 `watchdogTask`。
        //
        // 为什么：字段是共享的。`stop()` / 切会话取消这一轮之后，`bytes.lines` 的抛出
        // 要等到下一个 await 才回到这里 —— 如果用户手快（停 → 立刻再发），下一轮
        // 已经把 `watchdogTask` 换成了新的，此时这一轮的 `defer` 若按字段取消，
        // 掐掉的是**新一轮**的看门狗，于是那条流失去 30 秒空闲保护。
        let watchdog = startWatchdog(token: token)
        defer { watchdog.cancel() }

        do {
            try await performStream(token: token, userText: userText)
        } catch {
            // 代次变了 = 这轮流已经被 `stop()` / `newConversation()` / `load(id:)` 接手，
            // 状态也由那边收好了。这里**一个字都不许写**（写了就会把 `.cancelled` 改成 `.failed`）
            guard token == streamGeneration else { return }

            let failure = Self.failure(from: error, abort: abortReason)
            if failure.isCancelled {
                // 用户主动停止：不弹错误，只把气泡标成已停止
                lastError = nil
                updateAssistant(status: .cancelled, errorText: nil)
            } else {
                lastError = failure
                updateAssistant(status: .failed, errorText: failure.userMessage)
            }
        }

        guard token == streamGeneration else { return }
        isStreaming = false
        abortReason = .none
    }

    // MARK: - 流：真正的请求

    /// 发请求 + 逐行读 SSE。
    ///
    /// **这是唯一能编译的形态**（也是唯一正确的形态）：
    /// · 必须用 `bytes(for:)`：`data(for:)` 要等整个响应结束才返回，逐字上屏就没了；
    /// · 必须用 `bytes.lines`：行缓冲由系统兜住，跨包半行 / 半个 UTF-8 字节都不会切坏；
    /// · 非 `data: ` 开头的行一律跳过：空行是帧分隔，`: ping` 是心跳（它只用来喂
    ///   `lastByteAt`，证明连接还活着）。
    private func performStream(token: Int, userText: String) async throws {
        guard let url = API.aiChat() else {
            throw AIError.server("地址拼错了。")
        }

        let body: Data
        do {
            // 上下文快照在**发请求的这一瞬**取：天气与账本都是 @Published，
            // 早取一秒就可能少一次刷新，晚取又要跨 await（值会变）。这里取完立刻编码。
            body = try JSONEncoder().encode(AIChatRequest(convId: conversationId,
                                                          model: selectedModel,
                                                          text: userText,
                                                          weather: Self.weatherSnapshot(),
                                                          earnings: Self.earningsSnapshot()))
        } catch {
            throw AIError.server("这条消息发不出去。")
        }

        var request = API.aiRequest(url: url,
                                    method: "POST",
                                    token: AIKeychain.token(),
                                    body: body,
                                    accept: "text/event-stream")
        // 空闲超时语义（见 `idleTimeout`）：这是"多久没数据就断"，不是"整请求多久断"
        request.timeoutInterval = Self.idleTimeout

        let (bytes, response) = try await streamSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.network
        }

        guard (200..<300).contains(http.statusCode) else {
            // 非 200 时 body 是 JSON 错误信封，得先把字节收完才解得出 message
            var data = Data()
            do {
                for try await byte in bytes {
                    data.append(byte)
                    if data.count >= Self.maxErrorBodyBytes { break }
                }
            } catch {
                // 连错误体都读不下来（断线 / 取消）：按状态码给结论，别把错误吞掉
                throw Self.httpFailure(status: http.statusCode, body: data)
            }
            throw Self.httpFailure(status: http.statusCode, body: data)
        }

        for try await line in bytes.lines {
            // 每一步都校验代次：切会话 / 点停止之后，这一行一个字段都不许写
            guard token == streamGeneration else { return }

            // 任何一行都算"字节到了"（含 `: ping` 心跳）—— 空闲超时判的是"连接还活着吗"
            lastByteAt = Date()

            // 去掉行尾可能的 `\r`：服务端写的是 `\n`，但中间只要有一层代理把分帧改写成 CRLF，
            // 那个 `\r` 就会挂在 JSON 尾巴上，`JSONDecoder` 直接失败 —— 表现是"整条回复一个字都没有"，
            // 极难查。一行 `dropLast` 就能把这条路堵死。
            let raw = line.last == "\r" ? String(line.dropLast()) : line

            guard raw.hasPrefix("data: ") else { continue }

            let payload = Data(raw.dropFirst(6).utf8)
            guard payload.count > 1 else { continue }

            // 单帧解不开就跳过：服务端将来加字段 / 偶发半帧，都不该毁掉整条流。
            // （`AIStreamEvent` 是全可选 + 全 `try?` 解码，所以这里几乎只有非 JSON 才会失败，
            //  比如上游残留的 `[DONE]` —— 那种帧跳过就对了。）
            guard let event = try? APIJSON.decoder.decode(AIStreamEvent.self, from: payload) else {
                continue
            }

            if let failure = event.error {
                let message = failure.message.trimmingCharacters(in: .whitespacesAndNewlines)
                throw AIError.upstream(message.isEmpty ? "模型那头出了点问题。" : message)
            }

            if let delta = event.delta, !delta.isEmpty {
                appendDelta(delta, token: token)
            }

            if event.done == true {
                finishTurn(with: event, token: token)
                return
            }
        }

        // 走到这里 = 流被对端关掉，却始终没给 `{"done":true}`。
        // 这就是"半截回复"，**不能**标 `.done`（见类型注释第 1 条）
        throw AIError.interrupted
    }

    // MARK: - 上下文快照（随请求上传）

    /// 把当前天气做成随请求上传的快照。
    ///
    /// 为什么标 `@MainActor`：`WeatherStore.shared.current` 是 `@Published`，
    /// 读它必须在主线程。本类本身就是 `@MainActor`，所以 `performStream` 里
    /// 直接 `Self.weatherSnapshot()` 就够了，不用再跳一次 actor。
    ///
    /// `ok == false` 时返回 nil —— 那表示"这次没拿到天气"，不是"天气是空的"。
    /// 把一份 `ok == false` 的空壳传上去，等于让 AI 拿一张空白天气卡回答"今天穿什么"。
    @MainActor
    private static func weatherSnapshot() -> AIChatWeather? {
        guard let weather = WeatherStore.shared.current, weather.ok else { return nil }

        // `WeatherNow` 自己不存地名（它只认坐标），地名在 `LocationStore`。
        // `displayName` 已经处理好"指定城市优先、其次反查当前位置"的优先级，这里不再判 mode。
        let city = LocationStore.shared.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return AIChatWeather(city: (city?.isEmpty == false) ? city : nil,
                             temp: weather.temp,
                             tMin: weather.tMin,
                             tMax: weather.tMax,
                             feelsLike: weather.feelsLike,
                             text: weather.text,
                             humidity: weather.humidity,
                             wind: weather.wind,
                             windDirText: weather.windDirText,
                             // 分钟降水时段：`WeatherNow` 只有"过去一小时降水量"一个数，
                             // 没有 from/to/level 的分段数组 —— 传 nil，绝不硬造
                             precip: nil)
    }

    /// 把当前收益总览做成随请求上传的快照。
    ///
    /// `summary == nil` 就返回 nil：没登录、凭证过期清了缓存、还没拉到，都走这一条 ——
    /// 服务端于是告诉模型"这次没拿到收益"，AI 就不会编一句"你这个月赚了八千"。
    ///
    /// 金额**原样传分**，不做 `÷100`：换算是展示层（`EarningsMoney.formatCents`）的事。
    /// 这一层换一次、服务端 `earningsDigest` 再换一次，迟早出现两次取整对不上的账。
    @MainActor
    private static func earningsSnapshot() -> AIChatEarnings? {
        guard let summary = EarningsStore.shared.summary else { return nil }

        return AIChatEarnings(total: summary.total,
                              pending: summary.pending,
                              receivedUnclosed: summary.receivedUnclosed,
                              closed: summary.closed,
                              monthAdded: summary.monthAdded,
                              activityCount: summary.activityCount,
                              pendingActivityCount: summary.pendingActivityCount,
                              platformCount: summary.platformCount,
                              breakdown: summary.platformBreakdown.map {
                                  AIChatEarningsPlatform(name: $0.name, amount: $0.amount)
                              },
                              updatedAt: Self.isoText(EarningsStore.shared.lastUpdated))
    }

    /// `Date` → ISO8601 字符串。服务端只把它当"这份数据是什么时候的"参考，不参与任何计算。
    ///
    /// 为什么每次新建 formatter 而不存一个 static：`ISO8601DateFormatter` 不是线程安全的，
    /// 而这条路一轮对话只走一次 —— 省下的那点分配开销，换不来一份共享的可变状态。
    private static func isoText(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    // MARK: - 流：看门狗

    /// 空闲看门狗：每 5 秒看一眼"上次收到字节是多久前"，超过 30 秒就掐断。
    ///
    /// 为什么不用 `Timer`：本类已经在 `Task` 的世界里，`Task.sleep` 的取消语义比
    /// `Timer.invalidate()` 干净 —— 流结束时 `defer` 里一个 `cancel()` 全搞定。
    ///
    /// - Returns: 这一次新建的任务。调用方（`streamOnce`）把它收进 `defer` 里取消，
    ///   **不要**在收尾时按字段 `watchdogTask` 取消（理由见 `streamOnce` 的注释）。
    ///   字段仍然保留：`cancelInFlight()`（停止 / 切会话）需要跨任务取消它。
    @discardableResult
    private func startWatchdog(token: Int) -> Task<Void, Never> {
        watchdogTask?.cancel()
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.idleCheckInterval))
                guard !Task.isCancelled else { return }
                guard let self = self else { return }
                guard token == self.streamGeneration, self.isStreaming else { return }

                if Date().timeIntervalSince(self.lastByteAt) >= Self.idleTimeout {
                    // 先记原因再取消：收尾时才能说"是超时"，而不是笼统的"被取消"
                    self.abortReason = .idleTimeout
                    self.cancelInFlight()
                    return
                }
            }
        }
        watchdogTask = task
        return task
    }

    // MARK: - 流：状态落地

    /// 往最后一条 streaming 的 assistant 消息上贴字
    private func appendDelta(_ delta: String, token: Int) {
        guard token == streamGeneration else { return }
        guard let index = messages.lastIndex(where: { $0.role == .assistant && $0.status == .streaming }) else {
            return
        }
        messages[index].text += delta
    }

    /// 末帧到了：记 convId / 模型 / 原因 / 用量，然后把消息标成 `.done`
    private func finishTurn(with event: AIStreamEvent, token: Int) {
        guard token == streamGeneration else { return }

        if let id = event.convId, !id.isEmpty {
            conversationId = id
        }
        if let reason = event.reason, !reason.isEmpty {
            lastReason = reason
        }
        if let model = event.model, !model.isEmpty {
            // auto 时"到底谁答的"唯一凭据就是这一帧，写回消息（气泡底下那行小字）
            writeModel(model, token: token)
        }

        // 本机先 −1：今天剩余条数要跟着动。权威值仍以 `/api/ai/models` 为准，
        // 多设备同时用会偏一条，下次进页面 / 打开模型面板就校正回来。
        if let remaining = quotaRemaining, remaining > 0 {
            quotaRemaining = remaining - 1
        }

        // `finish` 只要来了就是服务端明确收尾（"stop" / "length" 都算），
        // 而且它已经把这轮写进 KV 了 —— 这时候标 `.failed` 会让用户重发，反而写出两条。
        guard let index = messages.lastIndex(where: { $0.role == .assistant && $0.status == .streaming }) else {
            return
        }
        if messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 收尾帧到了但一个字都没有：这不是"完整回复"，是这轮坏了 —— 给重试的入口
            messages[index].status = .failed
            messages[index].errorText = "模型这次没说话，重试一下。"
            return
        }
        messages[index].status = .done
    }

    /// 把真正答题的模型写到当前这条 assistant 消息上
    private func writeModel(_ model: String, token: Int) {
        guard token == streamGeneration else { return }
        guard let index = messages.lastIndex(where: { $0.role == .assistant && $0.status == .streaming }) else {
            return
        }
        messages[index].model = model
    }

    /// 给"最后一条还在 streaming 的 assistant 消息"落状态。
    ///
    /// 找不到就什么都不做 —— 这是**故意**的：找不到说明状态已经被别人收过了
    /// （比如 `stop()` 先跑完），重复落状态只会互相覆盖。
    private func updateAssistant(status: AIChatMessage.Status, errorText: String?) {
        guard let index = messages.lastIndex(where: { $0.role == .assistant && $0.status == .streaming }) else {
            return
        }
        messages[index].status = status
        if let errorText = errorText {
            messages[index].errorText = errorText
        }
    }

    // MARK: - 切会话（最容易出 bug 的一处）

    /// 掐掉在飞的流，为"换会话"让路。
    ///
    /// 三个动作缺一不可：
    /// 1. `abortReason` 记成 `.switchedConversation`（收尾文案用）；
    /// 2. `streamGeneration += 1` —— **先加代次再取消**：在 `await` 里等着的那个循环
    ///    回来后第一件事就是校验代次，于是它不可能再写任何状态；
    /// 3. `cancelInFlight()` —— 让 `bytes.lines` 立刻抛出去，不用等下一个心跳。
    ///
    /// 半截消息留在**旧**数组里（标 `.cancelled`），随后由调用方把 `messages` 换掉；
    /// 于是它不会出现在新会话里，也不会凭空消失于旧会话的列表（列表由服务端说了算）。
    private func abortInFlightForSwitch() {
        guard isStreaming else { return }
        abortReason = .switchedConversation
        streamGeneration &+= 1
        cancelInFlight()
        updateAssistant(status: .cancelled, errorText: nil)
        isStreaming = false
    }

    /// 取消任务 + 看门狗。
    ///
    /// 取消 `streamTask` 会让 `bytes.lines` 的迭代抛 `CancellationError` / `URLError.cancelled`，
    /// 于是 `streamOnce` 的 catch 立刻跑起来 —— 到时它会看到代次已经变了，直接返回。
    private func cancelInFlight() {
        watchdogTask?.cancel()
        watchdogTask = nil
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - 工具

    /// 错误 → `AIError`（把"为什么结束"的上下文一起带进去）
    ///
    /// 为什么要看 `abort`：`Task.cancel()` 之后 `URLSession` 抛出的是 `.cancelled`，
    /// 但"空闲超时"也是靠取消来收尾的 —— 两者必须分开，否则用户看到的是
    /// "已停止"（其实他什么都没点），或者"你停的"（其实他什么都没点）。
    private static func failure(from error: Error, abort: AbortReason) -> AIError {
        if let ai = error as? AIError { return ai }
        if abort == .idleTimeout { return .idleTimeout }

        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .cancelled : .network
        }
        return AIFailure.from(error)
    }

    /// 非 200 → `AIError`（message 取服务端信封里的原话）
    private static func httpFailure(status: Int, body: Data) -> AIError {
        let message = APIErrorEnvelope.anyMessage(from: body)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch status {
        case 401, 403:
            return .unauthorized
        case 429:
            return .quota(message)
        case 502, 503, 504:
            return .upstream(message.isEmpty ? "模型那头暂时不通。" : message)
        default:
            return .server(message.isEmpty ? "服务器打了个喷嚏（\(status)）。" : message)
        }
    }

    /// 统一 trim（空白一律当"没有"）
    private func trim(_ raw: String) -> String {
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
