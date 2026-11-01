import Foundation

/// 天气「类型」：把 WMO 天气代码归成 **8 组可渲染的视觉类型**。
///
/// 代码来源：Open-Meteo 的 `weather_code` 字段，取值来自 **WMO 4677**（世界气象组织天气代码表）。
/// 本文件是这张表的唯一落点 —— 后端只透传数字代码，翻译成"什么天"是客户端的事。
///
/// 为什么要有这一层，而不是把 `code` 直接交给组件：
/// 两个小组件（简报的纸面轨迹、天光的天空）画法完全相反，但它们需要判断的其实只有 4 件事：
/// 「天上有多少云」「有没有东西落下来」「落的是雨还是雪」「要不要打闪电」。
/// 归成 8 组之后，渲染层再也不用碰代码表；将来后端换一套代码体系，只改这一个文件。
///
/// **本文件同时被主 App 与 Widget target 编译**（`project.yml` 里 Widget 只吃
/// `Sources/Widget` + `Sources/Shared`），所以只 import Foundation：
/// 不引 SwiftUI，不出现任何颜色 / 粒子数 / 动画参数 —— 那些属于各组件的画法，不属于数据层。
enum WeatherKind: String, CaseIterable, Sendable {

    /// 0 晴 / 1 晴间多云
    ///
    /// 1 是「mainly clear」——云量 10~20%，视觉上仍是蓝天。真要按云量细分，等于把
    /// 「一片薄高云飘过」也算成多云，卡片一天变三次脸，反而不可信，故与 0 合并。
    case clear

    /// 2 多云（partly cloudy，云量 25~50%）
    case partly

    /// 3 阴（overcast，云量 85% 以上）
    case overcast

    /// 45 雾 / 48 雾凇（depositing rime fog）
    ///
    /// 48 归雾而不是归雪：视觉上是"看不见远处"，落的不是雪粒，按雪画会误导。
    case fog

    /// 51 小毛毛雨 / 53 中 / 55 大毛毛雨 / 56 轻冻毛毛雨 / 57 强冻毛毛雨
    case drizzle

    /// 61 小雨 / 63 中雨 / 65 大雨 / 66 轻冻雨 / 67 强冻雨 /
    /// 80 小阵雨 / 81 中阵雨 / 82 强阵雨（暴雨）
    ///
    /// 阵雨（80~82）与连续雨（61~67）合并：对"画多少条雨丝"没区别，
    /// 差别只在时间分布上，那是 `BriefSection` 里 `rain` 那段文字要表达的事，不是视觉类型的事。
    case rain

    /// 71 小雪 / 73 中雪 / 75 大雪 / 77 雪粒 / 85 小阵雪 / 86 大阵雪
    case snow

    /// 95 雷雨 / 96 雷雨伴小冰雹 / 99 雷雨伴大冰雹
    ///
    /// 冰雹不单独成类：它总和雷暴同时出现，画面上"闪电 + 密雨"已经能表达，
    /// 多一类只会让两个组件各自发明一套冰雹画法。
    case thunder

    // MARK: - 代码映射

    /// WMO 代码 → 天气类型。
    ///
    /// 覆盖 27 个已知代码（0,1,2,3,45,48,51,53,55,56,57,61,63,65,66,67,
    /// 71,73,75,77,80,81,82,85,86,95,96,99）；**未知代码与 nil 一律返回 nil**。
    ///
    /// 为什么不兜底成 `.clear`：缺数据就说缺数据。兜底成晴天的后果是——
    /// 后端字段漏了、上游超时了，卡片依然阳光明媚地骗人，而这种"看起来正常"的错误
    /// 没有任何人会发现（这个项目里已经踩过一次）。nil 会被渲染层显式表达为"天气未知"。
    static func from(code: Int?) -> WeatherKind? {
        guard let code = code else { return nil }
        switch code {
        case 0, 1:
            return .clear
        case 2:
            return .partly
        case 3:
            return .overcast
        case 45, 48:
            return .fog
        case 51, 53, 55, 56, 57:
            return .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return .rain
        case 71, 73, 75, 77, 85, 86:
            return .snow
        case 95, 96, 99:
            return .thunder
        default:
            return nil
        }
    }

    // MARK: - 展示名

    /// 类型级中文名（**粗粒度**，只用于"没有服务端文案时"的兜底）。
    ///
    /// 接口还给了 `text`（"小雨"、"雷阵雨伴冰雹"这种精确描述），有 `text` 就应该用 `text`：
    /// 这里只有 8 个词，说不了"小"和"大"的区别。
    var title: String {
        switch self {
        case .clear:
            return "晴"
        case .partly:
            return "多云"
        case .overcast:
            return "阴"
        case .fog:
            return "雾"
        case .drizzle:
            return "毛毛雨"
        case .rain:
            return "雨"
        case .snow:
            return "雪"
        case .thunder:
            return "雷雨"
        }
    }

    // MARK: - 视觉语义（只是"比例"，不是画法）

    /// 云层密度 0…1 —— 归一化后的"天上该有多少云"。
    ///
    /// 这是**语义值不是渲染值**：组件拿它去乘自己的层数 / 透明度 / 漂移速度都行，
    /// 但"0.95 到底画几层、多快"由组件决定。之所以给 8 个固定档而不是用接口的 `cloud` 百分比：
    /// `cloud` 是可选字段（空值不占位），缺了就没了；而类型本身已经蕴含了量级 ——
    /// 阴天不管百分比是多少，画出来就该是满云。
    var cloudiness: Double {
        switch self {
        case .clear:
            return 0
        case .partly:
            return 0.45
        case .overcast:
            return 0.95
        case .fog:
            // 雾天云量其实很高，但"看得见云"不是重点，重点是能见度 —— 0.6 让雾自己压上去
            return 0.6
        case .drizzle:
            return 0.7
        case .rain:
            return 0.85
        case .snow:
            return 0.8
        case .thunder:
            return 0.95
        }
    }

    /// 落下来的东西是什么。
    ///
    /// `nil` = **这类天不产生降水粒子**（晴 / 多云 / 阴 / 雾）。
    /// 那为什么还要有 `Precipitation.none`：给"需要一个非可选值"的调用方留正解 ——
    /// `kind.precipitation ?? .none` 是全工程统一的降级写法，省得每个组件自己写
    /// `?? .rain` 这种顺手写错、又只在某种天气下才暴露的默认值。
    enum Precipitation: String, Sendable {
        /// 明确不下（不会由 `precipitation` 返回，只会经由 `??` 出现）
        case none
        /// 毛毛雨：极细、几乎不落，画"空气里的湿气"而不是雨丝
        case drizzle
        /// 雨（含阵雨、冻雨、雷雨里的雨）
        case rain
        /// 雪（含雪粒、阵雪）
        case snow
    }

    /// 降水类型（无降水为 nil，理由见 `Precipitation.none` 的注释）
    var precipitation: Precipitation? {
        switch self {
        case .clear, .partly, .overcast, .fog:
            return nil
        case .drizzle:
            return .drizzle
        case .rain:
            return .rain
        case .snow:
            return .snow
        case .thunder:
            // 雷暴的"落下来"部分始终是雨（冰雹随雨一起，不单独成类）
            return .rain
        }
    }

    /// 是否强对流（要不要加闪电）。目前只有雷暴一类。
    var isSevere: Bool {
        return self == .thunder
    }

    // MARK: - 强度

    /// 降水强度 0…1，用来控制"雨丝条数 / 雪点密度 / 落速"这类**数量**。
    ///
    /// 与 `cloudiness` 同样是语义值：0.35 说的是"小雨"，具体画 12 条还是 20 条雨丝归组件。
    ///
    /// 为什么按代码细分而不是按类型给一个固定值：类型只有 8 组，`63`（中雨）和 `65`（大雨）
    /// 都在 `.rain` 里，只按类型给值就只能一律 0.6；实际体感上"中雨"和"大雨"差着一个量级。
    ///
    /// 映射表（落在 0.25~1.0 之间，无降水与未知代码为 0）：
    /// ```
    /// 毛毛雨  51:0.25  53:0.40  55:0.55   56:0.30  57:0.45
    /// 雨      61:0.35  63:0.60  65:1.00   66:0.45  67:0.75
    ///         80:0.45  81:0.70  82:1.00
    /// 雪      71:0.30  73:0.55  75:0.85   77:0.25  85:0.50  86:0.85
    /// 雷      95:0.70  96:0.90  99:1.00
    /// ```
    /// 雪的数值刻意偏低：雪片比雨丝大得多，同数量的雪在画面上已经"很满"，
    /// 按雨的百分比给会糊成一片白（0.85 的雪 ≈ 1.0 的雨）。
    ///
    /// - Parameter code: WMO 代码；nil 或未知返回 0（当作"无降水"处理，不猜）
    static func intensity(code: Int?) -> Double {
        guard let code = code else { return 0 }
        switch code {
        // 毛毛雨：细到几乎不落，强度上限也压得低
        case 51:
            return 0.25
        case 53:
            return 0.40
        case 55:
            return 0.55
        // 冻毛毛雨（56/57）比同级的普通毛毛雨略轻：冻雨视觉上更"慢"，粒子少而重
        case 56:
            return 0.30
        case 57:
            return 0.45
        // 连续雨
        case 61:
            return 0.35
        case 63:
            return 0.60
        case 65:
            return 1.00
        // 冻雨：同样是"看起来比实际轻"，但比毛毛雨重
        case 66:
            return 0.45
        case 67:
            return 0.75
        // 阵雨：来得急去得快，视觉密度比同量级的连续雨低一档
        case 80:
            return 0.45
        case 81:
            return 0.70
        case 82:
            return 1.00
        // 雪
        case 71:
            return 0.30
        case 73:
            return 0.55
        case 75:
            return 0.85
        // 77 雪粒：颗粒极小，密度给高会像噪点，压到最低档
        case 77:
            return 0.25
        case 85:
            return 0.50
        case 86:
            return 0.85
        // 雷暴：雨本身很密，闪电由 `isSevere` 单独表达
        case 95:
            return 0.70
        case 96:
            return 0.90
        case 99:
            return 1.00
        default:
            return 0
        }
    }
}
