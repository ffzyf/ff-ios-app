import Combine
import CoreLocation
import Foundation

/// 定位偏好的持久化键与常量。
///
/// **为什么放在 `@MainActor` 类外面**：`@MainActor` 类型的 `static let` 本身是隔离的，
/// `nonisolated init()` 里引用不了（`SunEventSettings` 当初独立成一个小 enum 是同一个原因）。
/// 这个 type 没有隔离，`init` 与主 actor 上的方法都能读。
enum WeatherLocationSetting {

    /// 设置里「用我的位置」的开关。**没设置过 = 关闭**（`UserDefaults.bool` 的缺省值就是 false）
    static let enabledKey = "weather.useLocation"

    /// 上次定位到的纬度 / 经度（度）
    static let latKey = "weather.lat"
    static let lonKey = "weather.lon"

    /// 上次定位的时刻。与上面两个坐标一起构成缓存的有效期判定
    static let fixedAtKey = "weather.fixedAt"

    /// 缓存有效期：6 小时。
    ///
    /// 天气按公里级网格、小时级粒度算，位置不需要"实时"。6 小时的意义是：
    /// 早上出门打开 App 定一次，中午、下午再打开直接用缓存，一天最多定位一两次。
    static let cacheLifetime: TimeInterval = 6 * 60 * 60
}

/// 设备定位的唯一状态源 —— 只服务一件事：让天气接口带上用户当前所在坐标。
///
/// 对外只有三样东西：`status`（开关 + 权限的综合状态）、`coordinate`（可用的坐标，可能为 nil）、
/// `isEnabled`（用户偏好）。谁需要坐标谁自己读，本类不发请求、不认识天气。
///
/// ## ① 为什么默认关闭
/// 定位是最敏感的一类权限。一装就弹框，等于在用户还不知道有天气卡片时就先要位置 ——
/// 拒绝率极高，而**一旦拒绝就回不去了**（之后只能去系统设置里翻）。所以默认 `false`：
/// 用户主动在「设置 → 天气」里打开，才第一次请求「使用期间」权限。
///
/// ## ② 为什么不用 `startUpdatingLocation`
/// 持续定位会持续耗电，并在状态栏常驻定位箭头。而这个 App 一天只关心一次天气 ——
/// 一次性的 `requestLocation()` 拿到一个点就结束，与需求同一量级。
/// 同理**不申请** Always 权限、**不开** `allowsBackgroundLocationUpdates`：
/// 后台定位既不是这个功能需要的，也会平白拖出审核问题。
///
/// ## ③ 已知限制：小组件拿不到这份坐标（不是 bug）
/// 桌面小组件跑在独立进程里，读不到本 App 的 `UserDefaults`（无 App Group，
/// 无签名 CI 也开不了 App Group）。所以小组件始终用服务端默认坐标，
/// 只有 App 内的天气卡片会跟着用户走。设置页的脚注把这条写给了用户。
///
/// ## ④ 为什么协议前面有 `@preconcurrency`（3.7.0 修）
/// `CLLocationManagerDelegate` 是 ObjC 协议，它的 requirement 全是 nonisolated；而本类是
/// `@MainActor`，那几个 delegate 方法是隔离到主 actor 的 witness。Swift 5 minimal 并发检查下，
/// 这种"隔离的 witness 去满足 nonisolated requirement"正好落在会被判成不满足的缝里 ——
/// 报错落在 `delegate = self` 那一行，指不到真正的原因。
///
/// 而这条历史约定是明确的：`CLLocationManager` **只在创建它的 runloop 回调 delegate**，
/// 本类的 `manager` 只在主 actor 上懒创建，所以 delegate 一定在主线程回来。
/// `@preconcurrency` 就是把这条约定写成"我知道这个协议当年没有并发标注，我保证在主线程满足它"，
/// 编译期不再追这条 witness 的隔离；运行时语义与今天完全一样（本来就在主线程）。
///
/// **不要**换成 `nonisolated` + `MainActor.assumeIsolated`：那会把 4 个 delegate 方法体都改成
/// 一段"假设自己在主线程"的闭包，其中任何一个在新的回调路径上假设错了就是运行时崩溃 ——
/// 用一行标注换掉这个陷阱，代价只是"编译器不再帮你查这一处"。
@MainActor
final class LocationStore: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {

    // MARK: - 对外状态

    /// 定位的当前处境。UI 只该按它选文案，不要自己再判权限。
    ///
    /// - `off`：用户把开关关了（或从来没开过）。此时**一定**不传坐标。
    /// - `asking`：正在等权限回应 / 等定位结果。
    /// - `ready`：`coordinate` 有值且可信。
    /// - `denied`：系统里权限是拒绝 / 受限。开关仍然可点（用户可能刚去系统设置打开），
    ///   但这里如实报告 `.denied`，按"不传坐标"处理。
    /// - `failed`：有权限但这次没拿到位置（室内、飞行模式、刚启动）。
    enum Status: Equatable {
        case off
        case asking
        case ready
        case denied
        case failed
    }

    /// 全 App 唯一实例。与 `MonitorStore` / `ToastStore` 一样用单例：
    /// 定位是设备级状态，多份实例只会出现"两份坐标不同步"。
    static let shared = LocationStore()

    /// 用户开着开关、且坐标可用时为非 nil。**唯一**允许拼进天气请求的东西
    @Published private(set) var coordinate: CLLocationCoordinate2D?

    /// 与 `coordinate` 配对的状态，见 `Status` 的逐项说明
    @Published private(set) var status: Status

    // MARK: - 内部状态

    private let defaults: UserDefaults

    /// 懒创建真正的 `CLLocationManager`。
    ///
    /// `nonisolated init` 里不能碰 `self`（设 delegate 需要 self），所以实例化推迟到
    /// 第一次在主 actor 上用到它时。这样"用户从没打开过开关"就等于**从来没创建过 manager**，
    /// 连系统级的定位初始化都省了。
    private var managerStorage: CLLocationManager?

    private var manager: CLLocationManager {
        if let existing = managerStorage { return existing }
        let created = CLLocationManager()
        created.delegate = self
        // 天气按公里级网格算，米级精度既是白费电，也会多弹一次「精确定位」的追问
        created.desiredAccuracy = kCLLocationAccuracyKilometer
        managerStorage = created
        return created
    }

    // MARK: - 构造

    /// 为什么是 `nonisolated`：与 `SurveyStore` / `ScrollLightStore` 同一条纪律 ——
    /// View 的属性初始化器在 Swift 5 的 minimal 并发检查下不保证是隔离上下文。
    /// 本 init 只做两件事：读缓存、初始化两个 `@Published` 的底层存储，都不需要主 actor。
    ///
    /// 为什么还要 `override`（3.7.0 首次编译报错的一处）：本类是 `NSObject` 子类，
    /// `NSObject` 自带 `init()`，所以这里的 `init()` 不是"新声明"而是**覆盖**父类的那个。
    /// 漏掉 `override` 就是 `error: overriding declaration requires an 'override' keyword`。
    /// 注意 `nonisolated` 与 `override` **不能**调换语义：父类的 `init()` 是 nonisolated 的，
    /// 写了 `override init()` 却让 init 继承类上的 `@MainActor`，等于用隔离的声明去覆盖非隔离的，
    /// 那是另一类编译错误。所以两个修饰符都要，且必须在同一行。
    nonisolated override init() {
        let defaults = UserDefaults.standard

        // 缓存还原：开关开着 + 坐标存在 + 6 小时内 → 直接可用，避免每次冷启动都定位一次。
        // 过期（或开关已关）就当没有：不后台补定位，等下次打开 App 由 `refreshIfNeeded()` 重取。
        var restored: CLLocationCoordinate2D?
        if defaults.bool(forKey: WeatherLocationSetting.enabledKey),
           let lat = defaults.object(forKey: WeatherLocationSetting.latKey) as? Double,
           let lon = defaults.object(forKey: WeatherLocationSetting.lonKey) as? Double,
           let fixedAt = defaults.object(forKey: WeatherLocationSetting.fixedAtKey) as? Date,
           Date().timeIntervalSince(fixedAt) < WeatherLocationSetting.cacheLifetime {
            let candidate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            if CLLocationCoordinate2DIsValid(candidate) {
                restored = candidate
            }
        }

        self.defaults = defaults
        _coordinate = Published(initialValue: restored)
        _status = Published(initialValue: restored == nil ? .off : .ready)
        super.init()
    }

    // MARK: - 偏好

    /// 设置里的「用我的位置」开关。读 `UserDefaults`，写走 `setEnabled(_:)`（两者等价，
    /// 写入口收拢到一个方法上，是为了"关掉时必须顺手清坐标"这件事只有一处实现）。
    var isEnabled: Bool {
        get { defaults.bool(forKey: WeatherLocationSetting.enabledKey) }
        set { setEnabled(newValue) }
    }

    /// 开关动作。
    ///
    /// - 打开：已授权 → 立刻请求一次定位；未决定 → 弹「使用期间」权限框；
    ///   已拒绝 → 只把状态记成 `.denied`（**不再弹任何东西**，也不会重复申请）。
    /// - 关闭：坐标与落盘缓存一起清掉，状态回 `.off`。
    ///   清缓存是刻意的：用户关掉之后，位置数据不该以任何形式（包括下一次启动的还原）继续生效。
    func setEnabled(_ on: Bool) {
        defaults.set(on, forKey: WeatherLocationSetting.enabledKey)
        guard on else {
            reset()
            return
        }
        requestPermissionOrLocation()
    }

    /// 启动时补一次：**已启用且缓存过期**才真正定位，其余情况纯短路（不会弹权限框）。
    ///
    /// 只该挂在进入 App 的 `.task` 上 —— 这是"一天关心一次"的频率，
    /// 放进按帧 / 按秒的路径会变成耗电大户。
    func refreshIfNeeded() {
        guard isEnabled else {
            reset()
            return
        }
        if coordinate != nil, hasFreshCache {
            status = .ready
            return
        }
        requestPermissionOrLocation()
    }

    // MARK: - CLLocationManagerDelegate

    /// 权限变化（含首次设 delegate 时的一次回调）。授权了就请求一次定位。
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // 开关没开：无论系统里是什么权限，都不该让这里悄悄变成 ready
        guard isEnabled else {
            status = .off
            return
        }

        // 用**实例属性** `manager.authorizationStatus`（iOS 14+ 的写法）。
        // 类方法 `CLLocationManager.authorizationStatus()` 已废弃，不要用。
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            status = .asking
            // 一次性定位，不是 startUpdatingLocation（理由见类型注释 ②）
            manager.requestLocation()
        case .denied, .restricted:
            dropCoordinate()
            status = .denied
        case .notDetermined:
            // 用户还没回应：保持等待，不重复申请（重复调用不会再弹框，但语义上没必要）
            status = .asking
        @unknown default:
            status = .failed
        }
    }

    /// 拿到位置：取最后一个（`locations` 是按时间升序的数组，最后一个最新）。
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 用户已经关掉开关，而这一发请求还在路上：结果直接丢弃，不写状态
        guard isEnabled else { return }
        guard let latest = locations.last else { return }

        let next = latest.coordinate
        // (0, 0) 与非法值一律当作"没拿到"：CoreLocation 刚开始时偶尔会先给一个空坐标，
        // 拿它去请求天气，用户会看到大西洋上的天气 —— 那比"没有天气"糟得多
        guard CLLocationCoordinate2DIsValid(next),
              !(next.latitude == 0 && next.longitude == 0) else {
            status = .failed
            return
        }

        coordinate = next
        persist(next, at: Date())
        status = .ready
    }

    /// 定位失败：**已有坐标时什么都不做**，保留上一次的位置。
    /// 天气卡片是装饰性信息，不该因为一次"暂时定位不到"就偷偷退回默认城市。
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard coordinate == nil else { return }
        status = .failed
    }

    // MARK: - 私有

    /// 按当前授权状态决定"申请权限"还是"直接定位"。两个入口（用户切开关 / 权限变化）共用。
    private func requestPermissionOrLocation() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            status = .asking
            manager.requestLocation()
        case .notDetermined:
            status = .asking
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            dropCoordinate()
            status = .denied
        @unknown default:
            status = .failed
        }
    }

    /// 落盘缓存是否还在 6 小时有效期内
    private var hasFreshCache: Bool {
        guard let fixedAt = defaults.object(forKey: WeatherLocationSetting.fixedAtKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(fixedAt) < WeatherLocationSetting.cacheLifetime
    }

    /// 关掉开关：内存与落盘一起清，状态回 `.off`
    private func reset() {
        dropCoordinate()
        status = .off
    }

    /// 只清坐标（内存 + 落盘），不动 `status`
    private func dropCoordinate() {
        coordinate = nil
        defaults.removeObject(forKey: WeatherLocationSetting.latKey)
        defaults.removeObject(forKey: WeatherLocationSetting.lonKey)
        defaults.removeObject(forKey: WeatherLocationSetting.fixedAtKey)
    }

    private func persist(_ coordinate: CLLocationCoordinate2D, at date: Date) {
        defaults.set(coordinate.latitude, forKey: WeatherLocationSetting.latKey)
        defaults.set(coordinate.longitude, forKey: WeatherLocationSetting.lonKey)
        defaults.set(date, forKey: WeatherLocationSetting.fixedAtKey)
    }
}
