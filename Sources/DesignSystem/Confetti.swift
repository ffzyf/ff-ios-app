import SwiftUI

// MARK: - 一次性彩带

/// 彩带爆开（**零依赖**：`Canvas` 手写 200 行，不引任何 SPM 包）。
///
/// ## 为什么不引一个现成的库
/// 市面上那类 Confetti 库的代码量都在 300–600 行，带一套自己的颜色/形状配置，
/// 而且为了"支持各种缓动"通常要挂 `CADisplayLink` 或每帧写 `@State`。
/// 本工程只用它放**一次**（问卷交卷），收益是"交卷那一瞬间的爽感"，
/// 代价却是一个第三方依赖进编译链 —— 不划算。手写反而更短：
/// 位置用解析解直接算，不需要状态机、不需要积分器、不需要依赖。
///
/// ## 三条实现约束（都是"不写就一定会被踩"的坑）
/// 1. **位置必须由「经过时间」解析求得，不能逐帧累加**：120Hz 的 ProMotion 上
///    每帧累加会跑得比 60Hz 快一倍，同一个动效在两台机器上是两个东西。
///    这里给的是带线性空气阻力的**闭式解**，同一时刻永远同一个坐标。
/// 2. **随机数只在开火时生成一次**，存进粒子结构。如果在 `Canvas` 闭包里现取，
///    每帧重新随机 = 满屏闪烁的噪点，不是彩带。
/// 3. **旋转不走 `drawLayer`**：72 个离屏图层/帧在 iPhone 上是实打实的开销，
///    直接把旋转矩阵并进 `Path`（`applying(_:)`）是一次纯路径变换，没有合成。
///
/// ## 触发方式
/// `trigger` 传一个**计数器**而不是 Bool：值不变就不重放（同一次成功不会被布局反复触发），
/// 连点两次能放两波。调用点只需在成功那一刻 `ticket += 1`。
///
/// ```swift
/// .overlay { ConfettiBurst(trigger: ticket).ignoresSafeArea() }
/// ```
///
/// ## 无障碍
/// 减弱动态效果开启时**一粒都不放**。设计规范 §9 要求"降级为淡入淡出"，
/// 但彩带的全部内容就是轨迹本身，没有可降级的静态形态；
/// 而它所庆祝的完成态本身已经有 `Motion.glassIn` 的淡入，不存在信息缺失。
struct ConfettiBurst: View {

    /// 每变一次放一波（值相同不重放）。
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 当前这一波（nil = 没在放）。持有它而不是只存一个开始时间，
    /// 是因为粒子的初值也只能在开火时算一次（见约束 2）。
    @State private var burst: Burst?
    /// 到点收尾的定时任务。放完必须停：`TimelineView` 一旦 unpause 就会一直按帧回调。
    @State private var stopTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: Burst.frameInterval, paused: burst == nil)) { timeline in
                Canvas { context, canvas in
                    guard let burst = burst else { return }
                    let elapsed = timeline.date.timeIntervalSince(burst.start)
                    // 超出寿命就什么都不画（时间轴的收尾由 stopTask 负责，这里只兜底）
                    guard elapsed >= 0, elapsed < Burst.lifetime else { return }
                    for particle in burst.particles {
                        particle.draw(in: &context, elapsed: elapsed, canvas: canvas)
                    }
                }
            }
            .onChange(of: trigger) { _, _ in
                fire(in: proxy.size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onDisappear {
            stopTask?.cancel()
            burst = nil
        }
    }

    // MARK: - 开火

    private func fire(in canvas: CGSize) {
        // 前庭安全：直接不放（理由见文件头「无障碍」）
        guard !reduceMotion else { return }
        // 还没拿到真实尺寸时不开火：粒子初值按画布算，用 0 尺寸算出来会全部挤在左上角
        guard canvas.width > 1, canvas.height > 1 else { return }

        stopTask?.cancel()
        burst = Burst.spawn(in: canvas)

        stopTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(Burst.lifetime * 1000) + 120))
            guard !Task.isCancelled else { return }
            burst = nil
        }
    }
}

// MARK: - 一波

/// 一次爆开的全部粒子 + 起始时刻。开火后是**只读**的。
private struct Burst {

    /// 总寿命（秒）。1.9 ≈ 抛物线升到顶、落回屏底、正好淡完；
    /// 再长就变成"还在飘的垃圾"，再短就看不清轨迹。
    static let lifetime: Double = 1.9
    /// 回调间隔。帧率由 ProMotion 决定，这里只给下限：位置是解析解，不依赖帧率。
    static let frameInterval: Double = 1.0 / 60.0

    /// 重力（pt/s²）
    static let gravity: Double = 1_100
    /// 空气阻力系数（1/s）。水平方向纯靠它收住，否则粒子会一路飞出屏幕。
    static let drag: Double = 2.0

    let start: Date
    let particles: [Particle]

    static func spawn(in canvas: CGSize) -> Burst {
        // 密度跟画布面积走：同一套常量在 iPad 上会显得稀稀拉拉
        let count = min(120, max(56, Int(canvas.width * canvas.height / 6_000)))
        // 爆心在偏上的中间：完成卡就在这个高度附近，彩带从"勾"后面往上炸开
        let origin = CGPoint(x: canvas.width / 2, y: min(canvas.height * 0.30, 300))

        let particles = (0..<count).map { _ in Particle.make(from: origin) }
        return Burst(start: Date(), particles: particles)
    }
}

// MARK: - 粒子

private struct Particle {

    /// 形状与尺寸（点）。宽度/厚度在 4–9pt 之间：再大就变成纸片，再小看不见。
    ///
    /// 名字叫 `Piece` 而不是 `Shape`：本文件在 DesignSystem 目录下，
    /// 一个内部类型盖住 `SwiftUI.Shape` 只会让后来的人多查一次定义。
    enum Piece {
        case chip(width: CGFloat, height: CGFloat)
        case dot(diameter: CGFloat)
    }

    /// 预渲染好的路径（形状以原点为中心）：绘制时整体套旋转 + 平移矩阵
    let path: Path
    let color: Color

    /// 爆心（画布坐标）
    let origin: CGPoint
    /// 初速度（pt/s）
    let velocity: CGVector
    /// 自旋角速度（rad/s）
    let spin: Double
    /// 初始角度（rad）
    let angle0: Double
    /// 左右摆动：相位 / 幅度 / 角频率。没有它，粒子是一条条死板的直线。
    let swayPhase: Double
    let swayAmplitude: Double
    let swayFrequency: Double

    // MARK: 生成

    static func make(from origin: CGPoint) -> Particle {
        // 向上扇形：20°–160°（0° 朝右、90° 朝正上），初速 420–980 pt/s
        let angle = Double.random(in: (20 * Double.pi / 180)...(160 * Double.pi / 180))
        let speed = Double.random(in: 420...980)

        let isDot = Int.random(in: 0..<10) < 3
        let piece: Piece = isDot
            ? .dot(diameter: CGFloat.random(in: 3.5...5.5))
            : .chip(width: CGFloat.random(in: 4...6), height: CGFloat.random(in: 7...10))

        return Particle(
            path: path(for: piece),
            color: color(),
            // 出射点加一点抖动：全部从同一个像素点冒出来，头 100ms 会像一颗"圆点"而不是一团
            origin: CGPoint(x: origin.x + CGFloat.random(in: -6...6),
                            y: origin.y + CGFloat.random(in: -4...4)),
            // 显式转 CGFloat：`CGVector` 的初参是 CGFloat，混着传 Double 在无编译器的地方
            // 只能靠 CI 试错（SE-0307 的隐式转换别指望在所有上下文都生效）
            velocity: CGVector(dx: CGFloat(cos(angle) * speed), dy: CGFloat(-sin(angle) * speed)),
            spin: Double.random(in: 2.5...9) * (Bool.random() ? 1 : -1),
            angle0: Double.random(in: 0...(2 * Double.pi)),
            swayPhase: Double.random(in: 0...(2 * Double.pi)),
            swayAmplitude: Double.random(in: 4...14),
            swayFrequency: Double.random(in: 2...5)
        )
    }

    private static func path(for piece: Piece) -> Path {
        switch piece {
        case .chip(let width, let height):
            let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            return Path(roundedRect: rect, cornerRadius: height * 0.28)
        case .dot(let diameter):
            let rect = CGRect(x: -diameter / 2, y: -diameter / 2,
                              width: diameter, height: diameter)
            return Path(ellipseIn: rect)
        }
    }

    /// 颜色**跟当前色板走**：换到暮紫/暖砂/海蓝，彩带自动换色。
    /// 硬编码一个绿，等于把"换肤"这件事在彩带上破了例。
    private static func color() -> Color {
        // 权重：品牌面为主，亮色次之，深色点缀，少量近白高光碎片
        switch Int.random(in: 0..<8) {
        case 0: return Theme.textPrimary
        case 1, 2: return Theme.limeBright
        case 3, 4, 5: return Theme.lime
        default: return Theme.limeDeep
        }
    }

    // MARK: 绘制

    /// 画某一帧。`elapsed` 是从开火算起的秒数。
    func draw(in context: inout GraphicsContext, elapsed: Double, canvas: CGSize) {
        // 全程 Double 算、最后一步才回 CGFloat：混着写会踩 CGFloat/Double 隐式转换的坑，
        // 而在无编译器的地方这种错要拿一轮 CI（8 分钟）才发现。
        let originX = Double(origin.x)
        let originY = Double(origin.y)
        let velocityX = Double(velocity.dx)
        let velocityY = Double(velocity.dy)

        // 带线性空气阻力的解析解：a = g - k·v  ⇒  位置是 t 的闭式函数
        //（不是逐帧积分：见文件头约束 1，120Hz 上会跑快一倍）
        let terminal = Burst.gravity / Burst.drag
        let decay = (1 - exp(-Burst.drag * elapsed)) / Burst.drag

        // 摆动：起手 0.35s 内线性长大，避免粒子出生瞬间就横跳
        let swayGrowth = min(1, elapsed / 0.35)
        let sway = sin(elapsed * swayFrequency + swayPhase) * swayAmplitude * swayGrowth

        let x = originX + velocityX * decay + sway
        let y = originY + terminal * elapsed + (velocityY - terminal) * decay

        // 出屏就别画了（落到底部之后还有大半秒寿命，白白吃绘制）
        guard y < Double(canvas.height) + 60,
              x > -60,
              x < Double(canvas.width) + 60 else { return }

        // 透明度：前 58% 实心，之后线性淡出到 0。
        // 只淡出、不淡入 —— 从 0 淡进来会显得"不够干脆"，爆开就该是硬的。
        let fadeStart = Burst.lifetime * 0.58
        let opacity = min(1, max(0, (Burst.lifetime - elapsed) / (Burst.lifetime - fadeStart)))
        guard opacity > 0.01 else { return }

        // 旋转 + 平移一次性并进路径：不做离屏图层（约束 3）
        let transform = CGAffineTransform(rotationAngle: CGFloat(angle0 + spin * elapsed))
            .concatenating(CGAffineTransform(translationX: CGFloat(x), y: CGFloat(y)))
        let framePath = path.applying(transform)

        let shading: GraphicsContext.Shading = opacity >= 0.999
            ? .color(color)
            : .color(color.opacity(opacity))
        context.fill(framePath, with: shading)
    }
}
