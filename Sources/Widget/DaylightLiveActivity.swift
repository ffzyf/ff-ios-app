import ActivityKit
import SwiftUI
import WidgetKit

/// 天光实时活动的锁屏 / 灵动岛界面（需求 A）。
///
/// 这里只管画，什么时候出现、什么时候消失全在 `DaylightActivityCoordinator`（主 App）。
///
/// 锁屏视图（天际线风格）：
/// 背景按 `SkyPhase` 取 `Theme.sky(_:)` 的三停渐变（top → horizon → ground）；
/// 地平线沿用 `HorizonGround` + `HorizonEdge`，太阳点 4pt 按 `SunClock.sunMark(at:on:)` 现算；
/// 左上 dayText + 天气，右下倒计时，底部 `ProgressView(timerInterval:)`。
///
/// 灵动岛：compact = 太阳图标 + 倒计时；expanded = 天气·温度 + 天际线进度；
/// minimal = 太阳图标。
///
/// 硬约束（方案 §1.6 主题闸门）：
/// 颜色只用 `Theme.sky(phase)` 的 6 个 token（top/horizon/ground/edge/ink/inkDim）；
/// 不出现 hex 字面量颜色构造、外观模式判断、白色半透明白色；
/// 不用 textPrimary / lime / TrackGradient。
struct DaylightLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DaylightActivityAttributes.self) { context in
            DaylightLockScreenView(state: context.state, attributes: context.attributes)
                .activityBackgroundTint(Theme.sky(SunClock.phase(at: Date())).top)
                .activitySystemActionForegroundColor(Theme.sky(SunClock.phase(at: Date())).ink)
        } dynamicIsland: { context in
            let phase = SunClock.phase(at: Date())
            let sky = Theme.sky(phase)
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        if let symbol = DaylightSymbol.of(WeatherKind.from(code: context.state.weatherCode)) {
                            Image(systemName: symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(sky.edge)
                        }
                        Text(phase.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(sky.ink)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        if let temp = context.state.tempC {
                            Text(String(format: "%.0f°", temp))
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(sky.ink)
                        }
                        if let text = context.state.weatherText {
                            Text(text)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(sky.inkDim)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(SkyPhase.countdownText(to: context.state.sunset, now: Date()))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(sky.inkDim)
                        DaylightProgress(state: context.state, height: 3)
                    }
                }
            } compactLeading: {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.sky(phase).edge)
            } compactTrailing: {
                DaylightCompactCountdown(state: context.state)
            } minimal: {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.sky(phase).edge)
            }
        }
    }
}

// MARK: - 锁屏视图（天际线风格）

/// 天光实时活动锁屏卡片：三停渐变 + 地平线 + 太阳点 + 文字 + 进度条。
struct DaylightLockScreenView: View {

    let state: DaylightActivityAttributes.ContentState
    let attributes: DaylightActivityAttributes

    /// 按当前时刻现算天色档位 —— 太阳位置也是现算的，两者保持同步。
    private var phase: SkyPhase { SunClock.phase(at: Date()) }
    private var sky: Theme.SkyColors { Theme.sky(phase) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                // 三停渐变背景（top → horizon → ground），停在 crestY
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: sky.top, location: 0),
                        Gradient.Stop(color: sky.horizon, location: SunClock.SunTrack.crestY),
                        Gradient.Stop(color: sky.ground, location: SunClock.SunTrack.crestY)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // 地面（弧线以下）
                HorizonGround(crestY: SunClock.SunTrack.crestY, edgeY: 0.74)
                    .fill(sky.ground)

                // 地平线亮边
                HorizonEdge(crestY: SunClock.SunTrack.crestY, edgeY: 0.74)
                    .stroke(sky.edge, lineWidth: 1)

                // 太阳点（4pt，按 Date() 现算位置）
                if let sun = SunClock.sunMark(at: Date(), on: state.sunrise), sun.isUp {
                    Circle()
                        .fill(sky.edge)
                        .frame(width: 4, height: 4)
                        .position(
                            x: sun.point.x * size.width,
                            y: sun.point.y * size.height
                        )
                }

                // 文字层
                VStack(alignment: .leading, spacing: 8) {
                    // 左上：日期 + 天气
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attributes.dayText)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(sky.ink)

                            if let weatherText = state.weatherText,
                               let symbol = DaylightSymbol.of(WeatherKind.from(code: state.weatherCode)) {
                                HStack(spacing: 4) {
                                    Image(systemName: symbol)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(sky.edge)
                                    Text(weatherText)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(sky.inkDim)
                                }
                            }
                        }

                        Spacer(minLength: 8)

                        // 右下：距日落倒计时
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(SkyPhase.countdownText(to: state.sunset, now: Date()))
                                .font(.system(size: 17, weight: .bold, design: .monospaced))
                                .foregroundStyle(sky.ink)
                                .monospacedDigit()
                            Text(phase.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(sky.inkDim)
                        }
                    }

                    Spacer(minLength: 0)

                    // 底部进度条
                    DaylightProgress(state: state, height: 2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 进度条

/// 覆盖「日出 → 日落」全程的细进度条。
///
/// 用 `ProgressView(timerInterval:)` 让系统按时间推进：主 App 退出前台之后它照样在走，
/// 这正是"锁屏看起来是活的"却零推送成本的来源。
struct DaylightProgress: View {

    let state: DaylightActivityAttributes.ContentState
    let height: CGFloat

    var body: some View {
        Group {
            if state.sunset > state.sunrise {
                ProgressView(timerInterval: state.sunrise...state.sunset, countsDown: false) {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(Theme.sky(SunClock.phase(at: Date())).edge)
                .frame(height: height)
            } else {
                // 时间区间非法（脏数据）时画一条静态轨道，绝不构造非法 Range
                Capsule()
                    .fill(Theme.sky(.night).ground)
                    .frame(height: height)
            }
        }
    }
}

// MARK: - 紧凑态倒计时

/// 灵动岛紧凑态的右侧倒计时文字。
///
/// `sunset > now` 时用 `Text(timerInterval:)` 系统倒计时；
/// `sunset <= now` 时改画静态「已日落」—— 因为 `timerInterval:`
/// 在右侧小于左侧的闭区间上是非法的，拿到会崩。
struct DaylightCompactCountdown: View {

    let state: DaylightActivityAttributes.ContentState

    var body: some View {
        let now = Date()
        if state.sunset > now {
            Text(timerInterval: now...state.sunset, countsDown: true)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.sky(SunClock.phase(at: now)).ink)
                .monospacedDigit()
        } else {
            Text("已日落")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.sky(.night).inkDim)
                .monospacedDigit()
        }
    }
}

// MARK: - 天气符号映射

/// 天气类型 → SF Symbol 名称。
///
/// 为什么不用 `WeatherKind` 自己带一个 symbol 属性：`WeatherKind` 属于数据层
/// （`Sources/Shared/Domain/`），不应该知道 SF Symbol 这种 UI 层的东西；
/// 而且只有实时活动这一处用这种尺寸/命名的图标，其他地方（简报卡、天光卡）
/// 都有自己的粒子/渐变画法。把映射单独放在这里，数据层保持零 UI 依赖。
enum DaylightSymbol {

    /// `nil` → 不画天气图标
    static func of(_ kind: WeatherKind?) -> String? {
        guard let kind = kind else { return nil }
        switch kind {
        case .clear:    return "sun.max.fill"
        case .partly:   return "cloud.sun.fill"
        case .overcast: return "cloud.fill"
        case .fog:      return "cloud.fog.fill"
        case .drizzle:  return "cloud.drizzle.fill"
        case .rain:     return "cloud.rain.fill"
        case .snow:     return "cloud.snow.fill"
        case .thunder:  return "cloud.bolt.rain.fill"
        }
    }
}
