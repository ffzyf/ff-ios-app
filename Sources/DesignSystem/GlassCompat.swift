import SwiftUI

/// 玻璃层级（PRD §4.4 / 设计文档 §5.6）。
///
/// 核心原则：**玻璃表达「浮在内容之上」，不表达「这是一个盒子」**。
/// 所以只有 4 层，且「越靠上越厚 —— 但 Tab 栏例外」（Tab 栏视觉最上层却用最薄的材质，
/// 因为它必须透出滚动内容才能证明自己在浮）。
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

    /// 白色叠层：材质本身不够「亮」，深底上会显脏，用纯白叠层提亮
    var whiteFill: Double {
        switch self {
        case .sheet: return 0.10
        case .floating: return 0.08
        case .card: return 0.06
        case .chrome: return 0.06
        }
    }

    /// 顶缘描边不透明度 —— **深色背景下玻璃与背景唯一的分界线**，没有它卡片就是一块脏背景
    var topStroke: Double {
        switch self {
        case .sheet: return 0.22
        default: return 0.18
        }
    }

    /// 下缘描边不透明度
    var bottomStroke: Double { return 0.04 }

    /// 内侧顶部 1pt 高光（模拟折射，玻璃「有厚度」的感觉 90% 来自这两条边）
    var innerHighlight: Double { return 0.14 }

    /// 外投影：投影是「浮起来」最直接的证据，比加 blur 有效得多
    var shadowOpacity: Double {
        switch self {
        case .card: return 0.35
        default: return 0.45
        }
    }

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

// MARK: - 唯一入口

extension View {
    /// 全工程**唯一**的玻璃入口。
    ///
    /// 调用方永远不写 `#available`：iOS 26 走系统 `glassEffect`，iOS 18–25 走手工配方，
    /// 两条轨用同一套 token、同一张层级表、同一个函数签名。
    ///
    /// - Parameters:
    ///   - level: 玻璃层级（决定材质、叠层、描边、投影）
    ///   - shape: 形状，必须是 `InsettableShape`（`inset(by:)` 与 `strokeBorder` 需要它）
    ///   - tint: 只用于状态类染色（青柠 8%），普通卡片传 nil
    ///   - interactive: 是否允许系统按压形变（浮层按钮 / Tab 栏传 true）
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
        .shadow(
            color: Color.black.opacity(level.shadowOpacity),
            radius: level.shadowRadius,
            x: 0,
            y: level.shadowY
        )
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
