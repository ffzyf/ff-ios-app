import SwiftUI

/// 地平线以下的地面（弧顶在正中，两端下沉）。
///
/// 用二次贝塞尔而不是圆弧：参考图里的地平线是"缓坡"不是"圆边"，
/// 圆弧在宽卡片上两端会翘得过于明显。控制点取 `2·crestY − edgeY`，
/// 使曲线在 t=0.5 处正好落在 `crestY`（数学上精确穿过弧顶，不是目测）。
struct HorizonGround: Shape {
    /// 弧顶位置（正中），占高度比例
    var crestY: CGFloat
    /// 两端位置，占高度比例（应大于 crestY）
    var edgeY: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let controlY = h * (2 * crestY - edgeY)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: h * edgeY))
        path.addQuadCurve(to: CGPoint(x: w, y: h * edgeY),
                          control: CGPoint(x: w / 2, y: controlY))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

/// 地平线亮边（只画那条弧，不闭合）
struct HorizonEdge: Shape {
    var crestY: CGFloat
    var edgeY: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h * edgeY))
        path.addQuadCurve(to: CGPoint(x: w, y: h * edgeY),
                          control: CGPoint(x: w / 2, y: h * (2 * crestY - edgeY)))
        return path
    }
}

/// 天际线卡（V3.2，照参考图重做简报卡）。
///
/// 结构是三段：**天空渐变 → 地平线弧 → 地面**。天色由 `SkyPhase`（按当地时间算）决定，
/// 所以一天里看过去卡片会自己变色：夜里深蓝、日出橙、白天蓝、日落红。
///
/// 为什么文字能压在上面还看得清：天空色是**物理色**（不随 App 深浅变），
/// 每一档都配了一组固定的浅色字（`ink / inkDim`），并且地平线压到 62% 以下 ——
/// 正文永远在天空区，时间落在暗色地面区，两边都不打架。
///
/// 与 `TrackCard` 的分工：`TrackCard` 是"深色底 + 一条光轨"（红石卡用），
/// 本组件是"整块天空"（简报卡用）。两者都只做底盘，内容由调用方给。
struct SkyCard<Content: View>: View {

    let phase: SkyPhase
    let now: Date
    /// 日出 / 日落时刻文案（`06:05`），由调用方从 `SunClock` 取
    let sunriseText: String
    let sunsetText: String
    var cornerRadius: CGFloat = Radius.card
    private let content: Content

    init(phase: SkyPhase,
         now: Date,
         sunriseText: String,
         sunsetText: String,
         cornerRadius: CGFloat = Radius.card,
         @ViewBuilder content: () -> Content) {
        self.phase = phase
        self.now = now
        self.sunriseText = sunriseText
        self.sunsetText = sunsetText
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    /// 地平线弧顶 / 两端（占卡片高度）
    private let crestY: CGFloat = 0.62
    private let edgeY: CGFloat = 0.74

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        let sky = Theme.sky(phase)

        ZStack {
            skyBackground(sky)
            VStack(alignment: .leading, spacing: 0) {
                headerRow(sky)
                Spacer(minLength: 10)
                content
                Spacer(minLength: 12)
                footerRow(sky)
            }
            .padding(Spacing.cardPadding)
        }
        .frame(minHeight: 196)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Theme.glassStrokeTop.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: Theme.glassShadowSoft, radius: 18, y: 10)
    }

    // MARK: - 背景

    private func skyBackground(_ sky: Theme.SkyColors) -> some View {
        ZStack {
            LinearGradient(
                colors: [sky.top, sky.horizon],
                startPoint: .top,
                endPoint: .bottom
            )
            HorizonGround(crestY: crestY, edgeY: edgeY)
                .fill(
                    LinearGradient(
                        colors: [sky.ground, sky.ground.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            // 地平线亮边：一条极细的弧线 + 轻微模糊，模拟大气折射的那道亮带
            HorizonEdge(crestY: crestY, edgeY: edgeY)
                .stroke(sky.edge, lineWidth: 1.4)
                .blur(radius: 0.5)
            HorizonEdge(crestY: crestY, edgeY: edgeY)
                .stroke(sky.edge.opacity(0.9), lineWidth: 0.7)
        }
    }

    // MARK: - 顶部：时段 + 倒计时

    private func headerRow(_ sky: Theme.SkyColors) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(sky.edge)
                .frame(width: 7, height: 7)
                .shadow(color: sky.edge.opacity(0.8), radius: 4)

            Text(phase.label)
                .font(Typography.caption)
                .foregroundStyle(sky.ink)

            Spacer(minLength: 8)

            if let deadline = phase.deadline(at: now) {
                Text(SkyPhase.countdownText(to: deadline, now: now))
                    .font(Typography.caption)
                    .foregroundStyle(sky.ink.opacity(0.92))
                    .monospacedDigit()
            }
        }
    }

    // MARK: - 底部：日出 / 日落（落在地面区）

    private func footerRow(_ sky: Theme.SkyColors) -> some View {
        HStack(spacing: 0) {
            Text(sunriseText)
                .font(Typography.caption)
                .foregroundStyle(sky.inkDim)
                .monospacedDigit()
            Spacer(minLength: 8)
            Text(sunsetText)
                .font(Typography.caption)
                .foregroundStyle(sky.inkDim)
                .monospacedDigit()
        }
    }
}

// MARK: - 卡上的正文（供简报卡复用）

/// 天空卡里的正文块：标题 + 一两行摘要。
///
/// 单独抽出来是因为**字号/行距/上限行数都要为"压在渐变上"调过**：
/// 行数一多就会越过地平线，所以这里硬性 `lineLimit`，而不是交给调用方自觉。
struct SkyCardBody: View {
    let title: String
    let lines: [String]
    let ink: Color
    let inkDim: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.titleS)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Typography.caption)
                    .foregroundStyle(inkDim)
                    .lineLimit(2)
                    .lineSpacing(Typography.lineSpacing(fontSize: 12, multiple: 1.35))
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
