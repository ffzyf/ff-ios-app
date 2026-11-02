import SwiftUI

/// 天光页的「预警 / 分钟降水 / 体感与空气」三块（3.19.0）。
///
/// 为什么单独一个文件，不并进 `SkyRoomCards.swift`：那四个卡片是**天气本身**的静态切片
/// （温度区间、风、云、天光），数据来自一次请求；这里三块各有自己的刷新节奏与失效语义
/// （预警 5 分钟、分钟降水 5 分钟、体感随天气 30 分钟）。放一起会让人以为它们同寿。

// MARK: - 预警横幅

/// 天气预警横幅。
///
/// 刻意**不用** `SkyRoomCardShell`：那个壳是"半透明玻璃 + 主题白纱"，它服务于
/// "信息浮在天上"的美感。预警恰好相反 —— 它必须在任何天色下都第一时间被看见，
/// 所以用预警色本身做底（低透明度）+ 同色描边 + 左侧实心竖条，靠色彩而不是玻璃质感抓眼睛。
///
/// 严重级别（`severe` / `extreme`）时整体加重一档：底色与描边各提一点不透明度。
struct SkyRoomAlertBanner: View {

    let alert: WeatherAlert
    let scale: CGFloat

    private var tint: Color {
        return Theme.alertColor(alert.colorHex)
    }

    /// 严重预警底色更实一点。0.14 → 0.22 是"仍能透出天色，但明显比普通预警更重"。
    private var fillOpacity: Double {
        return alert.isSevere ? 0.22 : 0.14
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint)
                .frame(width: 4)

            // 三行结构：① 什么灾害、多严重 ② 谁发布的、几点 ③ 一句话说的是什么。
            // 顺序不是排版偏好 —— 用户读预警时问的正是这三件事，而它们的答案以前
            // 全挤在一行里（发布单位干脆丢了，只剩一个"暴雨预警"）。
            VStack(alignment: .leading, spacing: 6) {
                // ① 主行：类型 + 级别
                HStack(spacing: 6) {
                    Image(systemName: Self.iconName(for: alert))
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(Self.headline(for: alert))
                        .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    // 级别 pill：主行已经写了"· 黄色预警"，这里就不再重复整句，
                    // 只留一个短词 + 色胶囊。
                    //
                    // 为什么不索性删掉：pill 的**底色**是级别信息本身（黄/橙/红），
                    // 而主行那一行在极端天气下会被 `minimumScaleFactor` 压小，
                    // 色块比缩过的小字更快被眼睛抓到。文字留着是为了色觉障碍用户。
                    if let level = Self.levelWord(of: alert) {
                        Text(level)
                            .font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                Capsule(style: .continuous).fill(tint.opacity(0.18))
                            }
                    }
                }

                // ② 次行：「郑州市气象台 · 18:20 发布」。两者各自可缺，
                // 都缺时整行不渲染（`publisherLine` 返回 nil）——
                // 这一行是为了回答"这是谁说的"，宁可没有，也不留空占位。
                if let publisher = Self.publisherLine(for: alert) {
                    Text(publisher)
                        .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                // ③ 正文：防御指南的第一句
                Text(alert.shortText)
                    .font(.system(size: 12 * scale, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            shape
                .fill(tint.opacity(fillOpacity))
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.strokeBorder(tint.opacity(alert.isSevere ? 0.55 : 0.35), lineWidth: 1))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityLabel(for: alert))
    }

    /// 主行：「暴雨 · 黄色预警」。
    ///
    /// 三段各自可缺，缺口的处理**不是**留空，而是退到下一档表达：
    /// 没有级别词 → 「暴雨预警」；连类型名都没有 → 整条 headline（现状兜底）。
    /// 之所以退到 headline 而不是只说"天气预警"：`title` 至少是上游的原话，
    /// 丢信息比多几个字更糟。
    private static func headline(for alert: WeatherAlert) -> String {
        return compose(type: typeWord(of: alert),
                       level: levelWord(of: alert),
                       fallback: alert.title)
    }

    /// 读屏用的主行：「暴雨 · 严重预警」—— 级别取的是**严重度**，不是四色。
    ///
    /// 两个出口各挑各的词，不是不一致，而是两种媒介能承载的信息不同：
    /// 屏幕上的等级词必须与左侧色条同体系（四色），否则一张卡上两套等级；
    /// 而读屏用户根本看不见那条色块，此时「严重」比「黄色」更能直接回答
    /// "要不要现在就躲一下" —— 紧急程度才是听觉通道最该先说的事。
    private static func spokenHeadline(for alert: WeatherAlert) -> String {
        return compose(type: typeWord(of: alert),
                       level: severityWord(of: alert),
                       fallback: alert.title)
    }

    /// 拼「类型 · 级别预警」。类型缺了退回整条 `title`（上游原话），
    /// 级别缺了只说「暴雨预警」—— 不留悬空的「· 预警」。
    private static func compose(type: String?, level: String?, fallback: String) -> String {
        guard let type else { return fallback }
        guard let level else { return type + "预警" }
        return "\(type) · \(level)预警"
    }

    /// 类型名（去空白后的「暴雨」）。空串一律当成"没有"，
    /// 这样下面几处判断不用各自写一遍 `?.trimmingCharacters`。
    private static func typeWord(of alert: WeatherAlert) -> String? {
        let type = alert.typeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return type.isEmpty ? nil : type
    }

    /// 级别短词（「蓝色」「黄色」…），主行与 pill 共用。
    ///
    /// 取的是**官方四色等级**，不是 `severityText`。后者是「轻微 / 中等 / 严重 / 特别严重」
    /// 的严重度评级（见 `WeatherAlert.severityText`），而气象台对外发布用的是四色 ——
    /// 用户从广播里听到、在预警短信里读到的都是「暴雨黄色预警」。用严重度词会得到
    /// 「暴雨 · 严重预警」，可卡片左侧那条色块又是黄的：同一张卡上两套体系，
    /// 用户会以为「严重」是我们的自评。
    ///
    /// 颜色只存在 `colorHex` 里（`severityText` 不含色名），所以只能按色值反查 ——
    /// 色值到四色的映射与后端 `_lib/qweather.js` 的 `SEVERITY_COLOR_HEX` 逐字对齐。
    /// `#F59E0B` 归到黄档：那是后端认不出颜色时的兜底值，视觉上就是琥珀黄。
    ///
    /// 查不到色（老接口没给 / 上游换了色值）才退回严重度词 —— 有一个不完美但相关的
    /// 词，总好过 pill 空着。「未知」不返回：它不是一个级别，写出来只是噪音。
    private static func levelWord(of alert: WeatherAlert) -> String? {
        if let hex = alert.colorHex?.uppercased() {
            switch hex {
            case "#3B82F6": return "蓝色"
            case "#EAB308", "#F59E0B": return "黄色"
            case "#F97316": return "橙色"
            case "#EF4444": return "红色"
            default: break
            }
        }
        return severityWord(of: alert)
    }

    /// 严重度短词（「严重」「特别严重」）—— **只给读屏用**（见 `spokenHeadline`）。
    ///
    /// 结尾的「预警」去掉：调用方会补一个，不剥就成「严重预警预警」。
    /// 「未知」当成没有：它不是一个级别。
    private static func severityWord(of alert: WeatherAlert) -> String? {
        guard let raw = alert.severityText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw != "未知" else { return nil }
        let short = raw.hasSuffix("预警") ? String(raw.dropLast(2)) : raw
        return short.isEmpty ? nil : short
    }

    /// 次行：「郑州市气象台 · 18:20 发布」。两者各自可缺，都缺 → nil。
    ///
    /// 这里逐个 `if` 往数组里塞而不是拼字符串，就是为了让「只有台站没有时间」
    /// 这种真实存在的情况（`pubTime` 解析失败）读起来是「郑州市气象台」，
    /// 而不是「郑州市气象台 ·  发布」。
    private static func publisherLine(for alert: WeatherAlert) -> String? {
        var parts: [String] = []
        // 只有主行是「暴雨 · 黄色预警」这种缩写时才补台站行。
        // 没有 `typeName` 时主行退成了整条 `title`（「郑州市气象台发布暴雨黄色预警」），
        // 台站已经在里面了 —— 再补一行就是把同一句话切成两半说两遍。
        if typeWord(of: alert) != nil, let station = stationName(of: alert) {
            parts.append(station)
        }
        if let date = alert.pubDate {
            parts.append(Formatters.timeHHmm(date) + " 发布")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 从 headline 里切出发布台站。
    ///
    /// 和风的 `title` 是「郑州市气象台发布暴雨黄色预警」这种整句，发布单位只在这里面 ——
    /// `WeatherAlert` 没有独立字段（上游的新版 weatheralert 接口把它塞在 headline 里）。
    /// 所以只能按「发布」二字切前缀：切不出来就返回 nil，**不要**拿整个 title 兜底，
    /// 那会让标题行和台站行重复同一句话。
    ///
    /// 长度 > 20 也返回 nil：那说明「发布」前面不是台站名（可能是「预计未来三小时…发布」
    /// 这类句式），硬切出来的半句话放在台站的位置上比不显示更糟。
    /// 结尾的「气象台」「气象局」原样保留 —— 那是发布主体身份的一部分，删掉就只剩地名。
    private static func stationName(of alert: WeatherAlert) -> String? {
        guard let range = alert.title.range(of: "发布") else { return nil }
        let head = String(alert.title[alert.title.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty, head.count <= 20 else { return nil }
        return head
    }

    /// 读屏稿：把三行拼成一句人话，台站在最前面 —— 听到的第一件事应该是"谁说的"。
    ///
    /// 级别走 `spokenHeadline`（严重度词）而不是屏幕上那套四色词，理由见它的注释。
    private static func accessibilityLabel(for alert: WeatherAlert) -> String {
        var sentence = spokenHeadline(for: alert)
        if typeWord(of: alert) != nil, let station = stationName(of: alert) {
            sentence = station + "发布" + sentence
        }
        if let date = alert.pubDate {
            sentence += "，" + Formatters.timeHHmm(date) + "发布"
        }
        return sentence + "。" + alert.shortText
    }

    /// 灾害类型 → SF Symbol。认不出来的类型统一用三角警告，
    /// **不要**按级别取图标：级别已经由颜色和文字标签表达了，图标该说明"是什么灾"。
    private static func iconName(for alert: WeatherAlert) -> String {
        let type = (alert.typeName ?? "") + alert.title
        if type.contains("暴雨") || type.contains("大雨") { return "cloud.heavyrain.fill" }
        if type.contains("雷") { return "cloud.bolt.rain.fill" }
        if type.contains("冰雹") { return "cloud.hail.fill" }
        if type.contains("雪") { return "cloud.snow.fill" }
        if type.contains("大风") || type.contains("台风") { return "wind" }
        if type.contains("沙") || type.contains("尘") { return "sun.dust.fill" }
        if type.contains("雾") || type.contains("霾") { return "cloud.fog.fill" }
        if type.contains("高温") || type.contains("热") { return "thermometer.sun.fill" }
        if type.contains("寒") || type.contains("低温") || type.contains("霜") { return "thermometer.snowflake" }
        if type.contains("道路结冰") || type.contains("结冰") { return "snowflake" }
        return "exclamationmark.triangle.fill"
    }
}

// MARK: - 无预警状态行

/// 无预警时的常驻状态行。
///
/// 为什么要有它：之前「没有预警」等于「这块区域不存在」，用户无法区分
/// 「今天确实没有预警」和「预警功能没接 / 接口挂了」。一条 20pt 高的行就能消除这个歧义。
///
/// 为什么不用卡片底板：这是「一切正常」的信息，视觉重量必须低于任何一条实况卡 ——
/// 否则每天占着一块卡片的位置说「没事」，反而制造焦虑。
///
/// 为什么 `.unknown` 也不用警示色：「拿不到数据」不是「有灾害」。用一个橙色三角去说
/// "接口挂了"，用户会先以为要下暴雨了，然后才发现是 App 的问题 —— 那是消耗信任。
struct SkyRoomAlertStatusRow: View {

    /// .none = 确认无预警；.unknown = 拿不到（不要把「不知道」渲染成「没有」）
    enum State {
        case none
        case unknown
    }

    let state: State
    let updatedAt: Date?
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(title)
                .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            // 右侧小字可缺：`.none` 且 `updatedAt == nil` 时只留「和风天气」，
            // `.unknown` 时它是一句承诺（我们真的会自动重试，见 `AlertStore.startPolling`）
            Text(detail)
                .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        // 高度靠内容撑（约 20pt），不设固定 frame：动态字体放大时它该跟着长，
        // 钉死高度只会换来一行被裁掉的字
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 不做手势、不可点：点它没有去处，可点的东西必须有反馈，这里给不出
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + "，" + detail)
    }

    private var iconName: String {
        switch state {
        case .none: return "checkmark.shield"
        case .unknown: return "exclamationmark.triangle"
        }
    }

    private var title: String {
        switch state {
        case .none: return "当前无天气预警"
        case .unknown: return "预警数据暂时取不到"
        }
    }

    /// 右侧小字。`.none` 时是「和风天气 · 18:20 更新」，时间那半句按 `updatedAt` 有无拼接 ——
    /// **不要**写成 `"和风天气 · \(time) · 更新"`，`updatedAt` 为 nil 时会渲染出
    /// 「和风天气 ·  · 更新」这种空占位（自查项 2）。
    private var detail: String {
        switch state {
        case .none:
            guard let updatedAt else { return "和风天气" }
            return "和风天气 · " + Formatters.timeHHmm(updatedAt) + " 更新"
        case .unknown:
            return "稍后自动重试"
        }
    }
}

// MARK: - 分钟降水

/// 未来两小时的分钟级降水。
///
/// 没有数据时**整块不渲染**（由调用方判断 `hasData`）—— 不显示"暂无数据"的空壳，
/// 那种空壳只会在每次打开页面时提醒用户"这里本来有条信息"，纯噪声。
struct SkyRoomMinutelyCard: View {

    let rain: MinutelyRain
    let scale: CGFloat

    /// 柱状区高度（pt）
    private static let barHeight: CGFloat = 38

    var body: some View {
        SkyRoomCardShell(title: "未来两小时", accessory: accessoryText, scale: scale) {
            VStack(alignment: .leading, spacing: 10) {
                if let summary = rain.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 15 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let points = rain.points, !points.isEmpty {
                    bars(points)
                }
            }
        }
    }

    /// 右上角辅注：现在下没下。
    private var accessoryText: String? {
        guard let points = rain.points, !points.isEmpty else { return nil }
        if rain.isWet { return "正在下" }
        return "暂无降水"
    }

    /// 24 根柱子，每根 5 分钟。
    ///
    /// 为什么用 `Capsule` 一列而不是 `Canvas`：24 个纯色圆角矩形交给 SwiftUI 的合成层
    /// 比每帧重绘一次画布便宜得多，而且它天然随 `scale` 与主题色走。
    /// 高度按 `scaleMax` 归一化 —— 全是毛毛雨时也撑得起来（下限 0.5mm 见模型）。
    private func bars(_ points: [MinutelyRain.Point]) -> some View {
        let maxValue = rain.scaleMax
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                let ratio = maxValue > 0 ? min(point.p / maxValue, 1) : 0
                let height = max(2, Self.barHeight * CGFloat(ratio))
                Capsule(style: .continuous)
                    .fill(point.p > 0.01 ? Theme.textPrimary.opacity(0.78) : Theme.textTertiary.opacity(0.28))
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
        .frame(height: Self.barHeight, alignment: .bottom)
        .accessibilityLabel("未来两小时降水强度")
    }
}

// MARK: - 体感与空气

/// 体感 / 湿度 / 空气 / 紫外线 / 气压。
///
/// 这些是**同一个体感层面**的信息：都在回答"外面待着舒不舒服"，
/// 而现有的「今日气温」卡回答的是"今天多少度"。分成两张卡，各自语义才清楚。
///
/// 任何一项缺省就整格不渲染（`metric` 返回 nil 时 `if let` 直接跳过），
/// 不显示 "—" 占位：一行破折号比少一行更难读。
struct SkyRoomComfortCard: View {

    let weather: WeatherNow?
    let scale: CGFloat

    var body: some View {
        let items = metrics
        return Group {
            if items.isEmpty {
                EmptyView()
            } else {
                SkyRoomCardShell(title: "体感与空气", scale: scale) {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12, alignment: .leading),
                        GridItem(.flexible(), spacing: 12, alignment: .leading)
                    ], spacing: 12) {
                        ForEach(items) { item in
                            cell(item)
                        }
                    }
                }
            }
        }
    }

    /// 一条指标。`id` 用标题，天然唯一。
    private struct Metric: Identifiable {
        let id: String
        let title: String
        let value: String
        /// 值的着色（空气质量用分档色，其余走主题主文字色）
        let tint: Color?
    }

    private var metrics: [Metric] {
        guard let weather, weather.ok else { return [] }
        var out: [Metric] = []

        if let feels = weather.feelsLike {
            // 体感与气温差 ≥3° 才值得单独强调 —— 差 1 度是测量误差，不值得占一行
            var tint: Color?
            if let temp = weather.temp, abs(feels - temp) >= 3 { tint = Theme.textPrimary }
            out.append(Metric(id: "feels", title: "体感", value: "\(Int(feels.rounded()))°", tint: tint))
        }
        if let humidity = weather.humidity {
            out.append(Metric(id: "humidity", title: "湿度", value: "\(Int(humidity.rounded()))%", tint: nil))
        }
        if let air = weather.air {
            let text = air.category.map { "\(air.aqi) \($0)" } ?? "\(air.aqi)"
            out.append(Metric(id: "air", title: "空气", value: text, tint: Theme.aqiColor(air.level)))
        }
        if let uv = weather.uvIndex {
            out.append(Metric(id: "uv", title: "紫外线", value: Self.uvText(uv), tint: nil))
        }
        if let pressure = weather.pressure {
            out.append(Metric(id: "pressure", title: "气压", value: "\(Int(pressure.rounded())) hPa", tint: nil))
        }
        return out
    }

    private func cell(_ item: Metric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                .foregroundStyle(Theme.textTertiary)
            Text(item.value)
                .font(.system(size: 17 * scale, weight: .medium, design: .rounded))
                .foregroundStyle(item.tint ?? Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 紫外线指数 → 中文档位（沿用国际通行五档）。
    /// 直接显示数字对普通用户没有意义，"很强"才是能行动的信息。
    private static func uvText(_ index: Int) -> String {
        switch index {
        case ..<3: return "\(index) 低"
        case 3..<6: return "\(index) 中等"
        case 6..<8: return "\(index) 高"
        case 8..<11: return "\(index) 很高"
        default: return "\(index) 极高"
        }
    }
}

// MARK: - 数据来源与更新时间（3.20.0）

/// 卡片区底部的一行「这屏天气是谁说的、什么时候说的」。
///
/// 为什么要把这件事写在界面上：现在天气是四个源拼出来的（和风主、心知补位与比对、
/// Open-Meteo 补天空参数、高德抽样），同一个坐标上四家经常差 2~3℃。用户看到 18℃
/// 却觉得明明 23℃，唯一能自证的不是解释，而是「这是和风 14:20 报的」——
/// 有了这一行，偏差就从「App 乱报」变成了「这家源在我这个位置偏冷」，是两种完全不同的结论。
///
/// 为什么放在卡片**外面**、不用卡片壳：它不是天气内容，是元信息。
/// 套一层玻璃卡会让它读起来像第五张数据卡，权重过高。一段低对比度的小字足够。
///
/// 缺省语义：`provider` 与 `updatedAt` 各自独立判断，缺哪个就少说哪半句，
/// 绝不用 "—" 占位（那会让「不知道」看起来像「查到了但是空的」）。
struct SkyRoomSourceFooter: View {

    let weather: WeatherNow?
    /// 页面级的分钟级走时（`TimelineView(.periodic(by: 60))`），"N 分钟前" 靠它自己变
    let now: Date
    let scale: CGFloat

    var body: some View {
        let parts = segments
        return Group {
            if parts.isEmpty {
                EmptyView()
            } else {
                Text(parts.joined(separator: " · "))
                    .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                    // 它是元信息，读屏时降级为「辅助说明」，不与天气正文抢焦点
                    .accessibilityLabel(accessibilityText)
            }
        }
    }

    /// 拼句子：来源 → 钟点 → 相对时间。三段各自可缺。
    private var segments: [String] {
        guard let weather, weather.ok else { return [] }
        var out: [String] = []

        if let raw = weather.provider, !raw.isEmpty {
            out.append(Self.sourceLabel(raw))
        }
        if let updated = weather.updatedAt {
            out.append("\(Formatters.timeHHmm(updated)) 更新")
            // 观测时间超过 3 小时说明上游很久没刷新（或我们读到的是旧缓存），
            // 这时「几小时前」比钟点更有信息量，两个都给出来
            let age = now.timeIntervalSince(updated)
            if age >= 3 * 3600 {
                out.append(Formatters.relative(updated, now: now))
            }
        }
        return out
    }

    private var accessibilityText: String {
        segments.isEmpty ? "" : "天气数据：" + segments.joined(separator: "，")
    }

    /// 后端的 `provider` 是 `+` 连接的机器名（`qweather+open-meteo`），这里翻成人话。
    ///
    /// 未知名字原样保留而不是丢掉：将来加第五个源时，界面上出现一个没翻译的英文名
    /// 比「这屏天气没有来源」要好 —— 前者是待补的文案，后者是错误的信息。
    static func sourceLabel(_ raw: String) -> String {
        let names: [String: String] = [
            "qweather": "和风天气",
            "seniverse": "心知天气",
            "open-meteo": "Open-Meteo",
            "amap": "高德"
        ]
        let parts = raw.split(separator: "+").map { token -> String in
            let key = String(token).trimmingCharacters(in: .whitespaces)
            return names[key] ?? key
        }.filter { !$0.isEmpty }
        return parts.isEmpty ? raw : parts.joined(separator: " + ")
    }
}
