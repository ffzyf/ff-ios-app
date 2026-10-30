import SwiftUI

/// 轨迹卡的核心几何（任务 1「太阳轨迹」弧线）。
///
/// 为什么单独一个文件、且放在 `Sources/Widget/`（不进 `Shared`）：
/// 主 App 根本不用这条弧线（主 App 走自己的卡片体系），进 `Shared` 只会增加复杂度、
/// 还可能把 Widget 专属的"贝塞尔控制点"污染到共享层。Widget target 自己编译一次就够。
///
/// 设计来源：设计文档 §5.1.1。弧线语义统一为「时间轴」——
/// 红石/简报 widget 用「当天已过比例」(0 在 00:00，1 在 24:00)，锁屏实时活动用「72 分钟窗口进度」。
/// 所有 widget 共用同一套几何，保证桌面四张卡视觉同源。
///
/// 关键不变量（任务硬要求）：`pointAt(progress)` 必须与 `shapePath` 画出来的弧线**严格重合**。
/// 做法：两者都用**同一组两段三次贝塞尔控制点**求值——`shapePath` 用 `addCurve` 把这条贝塞尔画出来，
/// `pointAt` 用贝塞尔公式把同一个控制点代进去求点。同一组点，绝不两套算法。
struct ArcGeometry {

    /// 画布宽（widget 坐标系，原点左上）
    let width: CGFloat
    /// 画布高
    let height: CGFloat
    /// 弧线所占高度带占整卡的比例（设计文档：约 0.55）
    let ratio: CGFloat
    /// 底部留白占整卡比例（放两行信息，设计文档 0.20）
    let bottomPad: CGFloat
    /// 顶部留白占整卡比例（弧顶上方留出放顶部一行的空间）
    let topPad: CGFloat

    // MARK: - 计算出来的几何量

    /// 弧线下端点 y（左下/右下落在这条线上）。由于 bottomPad=0.20，落在 0.80·H
    var yBottom: CGFloat { height * (1 - bottomPad) }
    /// 弧线所占高度带 = ratio·H（设计文档：约 55% 卡高）
    var bandHeight: CGFloat { height * ratio }
    /// 弧顶 y（顶点偏右处的最高点）。= yBottom - bandHeight，约在 0.25·H，给顶部一行留白
    var yTop: CGFloat { yBottom - bandHeight }
    /// 顶点横向位置（归一化，设计常量 0.60：弧顶偏右）
    let peakX: CGFloat = 0.60
    /// 顶点横向像素坐标
    var peakPixelX: CGFloat { width * peakX }

    // MARK: - 初始化

    init(width: CGFloat, height: CGFloat, ratio: CGFloat = 0.55, bottomPad: CGFloat = 0.20, topPad: CGFloat = 0.05) {
        self.width = width
        self.height = height
        self.ratio = ratio
        self.bottomPad = bottomPad
        self.topPad = topPad
    }

    // MARK: - 贝塞尔控制点（两段，左→顶→右）

    /// 段 1：左端点 (u=0) → 顶点 (u=peakX)。
    ///
    /// 控制点计算（关键，写在这里以便 `shapePath` 与 `pointAt` 完全一致）：
    /// · x 方向三等分：`0 → xp/3 → 2xp/3 → xp`，保证 x(t) = xp·t 即 x 随 u 线性（point 的 x=W·u）。
    /// · y 方向：`P0= yBottom`，`C1= yBottom - 0.40·band`（起步较陡，接近正弦在端点的陡升），
    ///   `C2= yTop`（顶点处切线水平，得到平滑的圆顶），`P1= yTop`。
    /// · 顶点处 y'(1)=3(yTop-yTop)=0 → 水平切线，圆顶不尖。
    private var segment1: (p0: CGPoint, c1: CGPoint, c2: CGPoint, p1: CGPoint) {
        let xp = peakPixelX
        let yb = yBottom
        let yt = yTop
        return (
            CGPoint(x: 0, y: yb),
            CGPoint(x: xp / 3, y: yb - 0.40 * bandHeight),
            CGPoint(x: 2 * xp / 3, y: yt),
            CGPoint(x: xp, y: yt)
        )
    }

    /// 段 2：顶点 (u=peakX) → 右端点 (u=1)。
    ///
    /// · x 方向三等分：`xp → xp+(W-xp)/3 → xp+2(W-xp)/3 → W`，保证右段 x 随 u 线性。
    /// · y 方向：`P0= yTop`（顶点处水平切线，与上段在顶点 C1 连续），`C1= yTop`，
    ///   `C2= yBottom - 0.40·band`（对称的下落控制点），`P1= yBottom`。
    private var segment2: (p0: CGPoint, c1: CGPoint, c2: CGPoint, p1: CGPoint) {
        let xp = peakPixelX
        let yb = yBottom
        let yt = yTop
        let right = width - xp
        return (
            CGPoint(x: xp, y: yt),
            CGPoint(x: xp + right / 3, y: yt),
            CGPoint(x: xp + 2 * right / 3, y: yb - 0.40 * bandHeight),
            CGPoint(x: width, y: yb)
        )
    }

    // MARK: - 完整弧线（两条三次贝塞尔）

    /// 画整条基线弧线（与 `pointAt` 同组控制点 → 严格重合）。
    ///
    /// `progress` 参数保留作将来「按进度裁剪」的扩展位，当前始终画整条；
    /// 真正的「已走/未走」切分交给 `trimmedPaths(progress:)`。
    func shapePath(progress: CGFloat = 1.0) -> Path {
        _ = progress // 预留：本方法始终返回完整弧，裁剪在 trimmedPaths 做
        let s1 = segment1
        let s2 = segment2
        var path = Path()
        path.move(to: s1.p0)
        path.addCurve(to: s1.p1, control1: s1.c1, control2: s1.c2)
        path.addCurve(to: s2.p1, control1: s2.c1, control2: s2.c2)
        return path
    }

    // MARK: - 任意进度对应的点（与 shapePath 同贝塞尔）

    /// 弧线上 `progress` 处的坐标。必须落在 `shapePath` 画出的线上——用同组控制点求值。
    /// `progress`: 0=左端点(00:00) → 1=右端点(24:00)。
    func pointAt(_ progress: CGFloat) -> CGPoint {
        let u = min(max(progress, 0), 1)
        if u <= peakX {
            // 段 1：u ∈ [0, peakX] 映射到 t ∈ [0, 1]
            let t = u / peakX
            return Self.cubic(segment1.p0, segment1.c1, segment1.c2, segment1.p1, t: t)
        } else {
            // 段 2：u ∈ [peakX, 1] 映射到 t ∈ [0, 1]
            let t = (u - peakX) / (1 - peakX)
            return Self.cubic(segment2.p0, segment2.c1, segment2.c2, segment2.p1, t: t)
        }
    }

    /// 三次贝塞尔求值 B(t) = (1-t)³P0 + 3(1-t)²t·C1 + 3(1-t)t²·C2 + t³P1
    private static func cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * c1.x + c * c2.x + d * p1.x,
            y: a * p0.y + b * c1.y + c * c2.y + d * p1.y
        )
    }

    // MARK: - 已走 / 未走 两段

    /// 把弧线按 `progress` 切成「已走 0→p」（亮实线）与「未走 p→1」（同色压低不透明度）。
    ///
    /// 用 `Path.trimmedPath(from:to:)`（iOS 16+，本 Widget target 部署 iOS 18，稳）。
    /// 它基于弧长参数化裁剪，对这条单调弧线裁剪点就在弧上、与 `pointAt(progress)` 落点视觉重合（亚像素级）。
    /// 发光节点仍由 `pointAt(progress)` 精确定位，保证「节点在弧线上」严格成立。
    func trimmedPaths(progress: CGFloat) -> (done: Path, todo: Path) {
        let full = shapePath()
        let p = min(max(progress, 0), 1)
        let done = full.trimmedPath(from: 0, to: p)
        let todo = full.trimmedPath(from: p, to: 1)
        return (done, todo)
    }

    // MARK: - 发光节点

    /// 当前时刻的发光节点：实心小圆 + 外层径向光晕（半径 ≈ 点半径 3.5×，向外虚化）。
    ///
    /// 用 `RadialGradient` 从 `tint` 渐变到透明 + 轻微 `blur` 做光晕；`.position` 用 `pointAt`
    /// 精确落点，保证节点严格在弧线上。调用方把它放进 ZStack 即可（弧线在底层）。
    func glowNode(at progress: CGFloat, radius: CGFloat = 4, tint: Color) -> some View {
        let center = pointAt(progress)
        let haloRadius = radius * 3.5
        return ZStack {
            // 光晕：径向渐变到透明 + 轻微模糊，半径约为点半径的 3.5 倍
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint, tint.opacity(0.0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: haloRadius
                    )
                )
                .frame(width: haloRadius * 2, height: haloRadius * 2)
                .blur(radius: radius * 0.5)
            // 实心点
            Circle()
                .fill(tint)
                .frame(width: radius * 2, height: radius * 2)
        }
        .position(center)
    }
}

/// 轨迹卡背景层：渐变之上的弧线 + 发光节点（透明底，叠在 `containerBackground` 渐变之上）。
///
/// 单独抽出来是因为红石小/中号、简报中号、锁屏实时活动都要画同一套弧线，避免四处复制。
/// 底部统一叠一层 `Color.black.opacity(0.12)` scrim（设计文档 §5.1.2 对策②）：浅色下把弧区压深保证
/// 下层文字可读；深色下叠在已经很深的渐变上几乎不可见，故不再按外观分支
/// （Widget target 不能读 `colorScheme ==`，否则会触发主题闸门规则 2）。
struct TrackCardBackdrop: View {

    let geometry: ArcGeometry
    let progress: CGFloat
    let tint: Color
    /// 弧线粗细（小号/中号一致即可，按画布比例给默认值）
    var lineWidth: CGFloat = 2.5
    /// 节点半径
    var nodeRadius: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let g = ArcGeometry(
                width: geo.size.width,
                height: geo.size.height,
                ratio: geometry.ratio,
                bottomPad: geometry.bottomPad,
                topPad: geometry.topPad
            )
            let paths = g.trimmedPaths(progress: progress)
            ZStack {
                // 底部 scrim：把弧区压深，保证下层文字可读（设计文档对策②）。
                // 统一施加：深色下叠在深色渐变上不可见，故无需按外观分支。
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.black.opacity(0.12))
                        .frame(height: geo.size.height * geometry.bottomPad)
                }
                // 已走：亮实线
                paths.done
                    .stroke(tint, lineWidth: lineWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 未走：同色压低不透明度（约 35%）
                paths.todo
                    .stroke(tint.opacity(0.35), lineWidth: lineWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 发光节点（严格落在弧线上）
                g.glowNode(at: progress, radius: nodeRadius, tint: tint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 当天进度（时间轴 progress）

/// 轨迹卡共用的「当天已过比例」计算。
///
/// 为什么用北京时间（而非设备本地时）：红石的所有时刻都是北京时间，弧线若跟着设备时区走，
/// 跨时区用户的「此刻位置」会和卡上显示的红石时刻对不上。和 `RedstoneClock` 保持一致最稳。
extension ArcGeometry {
    /// 0 在 00:00（北京）、1 在 24:00。`now` 默认当前时刻；Widget 端现算即可，无需从网络来。
    static func dayProgress(now: Date = Date()) -> CGFloat {
        let key = RedstoneClock.dayKey(now)
        guard let start = RedstoneClock.startOfDay(dayKey: key) else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return CGFloat(min(max(elapsed / 86_400, 0), 1))
    }
}
