import SwiftUI

// MARK: - 斜面强度表

/// 玻璃斜面的六条边强度 —— 一行六个颜色，几何共用、强度可换。
///
/// 为什么要独立成 struct 而不是在 `GlassBevel` 里直接读 `Theme`：
/// 桌面小组件恒为深色（背景永远是天空渐变），而 `Theme` 的动态色要靠 trait 解析，
/// Widget 进程里拿到的是"系统外观"而不是"这张卡的外观"。小组件因此注入一套固定强度表，
/// App 侧用默认的 `.theme`（走 token，深浅自动切换）——**默认参数保证 App 调用点零改动**。
struct GlassBevelPalette {

    /// 顶部内斜面（最亮）
    let top: Color

    /// 左侧内斜面（顺光侧，次亮）
    let left: Color

    /// 右侧内斜面（逆光侧，最弱）
    let right: Color

    /// 底缘暗边
    let bottom: Color

    /// 0.5pt 内轮廓
    let outlineInner: Color

    /// 0.5pt 外轮廓
    let outlineOuter: Color

    /// App 侧默认强度表：六个 `Theme.glassBevel*` / `Theme.glassOutline*` token。
    ///
    /// 写成 `static var` 而不是 `static let`：token 本身是动态 `Color`（内部包
    /// `UIColor(dynamicProvider:)`），每次取用重新组一遍是微不足道的成本，
    /// 但能避免"某个版本之后 token 变成计算属性"时这里的缓存变陈旧。
    static var theme: GlassBevelPalette {
        GlassBevelPalette(
            top: Theme.glassBevelTop,
            left: Theme.glassBevelLeft,
            right: Theme.glassBevelRight,
            bottom: Theme.glassBevelBottom,
            outlineInner: Theme.glassOutlineInner,
            outlineOuter: Theme.glassOutlineOuter
        )
    }
}

// MARK: - 四向斜面 + 双轮廓

/// 玻璃的"边" —— 四向内斜面 + 内白外黑 0.5pt 双轮廓，共 6 层。
///
/// ## 为什么是 4 层渐变，而不是 1 层 stroke
///
/// CSS 原型的厚度来自四条 `inset` 阴影：它们**四向独立衰减**（顶部 12px 内淡出、
/// 左侧 16px 内淡出、右侧更弱、底部干脆是黑），方向与强度各不相同。
/// 一条 `strokeBorder` 只能给出"整圈同亮度、同宽度"的线 —— 那正是旧配方
/// "看起来像一块平板"的根本原因：平板与厚板在 silhouette 上完全一样，
/// 差别全在**边的明暗分布**上。所以这里必须画四条方向不同的渐变，再用两个
/// 0.5pt 轮廓把边界"切"干净。
///
/// ## 两条实现要点
///
/// 1. **每层都必须 `shape.fill` 裁形**：矩形上的 `LinearGradient` 会溢出圆角，
///    在圆角外侧画出一圈方形渐变（白角），肉眼极明显；
/// 2. **顺序是底部 → 左 → 右 → 顶**：四条渐变在整个形状上叠加，最后画的那层在最上面，
///    顶部必须是最后一层，否则最亮的接光边会被下面几层冲淡。
///
/// 本 View **只画边、不画底**：底（材质 / 白叠层 / 染色 / 顶部 sheen）由调用方负责，
/// 所以 App 的真玻璃、静态玻璃与桌面小组件的玻璃罩能共用同一份边。
///
/// 渲染成本：4 个渐变填充 + 2 个描边，全部在 CPU 上一次性栅格化，没有 backdrop 采样，
/// 也没有 `blur` —— Widget 每帧重绘也扛得住。
struct GlassBevel<S: InsettableShape>: View {

    /// 被描边的形状（圆角矩形 / 胶囊 / 任意 `InsettableShape`）
    let shape: S

    /// 强度表。默认 `.theme`（App 侧走 token，深浅自动切换）
    var palette: GlassBevelPalette = .theme

    var body: some View {
        ZStack {
            // ① 底缘暗边：最先画，压在最下面 —— 它只负责"向下收"，不能盖住接光边
            band(palette.bottom, from: .bottom, to: Self.bottomEnd)
            // ② 左侧斜面：顺光侧
            band(palette.left, from: .leading, to: Self.leftEnd)
            // ③ 右侧斜面：逆光侧，强度由 token 决定（比左侧弱一档）
            band(palette.right, from: .trailing, to: Self.rightEnd)
            // ④ 顶部斜面：最后画，永远最亮
            band(palette.top, from: .top, to: Self.topEnd)
            // ⑤ 内轮廓：内缩 0.25pt 再描 0.5pt —— 落在"边界之内"，与斜面的收口处接住
            shape
                .inset(by: Self.outlineInset)
                .strokeBorder(palette.outlineInner, lineWidth: Self.outlineWidth)
            // ⑥ 外轮廓：贴边描 0.5pt，内白外黑这一对把玻璃"切"出实体边界
            shape
                .strokeBorder(palette.outlineOuter, lineWidth: Self.outlineWidth)
        }
        // 纯装饰层：绝不能吃掉卡片的点击 / 长按（Widget 的整卡深链、卡片的 tap 手势）
        .allowsHitTesting(false)
    }

    // MARK: - 单条斜面

    /// 一条斜面：从边缘的实色，在该方向上一个很短的行程内淡出到全透明。
    ///
    /// 渐变**必须**用 `shape.fill` 裁形 —— 见类型注释第 1 条。
    /// 透明端用 `Theme.glassHighlightFade`（两种外观都是 0）而不是就地 `.opacity(0)`：
    /// 主题闸门第 3 条拦的就是"颜色在 View 层被临时改造"这一类写法 —— 渐变的两端也该是 token。
    private func band(_ color: Color, from start: UnitPoint, to end: UnitPoint) -> some View {
        shape.fill(
            LinearGradient(
                colors: [color, Theme.glassHighlightFade],
                startPoint: start,
                endPoint: end
            )
        )
    }

    // MARK: - 几何常量

    /// 顶部斜面的淡出终点：只在**顶部 14% 高度**内收完。
    ///
    /// 对应 CSS 的 `inset 0 12px 14px -12px`（158pt 高的卡上 12px ≈ 7.6%，
    /// 再算上 1px blur 的余量，14% 是能让渐变"看起来有厚度但不脏"的档）。
    /// 拖到 0.3 以上就变成一层顶纱，卡片会重新发雾。
    private static var topEnd: UnitPoint { UnitPoint(x: 0.5, y: 0.14) }

    /// 左侧斜面的淡出终点：左侧 10% 宽度内收完（CSS `inset 10px 0 16px -14px`）
    private static var leftEnd: UnitPoint { UnitPoint(x: 0.10, y: 0.5) }

    /// 右侧斜面的淡出终点：右侧 10% 宽度内收完（CSS `inset -10px 0 16px -14px`）
    private static var rightEnd: UnitPoint { UnitPoint(x: 0.90, y: 0.5) }

    /// 底部暗边的淡出终点：底缘往上 14% 内收完（CSS `inset 0 -12px 16px -12px`）
    private static var bottomEnd: UnitPoint { UnitPoint(x: 0.5, y: 0.86) }

    /// 内轮廓的内缩量。0.25pt 让"内白"与"外黑"两根 0.5pt 线**部分重叠**：
    /// 重叠区由后画的外黑覆盖，于是边界看起来是一根 0.5pt 的暗线 + 紧贴内侧的一根白线，
    /// 中间没有缝隙 —— 有缝就会露出背景色，圆角处尤其明显。
    private static var outlineInset: CGFloat { 0.25 }

    /// 双轮廓的线宽，与 CSS 的 `0.5px` 对齐。
    /// Retina 上 0.5pt = 1 个物理像素，是"能看见但不抢戏"的最小单位。
    private static var outlineWidth: CGFloat { 0.5 }
}
