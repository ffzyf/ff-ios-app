import CoreGraphics
import SwiftUI

/// 沉浸式天光页（`SkyRoomView`）的**唯一量纲来源**：地平线档位 / 视差系数 / 字号 / 面板尺寸。
///
/// 为什么单独一个文件（与 `WidgetTheme` / `BriefMetrics` 同一个纪律）：
/// 这一页的每个数字都是"差 1pt 就破功"的量 —— 地平线档位差 2% 就不再像"抬头看天"、
/// 视差系数差 0.1 层与层就会互相穿插、字号差 2pt 就压到地平线。把它们摆在一起才调得动。
///
/// **颜色一个都不在这里**：全部走 `Theme.sky(phase)` 的六个 token
/// （top / horizon / ground / edge / ink / inkDim）与 `Theme.glass*`。
enum SkyRoomMetrics {

    // MARK: - 地平线（上滑三档 / 下滑关闭）

    /// 地平线位置的三个吸附档位，单位是**占屏幕高度的比例**（0 = 屏幕顶，1 = 屏幕底）。
    ///
    /// 推导：
    /// - **0.58（初始）**：地下 42% 高。这一档要同时放得下"地面 + 底部一行日出日落 + 呼吸余量"，
    ///   42% 在 852pt 的 iPhone 上约 358pt，扣掉一行 12pt 文字仍显得空 —— 空得正好，
    ///   因为天空是主角；而地平线一旦到 0.66（= 桌面小组件的 0.62~0.74 区间）地面就太厚了。
    /// - **0.38**：上滑一档，天空从 58% 涨到 62%… 这里量的是**地平线**：58 → 38 意味着天空占 62%。
    ///   这一档是"抬头"：能看出天在变高，但地面仍在地平线以下一整块。
    /// - **0.22**：极限档，天空占 78%，地面只剩屏幕底的一条边 —— 视觉上接近"躺下看天"。
    ///   三档间距 0.20 / 0.16 是**递减**的：越往上越难推，符合"再抬一点就到顶"的物理直觉。
    static let detents: [CGFloat] = [0.58, 0.38, 0.22]

    /// 初始档（= 用户第一次进来看到的那个高度）
    static let restStage: Int = 0

    /// 下拉时的最大比例（0.58 + 8% ≈ 68pt @852）：越过它就不再下压，改为继续蓄力关闭页面。
    static let maxPullFraction: CGFloat = 0.66

    /// 达到这个比例（0.58 + 5.5% ≈ 47pt @852）松手就关闭。
    ///
    /// 为什么比系统"下拉关闭"的 ~60pt 短：地平线本身已经在 58%，用户拉到这里时整块天空
    /// 已经明显下压，"再拉就关"必须早一点给反馈，否则会觉得"拉了没反应"。
    static let closeFraction: CGFloat = 0.635

    /// 惯量余量：快速一甩即使实拖没到阈值，`predictedEndTranslation` 超过它也算关闭。
    static let flickMargin: CGFloat = 0.04

    /// 吸附动画。响应 0.46s / 阻尼 0.82：与 `Motion.tab` 同一族手感，
    /// 但略慢一点 —— 这一页动的是整片天空，比"切一个 Tab"需要多一点时间落地。
    static let snapAnimation = Animation.spring(response: 0.46, dampingFraction: 0.82)

    /// 拖动的最小识别距离：太小会把"点按关闭按钮"误判成拖拽
    static let dragMinimum: CGFloat = 6

    // MARK: - 舞台（iPad 宽档限宽）

    /// 宽档天空舞台的最大宽度。
    ///
    /// 为什么封顶 880：iPad 横屏画布 1194，若让地平线弧拉满整屏，那条弧会变成一条
    /// 几乎水平的直线（弧的弯度 ∝ 宽高比），"抬头看天"的意象就散了。720–880 是
    /// 弧还读得出弯度的上限；这里取 880 让宽档的天空尽量大。
    static let wideStageMaxWidth: CGFloat = 880

    /// 宽档字号倍率。0.58 的地平线在 1194×834 上离眼睛更远，
    /// 1.0 倍的字会显得"卡在角落"，1.18 与 `LayoutMetrics` 里 iPad 卡片的放大比例同族。
    static let wideFontScale: CGFloat = 1.18

    /// 宽档天气面板宽度（悬浮在右下）。360 是"温度大字 + 三行细节"仍能一行读完的宽度。
    static let widePanelWidth: CGFloat = 360

    /// 窄档面板左右内缩
    static let compactPanelInset: CGFloat = 20

    /// 两侧暗角强度（只对宽档生效）。0.34 足够把视线收回舞台中心，
    /// 又不至于让边缘变成一条黑边。
    static let vignetteAlpha: Double = 0.34

    // MARK: - 视差（上滑时各层位移系数，× lift）
    //
    // 3.12.0 重排（用户原话："一塌糊涂，至少要不卡、流畅、好看、简约"）：
    // 旧的四层是 1.0 / 0.55 / 0.38 / 0.18，层次够但**最远那层几乎不动**，
    // 上滑时读起来像"整块天空贴在屏幕上"。现在按物理距离排成四档
    // **天空 0.20 / 云 0.50 / 山 0.75 / 地面 1.00**（任务书给的系数），
    // 太阳与地面同档（它贴着地平线落下去），星点跟天空同档（它们在最远的天球上）。
    //
    // 数字越大 = 动得越多 = 看起来越**近**。地面没有系数、也不该有：
    // 它的顶边就是地平线（`HorizonGround(crestY: frame.horizon)`），**天然与地平线 1:1**
    // —— 也就是任务书里的 1.0。给它再乘一个 offset 会变成 2 倍速，
    // 上滑时地面会比地平线快一倍，两者之间裂开一条缝（`SkyRoomView.ground` 的注释写了这件事）。
    enum Parallax {
        /// 天幕（含天顶冷色与地平线暖色）：只动 20%，是"最远的那层"
        static let sky: CGFloat = 0.20
        /// 星点：挂在天球上，与天幕同速
        static let star: CGFloat = 0.20
        /// 云：中景，比山远
        static let cloud: CGFloat = 0.50
        /// 远山：近景，只比地面慢一档
        static let mountain: CGFloat = 0.75
        /// 太阳：贴着地平线落下，与地平线同速
        static let sun: CGFloat = 1.0
    }

    // MARK: - 动态（克制：只走 offset / opacity）

    /// 太阳辉光呼吸周期 8s（设计铁律 §2 的下限就是 8s：再快就"看出来在动"了）
    static let breatheDuration: Double = 8
    /// 呼吸幅度：不透明度在 1.0 ↔ 0.92 之间，即 ±4%
    static let breatheFloor: Double = 0.92

    /// 云带漂移周期 40s、单程位移 6pt（设计铁律 §2：背景层 40s+）
    static let driftDuration: Double = 40
    static let driftDistance: CGFloat = 6

    // MARK: - 天空 / 地面几何

    /// 天幕网格（3.12.0，`MeshGradient`）。
    ///
    /// ## 为什么从"一条线性渐变"换成 4×4 网格
    ///
    /// 线性渐变只有两个端点色，中间是**直线插值** —— 不管换多少档天色，
    /// 看上去永远是"一条平直的双色带"（用户截图里的天空正是这个问题）。
    /// 真实天空是**大气散射**：天顶冷、地平线暖、太阳附近最亮，亮度沿高度是非线性的。
    /// `MeshGradient` 的 16 个控制点正好能表达这件事，而且是 GPU 一次画完（不卡）。
    ///
    /// ## 哪些点会动
    ///
    /// 16 个点里 **12 个**（第 1–3 行）随「太阳高度角 + 太阳横坐标」位移：
    /// 太阳越接近地平线，中间两行越往太阳那一侧收（暖色团跟着太阳走）；
    /// 四个角固定 —— 角点一旦动，整块网就会"扭"，观感从"天在呼吸"变成"布在抖"。
    enum SkyDome {
        /// 网格列数（4 列 × 4 行 = 16 个控制点）
        static let columns: Int = 4
        /// 网格行数
        static let rows: Int = 4
        /// 控制点横向位移幅度（相对画布宽度）。0.045 ≈ 393 屏上 18pt：
        /// 再大就能看出"网格在挪"，再小等于没有。
        static let sway: Float = 0.045
        /// 控制点纵向位移幅度（相对画布高度）
        static let bob: Float = 0.035
        /// 第 2 行（中间偏上）上下浮动的基准位置
        static let midRow: Float = 0.46
        /// 天顶（第 1 行）的基准位置
        static let zenithRow: Float = 0.16
        /// 地平线暖色带在天幕里的不透明度（贴着地平线那一行）
        static let horizonWarmth: Double = 0.92
        /// 中间行往地平线暖色过渡的比例（0.30 = 只染 30%，保住"天顶冷"）
        static let midWarmth: Double = 0.34
        /// 天顶那一行保留的天顶色不透明度（1.0 = 完全冷色，不掺暖）
        static let zenithAlpha: Double = 0.96
    }

    enum Sky {
        /// 上滑时的"提亮一档"：在天幕之上叠一层 `sky.horizon`，不透明度随 expand 从 0 到 0.16。
        ///
        /// **为什么不是改渐变颜色**：设计铁律要求"只改 offset/scale/opacity，不逐帧改色"。
        /// 叠一层固定色的半透明面，颜色是常量、只有不透明度在动 —— 观感等价于"天亮了"，
        /// 但每次重绘都不需要重新插值整块渐变（`MeshGradient` 更贵，这条纪律更重要了）。
        static let liftAlpha: Double = 0.16
    }

    enum Ground {
        /// 地平线两端比弧顶低多少（占屏高）。0.07 ≈ 60pt @852：缓坡而不是圆边。
        /// 卡片上这组数是 `HorizonSky`（弧顶 0.62 / 两端 0.74，落差 0.12），
        /// 这一页故意取 0.07（更平）—— 屏宽远大于卡宽，同样的落差会显得"翘得夸张"。
        static let sag: CGFloat = 0.07
        /// 地面渐变的最底端不透明度（留住一点天空的透，才像玻璃）
        static let bottomAlpha: Double = 0.90
        /// 地面渐变中段的位置（3.12.0）：地平线以下先在**天色**里停一下，再压向深色。
        /// 0.42 是"一眼看不出分界、但确实有渐变"的位置 —— 一刀切正是用户说的"断面生硬"。
        static let midStop: CGFloat = 0.42
        /// 地平线一带仍然是天空色的比例（从 1 落到 0 的那段起点）
        static let skyBleed: Double = 0.55
        /// 地平线亮边：雾化层（粗而淡）。光带本体的线宽 / 不透明度在 `Horizon` 里
        ///（3.12.0：原来这里还有 `edgeWidth` / `edgeCoreAlpha` 两个"实线层"参数，
        /// 现在实线层就是那条渐隐光带，参数统一收进 `Horizon`，不留两份）
        static let edgeHazeWidth: CGFloat = 3.6
        static let edgeHazeAlpha: Double = 0.30
        /// 夜里那条"极细的冷光"
        static let nightEdgeWidth: CGFloat = 1.0
        static let nightEdgeAlpha: Double = 0.55
        /// 竖向纹理的等距（pt）。26 ≈ 一屏 15 条：再密就成网，再疏就成装饰线。
        static let textureSpacing: CGFloat = 26
        /// 竖向纹理的不透明度（0.02 —— 只在截图对比里看得见，这才是"质感"而不是"线条"）
        static let textureAlpha: Double = 0.02
        /// 纹理向上收窄的比例（模拟草地上窄下宽的透视）
        static let textureSlant: CGFloat = 0.05
    }

    /// 地平线的"渐隐光带"（3.12.0 重做：旧版是一条纯白细线 + 一整块深色地面，断面生硬）
    enum Horizon {
        /// 光带厚度（pt）：2.5 是"读得出是一道光、又不是一条线"的厚度
        static let bandWidth: CGFloat = 2.5
        /// 光带本体（实线层）的不透明度
        static let bandAlpha: Double = 0.95
        /// 光带两端渐隐到的不透明度（横向 1 → 0，让地平线"消失在画面外"而不是断在屏幕边）
        static let bandFadeAlpha: Double = 0.0
        /// 地平线下方暖色辉光的高度（pt）
        static let glowHeight: CGFloat = 20
        /// 暖色辉光的不透明度
        static let glowAlpha: Double = 0.42
    }

    enum Sun {
        /// 核心实心圆直径（基准，随 expand 放大）。12pt：手机屏上"一颗看得见的圆点"，
        /// 不是 14pt 那种"像一个按钮"，也不是 9pt 那种"像一颗星"。
        static let coreDiameter: CGFloat = 12
        /// 内晕直径（半径 20pt → 直径 40）。三层结构里的"第二层"
        static let innerGlowDiameter: CGFloat = 40
        /// 内晕中心不透明度（任务书 0.55）
        static let innerGlowAlpha: Double = 0.55
        /// 外晕直径（半径 110pt → 直径 220）。这一层负责"整片天被照亮"的观感
        static let outerGlowDiameter: CGFloat = 220
        /// 外晕中心不透明度（任务书 0.18）
        static let outerGlowAlpha: Double = 0.18
        /// 上滑到顶时，三层一起放大的比例（1 + 0.45 = 1.45 倍）
        static let grow: CGFloat = 0.45
        /// 核心外面那圈高光环线宽（内晕之上再压一圈，让核心"立"起来）
        static let ringWidth: CGFloat = 1.2
        /// 高光环的不透明度
        static let ringAlpha: Double = 0.55
    }

    /// 云（3.12.0 重做：旧版是两条圆角胶囊，形状假）
    ///
    /// 每朵云由 3–4 个**模糊椭圆**叠加成不规则形状：椭圆各自有不同的宽高比与不透明度，
    /// 叠起来之后边缘互相吃掉，读起来才是一团云而不是几个胶囊。
    /// `blur` 半径是**固定常量**（铁律：模糊是离屏渲染，逐帧变会掉帧）——
    /// 这一页的模糊只在进场时算一次，之后所有动画只动 `offset` / `opacity`。
    enum Clouds {
        /// 每朵云 3–4 团椭圆
        static let minBlobs: Int = 3
        static let maxBlobs: Int = 4
        /// 固定模糊半径（pt）。18 是"边缘化开但不糊成一团"的值
        static let blur: CGFloat = 18
        /// 单团椭圆的不透明度上限（叠 3–4 团之后整朵云的峰值 ≈ `CloudSpec.alpha`）
        static let blobAlpha: Double = 0.55
        /// 云列表：`centerX` / `centerY` 是相对舞台宽 / 屏高的位置，`width` 相对舞台宽。
        /// 前两朵是远云（窄、淡、慢），后三朵是中近景 —— 远小近大是距离感的全部来源。
        static let specs: [CloudSpec] = [
            CloudSpec(centerX: 0.18, centerY: 0.17, width: 0.30, alpha: 0.10, drift: 0.35, seed: 0x5EED_0101),
            CloudSpec(centerX: 0.72, centerY: 0.24, width: 0.36, alpha: 0.12, drift: 0.45, seed: 0x5EED_0202),
            CloudSpec(centerX: 0.46, centerY: 0.34, width: 0.52, alpha: 0.16, drift: 0.75, seed: 0x5EED_0303),
            CloudSpec(centerX: 0.86, centerY: 0.42, width: 0.44, alpha: 0.14, drift: 0.85, seed: 0x5EED_0404),
            CloudSpec(centerX: 0.24, centerY: 0.47, width: 0.48, alpha: 0.18, drift: 1.0, seed: 0x5EED_0505)
        ]
    }

    /// 一朵云的形状参数（位置 / 大小 / 不透明度 / 漂移 / 随机种子）
    struct CloudSpec: Equatable {
        /// 云心横向位置（0…1，相对舞台宽）
        let centerX: CGFloat
        /// 云心纵向位置（0…1，相对屏高）
        let centerY: CGFloat
        /// 云宽（相对舞台宽）；云高由 `Clouds.aspect` 推
        let width: CGFloat
        /// 整朵云的不透明度（远云更淡）
        let alpha: Double
        /// 漂移距离系数（× `driftDistance`）：远云漂得慢
        let drift: CGFloat
        /// 固定种子：同一朵云每次进场都长一样（绝不用 `random`）
        let seed: UInt32
    }

    /// 云团椭圆的宽高比（宽 / 高）。云是横向拉长的 —— 1:1 的圆读起来像烟不像云。
    static let cloudAspect: CGFloat = 3.4

    /// 远山（3.12.0 重做：旧版是两个硬边三角形，像几何拼贴）
    ///
    /// 三层山脊，每层用 `Path` 的 `quadCurve` 画起伏（正弦叠加 → 至少 4 个波峰），
    /// 峰高由**固定种子**决定（同一台设备每次进来看见的山完全一样）。
    /// 颜色 = 天空色按距离混入地面色（越远越淡越蓝）—— 这就是大气透视。
    enum Ridges {
        /// 层数（远 / 中 / 近）
        static let layers: [RidgeSpec] = [
            // 远山：宽、扁、最淡（混入最多的天空色）
            RidgeSpec(crests: 4.0, amplitude: 0.55, widthRatio: 1.24,
                      centerX: 0.50, heightRatio: 0.10, rise: 0.045,
                      haze: 0.62, density: 0.34, seed: 0x11_0001),
            // 中山：错开半个波长，峰顶比远山高一点
            RidgeSpec(crests: 5.0, amplitude: 0.62, widthRatio: 1.10,
                      centerX: 0.42, heightRatio: 0.085, rise: 0.028,
                      haze: 0.40, density: 0.58, seed: 0x22_0002),
            // 近山：最窄的最高、最实
            RidgeSpec(crests: 6.5, amplitude: 0.50, widthRatio: 0.96,
                      centerX: 0.58, heightRatio: 0.065, rise: 0.012,
                      haze: 0.18, density: 0.82, seed: 0x33_0003)
        ]
        /// 曲线采样点数（72 段足够平滑，又不会在每帧重建时变贵）
        static let sampleCount: Int = 72
        /// 层间错位（pt）：任务书要求 6–10pt，取 8 —— 三层加起来错开 16pt，
        /// 山脊不会"叠成一条线"
        static let layerOffset: CGFloat = 8
    }

    /// 一层山脊的形状参数
    struct RidgeSpec: Equatable {
        /// 主频（视野内大约几个波峰）
        let crests: Double
        /// 高差（相对自身高度）
        let amplitude: CGFloat
        /// 这一层宽度相对舞台宽的比例
        let widthRatio: CGFloat
        /// 水平中心（0…1 相对舞台宽）
        let centerX: CGFloat
        /// 层高（相对屏高）
        let heightRatio: CGFloat
        /// 相对地平线基线往上抬多少（相对屏高）
        let rise: CGFloat
        /// 大气透视：混入天空色的比例（越远越大）
        let haze: Double
        /// 本体密度（不透明度）
        let density: Double
        /// 固定种子
        let seed: UInt32
    }

    enum Stars {
        /// 星点数量上限（多了像噪点）
        static let count: Int = 18
        /// 单颗直径
        static let diameter: CGFloat = 1.6
        /// 基础不透明度（夜里满亮，晨昏压暗）
        static let baseAlpha: Double = 0.75
    }

    // MARK: - 字号

    enum TextStyle {
        /// 顶部"阶段名"12pt（比系统 caption 大 1pt：这一行是唯一的状态说明）
        static let phaseSize: CGFloat = 12
        /// 顶部倒计时 12pt 等宽（秒在走，非等宽会左右跳）
        static let countdownSize: CGFloat = 12
        /// 底部日出日落 12pt 等宽
        static let sunTimeSize: CGFloat = 12
        /// 天气面板温度大字 64pt rounded（面板里唯一的"读数"）
        static let temperatureSize: CGFloat = 64
        /// 天气现象 17pt
        static let weatherSize: CGFloat = 17
        /// 面板细节行 12pt
        static let detailSize: CGFloat = 12

        static func phase(_ scale: CGFloat) -> Font {
            return Font.system(size: phaseSize * scale, weight: .semibold)
        }

        static func countdown(_ scale: CGFloat) -> Font {
            return Font.system(size: countdownSize * scale, weight: .medium, design: .monospaced)
        }

        static func sunTime(_ scale: CGFloat) -> Font {
            return Font.system(size: sunTimeSize * scale, weight: .medium, design: .monospaced)
        }

        static func temperature(_ scale: CGFloat) -> Font {
            return Font.system(size: temperatureSize * scale, weight: .bold, design: .rounded)
        }

        static func weather(_ scale: CGFloat) -> Font {
            return Font.system(size: weatherSize * scale, weight: .semibold)
        }

        static func detail(_ scale: CGFloat) -> Font {
            return Font.system(size: detailSize * scale, weight: .medium)
        }
    }

    // MARK: - 一帧的几何结论

    /// 把「屏幕尺寸 + 当前档位 + 拖动位移」折成几个派生数。
    ///
    /// 单独一个 struct 而不是在 `body` 里散着算：视差、地面弧、面板位移全都读同一组数，
    /// 只要有一个地方自己再算一遍 `lift`，层与层就会错位（而错位只会表现为"看起来怪"）。
    struct Frame {

        /// 屏幕尺寸（含安全区外）
        let size: CGSize
        /// 是否宽档（iPad）
        let wide: Bool
        /// 地平线比例 0…1（弧顶）
        let horizon: CGFloat

        init(size: CGSize, wide: Bool, horizon: CGFloat) {
            self.size = size
            self.wide = wide
            self.horizon = horizon
        }

        var width: CGFloat { max(size.width, 1) }
        var height: CGFloat { max(size.height, 1) }

        /// 天空扩张的绝对位移（pt，向上为正）
        var lift: CGFloat {
            return (SkyRoomMetrics.detents[SkyRoomMetrics.restStage] - horizon) * height
        }

        /// 上滑进度 0…1（0 = 初始档，1 = 极限档）
        var expand: CGFloat {
            let span = (SkyRoomMetrics.detents[SkyRoomMetrics.restStage]
                        - SkyRoomMetrics.detents[SkyRoomMetrics.detents.count - 1]) * height
            guard span > 1 else { return 0 }
            return min(max(lift / span, 0), 1)
        }

        /// 下拉进度 0…1（0 = 初始档，1 = `maxPullFraction`）
        var pull: CGFloat {
            let span = SkyRoomMetrics.maxPullFraction - SkyRoomMetrics.detents[SkyRoomMetrics.restStage]
            guard span > 0 else { return 0 }
            return min(max((horizon - SkyRoomMetrics.detents[SkyRoomMetrics.restStage]) / span, 0), 1)
        }

        /// 舞台宽度（宽档限宽居中，窄档满宽）
        var stageWidth: CGFloat {
            return wide ? min(width, SkyRoomMetrics.wideStageMaxWidth) : width
        }

        /// 字号倍率
        var fontScale: CGFloat {
            return wide ? SkyRoomMetrics.wideFontScale : 1
        }

        /// 地面弧的地平线两端高度
        var arcEdgeY: CGFloat {
            return horizon + SkyRoomMetrics.Ground.sag
        }

        /// 地平线下方那层暖色辉光占屏高的比例（= 20pt / 屏高）。
        ///
        /// 为什么不在渐变里写死一个 0.05：852 屏上 20pt 是 0.023，iPad 横屏 834 上是 0.024，
        /// 而分屏时高度可能只有 400pt（20pt = 0.05）—— 写死比例会让辉光在矮屏上突然变厚。
        /// 这里恒定按 **20pt 的绝对高度**换算，夹到 0.16 防止极小窗口下整块地面都被染暖。
        var horizonGlowFraction: CGFloat {
            return min(0.16, SkyRoomMetrics.Horizon.glowHeight / height)
        }

        /// 天气面板宽度
        var panelWidth: CGFloat {
            return wide
                ? min(SkyRoomMetrics.widePanelWidth, width - SkyRoomMetrics.compactPanelInset * 2)
                : width - SkyRoomMetrics.compactPanelInset * 2
        }
    }

    // MARK: - 档位工具

    /// 从任意比例找最近的吸附档
    static func nearestStage(for fraction: CGFloat) -> Int {
        var best = restStage
        var bestDelta = CGFloat.greatestFiniteMagnitude
        for (index, value) in detents.enumerated() {
            let delta = abs(value - fraction)
            if delta < bestDelta {
                bestDelta = delta
                best = index
            }
        }
        return best
    }

    /// 把目标档位夹进合法下标（防御式：`stage` 只由内部写，但绝不让越界崩在这里）
    static func clampedStage(_ stage: Int) -> Int {
        return min(max(stage, 0), detents.count - 1)
    }

    /// 把任意地平线比例夹进**可显示区间**：下限是最极限那一档（0.22），上限是 `maxPullFraction`。
    ///
    /// 为什么要单独抽出来：渲染（`horizonFraction`）与松手结算（`settle`）必须用**同一套夹取**。
    /// 一旦两边各写一遍，松手时算出的"差值"就会和屏幕上真正画出的地平线对不上 ——
    /// 少了这层一致性，换档那一帧（以及残留位移动画的第一帧）又会跳一次。
    static func clampedFraction(_ fraction: CGFloat) -> CGFloat {
        let lowest = detents[detents.count - 1]
        return min(max(fraction, lowest), maxPullFraction)
    }
}
