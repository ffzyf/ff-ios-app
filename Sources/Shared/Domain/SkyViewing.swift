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

// MARK: - 时段纠正：换色，还是换词

extension SkyPhase {

    /// 天气不支持时，纠正这个时段**说错的那一部分** —— 有时是配色，有时只是那个词。
    ///
    /// ## 判据一：这个词承诺的是**颜色**，还是**时间/事件**
    ///
    /// 七档里承诺颜色的有三档：「黄金时刻」（天边金橙）、「蓝调剩余」两档（天是蓝的）。
    /// 其余四档说的都是时间或事件：「日出」「日落剩余」「距离日落」「夜间」——
    /// 阴天说"日落还剩 20 分钟"依然是事实（日落照常发生，只是看不见）。
    ///
    /// 用户报过两次，都在这三档里：先是"多云蓝天却写着黄金时刻"，后是
    /// "阴天还给我显示蓝调时刻，蓝调时刻应该是蓝的嘛"。一个词只要在命名一种
    /// **看得到的东西**，它就归天气管。
    ///
    /// ## 判据二：纠正的粒度由**错误有多大**决定
    ///
    /// 归属同一条线，不等于同一个修法。两者错的量级差一个数量级，所以手段也不同：
    ///
    /// **黄金时刻 —— 错一整个色相轮，必须连配色一起换。**
    /// 它承诺天边是金橙，阴天抬头是一片铅灰，色相相差约 180°，中间没有
    /// "仍然是橙只是暗一点"这种状态。所以它降成 `.day`：天色换成白天的蓝
    /// （用户此刻抬头看到的确实是"灰蓝的天"，只是没有橙），继承的语言也仍然成立
    /// （「距离日落」+ 数到日落前 70 分钟）。这一档**保持现状，别再动**。
    ///
    /// **蓝调 —— 只错纯度与明度，换词就够。**
    /// 阴天的天仍然是**蓝灰**，色相对，只是不纯、不亮。而把配色也换掉，等于用一个
    /// 更大的错去纠正一个更小的错，账是这样算的：
    ///
    /// - `.night` 天顶 `#05070E`，亮度约 0.22%，配 18 颗 alpha 0.75 的星点；
    /// - 阴天日落后十分钟，室外实测还有 5%~15% 的灰蓝亮度；
    /// - 遮不住：浑浊度 `SkyHaze.baseLevel(.overcast) = 0.16`，雾层最厚一档才 8%；
    ///   云层固定 7 朵，也不随天气变。
    ///
    /// 于是"色相错（蓝 vs 灰）"被换成了"明度错（0.22% vs 8%）"，差 40 倍，**更显眼**。
    /// 3.23.0 补漏时走了这条路（把蓝调降成 `.night`），是过度纠正。
    ///
    /// 真正说谎的只有那个词：「蓝调」承诺的是**纯度**，天得是蓝的，还得蓝得够纯。
    /// 阴天给不了纯度，但给得了时间。所以这里**不动 phase** —— 配色、`deadline`、
    /// 倒计时一律保持原样 —— 只把词换成一句纯事件的话（`label(viewing:)`）：
    ///
    /// - 「蓝调剩余 8 分钟」是假的：天上没有蓝调，哪来"蓝调剩余"；
    /// - 「入夜剩余 8 分钟」是真的：暮光八分钟后结束，阴天照样结束，逐字可验。
    ///
    /// 一句话收口：**能换词就不换色；换色一定是因为色相真的错了。**
    ///
    /// - Parameter viewing: 判定结果；`nil`（没有数据）时**原样返回**，见 `SkyViewing` 的纪律
    func effective(viewing: SkyViewing.Verdict?) -> SkyPhase {
        // 没数据就不判：先按天文时间说，等数据到了再修正
        guard let viewing else { return self }

        switch self {
        case .golden:
            // 「金橙」与「铅灰」相差一个色相轮，必须连配色一起换
            return viewing == .clear ? .golden : .day
        case .night, .blueDawn, .sunrise, .sunset, .blueDusk, .day:
            // 蓝调两档**不降级**：阴天的天仍是蓝灰，色相对，错只在那个词 ——
            // 词由 `label(viewing:)` 换，phase 留着，配色与 deadline 都不动
            return self
        }
    }

    /// 这一刻「天上还有没有颜色」—— 三态口径的唯一判据。
    ///
    /// 只有**确认天是通的**才敢说颜色：
    /// - `.clear` / `.veiled`：多云、轻霾的霞光与蓝调**是真实存在的**，云被染成蓝紫、
    ///   天边比晴天更戏剧化，那正是拍照最好的时候，不该被否认；
    /// - `.blocked`（阴、雨、雪、雷、雾、厚云、低能见度）：整片天被封死，一个蓝像素都不会有；
    /// - `nil`：**没拿到数据**，不是"天很好"。工程纪律里 `nil` 永远表示缺数据，
    ///   所以它归到"不说颜色"这一边。
    ///
    /// 为什么默认值必须是"不说"而不是"说"：反过来写（默认说有颜色、有数据才降），
    /// 接口抖动一次假话就上屏了 —— 3.23.0 那个「阴天显示蓝调时刻」正是这么来的。
    /// 冷启动那一秒先给一句纯时间的话（暮光八分钟后结束，这是天文事实、与天气无关），
    /// 等实况到了再升级成「蓝调剩余」—— 两句话都真，只是精确度不同。
    func claimsColor(viewing: SkyViewing.Verdict?) -> Bool {
        return viewing == .clear || viewing == .veiled
    }

    /// 这句话该怎么说：能说颜色就说颜色，说不出口就只说时间。
    ///
    /// ## 三档承诺颜色，四档只承诺时间
    ///
    /// 「黄金时刻」「蓝调剩余」两档说的是**看得见的东西**，它们归天气管；
    /// 「夜间」「日出」「距离日落」「日落剩余」说的是时间或事件 ——
    /// 阴天说"日落还剩 20 分钟"依然是事实（日落照常发生，只是看不见）。
    ///
    /// ## 门是白名单，不是黑名单
    ///
    /// `claimsColor(viewing:)` 为真才返回原词，其余（含 `nil`）一律返回中性词。
    /// 这样"新出现一种没见过的判定"会落到安全的一侧，而不是落到"继续说颜色"。
    ///
    /// ## 换来的中性词都是纯事件
    ///
    /// 它们与**这一档自己的** `deadline` 天然咬合，不用改时间：
    /// `.blueDusk` 的 `deadline` 是 `sunset + 30min`，正是"入夜"那一刻；
    /// `.blueDawn` 的 `deadline` 是 `sunrise`，正是"天亮"那一刻；
    /// `.golden` 的 `deadline` 是 `sunrise + 70min`，正是晨光散尽那一刻。
    /// 于是「入夜剩余 8 分钟」逐字可验，而「蓝调剩余 8 分钟」在阴天是假的。
    ///
    /// ## 词必须锚在**这一档的 deadline** 上，不是锚在"听起来顺"上
    ///
    /// `.golden` 曾经在这里返回「距离日落」，那句词是错的：它的语义锚在日落，
    /// 而 `.golden` 数的是日出后 70 分钟 —— 天气缺数据时 phrase 仍是 `.golden`
    /// （`effective(viewing: nil)` 不降级），屏幕就成了「● 距离日落　39分钟」，
    /// 而当天真实日落还有九个小时。三处入口（天光小组件 / 简报卡 / 天光页顶栏）
    /// 全都这么读，且一整轮 golden 窗口都是 nil（`SkyLightProvider` 一轮只拉一次天气，
    /// 失败即整轮 103 帧全 nil），不是"冷启动一秒"。换成「晨光剩余」后，
    /// 词与倒计时指的是同一件事，任何一种输入下都自洽。
    ///
    /// ## 自我闭合，不依赖调用方先跑 `effective`
    ///
    /// `.golden` 只靠"`.blocked` 时它已被 `effective` 降成 `.day`"这个隐式契约是脆的 ——
    /// 谁拿一个裸 phase 来调（Widget 里现造一帧、预览、将来的第二处入口）就会漏。
    /// 所以这里自己判：非 `.clear` 直接返回「晨光剩余」。
    ///
    /// 注意它**不必**与 `effective` 降成 `.day` 之后的「距离日落」逐字相同 ——
    /// 两句话说的是两个不同的时段，各自与本档 deadline 对齐即可：降成 `.day` 的帧
    /// `deadline` 是 `sunset − 70min`（说「距离日落」对），留在 `.golden` 的帧
    /// `deadline` 是 `sunrise + 70min`（说「晨光剩余」对）。**词跟着 phase 走，不跟着天气走。**
    ///
    /// （唯一仍需调用方负责的是 `deadline`：词能自洽，时间轴不能凭空换。
    /// 所以调用方照旧应该传**已过 `effective`** 的 phase，这里只是把"词"这一半兜住。）
    ///
    /// - Parameter viewing: 判定结果；`nil`（没有数据）归到"不说颜色"这一边
    /// - Returns: 一句话里的那半句（不含倒计时）
    func label(viewing: SkyViewing.Verdict?) -> String {
        switch self {
        case .night:
            return "夜间"
        case .sunrise:
            return "日出"
        case .day:
            return "距离日落"
        case .sunset:
            return "日落剩余"
        case .blueDawn:
            // 晨间：天亮那一刻是天文事实，阴天照样发生 —— 所以中性词只说"天亮"
            return claimsColor(viewing: viewing) ? "蓝调剩余" : "天亮剩余"
        case .blueDusk:
            // 暮间：deadline = sunset + 30min，正是"入夜"那一刻
            return claimsColor(viewing: viewing) ? "蓝调剩余" : "入夜剩余"
        case .golden:
            // 「黄金时刻」只承诺颜色，`.golden` 的 deadline 是日出后 70 分钟 ——
            // 所以非通透时不能换成「距离日落」：那句话的语义锚在日落，而倒计时数的是
            // 日出后 70 分钟，屏幕上会读成"距离日落 39 分钟"，实际日落还有九个小时。
            // 词必须跟着已有的 deadline 走（与 `.blueDusk` → 「入夜剩余」同一手法）。
            //
            // 用 `== .clear` 而不是 `claimsColor` 是有意的：`.golden` 的配色容不下"有多云"
            // 这个中间态（色相差一整个轮，见 `effective`），只有真通透才敢说「黄金时刻」。
            // 而 `.veiled` / `.blocked` 到不了这里 —— `effective` 已把它们降成 `.day`，
            // 实际输入只有 `.clear` 与 `nil` 两种。
            return viewing == .clear ? "黄金时刻" : "晨光剩余"
        }
    }
}
