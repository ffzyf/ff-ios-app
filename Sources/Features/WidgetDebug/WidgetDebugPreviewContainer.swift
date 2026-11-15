import SwiftUI
import WidgetKit

/// 预览容器（5.1.2 · R5，架构 §1.6.2 / §1.6.3 / AC5-5）。
///
/// 三条纪律：
/// 1. **不自己画一套组件**：按 `descriptor.entryKind` 构造对应的模拟 TimelineEntry /
///    LiveActivity `ContentState`，直接交给既有 `*Face` / 锁屏 Face。
/// 2. **按 family 真实画布比例定框**，并用 `.environment(\.widgetDebugFamily, …)` 注入分档
///    （§8-4 的退路已落地：系统 `\.widgetFamily` 是只读 KeyPath，`.environment` 要可写，
///    所以改用 `WidgetDebugFamilyKey`（`Sources/Shared/WidgetDebug/`）。各 Face 读取处
///    走 `debugFamily ?? family`，**只改访问方式、不重画任何视觉**）。
/// 3. **不支持档 / 不适用态不渲染空壳**：直接显示 `WidgetDebugCatalog` 给的 `reason`。
struct WidgetDebugPreviewContainer: View {

    @ObservedObject var session: WidgetDebugSession

    var body: some View {
        if !session.isCurrentFamilySupported {
            unavailable(reason: session.selectedFamilyReason ?? "该尺寸档不支持")
        } else if !session.isCurrentStateApplicable {
            unavailable(reason: session.selectedStateReason ?? "该状态不适用")
        } else {
            previewFrame
        }
    }

    // MARK: - 置灰说明（AC5-3 / AC5-4，不渲染空壳）

    private func unavailable(reason: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "square.dashed")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
            Text(reason)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        .padding(.horizontal, Spacing.cardPadding)
    }

    // MARK: - 画布

    @ViewBuilder
    private var previewFrame: some View {
        if let family = widgetFamily {
            framed
                .environment(\.widgetDebugFamily, family)
        } else {
            // 两个实时活动用伪 family，ActivityKit 锁屏视图不读 `\.widgetFamily`
            framed
        }
    }

    private var framed: some View {
        faceContent
            .frame(width: frameWidth, height: frameHeight)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            }
    }

    private var widgetFamily: WidgetFamily? {
        switch session.selectedFamily {
        case .systemSmall:           return .systemSmall
        case .systemMedium:          return .systemMedium
        case .systemLarge:           return .systemLarge
        case .accessoryRectangular:  return .accessoryRectangular
        case .accessoryInline:       return .accessoryInline
        case .accessoryCircular:     return .accessoryCircular
        case .activityLockScreen, .activityDynamicIsland: return nil
        }
    }

    /// 各 family 的真实画布比例近似值（AC5-5）。真机/Xcode 可微调绝对尺寸，比例不变。
    private var frameWidth: CGFloat {
        switch session.selectedFamily {
        case .systemSmall:  return 170
        case .systemMedium, .systemLarge: return 340
        case .accessoryRectangular: return 320
        case .accessoryInline: return 300
        case .accessoryCircular: return 160
        case .activityLockScreen, .activityDynamicIsland: return 340
        }
    }

    private var frameHeight: CGFloat {
        switch session.selectedFamily {
        case .systemSmall:  return 170
        case .systemMedium: return 155
        case .systemLarge:  return 340
        case .accessoryRectangular: return 92
        case .accessoryInline: return 56
        case .accessoryCircular: return 160
        case .activityLockScreen, .activityDynamicIsland: return 120
        }
    }

    // MARK: - 分派到 *Face（同一份渲染层）

    @ViewBuilder
    private var faceContent: some View {
        switch session.descriptor?.entryKind ?? .redstone {
        case .redstone:
            RedstoneFace(entry: makeRedstoneEntry())
        case .brief:
            BriefFace(entry: makeBriefEntry())
        case .skyLight:
            SkyLightFace(entry: makeSkyLightEntry())
        case .sunArc:
            SunArcFace(entry: makeSunArcEntry())
        case .moonPhase:
            MoonPhaseFace(entry: makeMoonPhaseEntry())
        case .wind:
            WindFace(entry: makeWindEntry())
        case .sunEventActivity:
            // 架构 §1.6.2：两个 LiveActivity 只抽了 `internal` 锁屏 Face。
            // 灵动岛形态也交给这份锁屏 Face 预览内容，不自己画第二套组件。
            SunEventLockScreenView(
                state: makeSunEventState(),
                attributes: makeSunEventAttributes()
            )
        case .daylightActivity:
            DaylightLockScreenView(state: makeDaylightState())
        }
    }

    // MARK: - 模拟 entry 构造（只用 Shared 的值类型 + 纯函数）

    private var now: Date { session.previewNow }
    private var fields: [String: String] { session.activePreset?.fields ?? [:] }

    /// 无数据 / 加载中 / 错误：一律走「没有数据就说没有」，不造一个像有数据的空帧。
    private var hasData: Bool {
        switch session.selectedState {
        case .noData, .loading, .error:
            return false
        default:
            return true
        }
    }

    /// 红石阶段走 `RedstoneTimeline.phase(in:now:)` 按 `previewNow` 重算 ——
    /// 与真实 Widget 同一套纯函数，时间旅行拨动 `now`，看到的阶段就跟着变。
    private func makeRedstoneEntry() -> RedstoneEntry {
        let dayKey = RedstoneClock.dayKey(now)
        let times = ["11:08", "17:08", "23:08"]
        let map = fields["map"] ?? "暮土·失落方舟"
        let rate = Double(fields["rate"] ?? "") ?? 2.5
        let needsCheck = fields["needsCheck"] == "true"
        let day = RedstoneDay(
            date: dayKey, type: "红石", map: map, times: times,
            rate: rate, needsCheck: needsCheck, note: ""
        )
        let days = [day]
        let phase = RedstoneTimeline.phase(in: days, now: now)
        let occurrences = RedstoneTimeline.occurrences(in: days)

        return RedstoneEntry(
            date: now,
            hasData: hasData,
            updatedAt: nil,
            phase: hasData ? phase : .notGenerated,
            todayOccurrences: hasData ? occurrences : [],
            todayCount: hasData ? occurrences.count : 0,
            needsCheck: needsCheck,
            daylight: makeSkyLightEntry(),
            weekRows: makeWeekRows(dayKey: dayKey, times: times, map: map)
        )
    }

    private func makeWeekRows(dayKey: String,
                              times: [String],
                              map: String) -> [RedstoneWeekRow] {
        guard hasData else { return [] }
        return [
            RedstoneWeekRow(dayKey: dayKey,
                            dayLabel: "今天",
                            timesLabel: times.joined(separator: " · "),
                            map: map),
            RedstoneWeekRow(dayKey: dayKey + "-1",
                            dayLabel: "明天",
                            timesLabel: times.joined(separator: " · "),
                            map: map),
            RedstoneWeekRow(dayKey: dayKey + "-2",
                            dayLabel: "后天",
                            timesLabel: times.joined(separator: " · "),
                            map: map)
        ]
    }

    private func makeBriefEntry() -> BriefEntry {
        return BriefEntry(
            date: now,
            hasData: hasData,
            dateText: fields["dateText"] ?? "今天",
            weekdayText: fields["weekdayText"] ?? "周四",
            paragraphs: hasData ? [fields["paragraphs"] ?? "内置样例正文"] : [],
            pushedToday: false,
            pushedAt: nil,
            birthday: nil,
            yi: hasData ? [fields["yi"] ?? "散步"] : [],
            ji: hasData ? [fields["ji"] ?? "熬夜"] : [],
            sunrise: nil,
            sunset: nil,
            weather: nil,
            minutely: nil
        )
    }

    private func makeSkyLightEntry() -> SkyLightEntry {
        let times = SunClock.times(on: now)
        return SkyLightEntry(
            date: now,
            phase: SunClock.phase(at: now),
            viewing: hasData ? .clear : nil,
            deadline: times?.sunset,
            sunrise: times?.sunrise,
            sunset: times?.sunset,
            weather: nil,
            visibilityMeters: nil
        )
    }

    private func makeSunArcEntry() -> SunArcEntry {
        let times = SunClock.times(on: now)
        return SunArcEntry(
            date: now,
            phase: SunClock.phase(at: now),
            sunrise: hasData ? times?.sunrise : nil,
            sunset: hasData ? times?.sunset : nil,
            temp: hasData ? 21 : nil,
            weatherText: hasData ? "晴" : nil,
            tMax: hasData ? 24 : nil,
            tMin: hasData ? 12 : nil
        )
    }

    /// 月相由日期现算（`MoonPhaseMath` 纯函数），没有「无数据」这一说 ——
    /// 这类组件的 noData / loading / error 态不画空壳，仍交给同一份 Face。
    private func makeMoonPhaseEntry() -> MoonPhaseEntry {
        let age = MoonPhaseMath.age(on: now)
        return MoonPhaseEntry(
            date: now,
            age: age,
            illumination: MoonPhaseMath.illumination(age),
            name: MoonPhaseMath.name(age)
        )
    }

    private func makeWindEntry() -> WindEntry {
        return WindEntry(
            date: now,
            wind: hasData ? 12 : nil,
            windDirText: hasData ? "东北" : nil,
            windDirectionDegrees: hasData ? 45 : nil,
            updatedAt: hasData ? now : nil
        )
    }

    private func makeSunEventState() -> SunEventActivityAttributes.ContentState {
        let start = now.addingTimeInterval(-10 * 60)
        return SunEventActivityAttributes.ContentState(
            phase: session.selectedState == .ongoing ? "ongoing" : "upcoming",
            map: fields["map"] ?? "暮土·失落方舟",
            rate: Double(fields["rate"] ?? "") ?? 2.5,
            startAt: start,
            endAt: start.addingTimeInterval(
                SunEventActivityAttributes.ContentState.durationSeconds
            ),
            needsCheck: fields["needsCheck"] == "true"
        )
    }

    private func makeSunEventAttributes() -> SunEventActivityAttributes {
        return SunEventActivityAttributes(
            eventDate: RedstoneClock.dayKey(now),
            startTime: Formatters.timeHHmm(now.addingTimeInterval(-10 * 60))
        )
    }

    private func makeDaylightState() -> DaylightActivityAttributes.ContentState {
        let times = SunClock.times(on: now)
        let sunrise = times?.sunrise ?? now
        let sunset = times?.sunset ?? now.addingTimeInterval(8 * 3600)
        return DaylightActivityAttributes.ContentState(
            sunrise: sunrise,
            sunset: sunset,
            windowEnd: min(sunset, now.addingTimeInterval(8 * 3600)),
            weatherCode: hasData ? 0 : nil,
            weatherText: hasData ? "晴" : nil,
            tempC: hasData ? 21 : nil
        )
    }
}
