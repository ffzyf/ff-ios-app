import Foundation

/// 一份成功响应的快照：原始 JSON 字节 + 拿到它的时刻。
///
/// 为什么存**原始 Data** 而不是存 decode 后的对象：不同端点的模型各有各的形状，
/// 缓存层一旦开始理解业务模型，就会变成"半个 Store"。存字节 + 用的时候再 decode，
/// 缓存层就永远只需要 `Codable` 这一条约束。
struct Snapshot: Codable, Equatable {
    /// 上次成功响应的原始 JSON
    let payload: Data
    /// 拿到这份数据的时刻（用来算"数据可能过期"）
    let savedAt: Date
}

/// 离线降级的存储层：把上次成功的 JSON 塞进 `UserDefaults`（按 key 前缀隔离）。
///
/// 选 `UserDefaults` 而不是磁盘文件：本 App 单次响应的量级是几十 KB（简报 / 日程 / 列表），
/// 远在 UserDefaults 的舒适区内，换来的是零文件管理、零沙盒路径、零清理逻辑。
/// 用 `actor` 而不是加锁：所有调用点都是 async 上下文（Store → CachedLoader），
/// 用 actor 能把"编码 + 写盘"压在同一个串行域里，不需要手写 `DispatchQueue`。
actor SnapshotCache {

    /// 全 App 共用一份。`AppModel` 之外的新 Store（红石 / 问卷 / 监控）都走它。
    static let shared = SnapshotCache()

    /// 所有 key 的统一前缀：`clearAll()` 只清自己写的，不碰其他 UserDefaults 内容
    /// （例如 `appearance` 外观偏好 —— 清缓存绝不能把用户选的外观也清了）。
    static let keyPrefix = "snapshot."

    private let defaults: UserDefaults
    private let keyPrefix: String

    init(defaults: UserDefaults = .standard, keyPrefix: String = SnapshotCache.keyPrefix) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    /// 存一份成功响应。编码失败（理论上不会：`Snapshot` 只有 `Data` + `Date`）就静默跳过 ——
    /// 缓存写失败绝不能影响本次成功的展示。
    func save(_ payload: Data, for key: String) {
        let snapshot = Snapshot(payload: payload, savedAt: Date())
        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(encoded, forKey: keyPrefix + key)
    }

    /// 读一份快照。没有 / 解不开都返回 nil（缓存损坏等同于没有缓存，不做修复）。
    func load(for key: String) -> Snapshot? {
        guard let data = defaults.data(forKey: keyPrefix + key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// 只取时刻（判断"数据可能过期"时不需要把 payload 解出来）
    func savedAt(for key: String) -> Date? {
        return load(for: key)?.savedAt
    }

    func remove(for key: String) {
        defaults.removeObject(forKey: keyPrefix + key)
    }

    /// 清空全部快照（供"清空缓存"按钮或调试用）。只清本前缀，别的 UserDefaults 键不动。
    func removeAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
