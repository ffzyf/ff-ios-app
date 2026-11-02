import Foundation

/// 光遇版本四态（**服务端判定**，App 只 switch，不做任何版本号比较 —— 设计文档 §3.5）。
///
/// 真实实现里还有第五种：`unknown`（KV 里读不到 `app_monitor_history` 时，`apps` 为空），
/// 所以枚举必须留这个兜底，否则解码会落到 `.unknown` 之外的非法值上。
enum SkyState: String {
    case newVersion = "new-version"
    case noChange = "no-change"
    case initial = "init"
    case fetchFailed = "fetch-failed"
    case unknown = "unknown"
}

/// 整体版本状态 + 两服明细
struct SkyStatus: Decodable {
    let status: SkyState
    let hasUpdate: Bool
    let checkedAt: Date?
    let apps: [SkyAppVersion]

    /// 手写 `init(from:)` 后编译器不再自动合成 `CodingKeys`，必须显式声明。
    /// 服务端键名与属性名逐字一致（camelCase），故无需写 rawValue。
    private enum CodingKeys: String, CodingKey {
        case status
        case hasUpdate
        case checkedAt
        case apps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawStatus = (try? container.decode(String.self, forKey: .status)) ?? ""
        status = SkyState(rawValue: rawStatus) ?? .unknown
        hasUpdate = (try? container.decode(Bool.self, forKey: .hasUpdate)) ?? false
        checkedAt = try? container.decode(Date.self, forKey: .checkedAt)
        apps = (try? container.decode([SkyAppVersion].self, forKey: .apps)) ?? []
    }
}

/// 单服版本明细。
///
/// `previous` 在推送成功后即丢失（KV 是扁平快照，没有历史数组），所以只当「上次版本」展示，
/// **不要**用它做任何状态判定。
struct SkyAppVersion: Decodable, Identifiable {
    let id: String
    let name: String
    /// 国服 / 国际服（服务端给中文，直接上屏）
    let region: String
    /// 当前版本号。服务端可能给 null（从未成功检查过）
    let version: String?
    /// 与 version 同值（服务端三字段冗余下发，`current` / `latest` 只是别名）
    let current: String?
    let latest: String?
    let previous: String?
    /// 上一版自己的发布日期（date-only `"2026-10-21"`，可能为 null）。
    ///
    /// 与 `previous` 同源（服务端 v2.3.0 的版本流水）：`previous` 有值它才有值。
    /// **不要转 Date**（时区会把 21 号漂成 20 号），展示走 `Formatters.versionDateText`。
    /// 可空 + `try?` 解码：老快照 / 老部署没有这个键，缺键不能让整页解码失败。
    let previousReleaseDate: String?
    /// date-only 字符串 `"2026-10-28"`，**不要转 Date**（时区会把 28 号漂成 27 号）
    let releaseDate: String?
    let checkedAt: Date?
    let status: SkyState
    let hasUpdate: Bool
    let lastError: String?
    let source: String?
    let url: String?

    /// 手写 `init(from:)` 后编译器不再自动合成 `CodingKeys`，必须显式声明。
    /// 只列存储属性；计算属性 `displayVersion` 不属于解码契约，不得放进来。
    /// 服务端键名与属性名逐字一致（camelCase），故无需写 rawValue。
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case region
        case version
        case current
        case latest
        case previous
        case previousReleaseDate
        case releaseDate
        case checkedAt
        case status
        case hasUpdate
        case lastError
        case source
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        region = (try? container.decode(String.self, forKey: .region)) ?? ""
        version = try? container.decode(String.self, forKey: .version)
        current = try? container.decode(String.self, forKey: .current)
        latest = try? container.decode(String.self, forKey: .latest)
        previous = try? container.decode(String.self, forKey: .previous)
        // 老快照 / 老部署没有这个键：`try?` 解不出来就是 nil，不能让整页解码失败
        previousReleaseDate = try? container.decode(String.self, forKey: .previousReleaseDate)
        releaseDate = try? container.decode(String.self, forKey: .releaseDate)
        checkedAt = try? container.decode(Date.self, forKey: .checkedAt)
        let rawStatus = (try? container.decode(String.self, forKey: .status)) ?? ""
        status = SkyState(rawValue: rawStatus) ?? .unknown
        hasUpdate = (try? container.decode(Bool.self, forKey: .hasUpdate)) ?? false
        lastError = try? container.decode(String.self, forKey: .lastError)
        source = try? container.decode(String.self, forKey: .source)
        url = try? container.decode(String.self, forKey: .url)
    }

    /// 展示用版本号，永不为空
    var displayVersion: String {
        if let version = version, !version.isEmpty {
            return version
        }
        return "—"
    }
}
