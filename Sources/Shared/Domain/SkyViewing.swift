import Foundation

/// 「这片天现在值不值得为它写一句景观描述」。
///
/// ## 为什么需要这一层
///
/// 「黄金时刻」不是一个时间名词，是一句**关于颜色的话**：它承诺天边有金橙色的光。
/// 而 `SunClock.phase(at:)` 只算太阳高度角 —— 太阳在日出后 24~70 分钟之间必然
/// 落进这一档，无论天上是不是压着八层云。
///
/// 于是就有了用户报的那条：早上七点半，多云，抬头是蓝天白云，App 顶栏写着「黄金时刻」。
/// 这句话没有一处是 P0 bug（时间算对了、文案取到了），但它比 bug 更伤 ——
/// 它让用户当场发现 App 在说一件他肉眼就能证伪的事。一次之后，
/// 这个 App 说「日落 18:12」他也会怀疑一下。
///
/// ## 口径
///
/// 三路输入互相独立，**任何一路说「看不见」就是看不见**：
/// 云量说没遮，但能见度 800 米，抬头一样是白茫茫一片。所以判定取最坏那一路。
///
/// 浑浊度直接复用 `SkyHaze.level` —— 那是天光页 / 小组件画雾用的同一个数。
/// 如果这里另立一套能见度阈值，就会出现「画面在起雾、文案说通透」的错位，
/// 而错位比单点误差更难解释。
///
/// ## 纪律
///
/// **没有数据就不判**（返回 `nil`），而不是兜底成「看不见」或「看得见」。
/// 兜底成看不见，天气接口抖动一次，用户就再也看不到黄金时刻；
/// 兜底成看得见，就是现在这个 bug。返回 `nil` 让调用方**保持原样**——
/// 先按天文时间说，等数据到了再修正，这也和全工程「缺数据不出声」的口径一致。
///
/// 本文件与 Widget target 共用，只 import Foundation。
enum SkyViewing {

    /// 判定结果：三档。
    enum Verdict: String, Sendable {

        /// 通透：云少、无降水、能见度好。天边会有颜色
        case clear

        /// 有遮挡：中高云、轻霾。**也许**有一点颜色，但不该被许诺
        case veiled

        /// 看不见：降水、雾、厚云、低能见度
        case blocked
    }

    // MARK: - 阈值

    /// 所有阈值集中在这里，方便一次调完。
    ///
    /// 数字的依据写在每一条后面 —— 这些不是"感觉好看"，是对应现实里能验证的观察：
    enum Threshold {

        /// 云量（%）达到这个数就不算「晴」。50 = 半个天空被遮。
        ///
        /// 为什么不是更高的 70：`WeatherKind.partly`（多云）本身就是 25~50%，
        /// 用户抬头看到"很多云但天是蓝的"，第一反应就是"这不算晴"。
        /// 黄金时刻要的是**一条干净的天边**，半片云压过去，颜色就断了。
        static let cloudClear: Double = 50

        /// 云量（%）达到这个数就是厚云压顶（对应 WMO 3「阴」的 85% 下限）
        static let cloudBlocked: Double = 85

        /// 浑浊度达到这个数：中度霾（约能见度 3km），远山化掉，霞光没了
        static let hazeBlocked: Double = 0.56

        /// 浑浊度达到这个数：轻度霾（约能见度 10km），霞光饱和度明显下降
        static let hazeVeiled: Double = 0.20
    }

    // MARK: - 判定

    /// 从一份天气实况判定。`nil` = 没有可用数据（**不是**「看不见」）。
    ///
    /// `weather.ok == false` 也返回 nil：那表示这次没拿到数据，不代表天变坏了。
    ///
    /// - Parameters:
    ///   - weather: 天气实况
    ///   - fallback: 备用能见度。天气接口没带 `visibilityMeters` 时用它 ——
    ///     天光页与小组件各自还有一路独立的能见度探测（`VisibilityProbe`），
    ///     不接进来就等于白白丢掉一个已有的观测。
    static func verdict(of weather: WeatherNow?,
                        visibilityMeters fallback: Double? = nil) -> Verdict? {
        guard let weather, weather.ok else { return nil }
        return verdict(kind: weather.kind,
                       cloud: weather.cloud,
                       visibilityMeters: weather.visibilityMeters ?? fallback)
    }

    /// 判定主体。
    ///
    /// 短路顺序有讲究：先判**降水**（最硬的否决，雨幕里不存在霞光），
    /// 再判**浑浊度**（雾霾），最后才看**云量**。反过来写也能得出同样的结论，
    /// 但会白算一遍曲线插值 —— 而这条路径每次刷新都要走一次。
    ///
    /// - Parameters:
    ///   - kind: 天气类型；nil = 代码认不出
    ///   - cloud: 云量百分比 0…100；nil = 缺
    ///   - visibilityMeters: 水平能见度（米）；nil = 缺
    /// - Returns: 判定；三样全缺时返回 nil
    static func verdict(kind: WeatherKind?,
                        cloud: Double?,
                        visibilityMeters: Double?) -> Verdict? {
        // 一项数据都没有：不判。
        guard kind != nil || cloud != nil || visibilityMeters != nil else { return nil }

        // ① 降水否决：雨、雪、雷、毛毛雨。这一条不看能见度有多好 ——
        //    雨后的霞确实好看，但"此刻正在下"时天边是灰的。
        if let kind, kind.precipitation != nil { return .blocked }

        // ② 浑浊度（与天空渲染同一口径）
        let haze = SkyHaze.level(visibilityMeters: visibilityMeters, kind: kind)
        if haze >= Threshold.hazeBlocked { return .blocked }

        var worst: Verdict = haze >= Threshold.hazeVeiled ? .veiled : .clear

        // ③ 云量
        if let cloud, cloud.isFinite {
            if cloud >= Threshold.cloudBlocked { return .blocked }
            if cloud >= Threshold.cloudClear { worst = .veiled }
        }

        // ④ 类型兜底：云量常缺（上游不一定给），类型本身已经蕴含了量级
        if let kind {
            switch kind {
            case .overcast:
                return .blocked
            case .fog:
                // 有能见度数据时上面已经判过；能见度缺失时按"看不见"处理，
                // 因为雾的定义就是"看不见远处"，不该等一个可能永远不来的数字
                return .blocked
            case .partly:
                worst = .veiled
            case .clear, .drizzle, .rain, .snow, .thunder:
                // 降水类已在 ① 返回；.clear 不改变结论
                break
            }
        }

        return worst
    }
}

// MARK: - 时段降级

extension SkyPhase {

    /// 天气不支持时，把「承诺了颜色」的时段降级。
    ///
    /// ## 只降 `.golden` 一个
    ///
    /// 七档里只有「黄金时刻」这个词是在**描述颜色**。其余六档说的都是时间或事件：
    /// 「日出」「日落剩余」「蓝调剩余」「距离日落」——
    /// 阴天说"日落还剩 20 分钟"依然是事实（日落照常发生，只是看不见）。
    /// 而"黄金时刻"在阴天是**假的**：那一刻没有金色，只有一片铅灰。
    ///
    /// 所以降级不是"整段闭嘴"，而是**换一句不会错的话**：继承 `.day` 的口径
    /// （「距离日落」+ 数到日落前 70 分钟）。用户看到的是这一天的真实剩余白昼，
    /// 一句话都不假。
    ///
    /// ## 配色跟着一起变
    ///
    /// 天光页与小组件的天色都由 `Theme.sky(phase)` 取，phase 降到 `.day` 之后
    /// 天空自动从"金橙"变成"白天的蓝"—— 这与用户此刻抬头看到的（"蓝蓝的天空"）
    /// 是同一件事。文案和画面从此不会再分头撒谎。
    ///
    /// - Parameter viewing: 判定结果；`nil`（没有数据）时**原样返回**，见 `SkyViewing` 的纪律
    func effective(viewing: SkyViewing.Verdict?) -> SkyPhase {
        guard self == .golden, let viewing else { return self }
        return viewing == .clear ? .golden : .day
    }
}
