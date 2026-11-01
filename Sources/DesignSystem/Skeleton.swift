import SwiftUI

/// 骨架块：`Theme.skeleton` 纯色块（骨架不是玻璃，PRD §4.4 层 5）。
///
/// 双主题：深色是白 7%（与 V2 同值），浅色换成深灰蓝 6% ——
/// 浅色下如果沿用白 7%，骨架块与 `#F7F9F6` 页面几乎同色，加载态等于不存在（PRD §4 #6）。
///
/// 动效选型：**不用** `TimelineView` / `phaseAnimator`（签名与行为差异大、不好在 Linux 上确认），
/// 用最稳的 `withAnimation + repeatForever` 位移一道 40% 宽的高光带（PRD §4.6：1.4s 循环）。
/// `reduceMotion` 打开时高光带静止不动，只保留静态骨架块。
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.skeleton)
            .frame(width: width, height: height)
            .overlay {
                ShimmerBar()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
    }
}

/// 斜向光带：暗 → 亮 → 暗，带宽 40%，1.4s 循环
///
/// 双主题：V2 是 white 8% → 18% → 8%。浅色下白 8% 压在 `#0F1A26 6%` 的骨架块上**完全看不见**，
/// 等于没有加载态（PRD §4 #6），所以浅色换成深灰蓝 6% → 12% → 6%。
private struct ShimmerBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ShimmerBand(
                phase: phase,
                bandWidth: max(proxy.size.width, 1) * 0.4,
                travel: max(proxy.size.width, 1) * 1.4
            )
        }
        .clipped()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.shimmer) {
                phase = 1
            }
        }
    }
}

private struct ShimmerBand: View {
    let phase: CGFloat
    let bandWidth: CGFloat
    let travel: CGFloat

    var body: some View {
        LinearGradient(
            colors: [
                Theme.skeletonShimmerLow,
                Theme.skeletonShimmerMid,
                Theme.skeletonShimmerLow
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: bandWidth)
        .offset(x: -bandWidth + phase * travel)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - 按页面结构预置的骨架（尺寸与真实内容误差 <2pt，收起不跳动）

/// 列表：5 张 116pt 卡（含 56×56 圆角缩略块）
struct SkeletonList: View {
    var count: Int = 5

    var body: some View {
        VStack(spacing: Spacing.cardGap) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    SkeletonBlock(width: 56, height: 56, cornerRadius: Radius.smallCard)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(height: 16)
                        SkeletonBlock(width: 220, height: 16)
                        SkeletonBlock(width: 140, height: 12)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Spacing.smallCardPadding)
                .frame(height: 116)
                .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        }
    }
}

/// 详情：封面 220pt + 标题两行 + 元信息一行 + 6 行正文（行宽 60–100%）
struct SkeletonDetail: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.blockGap) {
                SkeletonBlock(height: 220, cornerRadius: 0)
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonBlock(height: 28)
                    SkeletonBlock(height: 28)
                    SkeletonBlock(width: 200, height: 12)
                }
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(0..<6, id: \.self) { index in
                        HStack(spacing: 0) {
                            SkeletonBlock(height: 17)
                            if index % 3 == 1 {
                                Spacer(minLength: 90)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.page)
        }
        .scrollIndicators(.hidden)
    }
}

/// 简报：并列两卡 + 一张 300pt 卡
struct SkeletonBrief: View {
    var body: some View {
        VStack(spacing: Spacing.cardGap) {
            HStack(spacing: Spacing.cardGap) {
                SkeletonBlock(height: 140, cornerRadius: Radius.card)
                SkeletonBlock(height: 140, cornerRadius: Radius.card)
            }
            SkeletonBlock(height: 300, cornerRadius: Radius.card)
        }
    }
}
