import Foundation

/// 一次加载的结果。
///
/// 三个字段就是 PRD §6 第 14 条（"任何页面都不出现白屏：显示缓存 + 顶部离线提示"）
/// 需要 UI 知道的全部信息：
///   · `value`    有值就渲染，`nil` 才允许进空态 / 错误态；
///   · `isStale`  true = 这份内容是缓存或上一次成功的，可以配顶部「离线 / 可能过期」条；
///   · `error`    非 nil = 本次请求失败，可以配重试按钮。
///
/// `value` 之所以是可选：首次安装 + 断网时既没有缓存也没有新数据，此时只有"失败"这一件事可说，
/// 不能编一个空对象让页面去渲染（会渲染出一堆 `—`，比明确的错误态更糟）。
struct LoadResult<T> {
    var value: T?
    /// 这份值是否"可能过期"（来自缓存，或本次请求失败后保留了旧值）
    var isStale: Bool
    /// 本次请求的错误（缓存命中时是 nil）
    var error: Error?

    var hasValue: Bool { value != nil }

    /// 本次请求刚拿到的、新鲜的值
    static func fresh(_ value: T) -> LoadResult<T> {
        return LoadResult(value: value, isStale: false, error: nil)
    }

    /// 来自缓存 / 旧值的降级结果
    static func degraded(_ value: T?, error: Error?) -> LoadResult<T> {
        return LoadResult(value: value, isStale: true, error: error)
    }

    /// 彻底失败：没有任何值可用
    static func failed(_ error: Error) -> LoadResult<T> {
        return LoadResult(value: nil, isStale: true, error: error)
    }
}

/// **离线降级的唯一实现点**（设计文档 §1.3.2）。
///
/// 顺序固定为三步，顺序本身就是需求：
/// 1. **先给缓存**（哪怕已经过期）—— 用户立刻有东西看，不掉进骨架屏；
/// 2. **再发请求** —— 成功就落盘并再发一次新鲜值，页面无感替换；
/// 3. **失败就保留旧值** —— 只把 `error` / `isStale` 翻起来，页面顶部挂「离线」条，
///    **绝不清空已经显示的内容**（PRD §5.2 / §7）。
///
/// 用回调而不是 `AsyncStream`：调用点都是 `@State` 驱动的 View，`emit` 直接写 State 最省事，
/// 也避免为"两次结果"引入一套流生命周期管理。全程不依赖 Combine（Widget 也要复用这套代码）。
@MainActor
final class CachedLoader {

    static let shared = CachedLoader()

    private let cache: SnapshotCache

    init(cache: SnapshotCache = .shared) {
        self.cache = cache
    }

    /// 加载一份数据，最多回调两次（缓存一次 + 请求一次）。
    ///
    /// - Parameters:
    ///   - key: 缓存键（同一端点 + 同一参数必须用同一个 key，否则会读到别人的数据）
    ///   - maxAge: 新鲜窗口（秒）。缓存年龄超过它就把 `isStale` 置 true —— 值照给，只是标注"可能过期"
    ///   - fetch: 真正的请求（由调用方用 `APIClient` 实现，本层不关心是哪个站）
    ///   - emit: 结果回调，保证在主线程；第一次可能 `isStale = true`（缓存），第二次是请求结果
    func load<T: Codable & Sendable>(
        key: String,
        maxAge: TimeInterval = 300,
        fetch: @escaping () async throws -> T,
        emit: (LoadResult<T>) -> Void
    ) async {
        var cachedValue: T?

        // 1) 缓存优先：解不开就当作没有缓存，继续走请求
        if let snapshot = await cache.load(for: key) {
            if let decoded = try? JSONDecoder().decode(T.self, from: snapshot.payload) {
                cachedValue = decoded
                let age = Date().timeIntervalSince(snapshot.savedAt)
                emit(LoadResult(value: decoded, isStale: age > maxAge, error: nil))
            } else {
                // 模型变了导致老快照解不开：清掉，免得每次启动都白试一遍
                await cache.remove(for: key)
            }
        }

        // 2) 请求：成功就落盘 + 发新鲜值
        do {
            let value = try await fetch()
            if let payload = try? JSONEncoder().encode(value) {
                await cache.save(payload, for: key)
            }
            emit(.fresh(value))
        } catch {
            // 3) 失败：有旧值就把旧值再发一次（页面因此不会闪成空屏），没有就发纯失败
            if let cachedValue = cachedValue {
                emit(.degraded(cachedValue, error: error))
            } else {
                emit(.failed(error))
            }
        }
    }

    /// 只读缓存、不发请求（页面首帧用：避免"先骨架、后缓存、再网络"的三段跳）
    func cachedValue<T: Codable>(_ type: T.Type, for key: String) async -> T? {
        guard let snapshot = await cache.load(for: key) else { return nil }
        return try? JSONDecoder().decode(type, from: snapshot.payload)
    }
}
