import SwiftUI

/// 5.7.0 redesign 动效（MASTER.md §7–8）。
///
/// 只做合成层变换（`offset` / `opacity` / `scaleEffect`），不碰任何布局属性 ——
/// 这是 MASTER.md 禁止项第三条：width/height 动画会触发逐帧 layout，掉帧。
/// 三个 modifier 全部在 `accessibilityReduceMotion` 为真时降级为纯淡入，
/// 位移与 stagger 归零，视觉信息完整保留。
///
/// 挂载点刻意独立于天光页已有的视差/呼吸系统 —— 那是滚动驱动的持续动画，
/// 这里是**一次性入场**，两者叠加用各自的 @State，互不干扰。

// MARK: - The one motion · 太阳下沉

/// 太阳沿地平线下沉入场：y −14 → 0，亮度渐显，1.2s easeInOut。
/// 减弱动态时太阳直接在位，只做 180ms 淡入。
struct SunSinkModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = false

    func body(content: Content) -> some View {
        content
            .opacity(started ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (started ? 0 : -14))
            .animation(
                Motion.choose(Motion.sunSink, reduced: reduceMotion),
                value: started
            )
            .onAppear { started = true }
    }
}

// MARK: - 卡片依次入场 · stagger

/// 一组卡片按 index 依次入场：位移 8pt + scale 0.96 → 1，每张间隔 60ms。
/// 减弱动态时位移/缩放/stagger 全归零，所有卡同时淡入。
///
/// - Parameter index: 第几张卡（0 起）。延迟 = index × Motion.staggerStep。
struct StaggerInModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var started = false

    func body(content: Content) -> some View {
        content
            .opacity(started ? 1 : 0)
            .scaleEffect(reduceMotion ? 1 : (started ? 1 : 0.96))
            .offset(y: reduceMotion ? 0 : (started ? 0 : 8))
            .animation(
                Motion.choose(
                    Motion.spring(response: 0.35, dampingFraction: 0.82)
                        .delay(reduceMotion ? 0 : Double(index) * Motion.staggerStep),
                    reduced: reduceMotion
                ),
                value: started
            )
            .onAppear { started = true }
    }
}

// MARK: - View 便捷入口

extension View {
    /// 太阳下沉入场（The one motion）。挂在天光页太阳视图上。
    func sunSink() -> some View {
        modifier(SunSinkModifier())
    }

    /// 卡片依次入场。挂在概览页每张卡上，传卡片序号。
    func staggerIn(index: Int) -> some View {
        modifier(StaggerInModifier(index: index))
    }
}
