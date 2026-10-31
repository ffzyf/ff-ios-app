import SwiftUI

/// 简报小组件的底盘：**天际线**（与 App 内 `SkyCard` 同一套语言）。
///
/// 为什么这里要重写一份而不是直接复用 `SkyCard`：
/// Widget target 只编译 `Sources/Widget` + `Sources/Shared`（project.yml），`DesignSystem`
/// 下的任何符号（`SkyCard` / `Typography` / `Radius` / `Spacing`）在小组件里都是**不存在**的。
/// 所以这里只搬"画法"，不搬控件：天空渐变 → 地平线弧 → 地面，三层，和 App 内那张卡同源
/// （几何来自 `Shared/UI/HorizonShape.swift`，天色来自 `Theme.sky(phase)`）。
///
/// 三个不能改的地方：
/// 1. **天色一律走 `Theme.sky(phase)`**。那七档是手调过的物理天空色，不随 App 深浅外观变化 ——
///    用户在 App 里选"始终深色"，桌面上的天空也不该跟着变白；
/// 2. 弧顶 / 两端比例由调用方传入，且必须和 `SkyCard` 用同一组数（0.62 / 0.74），
///    否则桌面上那条地平线会比 App 里高或低半个身位；
/// 3. 这里一个 `colorScheme` 都不判：天色是物理色，判深浅只会让同一时刻的小组件在深色桌面上变一个样。
///
/// V3.4 新增「实时太阳」：用户要的不是装饰，是**「太阳现在在哪儿」**。
/// 位置由 `SunClock.sunMark(at:on:)` 算（纯函数、归一化坐标），这里只管五层怎么叠：
/// ```
/// ① 天空渐变
/// ② 太阳光晕（RadialGradient，中心 = 太阳位置）
/// ③ 地平线大气光晕（原有那层，为了不和太阳光晕糊成一片已减弱）
/// ④ 地面 + 地平线亮边（亮边改成横向渐变，最亮处对准太阳 x）
/// ⑤ 太阳本体（实心圆 + 1.5pt 高光环 + 一层 shadow 柔光）
/// ```
/// 夜里（太阳在地平线以下）跳过 ②⑤，只在 ③ 之前留一小团余晖 —— 不能出现"夜里天上还挂个球"。
struct WidgetSkyBackdrop: View {

    /// 此刻属于哪一档天色（由 entry 的时刻算好传进来，不在渲染时调 `Date()`）
    let phase: SkyPhase
    /// 地平线弧顶位置（占高度比例）
    var crestY: CGFloat = 0.62
    /// 地平线两端位置（占高度比例）
    var edgeY: CGFloat = 0.74
    /// 这一帧对应的时刻（`entry.date`）。
    ///
    /// 传 `nil` 就退化成 V3.3 的纯天际线（无太阳）—— 这是给预览 / 老调用点留的兜底，
    /// 保证"太阳算不出来"时画面不会缺一块，只是少一颗太阳。
    var date: Date? = nil

    var body: some View {
        let sky = Theme.sky(phase)
        let mark = sunMark

        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                // ① 天空：顶部到地平线之间的一整段渐变
                skyLayer(sky)

                // ② 太阳光晕：落在天空之上、地平线亮边之下。
                //    强度由 `mark.intensity` 给 —— 太阳刚落到弧线下面那半小时还有余温，
                //    再往后衰减到 0，天空里就什么都不留了。
                if let mark = mark, mark.intensity > 0.01 {
                    glowLayer(sky: sky, mark: mark, size: size)
                }

                // ③ 地平线附近的一层大气光晕：让"亮边"不只是根线，而是真的在发光。
                //    中心取在地平线略上方 —— 光是自下而上漫出来的，落在弧顶上会显得脏。
                //    V3.4 把 0.30 降到 0.18：太阳光晕已经在那片区域发亮了，两层都满档会糊成一片白雾。
                atmosphereLayer(sky)

                // ④ 地面：弧线以下压深，让"地面上"的文字（日出日落）自然退到次要层级
                groundLayer(sky)

                // ⑤ 地平线亮边：最亮、最粗的那一段对准太阳的水平位置（参考图里那道光弧）
                horizonLayers(sky: sky, mark: mark)

                // ⑥ 太阳本体：夜里（isUp == false）不画 —— 这是"别在天上挂个球"的硬约束
                if let mark = mark, mark.isUp {
                    sunBody(sky: sky, mark: mark, size: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    // MARK: - 太阳位置（每帧算一次，纯函数，无状态）

    /// 这一帧的太阳印记。
    ///
    /// 为什么用 `date` 而不是在这里调 `Date()`：`entry.date` 是 Timeline 预渲染的时刻，
    /// 渲染时现取时间会让太阳位置和卡片上那句倒计时错位（太阳已经过午，文字还在正午）。
    private var sunMark: SunClock.SunMark? {
        guard let date else { return nil }
        return SunClock.sunMark(at: date, on: date, crestY: crestY)
    }

    // MARK: - ① 天空

    @ViewBuilder
    private func skyLayer(_ sky: Theme.SkyColors) -> some View {
        LinearGradient(
            colors: [sky.top, sky.horizon],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - ② 太阳光晕 + 夜间余晖

    /// 一层 `RadialGradient` 就够 —— Widget 每帧都要轻，**不要叠三层 blur**。
    ///
    /// `.plusLighter` 是"加成混合"：底下的天色被太阳往上提亮，而不是被盖住，
    /// 这是参考图里那团"光在空气里散开"的质感来源。核心里不透明度 0.45，
    /// 到 35% 半径时已经掉到 0.2，边缘 0 —— 不会把整片天空洗白。
    ///
    /// 太阳落到地平线以下时同一个函数退化成**余晖**：半径从 45% 屏宽缩到 18%、
    /// 强度按"落下多久"衰减（`SunClock.SunTrack.glowFadeMinutes`），
    /// 于是夜里只剩地平线背光处一小团暖冷交界的光，而不是天上挂个球。
    private func glowLayer(sky: Theme.SkyColors,
                           mark: SunClock.SunMark,
                           size: CGSize) -> some View {
        let color = WidgetTheme.sunGlow(sky, phase: phase)
        let strength = Double(mark.intensity)
        let radius = size.width * (mark.isUp ? WidgetTheme.sunGlowFactor : WidgetTheme.sunEmberFactor)
        // 余晖最高只给本体光晕的 0.7 —— 它必须"看得出有光"，但不能替太阳说话
        let alpha = WidgetTheme.sunGlowAlpha * (mark.isUp ? 1.0 : 0.7)

        return RadialGradient(
            gradient: Gradient(stops: [
                .init(color: color.opacity(alpha * strength), location: 0),
                .init(color: color.opacity(alpha * 0.42 * strength), location: 0.35),
                .init(color: color.opacity(0), location: 1)
            ]),
            center: UnitPoint(x: mark.point.x, y: mark.point.y),
            startRadius: 0,
            endRadius: radius
        )
        .blendMode(.plusLighter)
    }

    // MARK: - ③ 地平线大气光晕

    private func atmosphereLayer(_ sky: Theme.SkyColors) -> some View {
        RadialGradient(
            colors: [sky.edge.opacity(0.18), sky.edge.opacity(0)],
            center: UnitPoint(x: 0.5, y: max(0, edgeY - 0.10)),
            startRadius: 0,
            endRadius: 120
        )
    }

    // MARK: - ④ 地面

    private func groundLayer(_ sky: Theme.SkyColors) -> some View {
        HorizonGround(crestY: crestY, edgeY: edgeY)
            .fill(
                LinearGradient(
                    colors: [sky.ground, sky.ground.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    // MARK: - ⑤ 地平线亮边

    /// 三层同一条弧，用的是 `SkyCard` 的原始配方（模糊层做光晕、实线层做锐利边缘），
    /// 本次只把**纯色 stroke 换成横向渐变**：
    ///
    /// - 最亮处对准太阳的 x（`mark.point.x`），两侧渐隐 —— 参考图里那道弧越靠近太阳越白；
    /// - 第三层同一条弧加粗到 2.6pt 且两头全透明，只在太阳正下方露出一小段"加厚的高光"；
    /// - 夜里太阳不在天上，最亮点退回正中（`0.5`），亮边恢复成均匀的一道。
    private func horizonLayers(sky: Theme.SkyColors, mark: SunClock.SunMark?) -> some View {
        let sunX = (mark?.isUp ?? false) ? mark?.point.x : nil
        // 加粗段只在太阳露出地平线时出现；夜里靠 `sunX == nil` 整层不画
        let boost = Double(mark?.intensity ?? 0)

        return ZStack {
            // 雾化层：一头粗一头细，负责"光在折射"的那点柔
            HorizonEdge(crestY: crestY, edgeY: edgeY)
                .stroke(horizonStroke(sky.edge, sunX: sunX, peak: 0.55, base: 0.22, spread: 0.30),
                        lineWidth: 1.8)
                .blur(radius: 0.5)

            // 实线层：地平线本身，亮到 0.95 才像"一道亮边"
            HorizonEdge(crestY: crestY, edgeY: edgeY)
                .stroke(horizonStroke(sky.edge, sunX: sunX, peak: 0.95, base: 0.42, spread: 0.34),
                        lineWidth: 0.8)

            // 太阳正下方那一段：更亮、更粗，两头渐隐（`base: 0` = 弧的其他部分完全透明）
            if let sunX = sunX {
                HorizonEdge(crestY: crestY, edgeY: edgeY)
                    .stroke(horizonStroke(sky.edge,
                                          sunX: sunX,
                                          peak: 0.85 * boost,
                                          base: 0,
                                          spread: 0.16),
                            lineWidth: WidgetTheme.sunEdgeBoostWidth)
            }
        }
    }

    /// 地平线亮边的横向渐变。
    ///
    /// 用 `LinearGradient` 而不是 `AngularGradient`：地平线在我们这张卡上是一条
    /// 几乎水平的缓弧，横向渐变在它身上的效果和"从太阳位置向外辐射"肉眼无差，
    /// 但便宜得多（Angular 需要额外的角度变换）。
    ///
    /// - Parameters:
    ///   - edge: 亮边色（`sky.edge`）
    ///   - sunX: 最亮处的水平位置（归一化）；nil = 退回正中 0.5
    ///   - peak: 最亮处的不透明度
    ///   - base: 两侧的不透明度（传 0 就是"只在太阳下方露一段"）
    ///   - spread: 从最亮点向两侧衰减到 `base` 的横向距离（归一化）
    private func horizonStroke(_ edge: Color,
                               sunX: CGFloat?,
                               peak: Double,
                               base: Double,
                               spread: CGFloat) -> LinearGradient {
        let center = min(max(sunX ?? 0.5, 0), 1)
        let left = max(0, center - spread)
        let right = min(1, center + spread)

        // location 必须单调递增，所以两端落在 0 / 1 上的停靠点要按情况省略
        var stops: [Gradient.Stop] = [.init(color: edge.opacity(base), location: 0)]
        if left > 0.001 {
            stops.append(.init(color: edge.opacity(base), location: left))
        }
        stops.append(.init(color: edge.opacity(peak), location: min(max(center, 0), 1)))
        if right < 0.999 {
            stops.append(.init(color: edge.opacity(base), location: right))
        }
        stops.append(.init(color: edge.opacity(base * 0.85), location: 1))

        return LinearGradient(
            gradient: Gradient(stops: stops),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - ⑥ 太阳本体

    /// 参考图里的太阳：**一团亮核 + 向外扩散的光晕**，不是画一个完整的太阳图标。
    ///
    /// 所以只有三样东西：9pt 实心圆（亮核）、外面一圈 1.5pt 高光环、以及一个 `.shadow` 做的柔光。
    /// 刻意**不用 `.blur()`** —— Widget 渲染预算很紧，`shadow` 由系统合成，比模糊便宜一个量级。
    ///
    /// 太阳贴着地平线升起 / 落下时，圆心正好落在弧顶高度（0.62），
    /// 所以在两端看是"压在那条亮边上"，符合参考图里"日出贴左侧地平线"的观感。
    private func sunBody(sky: Theme.SkyColors,
                         mark: SunClock.SunMark,
                         size: CGSize) -> some View {
        let core = WidgetTheme.sunCoreDiameter
        let ring = core + WidgetTheme.sunRingGap
        let glow = WidgetTheme.sunGlow(sky, phase: phase)

        return ZStack {
            // 亮核
            Circle()
                .fill(WidgetTheme.sunCore(sky))
                .frame(width: core, height: core)
                .shadow(color: glow.opacity(0.85), radius: 5)
                .shadow(color: glow.opacity(0.45), radius: 10)

            // 高光环：亮而薄，是"核"与"光晕"之间的那道分界
            Circle()
                .strokeBorder(WidgetTheme.sunRing(sky), lineWidth: WidgetTheme.sunRingWidth)
                .frame(width: ring, height: ring)
        }
        .frame(width: ring + WidgetTheme.sunRingWidth, height: ring + WidgetTheme.sunRingWidth)
        .position(x: mark.point.x * size.width, y: mark.point.y * size.height)
    }
}
