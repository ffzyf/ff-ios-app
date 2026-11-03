import Combine
import CoreLocation
import Foundation

/// 首页穿搭建议的缓存与刷新（`POST /api/ai/outfit`，非流式）。
///
/// 只做三件事：
/// 1. 拿今天的天气（气温区间 + 体感 + 天气文字）去问一句"该穿什么"；
/// 2. 内存里扛 6 小时，期间重复调用直接返回；
/// 3. 成功后落一份盘，冷启动先上屏再回源。
///
/// 三条策略与 `WeatherStore` **刻意保持一致**（同一个 App 里两份缓存如果尺度不同，
/// 就会出现"天气是 10 分钟前的、建议是 6 小时前的"这种解释不清的错位）：
///
/// · **6 小时窗口**：与服务端 KV 的 TTL 对齐（`ai:outfit:<lat>,<lon>:<yyyyMMdd>` 压 6 小时）。
///   App 比服务端短只是把同一份缓存多读几次；比服务端长，用户就会看到"服务端早换了建议、
///   卡片还是上一件外套"。对齐之后两边永远是同一份。
/// · **失败保留旧值**：建议是卡片上的装饰性文案。拉失败就让它消失，等于用一次网络抖动
///   换掉用户眼前一段好好的话 —— 旧建议最多旧 6 小时，比"什么都没有"诚实得多。
///   旧值会被标 `stale = true`，界面据此加一句「稍早的建议」。
/// · **落盘**：冷启动先上屏。理由同 `WeatherStore`：每次打开都盯着"AI 还没说话"
///   是最频繁的坏体验，而跨天看到旧建议（一天最多一次）很好识别。
@MainActor
final class AIOutfitStore: ObservableObject {

    /// 全 App 唯一实例
    static let shared = AIOutfitStore()

    // MARK: - 常量

    /// 新鲜窗口（秒）：6 小时，与服务端 KV TTL 对齐
    private static let freshWindow: TimeInterval = 6 * 3600

    /// 落盘快照的最长寿命（秒）：24 小时。
    ///
    /// 比新鲜窗口长，是因为"旧一点但还能看"比"空白"好；超过一天就真的没意义了 ——
    /// 一天换一个季节，昨天的"加件外套"今天可能是"短袖出门"。
    private static let diskMaxAge: TimeInterval = 24 * 3600

    /// 坐标变化的作废阈值（0.05° ≈ 5.5km），与 `WeatherStore` 同一口径
    private static let coordinateTolerance: Double = 0.05

    /// 气温区间变化的作废阈值（摄氏度）。
    ///
    /// 一天之内 8℃ → 24℃ 是会发生的（早春、深秋）。差到 5℃ 以上，
    /// 那份建议说的就是另一段天气，留着只会教人穿错衣服。
    private static let temperatureTolerance: Double = 5

    /// 落盘快照的键
    private static let diskKey = "ai.outfit.v1"

    // MARK: - 状态

    /// 最近一份建议。nil = 从来没有过（首装 / 一直断网 / 没有坐标）
    @Published private(set) var advice: AIOutfitAdvice?

    /// 请求在飞（卡片转圈 + 防连点）
    @Published private(set) var isLoading = false

    /// 最近一次失败。注意：**失败不清空 `advice`**（见类型注释）
    @Published private(set) var lastError: AIError?

    // MARK: - 私有状态

    private let client: APIClient

    /// 上一次**成功**的时间（不是发起时间：否则一次失败会把 6 小时窗口重新计满）
    private var lastSuccessAt: Date?

    /// 上一次请求用的坐标（判断"换地方了没有"）
    private var lastLatitude: Double?
    private var lastLongitude: Double?

    /// 上一次请求时的气温区间（判断"天气换了没有"）
    private var lastTMin: Double?
    private var lastTMax: Double?

    // MARK: - 初始化

    init(client: APIClient = .shared) {
        self.client = client
        restoreFromDisk()
    }

    // MARK: - 派生

    var hasAdvice: Bool {
        advice != nil
    }

    /// 有没有一段非空的建议正文（空白当没有，界面走空态）
    var adviceText: String? {
        guard let text = advice?.text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - 加载

    /// 首页调用入口：自己从 `WeatherStore` 取坐标与实况。
    ///
    /// 为什么不要求调用方传参：`OverviewView` 已经观察着 `WeatherStore`，
    /// 再让它把同一份东西搬过来，就多了一处"传错了也不报错"的可能。
    /// 需要显式入参的场景（预览 / 自检 / 将来别的页面复用）走下面那个重载。
    func load(force: Bool = false) async {
        let coordinate = WeatherStore.resolvedCoordinate()
        await load(latitude: coordinate?.latitude,
                   longitude: coordinate?.longitude,
                   weather: WeatherStore.shared.current,
                   force: force)
    }

    /// 显式入参版本（不带默认值，避免"忘了传"变成"悄悄用 nil"）
    ///
    /// - Parameters:
    ///   - latitude: 纬度。nil（没有定位也没有「家」坐标）就不发请求 ——
    ///     服务端没有"默认城市"这一说，穿搭建议必须绑到一个地方
    ///   - longitude: 经度
    ///   - weather: 天气实况。nil 或 `ok == false` 就不发请求：
    ///     没有气温区间的"该穿什么"只能靠编，那不是我们想要的东西
    ///   - force: 下拉刷新传 true（忽略新鲜窗口，但仍保留旧值直到新值回来）
    func load(latitude: Double?,
              longitude: Double?,
              weather: WeatherNow?,
              force: Bool = false) async {

        guard let latitude = latitude, let longitude = longitude,
              latitude.isFinite, longitude.isFinite else { return }
        guard let weather = weather, weather.ok else { return }

        // 两位小数：0.01° ≈ 1.1km，已经比天气网格细。多给精度只会把同一片网格拆成
        // 多个缓存键 —— 服务端的 `ai:outfit:<lat>,<lon>` 键就是拿这两个数拼的
        let lat = (latitude * 100).rounded() / 100
        let lon = (longitude * 100).rounded() / 100

        // 换地方了 / 天气换了 → 手里这份说的是另一段天气，必须作废
        if hasMoved(lat: lat, lon: lon) || hasTemperatureShifted(weather) {
            advice = nil
            lastSuccessAt = nil
            clearDisk()
        }

        let age = lastSuccessAt.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        if !force, advice != nil, age < Self.freshWindow { return }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let body = try JSONEncoder().encode(
                AIOutfitRequest(lat: lat,
                                lon: lon,
                                tMin: weather.tMin,
                                tMax: weather.tMax,
                                feelsLike: weather.feelsLike,
                                text: weather.text,
                                // 分钟级降水时段留给 T06：契约里 `from` / `to` 的形状没定死，
                                // 猜错了整条请求 400。少带一个字段，服务端照样能给出建议
                                precip: nil)
            )
            guard let url = API.aiOutfit() else {
                throw AIError.server("地址拼错了。")
            }
            let request = API.aiRequest(url: url,
                                       method: "POST",
                                       token: AIKeychain.token(),
                                       body: body)
            let response = try await client.send(request, as: AIOutfitResponse.self)

            guard response.ok, var fresh = response.advice else {
                let message = response.error?.cleanMessage ?? "建议没生成出来，等下再看。"
                throw AIError.server(message)
            }
            guard !fresh.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIError.server("建议没生成出来，等下再看。")
            }

            fresh.stale = false
            advice = fresh
            lastSuccessAt = Date()
            lastLatitude = lat
            lastLongitude = lon
            lastTMin = weather.tMin
            lastTMax = weather.tMax
            lastError = nil
            saveToDisk(fresh, lat: lat, lon: lon)
        } catch {
            lastError = AIFailure.from(error)
            // 旧建议继续挂着，但标成"旧的"：界面上那句「稍早的建议」就是这个标记
            if advice != nil {
                advice?.stale = true
            }
        }
    }

    // MARK: - 落盘

    /// 盘上那份快照的形状。
    ///
    /// 为什么带坐标：只有建议本身的话，用户从上海飞到北京、冷启动时会把上海的建议摆上桌 ——
    /// 而且看起来完全正常（"今天穿件薄外套"在哪儿都通顺），没人会怀疑。
    ///
    /// 为什么带 `savedAt` 而不是复用 `advice.generatedAt`：后者是**服务端生成时间**，
    /// 可能因为命中服务端缓存而停在几小时前。判断"这份缓存还值不值得显示"要看我们
    /// **何时拿到它**，就像判断牛奶能不能喝要看放进冰箱的时间。
    private struct DiskSnapshot: Codable {
        let lat: Double
        let lon: Double
        let tMin: Double?
        let tMax: Double?
        let savedAt: Date
        let advice: AIOutfitAdvice
    }

    /// 冷启动时把上一份建议摆上屏。
    ///
    /// 三道闸门，任何一道不过就丢弃整份快照：
    /// 1. **超过 24 小时** —— 一天换一个季节，旧建议会教人穿错；
    /// 2. **坐标对不上** —— 说明用户换了地方，这是出发地的建议；
    /// 3. **解码失败** —— 换版本后字段改了，当作没有。
    ///
    /// 恢复 `lastSuccessAt` 是关键一步：不恢复的话冷启动一律视为"从没成功过"，
    /// 于是每次打开都强制拉一次 —— 服务端配额就是这么被白白烧掉的。
    private func restoreFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.diskKey),
              let snapshot = try? JSONDecoder().decode(DiskSnapshot.self, from: data) else { return }

        let age = Date().timeIntervalSince(snapshot.savedAt)
        guard age >= 0, age < Self.diskMaxAge else {
            clearDisk()
            return
        }

        // 盘上这份属于哪里？与"现在的家"对不上就不要
        if let here = WeatherStore.resolvedCoordinate() {
            let lat = (here.latitude * 100).rounded() / 100
            let lon = (here.longitude * 100).rounded() / 100
            if abs(lat - snapshot.lat) > Self.coordinateTolerance
                || abs(lon - snapshot.lon) > Self.coordinateTolerance {
                clearDisk()
                return
            }
        }

        var restored = snapshot.advice
        // 超过新鲜窗口的那份仍然显示，但要说清"是旧的"
        restored.stale = age >= Self.freshWindow
        advice = restored
        lastSuccessAt = snapshot.savedAt
        lastLatitude = snapshot.lat
        lastLongitude = snapshot.lon
        lastTMin = snapshot.tMin
        lastTMax = snapshot.tMax
    }

    /// 成功后写盘。失败静默 —— 落盘是体验优化，不是依赖
    private func saveToDisk(_ advice: AIOutfitAdvice, lat: Double, lon: Double) {
        let snapshot = DiskSnapshot(lat: lat,
                                    lon: lon,
                                    tMin: lastTMin,
                                    tMax: lastTMax,
                                    savedAt: Date(),
                                    advice: advice)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.diskKey)
    }

    /// 清掉盘上那份（换地方 / 数据过期时）
    private func clearDisk() {
        UserDefaults.standard.removeObject(forKey: Self.diskKey)
    }

    // MARK: - 变化判定

    /// 坐标是不是换了地方（同城内的移动不算，见 `coordinateTolerance`）
    private func hasMoved(lat: Double, lon: Double) -> Bool {
        guard let previousLat = lastLatitude, let previousLon = lastLongitude else {
            // 第一次请求：没有"上次"，不算换地方（否则每次冷启动都会白清一次缓存）
            return false
        }
        return abs(previousLat - lat) > Self.coordinateTolerance
            || abs(previousLon - lon) > Self.coordinateTolerance
    }

    /// 气温区间是不是换了一段天气（见 `temperatureTolerance`）
    private func hasTemperatureShifted(_ weather: WeatherNow) -> Bool {
        guard let previousMin = lastTMin, let previousMax = lastTMax,
              let currentMin = weather.tMin, let currentMax = weather.tMax else {
            // 缺一头就判不出来，当作没变 —— 拿不准就沿用旧值，比瞎作废好
            return false
        }
        return abs(currentMin - previousMin) > Self.temperatureTolerance
            || abs(currentMax - previousMax) > Self.temperatureTolerance
    }
}
