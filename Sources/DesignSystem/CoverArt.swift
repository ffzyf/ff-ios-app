import SwiftUI

/// 程序化封面（PRD §3.1.2）。
///
/// 后端 article **没有** cover 字段（PRD F1），所以不能留灰块占位。规则：
/// `coverSeed`（0–3，服务端 `fnv1a(id) % 4`）映射到 4 组青柠/深空渐变 +
/// 标题首字水印（48pt Bold）+ 极细噪点（避免纯渐变的塑料感）。
///
/// 这个方案是「不完美但体面」的取舍：与其显示一堆灰色占位方块，
/// 不如让每篇文章有独一无二的渐变身份；P1 拿到真实封面后只替换图片层，布局不变。
///
/// 双主题（批次 1）：4 组渐变的两套停靠点全部在 Theme 的 coverLime / coverDeep / coverAmber / coverCool 里
/// （PRD §3.2 末表逐行照抄），本文件只剩"水印 + 噪点"两个不透明度，也各自有 token。
struct CoverArt: View {
    let seed: Int
    let title: String
    /// 首字水印字号（大卡 48 / 列表缩略 20 / 详情 Hero 96）
    var watermarkSize: CGFloat = 48
    var showsGrain: Bool = true

    var body: some View {
        ZStack {
            LinearGradient(
                colors: Theme.coverColors(seed: seed),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if showsGrain {
                CoverGrain()
            }
            Text(initial)
                .font(.system(size: watermarkSize, weight: .bold))
                .foregroundStyle(Theme.coverWatermark)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// 标题首字：1 个汉字或字母。空标题给一个中性点，绝不留空。
    private var initial: String {
        guard let first = title.first else { return "·" }
        return String(first)
    }
}

/// 极细噪点：确定性布点（同一 seed 永远同一张图，不闪烁）
private struct CoverGrain: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<240 {
                let fx = CGFloat((index * 37) % 240) / 240.0
                let fy = CGFloat((index * 91) % 240) / 240.0
                let dot = CGRect(x: fx * size.width, y: fy * size.height, width: 1, height: 1)
                context.fill(Path(dot), with: .color(Theme.coverGrain))
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}
