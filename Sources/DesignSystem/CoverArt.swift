import SwiftUI

/// 封面：优先真实图片，缺失时退回程序化渐变（PRD §3.1.2）。
///
/// 服务端现在会下发 `cover`（写在博客后台的那张图，和网页、RSS 是同一张），
/// 有就铺满容器；为 nil 时退回老方案：`coverSeed`（0–3，服务端 `fnv1a(id) % 4`）
/// 映射到 4 组青柠/深空渐变 + 标题首字水印 + 极细噪点。
///
/// 渐变始终画在最底层：图片加载中或加载失败时，看到的是渐变而不是灰块，
/// 所以这个视图在任何网络状态下都不会出现空白。
///
/// 双主题（批次 1）：4 组渐变的两套停靠点全部在 Theme 的 coverLime / coverDeep / coverAmber / coverCool 里
/// （PRD §3.2 末表逐行照抄），本文件只剩"水印 + 噪点"两个不透明度，也各自有 token。
struct CoverArt: View {
    let seed: Int
    let title: String
    /// 服务端下发的真实封面；为 nil 时只用渐变。
    var coverURL: URL? = nil
    /// 首字水印字号（大卡 48 / 列表缩略 20 / 详情 Hero 96）
    var watermarkSize: CGFloat = 48
    var showsGrain: Bool = true

    var body: some View {
        ZStack {
            gradientLayer
            if let coverURL {
                // 图片铺满裁切；加载中/失败都留空，露出下面的渐变
                AsyncImage(url: coverURL, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// 渐变底 + 水印 + 噪点：没有封面时它就是封面，有封面时它是加载占位。
    private var gradientLayer: some View {
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
