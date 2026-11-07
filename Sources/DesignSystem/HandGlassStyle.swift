import SwiftUI

// MARK: - iOS 18–25 手工玻璃（保底配方，也是全平台的兜底路径）

/// 手工玻璃 —— 3.31.0 起改用「技能原味」B 配方（用户在 3 档效果图里选定）。
///
/// ## 配方（与 CSS 原型逐条对应）
///
/// ```
/// 薄材质 78%      ← backdrop-filter: blur(2px) saturate(180%) brightness(1.06)
/// 白叠层          ← background: rgba(255,255,255,0.14)
/// 顶部 sheen      ← 顶部向内的一层极淡渐亮
/// 四向斜面 + 双轮廓 ← 六条 inset shadow（见 `GlassBevel`）
/// 轻外投影        ← 0 4px 16px rgba(0,0,0,0.10)
/// ```
///
/// ## 为什么不再靠"加厚 Material"表达厚度
///
/// 3.8.1 的结论是"太玻璃了，要毛玻璃"，于是 `.card` 从 ultraThin 加厚到 regular。
/// 但 Material 的模糊半径**系统固定、不可调**，加厚只换来两件事：背后更糊、卡片更灰。
/// 而原型的"清透"恰恰来自 **blur 只有 2px** —— 天光和云的轮廓还在，只是被抬亮了。
/// 于是这一版反过来：
///
/// 1. 材质降到 **78%** 不透明度（`shape.fill(level.material).opacity(0.78)`）—— 这不是调模糊，
///    是把"雾"的占比降下来，让底下的天光重新参与成像；
/// 2. 厚度改由**边的明暗分布**表达：四向内斜面 + 内白外黑 0.5pt 双轮廓（`GlassBevel`）。
///    旧实现只有"单条顶光描边 + 1pt 内高光"，整圈同亮度，所以看起来像一块平板；
/// 3. 外投影同步调轻（`glassShadowSoft` 深色 35% → 20%），卡片才是"轻轻浮起"。
///
/// ## 双主题
///
/// 本文件**不读任何环境**：六个斜面 token、白叠层、投影色都由 `Theme` 的动态色自己解析，
/// 深浅切换走同一条代码路径。浅色的补偿只有一条原则 —— 白斜面要更亮、底缘暗边要换黑
/// （理由写在 `Theme.glassBevel*` 的注释里）。
struct HandGlass<S: InsettableShape>: ViewModifier {
    let level: GlassLevel
    let shape: S
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                // 顺序 = 底 → 边 → 内容：斜面画在**填充之上、内容之下**。
                //
                // 为什么不是 `.overlay { GlassBevel }`（内容之上）：CSS 的 `inset` 阴影
                // 绘制在元素的背景层，文字永远压在它上面。若画到内容之上，卡片顶端 14%
                // 的那条 50%（浅色 85%）白渐变会**洗掉标题**——浅色深字最明显。
                // 背景栈里画，天然就是"光打在玻璃上、字坐在玻璃里"。
                fill
                    .overlay { GlassBevel(shape: shape) }
            }
            // 半透明叠层先合成为一个离屏缓冲，再与背后做一次合成 ——
            // 否则每层各自与背后混合，边缘会出现一圈偏亮的"halo"
            .compositingGroup()
    }

    /// 底色：薄材质 → 白叠层（提亮）→ 业务染色 → 顶部向内渐亮
    ///
    /// 顺序不能换：白叠层与染色都必须压在材质之上（材质会继续采样背后的内容，
    /// 把它放在最上层会把下面所有颜色一起糊掉）。
    private var fill: some View {
        shape
            // 78% 的材质 = "雾只占七成"：天光、云、地平线仍然透得出来。
            //
            // 为什么把 `opacity` 挂在 View 层（`shape.fill(...).opacity(0.78)`）而不是写成
            // `shape.fill(level.material.opacity(0.78))`：
            // 后者要 `ShapeStyle.opacity(_:)`（iOS 17+），虽然目标 18.0 可用，但它在
            // `fill` 的泛型参数 S: ShapeStyle 上做类型推断，是本机无编译器时最不该赌的一行。
            // 而 `View.opacity(_:)` 是 iOS 13 就有的稳定 API，两者合成结果一致 ——
            // 都是"把材质这一层以 78% 压到背景上"，下面的白叠层 / 染色 / sheen 不受影响。
            .fill(level.material)
            .opacity(0.78)
            .overlay {
                shape.fill(level.fillColor)
            }
            .overlay {
                if let tint = tint {
                    shape.fill(tint)
                }
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [Theme.glassSheen, Theme.glassHighlightFade],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
    }
}
