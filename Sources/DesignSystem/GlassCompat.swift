import SwiftUI

/// 玻璃层级（PRD §4.4 / 设计文档 §5.6）。
///
/// 核心原则：**玻璃表达「浮在内容之上」，不表达「这是一个盒子」**。
/// 所以只有 4 层，且「越靠上越厚 —— 但 Tab 栏例外」（Tab 栏视觉最上层却用最薄的材质，
/// 因为它必须透出滚动内容才能证明自己在浮）。
///
/// 双主题改造（批次 1）：这里原本返回 4 个 `Double`（`whiteFill` / `topStroke` / …），
/// 由调用方"就地给白色加透明度"来造色 —— 浅色模式下这些值全都会失效（白叠白等于没叠）。
/// 现在改成**返回 token**：`GlassLevel` 只负责"这一层用哪一档"，具体明暗交给 `Theme`。
/// 这样 iOS 18–25 的手工路径也自动双主题，不需要在 `HandGlass` 里读任何环境。
enum GlassLevel: String, CaseIterable {
    /// 层 1：弹层 / 全屏图片查看
    case sheet
    /// 层 2：浮动 Tab 栏 / 圆形浮动按钮 / 底部操作条
    case floating
    /// 层 3：内容卡片
    case card
    /// 层 4：导航条（滚动后渐显）
    case chrome

    /// iOS 18–25 的降级材质（等效 blur 值见 PRD §4.4 参数表）
    var material: Material {
        switch self {
        case .sheet: return .thickMaterial      // ≈ 30pt
        case .floating: return .ultraThinMaterial // ≈ 20pt
        case .card: return .ultraThinMaterial   // ≈ 16pt
        case .chrome: return .regularMaterial   // ≈ 24pt
        }
    }

    /// 白叠层：材质本身不够「亮」，深底上会显脏，用一层白提亮。
    /// 深色 = 白 10% / 6%，浅色 = 白 88% / 72%（PRD §3.2 `glassFillStrong` / `glassFill`）。
    var fillColor: Color {
        switch self {
        case .sheet, .floating: return Theme.glassFillStrong
        case .card, .chrome: return Theme.glassFill
        }
    }

    /// 顶缘描边 —— **深色背景下玻璃与背景唯一的分界线**，没有它卡片就是一块脏背景；
    /// 浅色下换成白 90%，作用从"接光"变成"提亮"（PRD §3.2 玻璃层脚注）
    var strokeTopColor: Color { return Theme.glassStrokeTop }

    /// 下缘描边。浅色用 `#0F1A26` 8%，不用白 —— 白描边压在白底上等于没有
    var strokeBottomColor: Color { return Theme.glassStrokeBottom }

    /// 内侧顶部 1pt 高光（模拟折射，玻璃「有厚度」的感觉 90% 来自这两条边）
    var highlightColor: Color { return Theme.glassHighlight }

    /// 外投影：投影是「浮起来」最直接的证据，比加 blur 有效得多。
    /// 浅色换低饱和灰蓝（`#1B2E3F`），黑影在浅底上会发灰显脏（PRD §3.1 第 4 条）
    var shadowColor: Color {
        switch self {
        case .card: return Theme.glassShadowSoft
        default: return Theme.glassShadow
        }
    }

    /// 几何固定不随外观变（设计文档 §1.1.4 的取舍：浅色要求 18 而这里是 24，差 6pt 肉眼不可辨，
    /// 真正的观感目标由 `shadowColor` 换灰蓝 + 双层阴影达成）
    var shadowRadius: CGFloat {
        switch self {
        case .card: return 18
        default: return 24
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .card: return 6
        default: return 8
        }
    }
}

// MARK: - 二级玻璃样式（不采样背景）

/// 二级玻璃样式（不采样背景的廉价配方，见 `View.glassStatic`）。
///
/// 与 `GlassLevel` 刻意分开：真玻璃入口 `glassSurface` 的层级表是「采样背景」那一套，
/// 它的 `switch` 是穷尽的（30+ 调用点依赖它不变），不能因为加了一个「不采样」的级别就改它的 `switch`。
/// 这里只描述「静态配方」的几种圆角/填充档位，由调用方显式选择是否走廉价路径。
enum SurfaceStyle {
    /// 内容卡片档（与 `GlassLevel.card` 同圆角语义）
    case card
}

// MARK: - 唯一入口（真玻璃）

extension View {
    /// 全工程**唯一**的玻璃入口（真玻璃，采样背景）。
    ///
    /// 调用方永远不写 `#available`：iOS 26 走系统 `glassEffect`，iOS 18–25 走手工配方，
    /// 两条轨用同一套 token、同一张层级表、同一个函数签名。
    ///
    /// - Parameters:
    ///   - level: 玻璃层级（决定材质、叠层、描边、投影）
    ///   - shape: 形状，必须是 `InsettableShape`（`inset(by:)` 与 `strokeBorder` 需要它）
    ///   - tint: 只用于状态类染色（青柠 8%），普通卡片传 nil
    ///   - interactive: 是否允许系统按压形变（浮层按钮 / Tab 栏传 true）
    ///
    /// 签名与 V2 完全一致（30+ 个调用点零改动）：批次 1 只把里面的颜色换成 token、
    /// 把影子抽成 `GlassShadow` 修饰符。
    @ViewBuilder
    func glassSurface<S: InsettableShape>(
        _ level: GlassLevel,
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                self.glassEffect(
                    GlassLevel.nativeGlass(tint: tint, interactive: interactive),
                    in: shape
                )
            } else {
                self.modifier(HandGlass(level: level, shape: shape, tint: tint))
            }
        }
        .modifier(GlassShadow(level: level))
    }
}

// MARK: - 二级入口（静态玻璃，不采样背景）

extension View {
    /// 二级玻璃：不采样背景，用 theme-aware 渐变填充 + 顶缘 1pt 半透高光 + 1pt 描边。
    ///
    /// GPU 成本 ≈ 0，视觉接近真玻璃，用于列表卡等「一屏几十张」、不需要透出滚动内容的场景。
    /// 真玻璃（`glassSurface`）保留给 Tab 栏 / 浮层 / 置顶卡（红石倒计时卡、概览顶部卡）。
    ///
    /// 颜色全部走 Theme token：深底白线、浅底黑线由 `glassStaticHighlight` / `glassStaticStroke`
    /// 反向给出，深浅双主题都不必在这里判外观。
    ///
    /// 这是与 `glassSurface` 并行的**另一条路径**，由调用方选择；`glassSurface` 本身不变。
    @ViewBuilder
    func glassStatic<S: InsettableShape>(
        _ style: SurfaceStyle = .card,
        in shape: S,
        tint: Color? = nil
    ) -> some View {
        self.modifier(StaticGlass(shape: shape, tint: tint))
    }
}

// MARK: - 影子（双主题的关键一层）

/// 玻璃投影。抽成 `ViewModifier` 而不是写在 `glassSurface` 里的原因：
/// 影子颜色是 token（自动跟随外观），但**浅色要多一层"近场接触影"**才能压住白底，
/// 而这层在深色下必须是完全透明 —— 写成修饰符后，这一条逻辑只有一处，且不在 View 里判深浅。
struct GlassShadow: ViewModifier {
    let level: GlassLevel

    func body(content: Content) -> some View {
        content
            // 远场扩散影（两套值都在 token 里）
            .shadow(color: level.shadowColor, radius: level.shadowRadius, x: 0, y: level.shadowY)
            // 近场接触影：深色 token 是全透明（0%）→ 深色像素零变化；浅色 5% 灰蓝
            .shadow(color: Theme.glassShadowNear, radius: 2, x: 0, y: 1)
    }
}

// MARK: - 静态玻璃（不采样背景）

/// 静态玻璃：不采样背景的廉价配方。
///
/// 配方 = theme-aware 渐变填充 + 顶部 1pt 半透高光（深色白 12% / 浅色黑 8%）+ 1pt 描边（反向）。
/// 视觉接近真玻璃，但零 backdrop 采样，是「列表卡」这类一屏几十张场景的最大性能收益点（B1）。
///
/// 三条叠加与 `HandGlass` 一致：填充打底 → 顶部渐亮模拟折射 → 描边做分界线 → 顶缘 1pt 内高光。
/// 唯一区别是**不采样背景**，所以填充用 token 实色而非 `Material`，GPU 上几乎是免费的圆角矩形。
struct StaticGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(Theme.glassStaticFill)
                    .overlay {
                        if let tint = tint {
                            shape.fill(tint)
                        }
                    }
                    .overlay {
                        // 顶部向内渐亮：模拟玻璃折射，让静态填充也有"厚度"
                        shape.fill(
                            LinearGradient(
                                colors: [Theme.glassStaticHighlight, Theme.glassHighlightFade],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    }
            }
            .overlay {
                // 1pt 描边：深浅反向（深底白线 / 浅底黑线），玻璃与背景的分界线
                shape.strokeBorder(Theme.glassStaticStroke, lineWidth: 1)
            }
            .overlay {
                // 顶缘 1pt 内高光：与真玻璃同样的"折射感"来源
                shape
                    .inset(by: 0.5)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.glassStaticHighlight, Theme.glassHighlightFade],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.38)
                        ),
                        lineWidth: 1
                    )
            }
    }
}

// MARK: - iOS 26 原生玻璃

@available(iOS 26.0, *)
extension GlassLevel {
    /// 组装系统玻璃配置。
    ///
    /// 注意：`interactive` 必须显式传 `Bool` —— Apple 文档只给出 `interactive(_:)` 带参版本，
    /// 没有默认值，写成无参形式会编译失败。
    static func nativeGlass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint = tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive(true)
        }
        return glass
    }
}
