import Foundation

/// `GET /api/app/version`（简报站）的版本检查响应 —— 匿名可读，用于云控更新。
///
/// 字段契约：`ok` 是唯一必填字段；其余字段缺省表示"该维度无数据"，不代表接口失败。
/// 业务失败（`ok == false`，HTTP 仍是 200）只表示这次没拿到版本信息，
/// 调用方应保留上一次的值，而不是清空。
struct AppVersionEnvelope: Decodable, Equatable, Sendable {

    /// 业务成功标志。
    let ok: Bool

    /// 最新版本号（短版，如 "3.8.0"）。
    let latestVersion: String?

    /// 最新 build 号（整型递增）。
    let latestBuild: Int?

    /// 本次更新的标题。
    let title: String?

    /// 更新日志，按行拆好。
    let notes: [String]?

    /// ipa 下载地址（相对或绝对 URL 字符串）。
    let downloadUrl: String?

    /// 安装引导页相对路径。
    let installGuidePath: String?

    /// 是否强制更新。
    let forceUpdate: Bool?

    /// 服务端给出的最小兼容版本（低于此版本的客户端走强制更新）。
    let minVersion: String?

    /// 手写 `init(from:)`：服务端严格"空值不占位"，任何一个字段解不开都只是"这个字段没有"，
    /// 不影响整份响应。与 `WeatherNow` / `BriefResponse` 同一套纪律。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        latestVersion = try? container.decode(String.self, forKey: .latestVersion)
        latestBuild = try? container.decode(Int.self, forKey: .latestBuild)
        title = try? container.decode(String.self, forKey: .title)
        notes = try? container.decode([String].self, forKey: .notes)
        downloadUrl = try? container.decode(String.self, forKey: .downloadUrl)
        installGuidePath = try? container.decode(String.self, forKey: .installGuidePath)
        forceUpdate = try? container.decode(Bool.self, forKey: .forceUpdate)
        minVersion = try? container.decode(String.self, forKey: .minVersion)
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case latestVersion
        case latestBuild
        case title
        case notes
        case downloadUrl
        case installGuidePath
        case forceUpdate
        case minVersion
    }
}

/// 主 App 的当前版本信息，用于与服务端返回的 `latestVersion` / `latestBuild` 对比。
///
/// 为什么不直接用 `Bundle.main.infoDictionary`：两处（设置页版本号 + 更新检查）
/// 都要读，读一次集中在这里，调用方不用再记 `CFBundleShortVersionString` 这种键名。
enum AppRelease {

    /// 短版本号（如 "3.7.0"）。读不到返回空串，调用方自行判断。
    static var shortVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return info["CFBundleShortVersionString"] as? String ?? ""
    }

    /// build 号（字符串原始值）。
    static var buildString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return info["CFBundleVersion"] as? String ?? ""
    }

    /// build 号的整型值；解析失败返回 0。
    static var build: Int {
        Int(buildString) ?? 0
    }
}
