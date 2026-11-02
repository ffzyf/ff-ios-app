import Combine
import CoreLocation
import Foundation
import WidgetKit

/// 定位偏好的持久化键与常量。
///
/// **为什么放在 `@MainActor` 类外面**：`@MainActor` 类型的 `static let` 本身是隔离的，
/// `nonisolated init()` 里引用不了（`SunEventSettings` 当初独立成一个小 enum 是同一个原因）。
/// 这个 type 没有隔离，`init` 与主 actor 上的方法都能读。
enum WeatherLocationSetting {

    /// 设置里「用我的位置」的开关。**没设置过 = 关闭**（`UserDefaults.bool` 的缺省值就是 false）
    static let enabledKey = "weather.useLocation"

    /// 定位模式（3.26.0）：`follow` 跟随设备 / `fixed` 用户指定城市
    static let modeKey = "weather.locationMode"

    /// `fixed` 模式下的城市名与坐标（3.26.0）。
    ///
    /// 与下面的 `latKey` / `lonKey` **分开存**是刻意的：那一对是"设备上一次定到的位置"，
    /// 冷启动时会被 `WeatherStore.restoreFromDisk` 拿去校验盘上那份天气属不属于这里。
    /// 指定城市一旦混进同一对键，"取消指定 → 回到跟随定位"的第一帧就会拿一个
    /// 用户从没去过（也不需要去过）的坐标去比，盘上的天气被无端作废一次；
    /// 更糟的是 `init` 会把它当成"设备就在这里"，把定位这件事整个跳过。
    static let fixedNameKey = "weather.fixedName"
    static let fixedLatKey = "weather.fixedLat"
    static let fixedLonKey = "weather.fixedLon"

    /// 上次定位到的纬度 / 经度（度）
    static let latKey = "weather.lat"
    static let lonKey = "weather.lon"

    /// 上次定位的时刻。与上面两个坐标一起构成缓存的有效期判定
    static let fixedAtKey = "weather.fixedAt"

    /// 缓存有效期：6 小时。
    ///
    /// **3.26.0 起它只管一件事**：冷启动时能不能直接把盘上那个坐标拿来用
    /// （见 `LocationStore.init` 的还原逻辑）。它**不再**是"要不要重新定位"的闸门 ——
    /// 那条闸门是下面的 `reFixInterval`。
    /// 为什么必须拆开：原来的实现拿 6 小时判"要不要重新定位"，于是人从郑州开车到登封
    /// （一小时），App 全程认为"6 小时内，不用动"，天气、温度、降雨一直是郑州的。
    static let cacheLifetime: TimeInterval = 6 * 60 * 60

    /// 重定位间隔：15 分钟。
    ///
    /// 取值是三件事的交点：
    /// 1. **跟得上移动** —— 郑州 ↔ 登封 车程约 1 小时，15 分钟内必然跟上；
    /// 2. **不白耗电** —— 每次只 `requestLocation()` 一个点就停（见类型注释 ②），
    ///    单次成本是几十毫秒 GPS + 一发反查，15 分钟一次在一天的耗电里看不出来；
    /// 3. **不比天气本身更勤** —— 天气按小时级更新，定位比天气勤太多没有意义。
    static let reFixInterval: TimeInterval = 15 * 60

    /// 两次定位请求之间的最短间隔（秒）。
    ///
    /// 前台每切回来一次都会调 `refreshIfNeeded()`（`FFWangApp` 的 `scenePhase` task）。
    /// 没有这道闸门，用户"切出去看眼地图又切回来"的循环会把 GPS 反复唤醒 ——
    /// 那是纯浪费，因为几秒钟内位置不可能变得有意义。
    static let requestCooldown: TimeInterval = 60

    // MARK: - 地名（"这里是哪"，3.16.0）

    /// 反查出来的两级地名（"上海市 · 浦东新区"）
    static let placeNameKey = "weather.placeName"
    /// 这个地名对应的纬度 / 经度。
    ///
    /// 单独存一份（不复用 `latKey` / `lonKey`）的理由：地名是**异步**反查来的，
    /// 可能比坐标晚几秒落盘，也可能失败（此时旧地名要留着）。冷启动还原时只有
    /// "地名 + 它自己的那对坐标"能证明"这条地名说的就是这条坐标"——
    /// 拿主坐标去比，会出现"坐标刚刷新、地名还是上一座城市的"。
    static let placeLatKey = "weather.placeLat"
    static let placeLonKey = "weather.placeLon"

    /// 判定"还是同一个地方"的经纬度容差（度）。
    ///
    /// 0.02° ≈ 2.2km：天气网格是公里级的，这个范围内同一个地名（同一个区）不会变，
    /// 不值得再打一次反查接口（那是有配额的商业接口，且每次都是一次网络往返）。
    static let placeTolerance: Double = 0.02
}

/// 天气位置从哪儿来（3.26.0）。
///
/// 与 `WeatherLocationSetting` 一样放在 `@MainActor` 类**外面**：`LocationStore.init()`
/// 是 `nonisolated` 的，类上的嵌套枚举对它来说是隔离的（和 `static let` 同一个坑）。
enum LocationMode: String {

    /// 跟着设备走（默认）。移动超过 `WeatherLocationSetting.placeTolerance` 就重新取天气
    case follow

    /// 用户指定了城市。设备动到哪儿都不影响天气，也不再周期性发定位请求 ——
    /// 用户已经明确回答了"我要看哪儿的天"，再定位就只是耗电，且会让顶栏地名
    /// 在他自己的选择上跳来跳去。
    case fixed
}

/// 设备定位的唯一状态源 —— 主要服务一件事：让天气接口带上用户当前所在（或指定）的坐标。
///
/// 对外的东西分三类：
/// · **偏好**：`isEnabled`（要不要读设备位置）、`mode` / `setFixed` / `clearFixed`（看哪儿的天）；
/// · **结果**：`status`、`coordinate`、`placeName`、`fixedName`、`lastFixedAt`；
/// · **合并后的答案**（UI 与天气一律读这两个）：`effectiveCoordinate`（坐标）、`displayName`（地名）。
///
/// 谁需要坐标谁自己读，不要各自拼优先级 —— 优先级只有一处定义（见 `effectiveCoordinate`）。
/// 本类**不发天气请求**，只在"位置真的变了"时通知三个 Store 去重取（见 `refreshWeatherSources`），
/// 因为那个时机只有它知道。
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
/// ## ③ 与桌面小组件的一致性（3.17.0 首次尝试，3.17.0 改用单条记录）
/// 桌面小组件跑在独立进程里，读不到本 App 的 `UserDefaults`（无 App Group，无签名 CI 也开不了）。
/// 3.16.0 及之前的结果是：App 显示上海、小组件显示服务端默认的郑州 —— 用户原话
/// 「app和小组件天气和可见度都应该在同一个地区啊！」。
///
/// 现在靠**服务端中转**对齐：定位一拿到就把坐标 `POST /api/app/home`，地名反查成功后再补报一次
/// （带上 name），小组件 `GET` 同一条记录。服务端只存**一条**「当前位置」，两端读写同一条，
/// 因此不需要任何设备标识 —— 见 `Shared/Domain/HomeCoordinate.swift` 里「为什么不需要设备标识」。
/// （3.17.0 曾用 IDFV 当设备键，侧载安装下两端推导出的值不同，
/// App 报的坐标小组件永远读不到，且完全静默 —— 这条路不要再走。）
/// 上报有节流（2km / 6h / name 变化放行，见 `publishHome`），失败不推进节流。
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
///
/// ## ⑤ 位置要跟着人走（3.26.0）
/// 3.25.0 及之前，`refreshIfNeeded()` 用 6 小时的缓存有效期当"要不要重新定位"的闸门，
/// 于是人从郑州开车到登封，App 全程认为"6 小时内不用动"，天气、温度、降雨一直是郑州的；
/// 而 `refreshIfNeeded()` 只挂在 `RootView` 的 `.task` 上，一次启动只跑一次 ——
/// 前台切回来也不会重新定位。
///
/// 现在有两条路：
/// 1. **跟随模式**（默认）：`reFixInterval`（15 分钟）到了就静默重定位；距离超过
///    `placeTolerance` 时顺带强制刷新天气 / 预警 / 分钟降水。回前台也会触发一次。
/// 2. **指定城市**：用户自己选了地方（`setFixed`），设备动到哪儿都不再影响天气。
///    这条路同时是"我就想看老家的天"的唯一出口 —— 没有它，用户只能靠关定位来固定位置，
///    而关定位后天气会回落到 `HomeCoordinate.cached()`，那是个他控制不了的坐标。
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

    /// "这里是哪"的两级地名（"上海市 · 浦东新区"）。
    ///
    /// 为什么由本类持有而不是让 UI 自己反查：反查要跟着坐标走、要防重复请求、
    /// 要落盘缓存、要在用户关掉开关时一起清掉 —— 四件事都是本类的职责范围。
    /// 天光页只读它，不做任何判断。
    ///
    /// nil 有两种含义，UI 要分开表达：**还没反查出来**（开关开着→"定位中…"）、
    /// **开关关着**（→"上次位置 · …"，服务端没有任何记录时才是"默认位置 · 郑州"）。
    @Published private(set) var placeName: String?

    /// 天气位置从哪儿来（3.26.0）。`fixed` 时一切"位置"相关的读取都优先看指定坐标
    @Published private(set) var mode: LocationMode

    /// `fixed` 模式下用户指定的城市名（"登封" / "郑州 · 惠济区"）。
    /// UI 一律通过 `displayName` 读，不要直接读它 —— `follow` 模式下这里恒为 nil。
    @Published private(set) var fixedName: String?

    /// `fixed` 模式下的坐标。与 `fixedName` 同生共死（`setFixed` / `clearFixed` 一起写）
    private var fixedCoordinate: CLLocationCoordinate2D?

    /// 上一次**设备定位成功**的时刻（读 `weather.fixedAt` 还原，`persist` 时同步）。
    ///
    /// 与 `status` 分开的理由：`status == .ready` 只说"有坐标可用"，回答不了
    /// "这个坐标是多久以前的"。而"15 分钟该重新定位了"和设置页的"定位于 N 分钟前"
    /// 都必须要一个时刻。
    @Published private(set) var lastFixedAt: Date?

    // MARK: - 内部状态

    /// 上一次发起定位请求的时刻。防止前台反复切换时把 GPS 反复唤醒
    /// （闸门长度见 `WeatherLocationSetting.requestCooldown`）
    private var lastRequestAt: Date?

    private let defaults: UserDefaults

    /// 地名反查。CoreLocation 自带、无需密钥；同一个实例可以排队复用。
    ///
    /// `CLGeocoder` 不是 `Sendable`，但本类是 `@MainActor`，实例只在这里被创建与使用，
    /// `await` 之后回到主 actor 再赋值 —— 不跨线程共享。
    private let geocoder = CLGeocoder()

    /// 上一次**成功**反查的坐标（用来跳过 2km 内的重复请求）
    private var geocodedCoordinate: CLLocationCoordinate2D?

    /// 反查在飞。`requestLocation()` 偶尔会连着给两三个点，
    /// 没有这个闸门就会连发三次反查（商业接口有配额）。
    private var isResolvingPlace = false

    /// 上一次**上报给服务端**的坐标（`nil` = 还没报成功过）。与 `geocodedCoordinate` 分开：
    /// 那个管"要不要再反查"（2km 容差），这个管"要不要再上报"（2km + 6h + name 未变，全部满足才跳过）。
    /// 只在**上报成功后**才推进（见 `publishHome`）。
    private var lastPublished: CLLocationCoordinate2D?

    /// 上一次上报成功的时刻。与 `lastPublished` 一起构成节流判定 —— 见 `publishHome(_:name:)`。
    private var lastPublishedAt: Date?

    /// 上一次上报成功的**地名**。用来实现「name 变了就放行」这条节流豁免：
    /// 同一座城市里换区（坐标差不到 2km、时间不到 6h，但"浦东新区"→"黄浦区"）必须报得上去，
    /// 否则小组件那边会一直挂着旧区名。
    private var lastPublishedName: String?

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
    /// 本 init 只做两件事：读缓存、初始化那几个 `@Published` 的底层存储，都不需要主 actor。
    ///
    /// 为什么还要 `override`（3.7.0 首次编译报错的一处）：本类是 `NSObject` 子类，
    /// `NSObject` 自带 `init()`，所以这里的 `init()` 不是"新声明"而是**覆盖**父类的那个。
    /// 漏掉 `override` 就是 `error: overriding declaration requires an 'override' keyword`。
    /// 注意 `nonisolated` 与 `override` **不能**调换语义：父类的 `init()` 是 nonisolated 的，
    /// 写了 `override init()` 却让 init 继承类上的 `@MainActor`，等于用隔离的声明去覆盖非隔离的，
    /// 那是另一类编译错误。所以两个修饰符都要，且必须在同一行。
    nonisolated override init() {
        let defaults = UserDefaults.standard

        // 模式还原：读不懂的字符串（升级上来的旧版本 / 手改过的 plist）一律当 `follow`，
        // 那是这个功能上线前的行为，也是唯一不需要额外假设的默认值。
        let savedMode = LocationMode(rawValue: defaults.string(forKey: WeatherLocationSetting.modeKey) ?? "")
            ?? .follow

        // 指定城市还原。`mode == .fixed` 但拿不出可用坐标（plist 被清了一半）时**退回 follow**：
        // 留着 `fixed` 却没有坐标，等于让 `effectiveCoordinate` 静默回落到设备位置，
        // 而界面上还写着"固定在登封" —— 那种谎最难被发现。
        var restoredFixed: CLLocationCoordinate2D?
        var restoredFixedName: String?
        var restoredMode = savedMode
        if savedMode == .fixed {
            if let lat = defaults.object(forKey: WeatherLocationSetting.fixedLatKey) as? Double,
               let lon = defaults.object(forKey: WeatherLocationSetting.fixedLonKey) as? Double {
                let candidate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                if CLLocationCoordinate2DIsValid(candidate), !(lat == 0 && lon == 0) {
                    restoredFixed = candidate
                    let raw = defaults.string(forKey: WeatherLocationSetting.fixedNameKey)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    restoredFixedName = (raw?.isEmpty == false) ? raw : nil
                } else {
                    restoredMode = .follow
                }
            } else {
                restoredMode = .follow
            }
        }

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

        // 地名还原：只有「开关开着 + 地名存在 + 它与缓存坐标对得上」才用。
        // 对不上就留空 —— 让用户看到"定位中…"，而不是昨天那座城市的名字。
        var restoredPlace: String?
        if let place = defaults.string(forKey: WeatherLocationSetting.placeNameKey),
           let placeLat = defaults.object(forKey: WeatherLocationSetting.placeLatKey) as? Double,
           let placeLon = defaults.object(forKey: WeatherLocationSetting.placeLonKey) as? Double,
           let coordinate = restored,
           abs(coordinate.latitude - placeLat) <= WeatherLocationSetting.placeTolerance,
           abs(coordinate.longitude - placeLon) <= WeatherLocationSetting.placeTolerance {
            let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                restoredPlace = trimmed
            }
        }

        self.defaults = defaults
        self.fixedCoordinate = restoredFixed
        _mode = Published(initialValue: restoredMode)
        _fixedName = Published(initialValue: restoredFixedName)
        _lastFixedAt = Published(initialValue: defaults.object(forKey: WeatherLocationSetting.fixedAtKey) as? Date)
        _coordinate = Published(initialValue: restored)
        // 指定城市不需要设备坐标就已经"可用"：状态直接给 `.ready`，
        // 否则设置页副标题会一直停在"定位中…"
        _status = Published(initialValue: (restoredMode == .fixed || restored != nil) ? .ready : .off)
        _placeName = Published(initialValue: restoredPlace)
        super.init()
    }

    // MARK: - 偏好

    /// 设置里的「用我的位置」开关。读 `UserDefaults`，写走 `setEnabled(_:)`（两者等价，
    /// 写入口收拢到一个方法上，是为了"关掉时必须顺手清坐标"这件事只有一处实现）。
    var isEnabled: Bool {
        get { defaults.bool(forKey: WeatherLocationSetting.enabledKey) }
        set { setEnabled(newValue) }
    }

    /// 全 App **唯一**该拿来请求天气的坐标（3.26.0）。
    ///
    /// 优先级：指定城市 → 设备坐标 → `HomeCoordinate.cached()`。
    ///
    /// 为什么要有这个属性，而不是让调用方各自拼：`WeatherStore.resolvedCoordinate()`、
    /// 预警、分钟降水三处都按同一套优先级取值，任何一处漏掉"指定城市优先"，
    /// 就会出现"天气卡是登封、预警还在按郑州发"的错位 —— 而那种错位用户几乎不可能描述清楚。
    /// `WeatherStore.resolvedCoordinate()` 现在直接返回它，调用点一行都不用动。
    var effectiveCoordinate: CLLocationCoordinate2D? {
        // 指定城市优先，且**不依赖开关**：用户选了城市就是想看那儿的天，
        // 开关管的是"要不要读设备位置"，与这个选择无关
        if mode == .fixed, let fixed = fixedCoordinate { return fixed }
        if let device = coordinate { return device }
        guard let home = HomeCoordinate.cached() else { return nil }
        return CLLocationCoordinate2D(latitude: home.lat, longitude: home.lon)
    }

    /// 给 UI 用的地名（3.26.0）：指定城市优先，其次才是反查出来的当前位置。
    ///
    /// 天光页顶栏、设置页副标题都读它。别再让 UI 自己判 `mode` ——
    /// 那种判断一散到三处，就一定会有一处忘了改。
    var displayName: String? {
        return fixedName ?? placeName
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
        // 明确操作不该被 `requestCooldown` 挡掉（3.26.0 修）：用户先关再开、或刚关掉不到 60 秒
        // 又打开时，上一发请求留下的 `lastRequestAt` 会把这一次吞掉 —— 而 `reset()` 刚把状态
        // 写成 `.off`，界面于是停在"定位中…"，并且要等到下次回前台才会重试。
        // 与 `clearFixed()` 同一个写法：冷却只管"前台自动触发"，不管用户点的那一下。
        lastRequestAt = nil
        requestPermissionOrLocation()
    }

    // MARK: - 指定城市（3.26.0）

    /// 把天气位置固定在某个城市。
    ///
    /// 三件事必须同时发生，少一件就会出现"两处显示不同城市"：
    /// 1. **写盘 + 改模式** —— 冷启动才不会又跑回设备位置；
    /// 2. **`status = .ready`** —— 指定城市本身就是一个可用的位置，没有等待期；
    /// 3. **主动 `publishHome` 一次** —— 小组件读的是服务端那条 `home:current` 记录。
    ///    只改本地不报，App 会显示登封、桌面小组件显示郑州，一直挂到下一条定位上报为止。
    ///
    /// 调用方（设置页的城市选择弹层）已经校验过输入，这里再校验一次：坐标来自
    /// `CLGeocoder` / 手写常量，不排除某个 placemark 给出 (0, 0)。
    func setFixed(name: String, lat: Double, lon: Double) {
        let candidate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        guard CLLocationCoordinate2DIsValid(candidate), !(lat == 0 && lon == 0) else { return }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? nil : trimmed

        mode = .fixed
        fixedName = label
        fixedCoordinate = candidate
        defaults.set(LocationMode.fixed.rawValue, forKey: WeatherLocationSetting.modeKey)
        defaults.set(label, forKey: WeatherLocationSetting.fixedNameKey)
        defaults.set(lat, forKey: WeatherLocationSetting.fixedLatKey)
        defaults.set(lon, forKey: WeatherLocationSetting.fixedLonKey)
        status = .ready

        // 小组件那条记录跟上（name 一起报，否则小组件只有坐标没有地名）
        publishHome(candidate, name: label)

        // 位置换了，屏幕上那三份数据全部作废重取。不主动推这一下的话，
        // 用户选完城市回到天光页，看到的还是上一座城市的温度 —— 直到下一次轮询（最长 10 分钟）。
        refreshWeatherSources()
    }

    /// 取消指定，回到"跟着设备走"。
    ///
    /// 必须先清键再请求定位：`refreshIfNeeded()` / `effectiveCoordinate` 都以 `mode` 为第一判据，
    /// 键留在盘上就表示"下次冷启动还是指定城市"。
    func clearFixed() {
        mode = .follow
        fixedName = nil
        fixedCoordinate = nil
        defaults.removeObject(forKey: WeatherLocationSetting.modeKey)
        defaults.removeObject(forKey: WeatherLocationSetting.fixedNameKey)
        defaults.removeObject(forKey: WeatherLocationSetting.fixedLatKey)
        defaults.removeObject(forKey: WeatherLocationSetting.fixedLonKey)

        // 用户刚点的那一下必须立刻有反应：`requestCooldown` 是给"前台自动触发"用的，
        // 不该把一次明确的操作挡在外面。
        //
        // 但**开关关着时一发都不能发**（3.26.0 修）：`requestPermissionOrLocation()` 不看
        // `isEnabled`，而 `clearFixed()` 是用户随时会点的（取消指定城市回到跟随）——
        // 一个从没打开过定位开关、权限还是 `notDetermined` 的用户，只要点一下
        // 城市弹层里的「恢复跟随定位」，就会被弹一次系统权限框。那正是类型注释 ① 里
        // "一装就弹框"要避免的情形，只是换了个入口。
        if isEnabled {
            lastRequestAt = nil
            requestPermissionOrLocation()
        } else {
            // 开关关着：状态回到 `.off`，设置页副标题才不会说"跟随设备定位"
            status = .off
        }

        // 天气同样要立刻回到设备所在地（此时 `effectiveCoordinate` 已不再返回指定坐标）。
        // 定位结果回来还会再推一次，但定位可能失败 / 被拒 —— 那一路也必须有数据可显示。
        refreshWeatherSources()
    }

    /// 位置变了之后强制重取三份数据。
    ///
    /// 为什么三份都要：天气卡（`WeatherStore`）、预警（`AlertStore`）、分钟降水（`MinutelyStore`）
    /// 各自有独立的内存缓存窗（30 / 10 / 10 分钟），且都不认识"位置"这件事 ——
    /// 只推天气的话，人到了登封会看到"登封的温度 + 郑州的暴雨预警"，比不刷新更糟。
    ///
    /// 用 `Task` 而不是让调用方 `await`：`setFixed` / `clearFixed` 是 UI 动作的同步出口，
    /// 调用点（delegate 回调、sheet 按钮）不该为三次网络请求挂在那里等。
    private func refreshWeatherSources() {
        Task {
            await WeatherStore.shared.load(force: true)
            await AlertStore.shared.refresh(force: true)
            await MinutelyStore.shared.refresh(force: true)
        }
    }

    /// 补一次定位。**跟着人走**（3.26.0 重写）。
    ///
    /// 三个入口都调它：进 App（`RootView.task`）、回前台（`FFWangApp` 的 `scenePhase` task）、
    /// 以及切开关。既然回前台都会调，它就必须自己扛住"别把 GPS 反复唤醒"这件事 ——
    /// 闸门在 `requestPermissionOrLocation()` 里（60 秒冷却）。
    ///
    /// 三道判断，顺序不能换：
    /// 1. 开关关着 → `reset()`，一步都不往下走（**不会**弹权限框）；
    /// 2. `fixed` 模式 → 直接返回。用户已经指定了城市，再定位只是耗电，
    ///    而且拿到了也不能用 —— 用了才是 bug；
    /// 3. 有缓存但过了 `reFixInterval`（15 分钟）→ **继续往下走**去重新定位。
    ///    这一条正是 3.25.0 那个 bug 的修复点：以前这里看的是 6 小时的 `cacheLifetime`，
    ///    于是 6 小时内一律短路，人换城市了天气也不换。
    func refreshIfNeeded() {
        guard isEnabled else {
            reset()
            return
        }
        if mode == .fixed {
            // 指定城市是用户明确的选择，设备动到哪儿都与它无关
            status = .ready
            return
        }
        if let coordinate = coordinate, hasFreshCache, hasRecentFix {
            status = .ready
            // 坐标是冷启动还原的，地名可能还没反查过（首装升级 / 上次反查失败）：
            // 这里补一次，否则顶栏会一直停在"定位中…"。
            resolvePlaceNameIfNeeded(coordinate)
            return
        }
        // 静默刷新：失败时 `didFailWithError` 保留旧坐标，用户看不到任何错误，只是位置停在上一次
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

        // 指定城市：权限状态与天气无关，这里既不该请求定位也不该改写状态。
        // 少了这一条，用户在"指定城市"期间去系统设置改了权限，会顺带打一发定位 ——
        // 而那一发的结果落地时会把服务端那条共享记录改回设备位置（见 `didUpdateLocations`）。
        if mode == .fixed {
            status = .ready
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
        // 指定城市：这一发是 `setFixed` 之前就发出去的，结果一律丢弃。
        // **尤其不能 `publishHome`** —— 服务端只有一条共享记录，设备坐标盖上去之后
        // 小组件会跟着设备走，而 App 显示的是用户选的那座城，正是这次要消灭的分叉。
        guard mode == .follow else { return }
        guard let latest = locations.last else { return }

        let next = latest.coordinate
        // (0, 0) 与非法值一律当作"没拿到"：CoreLocation 刚开始时偶尔会先给一个空坐标，
        // 拿它去请求天气，用户会看到大西洋上的天气 —— 那比"没有天气"糟得多
        guard CLLocationCoordinate2DIsValid(next),
              !(next.latitude == 0 && next.longitude == 0) else {
            status = .failed
            return
        }

        // 换城市时**必须**把内存里的地名清掉：`placeName` 是上一座城市反查出来的结果，
        // 而这里只更新坐标（只有 `dropCoordinate` 才会连带清它）。不清就会出现
        // "定位已到上海、反查还在路上（或 `CLGeocoder` 一直失败）"，而天光页
        // `placeLabel` 会继续显示"郑州市 · 金水区" —— 连"定位中…"都等不到。
        //
        // "算不算换了地方"要在更新坐标**之前**算出来（更新之后就无从比较了），
        // 判据与 `publishHome` 的节流同口径（都用 `WeatherLocationSetting.placeTolerance`）：
        // 这个定义在整个 App 里只该有一处，换个数就会出现"上报认为换城市了、
        // 地名却还留着"的错位。2km 内保留旧地名，免得同城挪两步就让顶栏闪一下"定位中…"。
        //
        // **落盘的地名三键刻意不清**（`placeNameKey` / `placeLatKey` / `placeLonKey`）：
        // 那是给下次冷启动的兜底，`init` 还原时会校验"地名 + 它自己的坐标"对不对得上，
        // 对不上自然不用。清了只会让顶栏变空，不会让它更准。
        let moved = Self.hasMoved(from: coordinate, to: next)

        if moved { placeName = nil }

        coordinate = next
        persist(next, at: Date())
        status = .ready

        // 3.17.0：坐标一到**立刻**上报，不等地名反查。
        // 反查（`CLGeocoder`）会在室内 / 无网 / 配额耗尽时失败，3.17.0 把它当上报的前置条件，
        // 于是"反查一失败就完全不上报" —— App 用本地实时坐标（上海）、小组件用服务端默认（郑州），
        // 正是要修的那个 bug。`placeName` 此刻可能还是 nil，服务端允许。
        //
        // 这里刻意不传 `placeName`：它可能是上一座城市的名字（反查还没回来），
        // 拿它配新坐标会把「上海坐标 + 郑州市」写进服务端与本地缓存 ——
        // `HomeCoordinate.carriedName` 的 0.02° 距离保护只在 name 为 nil 时生效，
        // 传一个非 nil 的旧城市名等于直接绕过它。
        // 地名等 `resolvePlaceName` 成功后再补报（下面那条调用点）。
        publishHome(next, name: nil)

        // 地名反查要打网络，别卡住 delegate 回调：丢进任务里，2km 内的重复坐标直接跳过
        resolvePlaceNameIfNeeded(next)

        // 换地方了：屏幕上那三份数据都是上一座城市的，必须立刻重取（3.26.0）。
        //
        // 为什么不能等下一次轮询：天气 30 分钟、预警 / 分钟降水各 10 分钟。用户开车到登封
        // 打开 App，看到的会是"郑州的温度 + 郑州的暴雨预警"，最长要错半小时。
        //
        // 为什么放在 `publishHome` 之后、并且丢进 `Task`：delegate 回调必须尽快返回，
        // 这里没有任何一步的结果是本次回调需要的。
        if moved {
            refreshWeatherSources()
        }
    }

    /// 定位失败：**已有坐标时什么都不做**，保留上一次的位置。
    /// 天气卡片是装饰性信息，不该因为一次"暂时定位不到"就偷偷退回默认城市。
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 指定城市时坐标不是必需品，失败不该把状态改成 `.failed`（那会让设置页
        // 莫名其妙出现"定位失败"，而当前根本不需要定位）
        guard mode == .follow else { return }
        guard coordinate == nil else {
            // 还有旧坐标可用：**保留**它，但状态必须回到 `.ready`。
            // 停在 `.asking` 会让界面一直显示"定位中…"（`placeLabel` 就是这么读的），
            // 而屏幕上明明有当地天气 —— 那是自相矛盾的一种。
            status = .ready
            return
        }
        status = .failed
    }

    // MARK: - 私有

    /// 按当前授权状态决定"申请权限"还是"直接定位"。三个入口（用户切开关 / 权限变化 /
    /// 回前台）共用，所以"防连点"必须在这里，而不是在调用点各写一遍。
    ///
    /// 闸门只有**冷却时间**一条（60 秒），没有单独判 `status == .asking`：
    /// 后者听着更直接，但它有个致命副作用 —— 万一某次请求既没回调成功也没回调失败
    /// （CoreLocation 在室内 / 刚切飞行模式时确实会静默吞掉一次），`status` 会永久停在
    /// `.asking`，而这条判断会让定位从此再也不发起 —— 用户看到的是"位置卡住不动"，
    /// 与这次要修的 bug 症状一模一样。冷却时间天然自愈：60 秒后下一次前台切换就重试。
    private func requestPermissionOrLocation() {
        // 指定城市时**根本不发请求**：拿到了也不能用，只是白耗电。
        // 这条闸门放在最前面（早于防连点），否则"指定城市 + 打开开关"会白白弹一次权限框，
        // 而那个权限对这个模式毫无用处。
        if mode == .fixed {
            status = .ready
            return
        }
        if let last = lastRequestAt, Date().timeIntervalSince(last) < WeatherLocationSetting.requestCooldown {
            return
        }
        lastRequestAt = Date()

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

    /// 落盘缓存是否还在 6 小时有效期内（只管"冷启动能不能直接用"，见 `refreshIfNeeded`）
    private var hasFreshCache: Bool {
        guard let fixedAt = defaults.object(forKey: WeatherLocationSetting.fixedAtKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(fixedAt) < WeatherLocationSetting.cacheLifetime
    }

    /// 上一次定位距今是否还在 `reFixInterval`（15 分钟）内 —— 决定"要不要再去定一次"
    ///
    /// 与 `hasFreshCache` 分开：那个是 6 小时（能不用网络就别用），
    /// 这个是 15 分钟（位置会不会已经变了）。两个问题，两个数字。
    private var hasRecentFix: Bool {
        guard let last = lastFixedAt else { return false }
        return Date().timeIntervalSince(last) < WeatherLocationSetting.reFixInterval
    }

    /// 关掉开关：内存与落盘一起清，状态回 `.off`
    private func reset() {
        dropCoordinate()
        status = .off
    }

    /// 只清坐标与地名（内存 + 落盘），不动 `status`
    ///
    /// 地名必须跟坐标一起清：留着"上海市 · 浦东新区"而坐标已经没了，
    /// 界面就会用一个真实但不属于任何数据的城市名骗人。
    private func dropCoordinate() {
        coordinate = nil
        placeName = nil
        geocodedCoordinate = nil
        // 坐标没了，"上一次定位于何时"也不再指向任何真实位置，一起清掉
        lastFixedAt = nil
        defaults.removeObject(forKey: WeatherLocationSetting.latKey)
        defaults.removeObject(forKey: WeatherLocationSetting.lonKey)
        defaults.removeObject(forKey: WeatherLocationSetting.fixedAtKey)
        defaults.removeObject(forKey: WeatherLocationSetting.placeNameKey)
        defaults.removeObject(forKey: WeatherLocationSetting.placeLatKey)
        defaults.removeObject(forKey: WeatherLocationSetting.placeLonKey)
    }

    private func persist(_ coordinate: CLLocationCoordinate2D, at date: Date) {
        defaults.set(coordinate.latitude, forKey: WeatherLocationSetting.latKey)
        defaults.set(coordinate.longitude, forKey: WeatherLocationSetting.lonKey)
        defaults.set(date, forKey: WeatherLocationSetting.fixedAtKey)
        // 内存与盘上同步：`refreshIfNeeded` 判 15 分钟、设置页显示"定位于 N 分钟前"都读它
        lastFixedAt = date
    }

    // MARK: - 地名反查

    /// 两个坐标算不算"换了地方"（`placeTolerance` 容差内算同一个地方）。
    ///
    /// 单独抽成一个静态方法，是为了让"清地名 / 上报节流 / 强制刷新"三处**判据完全一致**。
    /// 三种输入各自的意义也要一致：
    /// · 旧值 nil（第一次定位 / 刚被清）→ 算换了：第一次拿到的位置本来就"不知道原来在哪"；
    /// · 旧值有、新值必然有（`next` 已经过合法性校验）→ 按容差比。
    private static func hasMoved(from previous: CLLocationCoordinate2D?,
                                 to next: CLLocationCoordinate2D) -> Bool {
        guard let previous else { return true }
        return abs(previous.latitude - next.latitude) > WeatherLocationSetting.placeTolerance
            || abs(previous.longitude - next.longitude) > WeatherLocationSetting.placeTolerance
    }

    /// 需不需要为这个坐标反查一次地名（2km 内不重复打接口）
    private func needsResolve(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard let last = geocodedCoordinate else { return true }
        return abs(last.latitude - coordinate.latitude) > WeatherLocationSetting.placeTolerance
            || abs(last.longitude - coordinate.longitude) > WeatherLocationSetting.placeTolerance
    }

    /// 条件满足才发起一次反查（不阻塞调用方）
    private func resolvePlaceNameIfNeeded(_ coordinate: CLLocationCoordinate2D) {
        // 关掉开关之后不该再有任何定位相关的网络请求在路上
        guard isEnabled else { return }
        guard !isResolvingPlace else { return }
        guard needsResolve(coordinate) else { return }
        isResolvingPlace = true
        // `Task` 继承本方法的 `@MainActor` 隔离，所以 `resolvePlaceName` 里的赋值
        // 仍然发生在主 actor 上（`CLGeocoder` 不是 `Sendable`，这一步不能省）
        Task {
            await resolvePlaceName(coordinate)
        }
    }

    /// 反查"这里是哪"：成功写入 `placeName` 并落盘；失败**保留旧值**（宁可旧，不要空）。
    private func resolvePlaceName(_ coordinate: CLLocationCoordinate2D) async {
        defer { isResolvingPlace = false }

        // 反查用的是**坐标**，与天气请求的公里级精度不同：这里要的是行政区划
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            // 用 async 版本（iOS 15+ 的并发覆盖），不要 completion 版本 ——
            // 后者要自己管回调线程与「同一个 geocoder 不能并发」的规矩
            let marks = try await geocoder.reverseGeocodeLocation(location)
            guard let mark = marks.first, let label = Self.placeLabel(from: mark) else { return }
            placeName = label
            geocodedCoordinate = coordinate
            defaults.set(label, forKey: WeatherLocationSetting.placeNameKey)
            defaults.set(coordinate.latitude, forKey: WeatherLocationSetting.placeLatKey)
            defaults.set(coordinate.longitude, forKey: WeatherLocationSetting.placeLonKey)
            // **补报**：坐标在 `didUpdateLocations` 里已经报过一次（那次 name 可能是 nil），
            // 这里把刚反查到的地名补上去 —— 小组件迟早要显示"上海市 · 浦东新区"，
            // 而那时再补一次反查就意味着在 extension 里调 CoreLocation（弹不出权限框，只会静默失败）。
            // 坐标没变、name 变了：`publishHome` 的"name 变化放行"会放过这一发。
            publishHome(coordinate, name: label)
        } catch {
            // 网络失败 / 配额 / 该坐标没有行政区划：什么都不做。
            // 清空 `placeName` 会让顶栏从"上海市"跳回"定位中…"，那是退步
            return
        }
    }

    // MARK: - 上报共享坐标（3.17.0，3.17.0 改造）

    /// 把「位置」上报给服务端，让桌面小组件与 App 显示同一个城市。
    ///
    /// ## 节流（三条**同时**满足才跳过）
    /// 1. 新坐标与上次成功上报的坐标距离 < 0.02°（约 2km）；
    /// 2. **且**距上次成功上报不到 6 小时；
    /// 3. **且** `name` 与上次上报的相同（新加的豁免，见 `lastPublishedName`）。
    ///
    /// 只用第 1 条会让"同一城市内换区"永远报不上去（地名变了，小组件那边还是旧区名）；
    /// 只用第 2 条等于每 6 小时盲报一次，用户在城市里挪两步就白打一发。
    ///
    /// ## 失败（含被服务端限频）不推进节流
    /// 先 `await` 服务端确认，**只有 `HomeCoordinate.publish` 返回 `true`**（服务端真收下了，
    /// 或回 `unchanged` 表示已有记录就是这次这个点）才写 `lastPublished*`。
    /// `throttled` 与网络失败一样返回 `false`：地铁里第一发失败、或 60 秒窗口内换城市，
    /// 都不能当成"6 小时内不再重试" —— 那正好是 App 与小组件分叉最长 6 小时的原因。
    ///
    /// ## 上报成功后推一次小组件（本次修复）
    /// 小组件的一轮 timeline 覆盖 24 小时（`.atEnd`），期间不会自己重新拉数据。跨城不推，
    /// 桌面就一直挂着旧城市：App 几分钟就变上海，小组件能挂一整天郑州。
    /// 但 `reloadAllTimelines()` 花的是系统给这个 App 的**刷新预算**，所以必须加条件 ——
    /// 只在"新坐标与上次成功上报的坐标差超过 2km"时推：为同城挪了 500 米刷一次是纯浪费；
    /// 而跨城不刷，用户会看到一整天的旧城市，那正是这次要修的 bug。
    /// 首次上报（`lastPublished == nil`）也不推：App 刚装，小组件大概率还没被加到桌面。
    ///
    /// ## 为什么是 `Task` 而不是 `await`
    /// 本方法跑在 `CLLocationManagerDelegate` 的回调链上（`didUpdateLocations` → 反查 → 这里），
    /// 上报是纯附属动作：让它多等一个 RTT 只会推迟 delegate 返回，对用户没有任何好处。
    /// 失败不打扰用户，但**不吞掉节流状态**（见上）。
    ///
    /// ## 为什么节流放在这里而不是 `HomeCoordinate` 里
    /// 那边只负责"把一条坐标送出去"；"多久送一次"是本类的事（它才知道定位何时发生）。
    private func publishHome(_ coordinate: CLLocationCoordinate2D, name: String?) {
        let now = Date()
        if let last = lastPublished,
           let lastAt = lastPublishedAt,
           abs(last.latitude - coordinate.latitude) <= WeatherLocationSetting.placeTolerance,
           abs(last.longitude - coordinate.longitude) <= WeatherLocationSetting.placeTolerance,
           now.timeIntervalSince(lastAt) < WeatherLocationSetting.cacheLifetime,
           name == lastPublishedName {
            return
        }

        // 只把两个 `Double` 与字符串带进任务（`CLLocationCoordinate2D` 不必跨任务传）
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        Task {
            let ok = await HomeCoordinate.publish(lat: lat, lon: lon, name: name)
            guard ok else { return }        // 未接受（含 throttled）：下次定位还会重试

            // 「上次成功上报的坐标」必须在**更新这一步之前**读：它代表"推小组件之前，
            // 小组件那份数据站的位置"。放在 `Task` 里读（而不是进任务前读成常量）还有一个用处：
            // 连续两次定位各起一个任务时，后完成的那个读到的是先完成那个刚写下的坐标，
            // 距离为 0 → 不会再推一次，天然去重。
            let previous = lastPublished
            lastPublished = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            lastPublishedAt = now
            lastPublishedName = name

            // 首次上报（App 刚装 / 刚打开定位）：小组件大概率还没加到桌面，不值得花一次预算
            guard let previous = previous else { return }
            // 同城挪动（≤ 2km）不推 —— 理由见方法注释「上报成功后推一次小组件」。
            // 阈值与节流、与 `LocationStore` 清地名的判定同口径（`placeTolerance`）。
            let moved = abs(previous.latitude - lat) > WeatherLocationSetting.placeTolerance
                || abs(previous.longitude - lon) > WeatherLocationSetting.placeTolerance
            guard moved else { return }

            // 跨城且已被服务端接受：现在不推，用户就要看一整天的旧城市
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// 从 `CLPlacemark` 拼两级地名："上海市 · 浦东新区"。
    ///
    /// 规则：
    /// 1. 「市」优先 `locality`，缺了退 `administrativeArea`（有些地区只给省/州）；
    /// 2. `subLocality` 有就再拼一级（"浦东新区" / "海淀区"）—— 用户问"我到底在哪儿"，
    ///    市级太粗，区级才答得上来；
    /// 3. 两级都没有 → nil（交给 UI 说"定位中…"，不编一个名字）；
    /// 4. 两级正好同名（"上海市 · 上海市"）只留一级。
    private static func placeLabel(from mark: CLPlacemark) -> String? {
        let city = cleaned(mark.locality) ?? cleaned(mark.administrativeArea)
        let district = cleaned(mark.subLocality)

        switch (city, district) {
        case let (city?, district?):
            return city == district ? city : city + " · " + district
        case let (city?, nil):
            return city
        case let (nil, district?):
            // 只拿到区（少数地区的 placemark 不给 locality）：给这一级也比空着强
            return district
        case (nil, nil):
            return nil
        }
    }

    /// 去掉空白与空串（服务端 / 系统偶尔给一个 `" "`）
    private static func cleaned(_ value: String?) -> String? {
        guard let value = value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
