import SwiftUI

/// 天光页的「今日天气面板」—— 下拉时从屏幕底部浮出来的那块玻璃卡。
///
/// 数据源是 `WeatherNow`（`GET /api/app/weather`，App 侧由 `WeatherStore` 缓存，
/// 本组件只吃快照、不发请求）。五个字段按"抬眼要看什么"排序：
/// ```
/// 18°  小雨                    ← 温度大字 + 天气现象（第一眼）
/// 最高 22° · 最低 11°           ← 今天穿多少
/// 东北风 3.2 m/s               ← 出门体感
/// 云量 85%                     ← 与天上的云对得上（这一页就是看天，所以云量必须给）
/// ```
///
/// 三条铁律（与全工程同源）：
/// 1. **没有的字段整行不渲染**：不写「—」、不写 0（0 m/s 是合法的"无风"）；
/// 2. `weather == nil` / `ok == false` 是正常状态（首装还没拉、断网），
///    只说「天气还没到」，绝不猜一个晴天出来；
/// 3. 颜色全部走 `Theme` token（玻璃 / 文字三级），本文件零颜色字面量。
struct SkyRoomWeatherPanel: View {

    /// 天气快照。nil = 还没拉到（不是错误）
    let weather: WeatherNow?
    /// 字号倍率（宽档 1.18）
    let scale: CGFloat
    /// 是否宽档（决定行距与内边距）
    let wide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: wide ? 16 : 14) {
            if let weather = weather, weather.ok, hasAnyReading(weather) {
                hero(weather)
                if !details(weather).isEmpty {
                    rule
                    detailRows(details(weather))
                }
            } else {
                placeholder
            }
        }
        .padding(wide ? 24 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.sheet, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: - 主视觉

    /// 温度大字 + 天气现象。温度取整用 `Int(_:)` 截断（与简报小组件
    /// `BriefFace.weatherHero` 同一写法）：21.9° 显示 21°，永远"不高于实际"。
    private func hero(_ weather: WeatherNow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let temp = weather.temp {
                Text("\(Int(temp))°")
                    .font(SkyRoomMetrics.TextStyle.temperature(scale))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let phrase = phrase(weather) {
                Text(phrase)
                    .font(SkyRoomMetrics.TextStyle.weather(scale))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 细节行

    private func detailRows(_ rows: [(label: String, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: wide ? 8 : 6) {
            ForEach(rows, id: \.label) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.label)
                        .font(SkyRoomMetrics.TextStyle.detail(scale))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(SkyRoomMetrics.TextStyle.detail(scale))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
    }

    /// 没数据时的口语化占位：不写「未知」，也不写「--」
    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("天气还没到")
                .font(SkyRoomMetrics.TextStyle.weather(scale))
                .foregroundStyle(Theme.textPrimary)
            Text("这一页只看天光，天气是顺带的。等它到了自己会出现。")
                .font(SkyRoomMetrics.TextStyle.detail(scale))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 派生文案

    /// 面板里至少要有一个"读数"才摆 hero（温度或现象有一头就够）
    private func hasAnyReading(_ weather: WeatherNow) -> Bool {
        return weather.temp != nil || phrase(weather) != nil
    }

    /// 天气现象：服务端中文描述优先，缺了才用八档视觉类型的中性名
    private func phrase(_ weather: WeatherNow) -> String? {
        if let text = weather.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        return weather.kind?.title
    }

    /// 高低温 / 风 / 云量 —— 缺哪个就不出哪一行（顺序即视觉顺序）
    private func details(_ weather: WeatherNow) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []

        if let high = weather.tMax, let low = weather.tMin {
            rows.append((label: "气温", value: "最高 \(Int(high))° · 最低 \(Int(low))°"))
        }

        if let speed = weather.wind {
            // 防风措辞：后端把 16 方位换算成中文（"东北"），这里只补一个「风」字 + 数值。
            // 缺方位就只报风速 —— 不编一个方向出来。
            let direction = weather.windDirText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let value = direction.isEmpty
                ? "风速 " + speedText(speed)
                : direction + "风 " + speedText(speed)
            rows.append((label: "风", value: value))
        }

        if let cloud = weather.cloud {
            rows.append((label: "云量", value: "\(Int(cloud))%"))
        }

        return rows
    }

    /// 风速两位有效数字就够（气象台口径 0.1 m/s），`String(format:)` 是全工程统一写法
    private func speedText(_ speed: Double) -> String {
        return String(format: "%.1f m/s", speed)
    }
}
