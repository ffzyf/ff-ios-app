import SwiftUI

/// 骨架块：`rgba(255,255,255,0.07)` 纯色块（骨架不是玻璃，PRD §4.4 层 5）。
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

/// 斜向光带：白 8% → 18% → 8%，带宽 40%，1.4s 循环
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
                Color.white.opacity(0.08),
                Color.white.opacity(0.18),
                Color.white.opacity(0.08)
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

/// 首页：日期两条短块 + 状态卡 + 简报卡 + 两张封面大卡
struct SkeletonHome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            SkeletonBlock(width: 90, height: 12)
            SkeletonBlock(width: 180, height: 34)
            SkeletonBlock(height: 132, cornerRadius: Radius.card)
            SkeletonBlock(height: 168, cornerRadius: Radius.card)
            ForEach(0..<2, id: \.self) { _ in
                SkeletonBlock(height: 200, cornerRadius: Radius.card)
            }
        }
    }
}

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
