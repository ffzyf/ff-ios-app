import SwiftUI
import WidgetKit

// MARK: - 月盘
//
// 5.1.2 · T03：从 `MoonPhaseWidget.swift` **纯平移**到本文件（视觉零改动）。
// `MoonPhaseMath` 已抽到 `Sources/Shared/WidgetDebug/WidgetEntries.swift`
// （App / Widget 双 target 共用），`MoonPhaseEntry` 同在 Shared。
// 原文件保留 Provider / Widget 注册；本文件由 `project.yml` 独立 `path:` 引入主 App。

/// 月盘：亮圆 + 同尺寸阴影圆横向偏移 + 圆形裁剪（"两个圆交叠"画法，见
/// `MoonPhaseMath.shadowOffset` 的推导）。**零 blur、零颜色字面量**：
/// 亮面 = `Theme.sky(.night).ink`（近白），暗面 = 同一支 ink 压 0.12
///（压在夜空渐变上读作"地照"），描边让月盘在亮天上也有轮廓。
struct MoonDisc: View {

    /// 照明度 0…1
    let illumination: Double
    /// 盈月（亮面在右）还是亏月（亮面在左）
    let isWaxing: Bool
    /// 月盘直径（pt）
    let diameter: CGFloat

    /// 亮面色（月光是反射的日光，用夜里那档最亮的 ink，不新造色）
    private var bright: Color {
        return Theme.sky(.night).ink
    }

    var body: some View {
        let radius = Double(diameter / 2)
        let offset = MoonPhaseMath.shadowOffset(for: illumination, radius: radius)
        let direction: CGFloat = isWaxing ? -1 : 1

        ZStack {
            Circle()
                .fill(bright)
            // 阴影圆：与月盘同尺寸，横向偏移盖出明暗界线。
            // 盈月亮面在右 → 阴影往左推；亏月相反。
            Circle()
                .fill(Theme.sky(.night).ground)
                .offset(x: direction * CGFloat(offset))
        }
        // 裁回月盘：阴影圆溢出的部分不画
        .mask {
            Circle()
        }
        .overlay {
            Circle()
                .strokeBorder(bright.opacity(0.35), lineWidth: WidgetTheme.Moon.discStrokeWidth)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - 卡面

/// 月相卡面 —— 参考图 IMG_9274 右3 的语言：深空渐变底 + 居中月盘，
/// 上月名、下照明度百分比。
///
/// 3.12.0 家族表：
/// - `systemSmall`：完整版式（月名 / 月盘 / 百分比）；
/// - `systemLarge`：**大月盘（148pt）+ 18pt 月名 + 15pt 照明度 + 新增一行「下次满月还有 N 天」**
///   —— 这一行是大号独有的内容（任务书要求），纯天文计算，不需要网络；
/// - `accessoryCircular`：只留月盘（环形里百分比与月名都是不可读的噪点）；
/// - `accessoryRectangular`：月名 + 百分比两行；
/// - `accessoryInline`：一行「上弦 52%」。
struct MoonPhaseFace: View {

    @Environment(\.widgetFamily) private var family

    private let entry: MoonPhaseEntry

    init(entry: MoonPhaseEntry) {
        self.entry = entry
    }

    /// 夜空的两端（月相卡永远是夜——月相只在夜里成立，跟天光七档无关）
    private var nightSky: Theme.SkyColors {
        return Theme.sky(.night)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                MoonDisc(illumination: entry.illumination,
                         isWaxing: MoonPhaseMath.isWaxing(entry.age),
                         diameter: 28)
            case .accessoryInline:
                Text("\(entry.name) \(Int(round(entry.illumination * 100)))%")
                    .font(WidgetTheme.Accessory.inlineText)
                    .widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: WidgetTheme.Accessory.lineSpacing) {
                    Text(entry.name)
                        .font(WidgetTheme.Accessory.linePrimary)
                        .widgetAccentable()
                    Text("照明 \(Int(round(entry.illumination * 100)))%")
                        .font(WidgetTheme.Accessory.lineSecondary)
                }
            case .systemLarge:
                largeFace
            default:
                smallFace
            }
        }
        // accessory 的背景由系统提供；桌面档给深空渐变
        .containerBackground(for: .widget) {
            if isSystemFamily {
                LinearGradient(colors: [nightSky.top, nightSky.ground],
                               startPoint: .top,
                               endPoint: .bottom)
            } else {
                Color.clear
            }
        }
        // 月相画的是"此刻的月亮"，点开就进沉浸式天光页（`skyapp://sky`，
        // 与天光 / 日弧 / 风 三张卡同一个落点）
        .widgetURL(WidgetDeepLink.sky)
    }

    private var isSystemFamily: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return false
        default:
            return true
        }
    }

    /// 桌面小号版式：月名在上、月盘居中、百分比在下（参考图 IMG_9274 右3 的排布）
    private var smallFace: some View {
        VStack(spacing: 6) {
            Text(entry.name)
                .font(WidgetTheme.Moon.name)
                .foregroundStyle(nightSky.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .widgetAccentable()

            MoonDisc(illumination: entry.illumination,
                     isWaxing: MoonPhaseMath.isWaxing(entry.age),
                     diameter: 158 * WidgetTheme.Moon.discRatio)
                .widgetAccentable()

            Text("\(Int(round(entry.illumination * 100)))%")
                .font(WidgetTheme.Moon.percent)
                .foregroundStyle(nightSky.inkDim)
                .monospacedDigit()
        }
        .padding(WidgetTheme.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 桌面大号版式（3.12.0）：大月盘 + 月名 + 照明度 + **下一次满月**
    ///
    /// 纵向三段：月名（18pt）/ 月盘（148pt）/ 照明度（15pt）→ 底部一行提示（12pt）。
    /// 与中/小号的关系不是"放大"：那两档没有「下次满月」这一行 —— 它是大号独有的内容。
    private var largeFace: some View {
        VStack(spacing: 10) {
            Text(entry.name)
                .font(WidgetTheme.Moon.largeName)
                .foregroundStyle(nightSky.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .widgetAccentable()

            MoonDisc(illumination: entry.illumination,
                     isWaxing: MoonPhaseMath.isWaxing(entry.age),
                     diameter: WidgetTheme.Moon.largeDiscDiameter)
                .widgetAccentable()

            Text("照明度 \(Int(round(entry.illumination * 100)))%")
                .font(WidgetTheme.Moon.largePercent)
                .foregroundStyle(nightSky.inkDim)
                .monospacedDigit()

            Spacer(minLength: 0)

            Text(entry.fullMoonText)
                .font(WidgetTheme.Moon.largeHint)
                .foregroundStyle(nightSky.inkDim)
                .lineLimit(1)
        }
        .padding(WidgetTheme.Moon.largePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
