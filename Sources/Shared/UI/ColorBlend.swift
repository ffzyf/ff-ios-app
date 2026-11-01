import SwiftUI
import UIKit

extension Color {

    /// 两个颜色按 `t` 做**不透明**线性混合（`t = 0` 取 `a`，`t = 1` 取 `b`）。
    ///
    /// ## 为什么必须有这个函数（3.15.0 的教训）
    ///
    /// `Color.opacity(_:)` 得到的是**半透明色**。它叠在渐变里时，露出来的是**下层**的颜色，
    /// 不是"更深的它自己"。用半透明色去搭天空 = 天空的颜色由"底下垫着什么"决定：
    ///
    /// ```
    /// 天顶想更暗 → sky.ground.opacity(0.44)
    ///            → 实际画出来是「44% 深棕 + 56% 白底」= 中灰
    /// ```
    ///
    /// 3.13 / 3.14 的真机天空一片灰白、山是一块土黄抹布，全部来自这一条：
    /// **整条渐变链每一层都是半透明**，最底下是 App 的白底，于是所有颜色都被稀释成灰。
    /// 设计预览用的 HTML 里颜色是实色，所以"预览好看、真机难看"。
    ///
    /// 要"更深的天顶"，正确做法是**真的把两个颜色混成一个新颜色**，而不是调透明度。
    /// 这个函数就是干这件事的：输出永远是 `opacity: 1`。
    ///
    /// - Parameters:
    ///   - a: 起点色
    ///   - b: 终点色
    ///   - t: 混合比例（0…1，超出会被夹紧）
    static func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let amount = min(max(t, 0), 1)
        let from = UIColor(a).resolvedSRGB
        let to = UIColor(b).resolvedSRGB
        return Color(
            .sRGB,
            red: Double(from.red + (to.red - from.red) * CGFloat(amount)),
            green: Double(from.green + (to.green - from.green) * CGFloat(amount)),
            blue: Double(from.blue + (to.blue - from.blue) * CGFloat(amount)),
            opacity: 1
        )
    }
}

// MARK: - UIColor → sRGB 分量

private extension UIColor {

    /// 统一折算到 sRGB 分量。动态色（`Theme` 里那批 `dyn()`）先解析成当前外观的实色，
    /// 灰度色也能拿到三分量 —— `getRed` 对这两种输入都可能返回 false，所以要兜底。
    var resolvedSRGB: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let resolved = self.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (red, green, blue)
        }
        // 灰度 / 图案色兜底：取白度当三分量，至少不会算出黑色
        var white: CGFloat = 0
        if resolved.getWhite(&white, alpha: &alpha) {
            return (white, white, white)
        }
        return (0, 0, 0)
    }
}
