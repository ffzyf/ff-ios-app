import Foundation

// MARK: - 模型

/// `GET /api/app/config` 的 `values` 对象（3.9.0，热更通道的载荷）。
///
/// 三个字段**全部可选带默认**、逐个 `try?` 解码 —— 照抄 `UpdateStore.AppRelease` 那套
/// 「每个字段都有兜底」的写法：服务端少给一个字段，只丢那一个功能，不会让整包解码失败。
/// 远程配置是附加功能，宁可少一个能力，也不能因为一个字段缺失整份配置作废。
struct RemoteConfigValues: Codable, Hashable {

    /// 公告横幅（**热更的主要载体**）：OverviewView 顶部那张卡。
    /// nil = 不渲染；title / body 有一个非空就展示（空串字段各自不渲染那一行）。
    let announcement: RemoteAnnouncement?

    /// 强更门槛：本机 `CFBundleVersion` 低于它时，更新弹窗**不可关闭**（无「稍后」）。
    /// nil = 本版没有强更。由 `UpdateStore.apply` 读取并折算成 `isForced`。
    let minBuild: Int?

    /// 覆盖安装引导页地址（`UpdateInstaller.installGuideURL` 优先用它）。
    /// 换域名只改云端配置，不用发版 —— 热更通道的核心用途之一。nil = 用硬编码地址。
    let installGuideURL: String?

    /// 远程通知队列（设计 §2.1，最新在前）。**只在这里多一个字段，不新增解码路径**：
    /// 老配置没有 `notification` 键时解成 nil，公告 / 强更 / 引导页行为逐像素不变。
    /// `RemoteNotificationStore` 虽然复用本类型解码，但**不订阅**本 Store 的 1h 闸门（见其类注释）。
    let notification: [RemoteNotification]?

    /// 手写 `init(from:)` 之后编译器不再自动合成 `CodingKeys`，必须显式声明。
    private enum CodingKeys: String, CodingKey {
        case announcement
        case minBuild
        case installGuideURL
        case notification
    }

    /// 全字段默认值的构造器：给测试与「空配置」兜底用。
    /// 新增参数带默认值 —— 既有调用点（目前只有解码路径）不必改。
    init(
        announcement: RemoteAnnouncement? = nil,
        minBuild: Int? = nil,
        installGuideURL: String? = nil,
        notification: [RemoteNotification]? = nil
    ) {
        self.announcement = announcement
        self.minBuild = minBuild
        self.installGuideURL = installGuideURL
        self.notification = notification
    }

    /// 逐个 `try?`：任何一个字段解不开都只是「这个字段没有」，不影响整份配置。
    /// `announcement` 整体解码失败（缺 title / body）也收成 nil —— 半截公告比没有公告更糟。
    /// `notification` 逐条用 `RemoteNotification` 的 `try?` 纪律，坏条目由 Store 的 `isValid` 跳过。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        announcement = try? container.decode(RemoteAnnouncement.self, forKey: .announcement)
        minBuild = try? container.decode(Int.self, forKey: .minBuild)
        installGuideURL = try? container.decode(String.self, forKey: .installGuideURL)
        notification = try? container.decode([RemoteNotification].self, forKey: .notification)
    }
}

/// 公告横幅的内容（`values.announcement`）。
///
/// `title` / `body` 必填（服务端管理页负责给全），`url` 可选 —— 有 url 时整条横幅可点。
/// 刻意**不做**手写 init(from:)：合成解码对可选字段用 `decodeIfPresent`，
/// title / body 缺一个就让整体解码失败 → 上层 `try?` 收成 nil，正好是想要的语义。
/// 5.4.0 新增的 `level` / `color` 同样是 `let ... : String?`，因此**不需要**补 `CodingKeys`
/// 也不需要改解码路径：老配置（没有这两个键）解出来就是 nil，行为与改版前逐像素一致。
struct RemoteAnnouncement: Codable, Hashable {
    /// 一行加粗标题
    let title: String
    /// 正文（横幅最多 2 行；弹窗里完整显示、可滚动）
    let body: String
    /// 可选的外部链接（横幅整条可点；弹窗里成为主按钮）
    let url: String?
    /// 呈现方式：`"banner"`（缺省）/ `"sheet"`。见 `presentation`。
    let style: String?
    /// 弹窗主按钮文案。nil = 有 url 时用「去看看」，没 url 时用「知道了」。
    let actionTitle: String?
    /// 弹窗图标（SF Symbol 名）。nil = 按 `style` 给默认图标。
    let icon: String?

    /// 公告级别：`"notice"`（普通，缺省）/ `"emergency"`（紧急）。见 `isEmergency`。
    ///
    /// 为什么是 `String?` 而不是枚举：这是**服务端下发的字段**，枚举解码遇到没见过的值会让
    /// 整份 `RemoteAnnouncement` 解码失败 → 上层 `try?` 收成 nil → 公告静默消失。
    /// 用字符串 + 派生属性，未知值最坏也只是退回"普通公告"，内容还能看到。
    let level: String?
    /// 紧急公告的主色（hex，如 `"#E5484D"`）。解析交给 `AnnouncementPalette`，
    /// 模型层不认识颜色：hex 写错不该让公告解不出来，只该让颜色回落到默认红。
    /// 「太亮」也不归模型层管 —— 亮度闸门与压暗在 `AnnouncementPalette` 里统一做，
    /// 这里只负责原样转发服务端写的字符串。
    let color: String?

    /// 是不是紧急公告。
    ///
    /// **只有逐字等于 `"emergency"` 才算**（大小写不敏感），其余一切 —— nil、空串、
    /// 以后新增的 `"maintenance"` 之类 —— 全部当普通公告。这个方向的降级必须是"宁轻勿重"：
    /// 把普通公告误判成紧急，用户会撞上一屏关不掉的红屏（只能点按钮才能脱身）；
    /// 反过来的误判只是少了一点强调，用户仍然看得见内容。
    var isEmergency: Bool {
        level?.lowercased() == "emergency"
    }

    /// 呈现方式。**未知值一律退回 banner**：
    /// 服务端以后加了新形态（比如全屏），旧版本 App 也不能因此把公告整条吞掉 ——
    /// 退成横幅至少还能看到，退成"什么都不显示"就是静默失败。
    ///
    /// 紧急公告例外：**恒为 `.sheet`**，与 `style` 无关。横幅是可以被 × 掉的
    /// （`AnnouncementBanner` 一按就落盘已读），而紧急公告的语义是"必须看到"——
    /// 让它进横幅位等于把"必须"降级成"随便"。
    ///
    /// 注意这里的 `.sheet` 是**枚举值**（"走弹层"），不是 UIKit 的 sheet 模态：
    /// 紧急公告实际用 `.fullScreenCover` 呈现（整屏、无下滑手势），普通公告才是 `.sheet`。
    /// 这个枚举表达的是"要不要挡在用户面前"，具体用哪种模态由 `OverviewView` 决定。
    var presentation: AnnouncementStyle {
        if isEmergency { return .sheet }
        return AnnouncementStyle(rawValue: style?.lowercased() ?? "") ?? .banner
    }

    /// 有没有可点的链接。`url` 存在但拼不成 URL 时按"没有链接"处理（同横幅）。
    var hasLink: Bool {
        guard let raw = url, raw.isEmpty == false else { return false }
        return URL(string: raw) != nil
    }

    /// 弹窗主按钮文案。优先级：自定义 > 有链接就「去看看」> 「知道了」。
    var primaryActionTitle: String {
        if let custom = actionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           custom.isEmpty == false {
            return custom
        }
        return hasLink ? "去看看" : "知道了"
    }

    /// 弹窗图标。自定义优先；否则：紧急公告用警示三角（它表达的是"危险 / 必须处理"），
    /// 普通公告按有没有链接给一个 —— 有链接是"带你去某处"，没链接是"通知"，
    /// 两种意图不该用同一个图标。
    var symbolName: String {
        if let custom = icon?.trimmingCharacters(in: .whitespacesAndNewlines),
           custom.isEmpty == false {
            return custom
        }
        if isEmergency { return "exclamationmark.triangle.fill" }
        return hasLink ? "arrow.up.right.circle.fill" : "megaphone.fill"
    }
}

/// 公告的呈现方式。
///
/// 为什么要有两种：**大部分公告不值得打断用户**。版本号变了、活动上线这类信息，
/// 顶部横幅扫一眼就够了；只有"必须现在知道"的（服务中断、数据迁移）才配弹窗。
/// 把选择权交给服务端，比在客户端按正文长度猜要可靠。
enum AnnouncementStyle: String {
    case banner
    case sheet
}

/// `GET /api/app/config` 的完整载荷（信封 + 内容合一：字段与后端响应逐字一致）。
struct RemoteConfig: Codable, Hashable {

    /// 配置版本号，每次保存 +1（服务端维护）。横幅的「关闭」记忆挂在它上面：
    /// 新 revision 发布 → 已关闭的旧公告自动重新出现。
    let revision: Int
    /// 业务字段。nil = 线上没有下发任何配置（横幅不渲染、无强更、引导页走硬编码）。
    let values: RemoteConfigValues?

    private enum CodingKeys: String, CodingKey {
        case revision
        case values
    }

    init(revision: Int, values: RemoteConfigValues?) {
        self.revision = revision
        self.values = values
    }

    /// 逐个 `try?`（同 `RemoteConfigValues` 的纪律）。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = (try? container.decode(Int.self, forKey: .revision)) ?? 0
        values = try? container.decode(RemoteConfigValues.self, forKey: .values)
    }
}

// MARK: - 状态源

/// 远程配置的唯一状态源（3.9.0，热更通道）。
///
/// 与 `UpdateStore` 同一套纪律：**失败必须静默** —— 配置是附加功能，接口挂了、断网、
/// 解码失败都不弹任何东西、不清空旧值（旧公告继续显示，总比"公告突然消失"体面）。
/// 也不占用 `ToastStore`：没有哪条配置值得打断用户正在做的事。
@MainActor
final class RemoteConfigStore: ObservableObject {

    static let shared = RemoteConfigStore()

    /// 拉取闸门（秒）。**1 小时而不是 UpdateStore 的 6 小时**：公告是"运营想让人看到"的信息，
    /// 钝 6 小时就失去了时效；1 小时在"够及时"与"不刷接口"之间取的折中（接口自己还有 60s 缓存）。
    static let refreshInterval: TimeInterval = 3600

    /// 落盘键：上次成功拉取的时刻（闸门跨启动生效）。
    private static let keyLastFetch = "remoteConfig.lastFetchAt"

    // MARK: 对外只读状态

    /// 最近一次成功拉到的配置。**失败时不清空** —— 断网不该让首页的公告消失。
    /// 冷启动（进程内第一次成功拉取前）为 nil：所有消费方都按"没有配置"兜底。
    @Published private(set) var latest: RemoteConfig?

    // MARK: 依赖

    private let client: APIClient
    private let defaults: UserDefaults
    /// 本进程是否已经拉过一次（闸门只对"进程内第二次以后"生效，理由见 `refreshIfNeeded()`）
    private var didLaunchRefresh: Bool = false

    nonisolated init(client: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    // MARK: 拉取入口

    /// 统一入口（冷启动 / 回前台都走这里，挂法与 `UpdateStore.checkIfNeeded` 对齐）。
    ///
    /// 闸门规则：
    /// · **进程内第一次调用无视闸门直接拉** —— 进程内存是空的，不拉就没有任何配置可消费；
    ///   落盘的上次时间只用于"这次启动里已经拉过、又回前台"的场景。
    /// · 成功后写落盘时间（"冷启动成功后重置闸门"由此达成：下一次冷启动必然重拉）。
    /// · 失败静默：不清空旧值、不写时间（下个前台时机立刻重试）。
    func refreshIfNeeded() async {
        if didLaunchRefresh {
            guard isDue else { return }
        }
        didLaunchRefresh = true

        guard let url = Endpoint.url(base: Endpoint.briefBase, path: Endpoint.appConfigPath) else {
            // 地址拼错是代码问题，不该让用户看到任何东西
            return
        }

        do {
            let envelope = try await client.get(url, as: RemoteConfigEnvelope.self)
            // 业务失败（HTTP 200 + ok:false）：静默放弃这一次，旧值保留
            guard envelope.ok, envelope.revision > 0 else { return }
            latest = RemoteConfig(revision: envelope.revision, values: envelope.values)
            markFetched()
        } catch {
            // 网络 / 解码失败：静默。旧值不清空（理由见类注释）。
        }
    }

    // MARK: 内部

    /// 距上次**成功**拉取是否已满 1 小时。
    var isDue: Bool {
        guard let last = lastFetchedAt else { return true }
        return Date().timeIntervalSince(last) >= Self.refreshInterval
    }

    private var lastFetchedAt: Date? {
        let raw = defaults.double(forKey: Self.keyLastFetch)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    private func markFetched() {
        defaults.set(Date().timeIntervalSince1970, forKey: Self.keyLastFetch)
    }
}

// MARK: - 响应信封

/// `GET /api/app/config` 的响应信封（与 `AppVersionEnvelope` 同一套写法）。
///
/// 从 `private` 放开为 internal：通知 Store 需要**复用同一份解码定义**去拉取同一个端点
/// （设计 §3.3.1）。这是"网络协议层复用、闸门层解耦"的关键 —— 两个消费者各自拉，
/// 但响应结构只有一份，将来字段增删不会漏改其中一处。
/// 服务端 POST 响应新增的 `values` / `notificationTrimmed` 属于未知键，Codable 默认忽略，零影响。
struct RemoteConfigEnvelope: Decodable {

    /// 业务成功标志
    let ok: Bool
    /// 服务端维护的版本号；没有配置过时为 0
    let revision: Int
    /// 最近一次保存时间（ISO 串，App 侧暂不展示，模型里留着备查）
    let updatedAt: String?
    /// 业务字段；从未配置过时为 null
    let values: RemoteConfigValues?

    private enum CodingKeys: String, CodingKey {
        case ok
        case revision
        case updatedAt
        case values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        revision = (try? container.decode(Int.self, forKey: .revision)) ?? 0
        updatedAt = try? container.decode(String.self, forKey: .updatedAt)
        // values 缺失或显式 null 都收成 nil：对 App 是同一个结论（没有配置）。
        values = try? container.decode(RemoteConfigValues.self, forKey: .values)
    }
}
