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

            VStack(alignment: .leading, spacing: 6) {
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
                    if let level = alert.severityText, !level.isEmpty {
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
        .accessibilityLabel("\(alert.typeName ?? "天气")预警，\(alert.severityText ?? "")。\(alert.shortText)")
    }

    /// 标题：有类型名时用「暴雨预警」而不是几十个字的台站全称 ——
    /// 台站名在横幅上读起来像公文，用户要的是"什么灾害、多严重"。
    private static func headline(for alert: WeatherAlert) -> String {
        if let type = alert.typeName?.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty {
            return type + "预警"
        }
        return alert.title
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
