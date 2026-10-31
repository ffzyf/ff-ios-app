import Foundation

// MARK: - 模型

/// 站点发布的一个 App 版本（`GET /api/app/version` 的 `latest` 对象）。
///
/// **每个字段都有兜底**：站点少给一个字段，只丢那一个字段，不会让整包解码失败
/// —— 这是 `WeatherNow` 那套「逐个 `try?`」的写法，本文件照抄同一套。
/// 更新提示是打扰型 UI，宁可少显示一条信息，也不能因为一个字段缺失就整块消失。
struct AppRelease: Codable, Hashable, Identifiable {

    /// build 号（对应 `CFBundleVersion`）。**版本比较的唯一主键**
    let build: Int
    /// 版本名（对应 `CFBundleShortVersionString`）。**只做展示**
    let version: String
    /// 更新说明（多行文本，换行就是 `\n`）
    let notes: String
    /// ipa 大小（字节）。0 = 站点没给，UI 整段不渲染
    let size: Int
    /// ipa 的 sha256。本版不校验（全能签那边自己有），留在模型里只是备查
    let sha256: String
    /// 发布时间（服务端给的 ISO 字符串；**不转 Date**，见 `publishedText`）
    let publishedAt: String
    /// ipa 下载路径（形如 `"/api/app/download/3.8.0-14.ipa"`，服务端已拼好）
    let ipaPath: String
    /// ipa 在 KV 里的键（形如 `"3.8.0-14.ipa"`）
    let ipaKey: String

    /// `.sheet(item:)` 要求 `Identifiable`。3.9.0 起用 `"build|version"`：
    /// 服务端拒收回退（build 小于当前 latest 直接 400），所以 build 单调不减；
    /// 但**同 build 重发是合法操作**（改版本名 / 说明后重新发布），重发后 sheet 内容变了、
    /// id 却不变的话，SwiftUI 会把它当同一个 item 复用 —— 弹层里还是旧内容。
    /// build 保证不回退、version 在同 build 内可变，两者拼起来在一个站点上不会撞。
    var id: String { return "\(build)|\(version)" }

    /// 手写 `init(from:)` 之后编译器不再自动合成 `CodingKeys`，必须显式声明。
    /// 服务端键名与属性名逐字一致（camelCase），故无需写 rawValue。
    private enum CodingKeys: String, CodingKey {
        case build
        case version
        case notes
        case size
        case sha256
        case publishedAt
        case ipaPath
        case ipaKey
    }

    /// 逐个 `try?`：任何一个字段解不开都只是「这个字段没有」，不影响整份响应。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        build = (try? container.decode(Int.self, forKey: .build)) ?? 0
        version = (try? container.decode(String.self, forKey: .version)) ?? ""
        notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
        size = (try? container.decode(Int.self, forKey: .size)) ?? 0
        sha256 = (try? container.decode(String.self, forKey: .sha256)) ?? ""
        publishedAt = (try? container.decode(String.self, forKey: .publishedAt)) ?? ""
        ipaPath = (try? container.decode(String.self, forKey: .ipaPath)) ?? ""
        ipaKey = (try? container.decode(String.self, forKey: .ipaKey)) ?? ""
    }
}

/// `GET /api/app/version` 的响应信封。
struct AppVersionEnvelope: Decodable {

    /// 业务成功标志
    let ok: Bool
    /// 最新版本；**站点一次都没发布过时为 nil**
    let latest: AppRelease?

    private enum CodingKeys: String, CodingKey {
        case ok
        case latest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? false
        // `latest` 缺失或显式为 null 都收成 nil：这两件事对 App 是同一个结论（没有新版本）。
        // `decode(AppRelease.self)` 遇 null 会抛 `valueNotFound`，`try?` 正好吃掉它。
        latest = try? container.decode(AppRelease.self, forKey: .latest)
    }
}

extension AppRelease {

    /// 包大小（"2.1 MB"）；拿不到给空串，调用方整段不渲染。
    ///
    /// 用系统的 `ByteCountFormatter` 而不是手写 `bytes / 1024 / 1024`：
    /// 进制取 1024 还是 1000、单位显示 MB 还是 KB，都由系统按用户所在地区的习惯决定，
    /// 自己定一套只会跟系统别处的数字对不上。
    var sizeText: String {
        guard size > 0 else { return "" }
        return UpdateFormat.bytes.string(fromByteCount: Int64(size))
    }

    /// 发布日期（"10月31日"）；拿不到给空串。
    ///
    /// 服务端给的是**带毫秒的 ISO 串**（`"2026-10-31T…"`），这里切前 10 位按字符串格式化，
    /// **不转 `Date` 再格式化** —— 转一次就会被设备时区把 31 号漂成 30 号
    /// （与 `Formatters.versionDateText` / `MonitorAppVersion` 同一条纪律）。
    var publishedText: String {
        guard publishedAt.count >= 10 else { return "" }
        return Formatters.versionDateText(String(publishedAt.prefix(10)))
    }

}

/// `AppRelease` 的展示格式化器（包大小）。
///
/// 与 `Formatters` 分开的理由：`Formatters` 在 `Sources/Shared`（Widget target 也编译它），
/// 而云控更新只服务主 App —— 把一个只有一处用到的 formatter 塞进共享命名空间，
/// 等于让 Widget 也背上它。
private enum UpdateFormat {

    /// 只在文件与包大小的档位里用，限制成 MB / KB 两个单位（不显示 "2,122,911 bytes"）
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useKB]
        return formatter
    }()
}

// MARK: - 状态源

/// 云控更新的唯一状态源（设计文档 §4.6）。
///
/// 只做四件事：拉一次版本接口、比 build、决定要不要弹层、记住「这个 build 用户点了稍后」。
///
/// **失败必须静默**：更新提示是附加功能，站点挂掉、KV 不可用、断网，都不许影响用 App
/// —— 所以 `.failed` 只是监控页那一行改个文案，不弹 alert、不占用 `ToastStore`
/// （那条通道留给「记账成功」「登录过期」这类需要用户反应的事）。
@MainActor
final class UpdateStore: ObservableObject {

    /// 检查状态机
    enum CheckState {
        /// 还没查过（首装，或上一次请求被取消）
        case idle
        /// 请求在飞
        case checking
        /// 远端 build ≤ 本机，或站点一次都没发布过
        case upToDate
        /// 远端 build > 本机，有可安装的新版本
        case available(AppRelease)
        /// 检查失败（网络 / 4xx / 5xx / 解码）
        case failed
    }

    static let shared = UpdateStore()

    /// 前台闸门（秒）。理由见 `check(force:)` 的注释
    static let checkInterval: TimeInterval = 6 * 3600

    /// 冷启动这一次延后多少秒再发。理由见 `checkIfNeeded()` 的注释
    static let launchDelay: TimeInterval = 3

    /// 「立即检测」的客户端限频（秒，3.9.0）。理由见 `checkNow()` 的注释。
    private static let forceGate: TimeInterval = 60

    /// 落盘键（改这里的后缀 = 让所有人的闸门重新计一次，只会多一次请求，不会出错）
    private static let keyLastCheck = "appUpdate.lastCheckAt"
    /// 「稍后」记忆键（3.9.0 从 `appUpdate.dismissedBuild`（Int）换成发布标识（String，"build|version"））。
    ///
    /// 为什么换：同 build 重发一个新版本名是服务端的合法操作，旧记忆（只记 build）
    /// 会把重发后的新弹层也压住 —— 用户永远看不到重发的内容。改成"build|version"
    /// 之后，重发（version 变了）= 新的发布 = 自动弹层恢复。
    ///
    /// **旧 Int 键刻意不迁移**：直接换 key 等价于"重置一次稍后记忆"，最坏情况只是
    /// 对老用户多自动弹一次他点过稍后的版本，不会出错；写迁移逻辑反而多一条会坏的路
    /// （读写两个 key、版本判断、脏值清理），收益撑不起复杂度。
    private static let keyDismissedRelease = "appUpdate.dismissedRelease"

    // MARK: 对外只读状态

    @Published private(set) var state: CheckState = .idle

    /// 最近一次查到的可用更新。**失败时不清空** —— 下次进来还能看到上次的说明，
    /// 用户也不至于因为一次断网就丢掉「有个新版可以装」这件事。
    @Published private(set) var release: AppRelease?

    /// 非 nil 时弹出更新层，由 `FFWangApp` 的 `.sheet(item:)` 消费。
    ///
    /// 对外**只应写 nil**（= 关闭弹层）；要弹请用 `present()` ——
    /// 让「决定弹不弹」的判断只有一处（同一个 build 被「稍后」过就不再自动弹）。
    @Published var presentedRelease: AppRelease? = nil

    /// 唤起全能签失败时置 true（弹层里补一行「去看安装步骤」的入口）。
    /// 用状态位而不是直接跳转：跳出去之后用户还会回来，那时得有东西可点。
    @Published private(set) var needsInstallGuide: Bool = false

    /// 当前可用更新是否为**强制**（3.9.0，远程配置的 `minBuild` 高于本机 build）。
    /// true 时 `UpdateSheet` 隐藏「稍后」、右上角关闭与下滑手势都不可用。
    /// 随每次成功检查重新评估：远端把 minBuild 撤掉后，下一次检查自然回到可关闭。
    @Published private(set) var isForced: Bool = false

    // MARK: 依赖

    private let client: APIClient
    private let defaults: UserDefaults
    /// 冷启动那一次已经排过队了（`.task(id: scenePhase)` 在冷启动时也会跑一次，
    /// 别让"启动检查"和"前台检查"变成两个独立入口）
    private var didLaunchCheck: Bool = false
    /// 上一次「立即检测」的时刻。**只放内存、不落盘**：这是防连点的软闸，
    /// 冷启动清零毫无影响（用户重启 App 后多点一次请求，天塌不下来）。
    private var lastForcedAt: Date?

    nonisolated init(client: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    // MARK: 派生

    /// 距上次**成功**检查是否已满 6 小时（闸门是否打开）。
    ///
    /// ## 为什么前台检查要去重（不能每次回前台都查）
    /// 1. **打扰**：App 切一次前台就打一次接口，一天几十次；更糟的是"有新版本"弹层会
    ///    **反复出现** —— 用户每次切回来都被劝一次装更新。`dismissedBuild` 只能压住
    ///    "自动弹"，压不住"每切一次就被打扰一次"。
    /// 2. **无收益**：服务端 `latest` 一天最多变一两次，6 小时取一次与 5 分钟取一次
    ///    在"用户能不能及时知道"上没有可感知差别（接口自己还带 60s 缓存）。
    /// 3. **有成本**：每次都是一次完整 TLS 握手 + 一次 KV 读。
    var isDue: Bool {
        guard let last = lastCheckedAt else { return true }
        return Date().timeIntervalSince(last) >= Self.checkInterval
    }

    /// 手动按钮现在点下去**会不会真发请求**。不会就把按钮置灰
    /// —— 点了个寂寞不如明确告诉用户"刚查过"。
    ///
    /// 3.9.0 起「检查更新」改走 `checkNow()`（跳过 6 小时闸门的真·立即检测），
    /// 所以这里的闸从 6 小时换成 60 秒客户端限频（`forceGate`）。
    var canCheckNow: Bool {
        switch state {
        case .checking:
            return false
        case .failed:
            // 失败不写检查时间，所以重试永远是真重试（闸门对它不生效）
            return true
        case .idle, .upToDate, .available:
            guard let last = lastForcedAt else { return true }
            return Date().timeIntervalSince(last) >= Self.forceGate
        }
    }

    /// 本机版本（"3.8.0 (14)"），监控页那一行用
    var currentVersionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        return version + " (" + build + ")"
    }

    // MARK: 检查入口

    /// 三个**自动**时机（冷启动 / 进监控页 / 回前台）的统一入口。
    ///
    /// 只有冷启动这一次延后 3 秒：首屏同时要拉简报 / 天气 / 红石排期，
    /// 更新检查不该跟它们抢连接 —— 而它晚 3 秒没有任何人会发现。
    /// 之后每次回前台直接走 6 小时闸门，不再睡。
    func checkIfNeeded() async {
        if !didLaunchCheck {
            didLaunchCheck = true
            do {
                try await Task.sleep(for: .seconds(Self.launchDelay))
            } catch {
                // 退后台 / 场景切换会取消这个 task，此时不该继续往下发请求
                return
            }
        }
        await check()
    }

    /// 真发一次 `GET /api/app/version`。
    ///
    /// - Parameter force:
    ///   - `false`（默认）：先过 6 小时闸门。自动时机与「检查更新」按钮都走这条路，
    ///     所以**连点按钮只有第一次真发请求**（设计文档 §5 T7 验收第 5 条）。
    ///   - `true`：跳过闸门，只有「重试」用 —— 失败不写检查时间，
    ///     如果重试还被闸门挡住，那个按钮就永远点不动了。
    func check(force: Bool = false) async {
        // 上一发还在飞：直接返回，不叠加请求
        if case .checking = state { return }
        if !force, !isDue { return }

        state = .checking

        guard let url = Endpoint.url(base: Endpoint.briefBase, path: Endpoint.appVersionPath) else {
            // 地址拼错是代码问题，不该表现为"有更新"之外的任何东西
            state = .failed
            return
        }

        do {
            let envelope = try await client.get(url, as: AppVersionEnvelope.self)
            apply(envelope)
        } catch let error as APIError where error.isCancelled {
            // 退后台 / 页面销毁造成的取消是正常行为，下一次前台会再查；
            // 写成 `.failed` 会让用户看到一次根本没发生过的失败
            state = .idle
        } catch {
            state = .failed
        }
    }

    /// 真·立即检测（3.9.0，监控页「检查更新」按钮）。
    ///
    /// 与 `check(force: true)` 的区别：自带 **60 秒客户端限频**（`forceGate`）。
    /// 为什么是 60 秒：版本接口自带 `Cache-Control: max-age=60` —— 60 秒内重复点，
    /// 拿到的都是同一份边缘缓存，请求发出去了也白发；限在客户端还能省一次 TLS 握手。
    /// `check(force:)` 的既有语义（**重试用**，失败不受闸门）保持不变，本方法不碰它。
    ///
    /// - Returns: 是否真的发起了检查。`false` = 60 秒内重复点击被拦（调用方给瞬时反馈）。
    @discardableResult
    func checkNow() async -> Bool {
        // 上一发还在飞：算被拦（UI 那一格本来就转着圈，不需要反馈）
        if case .checking = state { return false }
        if let last = lastForcedAt, Date().timeIntervalSince(last) < Self.forceGate {
            return false
        }
        lastForcedAt = Date()
        await check(force: true)
        return true
    }

    // MARK: 弹层

    /// 手动打开更新层（监控页那一行 /「查看更新」）
    func present() {
        guard let release = release else { return }
        needsInstallGuide = false
        presentedRelease = release
    }

    /// 「稍后」：关掉弹层 + 记住这个发布（"build|version"）不再自动弹。
    ///
    /// 与右上角关闭是**同一个 dismiss**（都是把 `presentedRelease` 写 nil），
    /// 只是多记一笔「用户已经看过这一版并且选择不装」。
    /// 同 build 重发新版本名后 key 对不上 → 自动弹层恢复（见 `keyDismissedRelease` 的注释）。
    func snooze() {
        if let release = release {
            defaults.set(dismissalKey(for: release), forKey: Self.keyDismissedRelease)
        }
        presentedRelease = nil
    }

    /// 让全能签去装这个版本。装不了（没装全能签）就落到安装引导页
    func install() {
        guard let release = release else { return }
        // 闭包**显式**写成 `onFallback:` 而不是尾随闭包：这个参数是 `@escaping` 的
        // 逃逸闭包，写出来更不容易被误读成"install 的收尾动作"
        UpdateInstaller.install(ipaPath: release.ipaPath, onFallback: { [weak self] in
            // 先置状态位、再跳：跳去 Safari 之后用户还会回来（那时弹层还在），
            // 得留一个"打开安装引导页"的按钮给他 —— 状态位就是那个按钮的开关。
            self?.needsInstallGuide = true
            // 同一个动作里立刻跳引导页，不要让用户再点一次。
            // **沉默是 bug 的第一嫌疑人**：主按钮点下去屏幕毫无变化，用户只会读成
            // "这个按钮坏了"，而不是"它悄悄换了个方案"。一个动作必须完成闭环。
            self?.openInstallGuide()
        })
    }

    /// 打开站点的安装引导页（弹层里那行「去看安装步骤」）
    func openInstallGuide() {
        UpdateInstaller.openInstallGuide()
    }

    // MARK: 内部

    /// 本机 build 号（`CFBundleVersion`）。
    ///
    /// ## 为什么只比 build 不比 version 字符串
    /// 1. **字符串比较会被字典序骗**：`"3.10.0" < "3.9.0"` 为真，于是 3.9 之后
    ///    的每一个版本都"不比本机新"，更新提示从此永久失效 —— 而且不报错、很难发现。
    /// 2. **本地拿到的未必是干净的版本号**：可能是 `"3.7.0 (13)"` 这种拼串，根本没有可比性。
    /// 3. **服务端保证了单调**：发布接口对 `build < 当前 latest.build` 返回 `400 build_regression`，
    ///    所以远端 build 单调不减，App 侧只需要一个 `>`。
    ///
    /// 读不到（缺 key / 非数字）返回 nil → 调用方按「已是最新」处理：
    /// 宁可漏一次提示，也不弹一个自己都拿不准的更新。
    private var localBuild: Int? {
        guard let raw = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else { return nil }
        return Int(raw)
    }

    /// 本机版本名（`CFBundleShortVersionString`，如 "3.9.0"）。3.9.0 新增。
    ///
    /// **只在 build 相等时**参与比较（见 `apply` 的第二段推导）—— build 是主键，
    /// 版本名只是同 build 重发场景下的"再来一次"判据，不是另一条比较通道。
    /// 读不到（缺 key / 空串）返回 nil → 按"只比 build"处理，宁可不弹拿不准的。
    private var localVersion: String? {
        guard let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 最近一次**成功**检查的时刻。落盘而不是放内存：
    /// 6 小时闸门要跨启动生效（否则每次冷启动都必查一次，那"冷启动一次"就成了"每次启动都查"）。
    var lastCheckedAt: Date? {
        let raw = defaults.double(forKey: Self.keyLastCheck)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    /// 被「稍后」过的发布标识（"build|version"）。空串 = 没有。
    private var dismissedReleaseKey: String {
        return defaults.string(forKey: Self.keyDismissedRelease) ?? ""
    }

    /// 「稍后」记忆键的值：发布标识（与 `AppRelease.id` 同一格式，语义也同一件事）
    private func dismissalKey(for release: AppRelease) -> String {
        return "\(release.build)|\(release.version)"
    }

    private func markChecked() {
        defaults.set(Date().timeIntervalSince1970, forKey: Self.keyLastCheck)
    }

    private func apply(_ envelope: AppVersionEnvelope) {
        // 业务失败（HTTP 200 + `ok:false`）：不写检查时间，下一次机会立刻重试，
        // 而不是被闸门挡 6 小时
        guard envelope.ok else {
            state = .failed
            return
        }

        // 站点一次都没发布过 → 不是错误，就是"没有更新"
        guard let latest = envelope.latest else {
            release = nil
            state = .upToDate
            markChecked()
            return
        }

        guard let local = localBuild else {
            release = nil
            state = .upToDate
            markChecked()
            return
        }

        // ## 为什么 build 是主键（原文保留）
        // 1. **字符串比较会被字典序骗**：`"3.10.0" < "3.9.0"` 为真，于是 3.9 之后
        //    的每一个版本都"不比本机新"，更新提示从此永久失效 —— 而且不报错、很难发现。
        // 2. **本地拿到的未必是干净的版本号**：可能是 `"3.7.0 (13)"` 这种拼串，根本没有可比性。
        // 3. **服务端保证了单调**：发布接口对 `build < 当前 latest.build` 返回 `400 build_regression`，
        //    所以远端 build 单调不减，App 侧只需要一个 `>`。
        //
        // ## 为什么同 build 还要比一次版号（3.9.0 放宽）
        // 服务端只拒 `build < latest`（400 build_regression），**同 build 重发是合法操作**
        // —— 管理页对同一个 build 改了版本名 / 说明后重新发布，就是用户遇到的场景：
        // 手机上装的就是这个 build，只比 build 会永远判定"已是最新"，重发的内容到不了用户手里。
        // 所以：build 严格大于 → 有更新；build 相等且本机读得到版本名、与远端不同 → 也算有更新。
        // 版本名读不到（`localVersion` 为 nil）时退回"只比 build"：
        // 宁可不弹，也不弹一个自己都拿不准的更新（与 localBuild 的兜底同一条纪律）。
        let isUpdateAvailable: Bool
        if latest.build > local {
            isUpdateAvailable = true
        } else if latest.build == local, let localVersion = localVersion {
            isUpdateAvailable = latest.version != localVersion
        } else {
            isUpdateAvailable = false
        }

        guard isUpdateAvailable else {
            release = nil
            isForced = false
            state = .upToDate
            markChecked()
            return
        }

        release = latest
        state = .available(latest)
        // 强更门槛（3.9.0）：远程配置给了 minBuild 且本机 build 低于它 → 弹窗不可关闭。
        // 耦合方向只有一条：UpdateStore 读 RemoteConfigStore（配置是更新判定的输入之一），
        // 反向禁止 —— RemoteConfigStore 不引用 UpdateStore，避免成环。
        // 配置还没拉到（冷启动竞速）时按"非强制"处理，下一次检查会重新评估。
        if let minBuild = RemoteConfigStore.shared.latest?.values?.minBuild {
            isForced = local < minBuild
        } else {
            isForced = false
        }
        markChecked()
        // 已经被「稍后」过的同一个发布（build + 版本名）不再自动弹：用户已经做过这个决定，
        // 再弹就是拿"我们觉得你该装"覆盖"你说过先不装"。同 build 重发新版本名 = 新的 key
        // = 用户还没见过 = 自动弹恢复。
        if dismissalKey(for: latest) != dismissedReleaseKey {
            presentedRelease = latest
        }
    }
}
