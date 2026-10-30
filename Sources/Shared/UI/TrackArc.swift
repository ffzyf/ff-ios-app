import SwiftUI

/// 轨迹卡（Track Card）的核心几何 —— **App 与桌面小组件共用这一份**。
///
/// 为什么从 `Sources/Widget/` 搬到 `Sources/Shared/`：V3.1 返工后首页卡片与桌面 widget
/// 必须是同一套视觉语言（同一条弧线、同一个发光节点、同一套进度算法），
/// 各写一份迟早"卡上是 62%、桌面上是 58%"。放进 Shared 后两个 target 编译同一份代码，
/// 像素级一致是编译期保证，不靠人自觉。
///
/// 语义统一为「时间轴」：progress = 当天已过比例（0 在 00:00，1 在 24:00），
/// 锁屏实时活动用「72 分钟窗口进度」，只是换 progress 的来源，几何不变。
///
/// 关键不变量：`pointAt(progress)` 必须与 `shapePath` 画出来的弧线**严格重合**。
/// 做法：两者都用**同一组两段三次贝塞尔控制点**求值 —— `shapePath` 用 `addCurve` 画，
/// `pointAt` 把同一组控制点代进贝塞尔公式。同一组点，绝不两套算法。
struct ArcGeometry {

    /// 画布宽（坐标系原点左上）
    let width: CGFloat
    /// 画布高
    let height: CGFloat
    /// 弧线所占高度带占整卡的比例
    let ratio: CGFloat
    /// 底部留白占整卡比例
    let bottomPad: CGFloat
    /// 顶部留白占整卡比例
    let topPad: CGFloat
    /// 弧顶横向位置（归一化）。0.5 = 正中，>0.5 = 弧顶偏右（参考图的手感）
    let peakX: CGFloat

    // MARK: - 计算出来的几何量

    /// 弧线下端点 y（左下/右下落在这条线上）
    var yBottom: CGFloat { height * (1 - bottomPad) }
    /// 弧线所占高度带 = ratio·H
    var bandHeight: CGFloat { height * ratio }
    /// 弧顶 y（最高点）
    var yTop: CGFloat { yBottom - bandHeight }
    /// 顶点横向像素坐标
    var peakPixelX: CGFloat { width * peakX }

    // MARK: - 初始化

    init(width: CGFloat,
         height: CGFloat,
         ratio: CGFloat = 0.55,
         bottomPad: CGFloat = 0.20,
         topPad: CGFloat = 0.05,
         peakX: CGFloat = 0.62) {
        self.width = width
        self.height = height
        self.ratio = ratio
        self.bottomPad = bottomPad
        self.topPad = topPad
        self.peakX = min(max(peakX, 0.2), 0.85)
    }

    // MARK: - 贝塞尔控制点（两段，左→顶→右）

    /// 段 1：左端点 (u=0) → 顶点 (u=peakX)。
    /// x 三等分保证 x 随 u 线性；y 起步 0.40·band（近正弦端部陡升），顶点切线水平（圆顶不尖）。
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

    /// 段 2：顶点 (u=peakX) → 右端点 (u=1)，与段 1 在顶点处 C1 连续。
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

    // MARK: - 完整弧线

    func shapePath() -> Path {
        let s1 = segment1
        let s2 = segment2
        var path = Path()
        path.move(to: s1.p0)
        path.addCurve(to: s1.p1, control1: s1.c1, control2: s1.c2)
        path.addCurve(to: s2.p1, control1: s2.c1, control2: s2.c2)
        return path
    }

    // MARK: - 任意进度对应的点

    /// 弧线上 `progress` 处的坐标（与 `shapePath` 同一组控制点，所以严格落在线上）。
    func pointAt(_ progress: CGFloat) -> CGPoint {
        let u = min(max(progress, 0), 1)
        if u <= peakX {
            let t = u / peakX
            return Self.cubic(segment1.p0, segment1.c1, segment1.c2, segment1.p1, t: t)
        } else {
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

    /// 按 `progress` 切成「已走 0→p」（亮实线）与「未走 p→1」（同色压低）。
    func trimmedPaths(progress: CGFloat) -> (done: Path, todo: Path) {
        let full = shapePath()
        let p = min(max(progress, 0), 1)
        return (full.trimmedPath(from: 0, to: p), full.trimmedPath(from: p, to: 1))
    }

    // MARK: - 发光节点

    /// 当前时刻的发光节点：实心小圆 + 外层径向光晕，`.position(pointAt)` 精确落点。
    func glowNode(at progress: CGFloat, radius: CGFloat = 4, tint: Color) -> some View {
        let center = pointAt(progress)
        let haloRadius = radius * 3.6
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.85), tint.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: haloRadius
                    )
                )
                .frame(width: haloRadius * 2, height: haloRadius * 2)
                .blur(radius: radius * 0.6)
            Circle()
                .fill(tint)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .strokeBorder(tint.opacity(0.9), lineWidth: 0.6)
                .frame(width: radius * 2.6, height: radius * 2.6)
                .opacity(0.5)
        }
        .position(center)
    }
}

// MARK: - 弧线背景层（App 与 Widget 共用）

/// 轨迹卡的背景层：**只在指定高度带内**画弧线 + 发光节点。
///
/// 为什么必须限定高度带（这是本轮返工的核心修正）：
/// 上一版把弧线画满整张卡，弧顶正好穿过标题与右侧列表 —— 文字压在曲线上，既难读又难看。
/// 现在弧线只占卡片偏下的 `bandTop…bandBottom` 区间，文字区永远在弧线之上，
/// 曲线只在空白处"扫过"，这才是参考图里那条安静的光轨。
///
/// 同时给底部叠一层很淡的 scrim：浅色主题下卡片偏白，弧线会发灰；压深一点点就能立住。
struct TrackArcBackdrop: View {

    /// 0 = 左端（00:00），1 = 右端（24:00）
    var progress: CGFloat
    var tint: Color
    var lineWidth: CGFloat = 2
    /// 节点半径（小号卡给 3.5，中号卡 4.5）
    var nodeRadius: CGFloat = 4
    /// 弧线带的上沿（占整卡高度比例）
    var bandTop: CGFloat = 0.34
    /// 弧线带的下沿
    var bandBottom: CGFloat = 0.94
    /// 弧顶横向位置
    var peak: CGFloat = 0.62
    /// 底部压暗强度（0 关闭）
    var scrimOpacity: Double = 0.10

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let bandH = max(8, h * (bandBottom - bandTop))
            let g = ArcGeometry(width: geo.size.width,
                                height: bandH,
                                ratio: 1,
                                bottomPad: 0,
                                topPad: 0,
                                peakX: peak)
            let paths = g.trimmedPaths(progress: progress)
            ZStack(alignment: .topLeading) {
                if scrimOpacity > 0 {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0), Theme.scrim.opacity(scrimOpacity)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: h * (1 - bandTop))
                    }
                }
                ZStack(alignment: .topLeading) {
                    paths.todo
                        .stroke(tint.opacity(0.30), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    paths.done
                        .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    g.glowNode(at: progress, radius: nodeRadius, tint: tint)
                }
                .frame(width: geo.size.width, height: bandH, alignment: .topLeading)
                .offset(y: h * bandTop)
            }
            .frame(width: geo.size.width, height: h, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 当天进度（时间轴 progress）

extension ArcGeometry {
    /// 0 在 00:00（北京）、1 在 24:00。红石时刻都是北京时间，弧线若跟设备时区走，
    /// 跨时区用户的"此刻"就会和卡上的时刻对不上。
    static func dayProgress(now: Date = Date()) -> CGFloat {
        let key = RedstoneClock.dayKey(now)
        guard let start = RedstoneClock.startOfDay(dayKey: key) else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return CGFloat(min(max(elapsed / 86_400, 0), 1))
    }
}
