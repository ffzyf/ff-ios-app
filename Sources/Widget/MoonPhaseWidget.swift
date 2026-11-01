import SwiftUI
import WidgetKit

// MARK: - 月相计算（纯本地，3.10.0）

/// 月龄 / 照明度 / 月名 —— **纯天文计算，零网络**。
///
/// ## 算法与误差（推导）
/// 以 **2000-01-06 18:14 UTC 的新月（朔）为纪元**（NASA 授时的近农历参考点），
/// 朔望月周期取 **29.53059 天**（平均朔望月）。月龄：
///
/// ```
/// age = ((now − epoch) mod 29.53059天)，结果落在 0…29.53 天
/// ```
///
/// 误差说明（为什么不搞更精确的）：真实朔望月在 29.27 ~ 29.83 天之间摆动（轨道离心率），
/// 固定周期模型的**长期误差约 ±0.5 天**，照明度误差 ±3% 左右 —— 对"今晚月亮多圆"
/// 这个展示粒度足够；而精确月相要展开 ELP2000 级别的摄动级数（几百项），
/// 在 Widget 里属于把卡片做成天文台。某次月相偏离 1 天属预期，不是 bug。
enum MoonPhaseMath {

    /// 纪元：2000-01-06 18:14:00 UTC（那刻是朔）的 Unix 秒
    private static let epochSeconds: Double = 947_182_440
    /// 平均朔望月（天）
    static let synodicMonth: Double = 29.53059

    /// 月龄（天，0…29.53）。0 = 朔、14.77 = 望
    static func age(on date: Date) -> Double {
        let elapsed = date.timeIntervalSince1970 - epochSeconds
        let days = elapsed / 86_400
        let raw = days.truncatingRemainder(dividingBy: synodicMonth)
        return raw < 0 ? raw + synodicMonth : raw
    }

    /// 照明度（0…1）。朔 0、望 1：
    /// ` illumination = (1 − cos(2π·age/周期)) / 2 `
    static func illumination(_ age: Double) -> Double {
        return (1 - cos(2 * .pi * age / synodicMonth)) / 2
    }

    /// 八段月名（与后端无契约、纯展示；顺序按月龄均分 8 段，每段 ≈ 3.69 天）。
    /// 取整规则：`round(age / 段长)` —— 月龄 0 落在「朔」段的正中，月龄 7.4 落「上弦」。
    static func name(_ age: Double) -> String {
        let names = ["朔", "娥眉", "上弦", "盈凸", "望", "亏凸", "下弦", "残月"]
        let segment = synodicMonth / 8
        let index = Int((age / segment).rounded()) % names.count
        return names[max(0, index)]
    }

    /// 是否盈月（月龄 < 半周期，亮面在西边 / 视觉右侧）
    static func isWaxing(_ age: Double) -> Bool {
        return age < synodicMonth / 2
    }

    /// 阴影圆的偏移量（相对月盘半径的比例，0…2）。
    ///
    /// 画法是"两个圆交叠 + 裁剪"：亮圆在上，同尺寸的阴影圆**横向偏移**盖上去，
    /// 再用圆形裁剪裁回月盘 —— 偏移为 0 时全暗（朔）、2r 时全亮（望），
    /// 中间连续过渡出娥眉 / 弦 / 凸月（被咬一口 = 凸月，剩一弯 = 娥眉）。
    ///
    /// 偏移量由**等圆透镜面积公式**反解（二分 32 次，纯函数、确定性 ——
    /// Widget 每帧重绘，绝不能有随机或近似抖动）：
    ///   lens(d) = 2r²·acos(d/2r) − (d/2)·√(4r²−d²)，亮面占比 = 1 − lens(d)/πr²
    /// 这样"图上的亮面比例"与文字里的照明度百分比严格一致，
    /// 而不是"线性估一个 offset"造成的图与数对不上。
    static func shadowOffset(for illumination: Double, radius: Double) -> Double {
        let clamped = min(max(illumination, 0), 1)
        let area = Double.pi * radius * radius
        func lensArea(_ d: Double) -> Double {
            let half = d / 2
            let term = 4 * radius * radius - d * d
            return 2 * radius * radius * acos(min(max(half / radius, 0), 1))
                - half * (term > 0 ? term.squareRoot() : 0)
        }
        var low = 0.0
        var high = 2 * radius
        // 边界快速返回：全暗 / 全亮不需要迭代
        if clamped <= 0.001 { return 0 }
        if clamped >= 0.999 { return 2 * radius }
        for _ in 0..<32 {
            let mid = (low + high) / 2
            let bright = 1 - lensArea(mid) / area
            if bright < clamped { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }
}

// MARK: - entry / provider

/// 月相卡的 Timeline entry（纯本地计算，无网络）
struct MoonPhaseEntry: TimelineEntry {
    let date: Date
    /// 月龄（天）
    let age: Double
    /// 照明度 0…1
    let illumination: Double
    /// 月名（朔 / 娥眉 / 上弦 / 盈凸 / 望 / 亏凸 / 下弦 / 残月）
    let name: String

    static func make(date: Date) -> MoonPhaseEntry {
        let age = MoonPhaseMath.age(on: date)
        return MoonPhaseEntry(date: date,
                              age: age,
                              illumination: MoonPhaseMath.illumination(age),
                              name: MoonPhaseMath.name(age))
    }
}

/// 月相卡的 Timeline：**6 小时一帧、铺 24 小时、`.atEnd` 重取，零网络请求**。
///
/// 为什么敢比别的卡更省：月相一天变约 2% 照明度 —— 6 小时一帧（4 帧）的变化量
/// 连 1% 都不到，肉眼完全无差。这是"刷新预算"意义上的极端奢侈：
/// 它一天 0 次网络、`getTimeline` 一天 1 次，全部预算留给联网的卡。
struct MoonPhaseProvider: TimelineProvider {

    /// 帧距（6 小时）
    static let gridStep: TimeInterval = 6 * 3600
    /// 视野（24 小时）
    static let horizon: TimeInterval = 24 * 3600

    func placeholder(in context: Context) -> MoonPhaseEntry {
        return MoonPhaseEntry.make(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (MoonPhaseEntry) -> Void) {
        completion(MoonPhaseEntry.make(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoonPhaseEntry>) -> Void) {
        let now = Date()
        let stamps = WidgetTimeline.stamps(now: now, horizon: Self.horizon, step: Self.gridStep)
        let entries = stamps.filter { $0 >= now }.sorted().map { MoonPhaseEntry.make(date: $0) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - 月盘

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
/// 3.10.0 家族表（#8 审计）：
/// - `systemSmall`：完整版式（月名 / 月盘 / 百分比）；
/// - `accessoryCircular`：只留月盘（环形里百分比与月名都是不可读的噪点）；
/// - `accessoryRectangular`：月名 + 百分比两行；
/// - `accessoryInline`：一行「上弦 52%」。
/// 不加 systemMedium / systemLarge：这张卡的内容密度就是一个方章 ——
/// 拉长后月盘两侧全是空天（参考图里它也只以小方卡形态出现），不做硬缩放的假适配。
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
        .widgetURL(WidgetDeepLink.brief)
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
}

// MARK: - 组件注册

/// 月相卡（3.10.0 新组件）。纯本地计算（见 `MoonPhaseMath`），永不因网络失败而空白。
struct MoonPhaseWidget: Widget {

    /// WidgetKit 用 kind 匹配已上桌的实例，改名等于让所有用户的小组件失效
    static let kind = WidgetTheme.Moon.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MoonPhaseWidget.kind, provider: MoonPhaseProvider()) { entry in
            MoonPhaseFace(entry: entry)
        }
        .configurationDisplayName(WidgetTheme.Moon.displayName)
        .description(WidgetTheme.Moon.description)
        .supportedFamilies([.systemSmall,
                            .accessoryCircular,
                            .accessoryRectangular,
                            .accessoryInline])
        .contentMarginsDisabled()
    }
}
