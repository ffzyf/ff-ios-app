import SwiftUI

/// 天光页 3.13.0 的**卡片流**——调研（Apple 天气 / Pixel 天气 / 墨迹 / 彩云）的共性落地：
/// 背景负责氛围，信息由玻璃卡承载，卡片在标准 `ScrollView` 里滚动、松手后**留在原地**。
///
/// 四张卡全部只吃接口已有的字段（温度 / 现象 / 高低温 / 风 / 云量 / 日出日落），
/// **没有的数据不放假卡**——不编湿度、不编 UV（那是 3.12.0 没犯、也不能犯的错）。
///
/// 三条纪律（全工程通用，自 3.10.0 天气面板时代沿用）：
/// 1. 没有的字段整行不渲染：不写「—」、不写 0；
/// 2. `weather == nil` / `ok == false` 是正常状态，文案说「还没到」，绝不猜一个晴天出来；
/// 3. 颜色全部走 `Theme` token 与 `sky` 六 token，本文件零颜色字面量。
// MARK: - 卡片外壳

/// 统一的玻璃卡壳：标题行（标题 + 右侧辅注）+ 内容。
/// 材质与全 App 同源（`glassSurface(.card)`），读起来是 Pixel 天气那套"悬浮卡"。
struct SkyRoomCardShell<Content: View>: View {

    let title: String
    /// 右上角辅注（可选）——放"当前阶段"这类一句话状态
    var accessory: String? = nil
    let scale: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(SkyRoomMetrics.TextStyle.cardTitle(scale))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let accessory, !accessory.isEmpty {
                    Text(accessory)
                        .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

// MARK: - 卡片① 今日天光（本 App 的身份卡）

/// 日弧进度：从日出到日落的一条进度线，太阳游标标出现在，
/// 中央是「距日落 / 距日出」的秒级倒计时。夜里游标停在端点、倒计时指向下一次日出。
struct SkyRoomDaylightCard: View {

    let now: Date
    /// 已解析的日出日落（view 侧统一算好传入：优先天气接口，回落 `SunClock`，夜里顺延明天）
    let sunrise: Date
    let sunset: Date
    let sky: Theme.SkyColors
    let scale: CGFloat

    var body: some View {
        SkyRoomCardShell(title: "今日天光",
                         accessory: SunClock.phase(at: now).label,
                         scale: scale) {
            VStack(alignment: .leading, spacing: 10) {
                progressLine
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("日出 " + Formatters.timeHHmm(sunrise))
                        .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    Text(countdown)
                        .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Text("日落 " + Formatters.timeHHmm(sunset))
                        .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
            }
        }
    }

    /// 进度线：轨道 = divider，已走过的部分 = 地平线暖色，游标 = 该档最亮的 `sky.edge`。
    /// 全部是静态形状 + 一次性布局，秒级变化只发生在倒计时文字上（外层 TimelineView 刷新）。
    private var progressLine: some View {
        let span = max(sunset.timeIntervalSince(sunrise), 1)
        let raw = now.timeIntervalSince(sunrise) / span
        let progress = CGFloat(min(max(raw, 0), 1))

        return GeometryReader { proxy in
            let width = proxy.size.width
            let knob = 10.0
            ZStack(alignment: .leading) {
                // 轨道
                Capsule()
                    .fill(Theme.divider)
                // 已走过的白昼
                Capsule()
                    .fill(sky.horizon.opacity(0.85))
                    .frame(width: max(0, min(width * progress, width)))
                // 太阳游标
                Circle()
                    .fill(sky.edge)
                    .frame(width: knob, height: knob)
                    .overlay(
                        Circle().strokeBorder(sky.edge.opacity(0.35), lineWidth: 3)
                    )
                    .offset(x: max(0, min(width * progress - knob / 2, width - knob)))
            }
        }
        .frame(height: 10)
    }

    /// 中央倒计时：白天指向日落，夜里（含日落后）指向下一次日出。
    private var countdown: String {
        if now < sunrise {
            return "距日出 " + SkyPhase.countdownText(to: sunrise, now: now)
        }
        if now >= sunset {
            return "已日落"
        }
        return "距日落 " + SkyPhase.countdownText(to: sunset, now: now)
    }
}

// MARK: - 卡片② 今日气温（范围条 + 当前温度游标）

/// Apple 天气"10 日预报"那条温度范围条的移植：
/// 整条轨道 = 今日最低…最高的区间，游标 = 现在的温度落在哪。
struct SkyRoomTemperatureCard: View {

    let weather: WeatherNow?
    let sky: Theme.SkyColors
    let scale: CGFloat

    var body: some View {
        SkyRoomCardShell(title: "今日气温", scale: scale) {
            if let weather, weather.ok, let low = weather.tMin, let high = weather.tMax, high >= low {
                VStack(alignment: .leading, spacing: 10) {
                    rangeBar(weather: weather, low: low, high: high)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("最低 \(Int(low))°")
                            .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                        Spacer(minLength: 8)
                        if let temp = weather.temp {
                            Text("现在 \(Int(temp))°")
                                .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                                .foregroundStyle(Theme.textPrimary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text("最高 \(Int(high))°")
                            .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                }
            } else {
                Text("今天的范围还没到")
                    .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// 范围条：从冷到暖的横向渐变（同一 token 的两端不透明度差，不造新色），
    /// 游标标出当前温度在区间里的位置（越界时夹到端点——不猜）。
    private func rangeBar(weather: WeatherNow, low: Double, high: Double) -> some View {
        let span = max(high - low, 1)
        let clampedTemp = weather.temp.map { min(max($0, low), high) }
        let progress = clampedTemp.map { CGFloat(($0 - low) / span) }

        return GeometryReader { proxy in
            let width = proxy.size.width
            let knob = 10.0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: sky.horizon.opacity(0.45), location: 0),
                                .init(color: sky.horizon.opacity(0.95), location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                if let progress {
                    Circle()
                        .fill(sky.edge)
                        .frame(width: knob, height: knob)
                        .overlay(
                            Circle().strokeBorder(Theme.glassFillStrong, lineWidth: 3)
                        )
                        .offset(x: max(0, min(width * progress - knob / 2, width - knob)))
                }
            }
        }
        .frame(height: 10)
    }
}

// MARK: - 卡片③④ 半宽双列（风 / 云量）

/// 风：大数值 = 风速，细节 = 方向。方向是**服务端换算好的中文**（16 方位），
/// 这里只透传——三端各换算一份迟早出现「App 说东北、小组件说东东北」的分叉。
struct SkyRoomWindCard: View {

    let weather: WeatherNow?
    let scale: CGFloat

    var body: some View {
        SkyRoomCardShell(title: "风", scale: scale) {
            if let weather, weather.ok, let speed = weather.wind {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", speed))
                            .font(SkyRoomMetrics.TextStyle.cardValue(scale))
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("m/s")
                            .font(SkyRoomMetrics.TextStyle.cardUnit(scale))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Text(directionText(weather))
                        .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            } else {
                Text("还没到")
                    .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func directionText(_ weather: WeatherNow) -> String {
        let direction = weather.windDirText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return direction.isEmpty ? "风速" : direction + "风"
    }
}

/// 云量：大数值 = 百分比。这一页本身就是看天，云量与天上画的云（`kind.cloudiness`）
/// 正好互相印证——数字来自接口，云的浓淡来自天色档位，两者各走各的 token。
struct SkyRoomCloudCard: View {

    let weather: WeatherNow?
    let scale: CGFloat

    var body: some View {
        SkyRoomCardShell(title: "云量", scale: scale) {
            if let weather, weather.ok, let cloud = weather.cloud {
                Text("\(Int(cloud))%")
                    .font(SkyRoomMetrics.TextStyle.cardValue(scale))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("还没到")
                    .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}
