import Foundation

/// `GET /api/app/config` → `values.notification` 队列中的一条远程通知（设计 §2.1）。
///
/// ## 职责边界
/// 只做「字段解码 + 派生属性」，不碰网络、不碰通知中心、不碰 UserDefaults。
/// 因此它放在 `Sources/Shared/Domain`（App 与 Widget 两个 target 都能编），且只 import Foundation。
///
/// ## 逐字段 `try?` 解码纪律（设计 §3.3）
/// 服务端虽然已经在写入侧过滤脏条目，但 App 仍要假设"线上可能残留任何形状的数据"
/// （老版本写入、手工改 KV、未来字段类型变化）。这里每个字段单独 `try?`：
/// 一个字段解不开只丢那一个字段，绝不让一条坏数据把**整份 values** 解成 nil ——
/// 那会连公告 / 强更 / 引导页一起失效，是把"一条通知的问题"放大成"热更通道全挂"。
///
/// 必填字段（msgId / title / body / createdAt）解不开时给空值 / 0，再用 `isValid` 让
/// 消费方（`RemoteNotificationStore`）跳过这一条 —— 坏条目被隔离，不影响同批其它通知。
struct RemoteNotification: Hashable, Codable {

    /// 逻辑通知身份，格式 `n_<base36 时间>_<6 位随机>`；重发时**沿用**。
    let msgId: String
    /// 投递序号，从 1 起；重发 +1。与 msgId 合起来才是去重键（只用 msgId 会让重发被吞掉）。
    let seq: Int
    /// 通知栏标题（服务端约定 ≤40 字）
    let title: String
    /// 通知栏正文（服务端约定 ≤100 字）
    let body: String
    /// `info / warn / urgent`；未知值降级 info（不产生副标题），不解析成枚举以免整条解不开
    let level: String?
    /// 协议保留：iOS 本地通知 v1 不渲染图标
    let icon: String?
    /// 协议保留：iOS `UNMutableNotificationContent` 没有 tint 能力
    let color: String?
    /// `skyapp://` 深链或 `http(s)://` H5；其它 scheme 由 `routableURL` 收成 nil
    let url: String?
    /// 协议保留：v1 没有注册 UNNotificationAction，不产生自定义按钮
    let actionTitle: String?
    /// Unix 毫秒时间戳（number，不是 ISO 串）。决定时效窗与队列淘汰顺序。
    let createdAt: Int64

    /// 投递时效窗：超过 24h 的条目记为已投递但不弹。
    /// 集中在这一处（设计 §2.4），随时可调；不散落到 Store 的判断里。
    static let deliverMaxAge: TimeInterval = 24 * 3600

    private enum CodingKeys: String, CodingKey {
        case msgId, seq, title, body, level, icon, color, url, actionTitle, createdAt
    }

    /// 全字段默认值的构造器：测试与「空条目兜底」用。
    init(
        msgId: String = "",
        seq: Int = 1,
        title: String = "",
        body: String = "",
        level: String? = nil,
        icon: String? = nil,
        color: String? = nil,
        url: String? = nil,
        actionTitle: String? = nil,
        createdAt: Int64 = 0
    ) {
        self.msgId = msgId
        self.seq = seq
        self.title = title
        self.body = body
        self.level = level
        self.icon = icon
        self.color = color
        self.url = url
        self.actionTitle = actionTitle
        self.createdAt = createdAt
    }

    /// 逐字段 `try?`：任何字段类型变了都只是那一个字段回退，整条通知仍然可用。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        msgId = (try? container.decode(String.self, forKey: .msgId)) ?? ""
        seq = (try? container.decode(Int.self, forKey: .seq)) ?? 1
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        body = (try? container.decode(String.self, forKey: .body)) ?? ""
        level = try? container.decode(String.self, forKey: .level)
        icon = try? container.decode(String.self, forKey: .icon)
        color = try? container.decode(String.self, forKey: .color)
        url = try? container.decode(String.self, forKey: .url)
        actionTitle = try? container.decode(String.self, forKey: .actionTitle)
        // 用 Int64 而不是 Double：毫秒时间戳在 JSON 里是整数，Double 会在极大值上丢精度
        createdAt = (try? container.decode(Int64.self, forKey: .createdAt)) ?? 0
    }

    /// 这条通知是否具备可投递的最基本条件。
    /// 坏条目（字段解不开 / 服务端漏过滤）在这里被隔离，不会污染同批其它通知。
    var isValid: Bool {
        !msgId.isEmpty && !title.isEmpty && !body.isEmpty && createdAt > 0
    }

    /// 去重键：**`msgId#seq`**（不是 msgId）。
    /// 同一 key 多次拉取不重复弹；重发时 seq+1 → key 变化 → 所有设备再弹一次。
    var dedupKey: String {
        msgId + "#" + String(seq)
    }

    /// 是否还在 24h 投递时效窗内。
    /// createdAt 为 0（解不出来）视为过期；时钟略快（age 为负）仍视为新鲜，不因设备时间差吞掉通知。
    var isFresh: Bool {
        guard createdAt > 0 else { return false }
        let age = Date().timeIntervalSince1970 - Double(createdAt) / 1000.0
        return age <= Self.deliverMaxAge
    }

    /// 可交给 `UIApplication.shared.open` 的 URL。
    /// 只认 `skyapp://` 与 `http(s)://`：其它 scheme 视为无链接（设计 §2.1 字段约定）。
    /// `skyapp:///brief`（host 空、path 有值）也要放行 —— `RootView.open(deepLink:)` 兼容这个写法。
    var routableURL: URL? {
        guard let raw = url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let candidate = URL(string: raw),
              let scheme = candidate.scheme?.lowercased() else { return nil }
        if scheme == "skyapp" {
            guard candidate.host != nil || !candidate.path.isEmpty else { return nil }
            return candidate
        }
        if scheme == "http" || scheme == "https" {
            guard candidate.host != nil else { return nil }
            return candidate
        }
        return nil
    }
}
