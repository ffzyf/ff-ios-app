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
struct WidgetSkyBackdrop: View {

    /// 此刻属于哪一档天色（由 entry 的时刻算好传进来，不在渲染时调 `Date()`）
    let phase: SkyPhase
    /// 地平线弧顶位置（占高度比例）
    var crestY: CGFloat = 0.62
    /// 地平线两端位置（占高度比例）
    var edgeY: CGFloat = 0.74

    var body: some View {
        let sky = Theme.sky(phase)

        ZStack {
            // ① 天空：顶部到地平线之间的一整段渐变
            LinearGradient(
                colors: [sky.top, sky.horizon],
                startPoint: .top,
                endPoint: .bottom
            )

            // ② 地平线附近的一层大气光晕：让"亮边"不只是根线，而是真的在发光。
            //    中心取在地平线略上方 —— 光是自下而上漫出来的，落在弧顶上会显得脏。
            RadialGradient(
                colors: [sky.edge.opacity(0.30), sky.edge.opacity(0)],
                center: UnitPoint(x: 0.5, y: max(0, edgeY - 0.10)),
                startRadius: 0,
                endRadius: 120
            )

            // ③ 地面：弧线以下压深，让"地面上"的文字（日出日落）自然退到次要层级
            HorizonGround(crestY: crestY, edgeY: edgeY)
                .fill(
                    LinearGradient(
                        colors: [sky.ground, sky.ground.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // ④ 地平线亮边：一条极细的弧 + 轻微模糊，模拟大气折射的那道亮带
            //    （两层叠画是 `SkyCard` 的原始配方：模糊层做光晕，实线层做锐利边缘）
            HorizonEdge(crestY: crestY, edgeY: edgeY)
                .stroke(sky.edge, lineWidth: 1.2)
                .blur(radius: 0.5)
            HorizonEdge(crestY: crestY, edgeY: edgeY)
                .stroke(sky.edge.opacity(0.9), lineWidth: 0.7)
        }
    }
}
