import SwiftUI

/// Dynamic Type 护栏（HIG 迭代 · L3）。
///
/// 固定高度的数字读数 / 徽标 / 图标标签不能无限放大（会溢出或互相重叠），
/// 但正文必须跟随系统字号。本 modifier 用 `.dynamicTypeSize(_ range:)` 给某一处
/// 视图**限定上下限**：默认上限 `accessibilityLarge`，超出后系统停在该档，
/// 不会破版；不影响同级其它视图的字号。
struct DynamicTypeGuard: ViewModifier {
    let limits: ClosedRange<DynamicTypeSize>

    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(limits)
    }
}

extension View {
    /// 限制本视图响应 Dynamic Type 的范围，默认 `.xSmall...accessibilityLarge`。
    ///
    /// 只加在固定尺寸处（徽标、Tab 标签、倒计时读数）；正文用语义 Font 自然跟随即可。
    func guardedDynamicType(
        _ limits: ClosedRange<DynamicTypeSize> = .xSmall...accessibilityLarge
    ) -> some View {
        modifier(DynamicTypeGuard(limits: limits))
    }
}

/// 少数"必须自己按字号算尺寸"的位置用的换算（本轮无调用点，供后续尺寸护栏使用）。
///
/// 语义 Font 已经覆盖了绝大多数文本；只有自绘刻度 / 机器码画布这类位置需要
/// 把基准 pt 按当前 Dynamic Type 档位手动缩放。比例以 `.large` 为 1.0 基线，
/// 数值取 Apple Dynamic Type 各档相对基准的近似放大倍率。
enum HIGTypeScale {
    /// 基线档：App 默认视觉规范对应的档位。
    static let baseline: DynamicTypeSize = .large

    /// 当前档相对 `.large` 的放大倍率。
    static func ratio(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: return 0.86
        case .small: return 0.92
        case .medium: return 0.96
        case .large: return 1.0
        case .xLarge: return 1.12
        case .xxLarge: return 1.24
        case .xxxLarge: return 1.36
        case .accessibility1: return 1.50
        case .accessibility2: return 1.64
        case .accessibility3: return 1.78
        case .accessibility4: return 1.92
        case .accessibility5: return 2.06
        @unknown default: return 1.0
        }
    }

    /// 把基准 pt 按当前档位缩放。
    static func scaledMetric(_ base: CGFloat, for size: DynamicTypeSize) -> CGFloat {
        return base * ratio(for: size)
    }
}
