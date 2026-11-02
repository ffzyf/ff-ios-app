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

/// 卡片底板「随滚动显现」的程度（0…1）。由 `SkyRoomView` 按滚动进度注入，
/// 卡片壳自己读 —— 这样 4 张卡片的构造点一个参数都不用加。
///
/// 为什么走 Environment 而不是逐张传参：卡片是 `SkyRoomCardShell` 的内部细节，
/// 调用方（`SkyRoomDaylightCard` 等）不该知道"底板现在有多实"。加参数等于把
/// 一个纯视觉状态漏进 4 个组件的公开 API，以后第 5 张卡还得再传一遍。
private struct SkyRoomGlassRevealKey: EnvironmentKey {
    /// 默认 1（全显）：不在天光页里用这套卡片时，行为与 3.17.0 完全一致
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var skyRoomGlassReveal: CGFloat {
        get { self[SkyRoomGlassRevealKey.self] }
        set { self[SkyRoomGlassRevealKey.self] = newValue }
    }
}

/// 统一的玻璃卡壳：标题行（标题 + 右侧辅注）+ 内容。
///
/// ## 3.18.0：底板与内容分离，底板随滚动"长出来"
///
/// 用户原话：「正常时它是透明的只显示文字，如果上滑，让它的可见度高一些，
/// 把白色毛玻璃显示出来」。所以底板不再是卡片的一部分，而是**内容后面的一层**：
///
/// · `reveal == 0` → 底板完全透明，卡片只剩文字浮在天上（首屏就是这样）；
/// · 上滑 → `reveal` 涨到 1，白色毛玻璃（浅色）/ 淡白雾（深色）显出来。
///
/// 颜色仍然全部走 `Theme` 的玻璃 token（`glassFill` 浅色是白 72%、深色是白 6%），
/// 于是"白天白玻璃、夜里深玻璃"是 token 自动给的，本文件不需要判断 `colorScheme`
/// （主题闸门第 2 条也禁止在 View 层判断）。
struct SkyRoomCardShell<Content: View>: View {

    let title: String
    /// 右上角辅注（可选）——放"当前阶段"这类一句话状态
    var accessory: String? = nil
    let scale: CGFloat
    @ViewBuilder let content: () -> Content

    /// 底板显现程度（见 `SkyRoomGlassRevealKey`）
    @Environment(\.skyRoomGlassReveal) private var reveal

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
        .background { plate }
    }

    /// 底板：毛玻璃材质 + 一层主题白纱 + 1pt 顶缘描边 + 柔和投影。
    ///
    /// 为什么不用 `glassSurface`：那个入口的投影与描边都绑在材质上，整套一起 `opacity`
    /// 淡出没问题，但 iOS 26 的 `glassEffect` 在 0 透明度时会**仍然采样背景**并留一点
    /// 边框残影 —— 用户要的"完全透明、只剩文字"就做不到。手搓这一层反而是跨版本一致的。
    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return shape
            .fill(.ultraThinMaterial)          // 毛玻璃本体（采样背后那片天）
            .overlay(shape.fill(Theme.glassFill))   // 主题白纱：浅色白 72%、深色白 6%
            .overlay(shape.strokeBorder(Theme.glassStrokeTop, lineWidth: 1))
            .shadow(color: Theme.glassShadowSoft, radius: 18, y: 6)
            .opacity(Double(reveal))
            .allowsHitTesting(false)
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
