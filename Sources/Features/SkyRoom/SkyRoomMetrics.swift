import CoreGraphics
import SwiftUI

/// 沉浸式天光页（`SkyRoomView`）的**唯一量纲来源**：固定地平线 / 滚动反馈 / 字号 / 卡片尺寸。
///
/// 为什么单独一个文件（与 `WidgetTheme` / `BriefMetrics` 同一个纪律）：
/// 这一页的每个数字都是"差 1pt 就破功"的量 —— 地平线差 2% 就不再像"抬头看天"、
/// 字号差 2pt 就压到地平线。把它们摆在一起才调得动。
///
/// **颜色一个都不在这里**：全部走 `Theme.sky(phase)` 的六个 token
/// （top / horizon / ground / edge / ink / inkDim）与 `Theme.glass*`。
///
/// ## 3.13.0 删掉了什么
///
/// 3.12.0 的三档吸附系统（`detents` / `dragOffset` / `settle` / `pull`）整块移除 ——
/// 用户反馈「想看温度只能往下滑，一把手拿开就返回了」正是 snap-back 反模式
/// （内容只在拖动期间可见）。调研（Apple 天气 / Pixel 天气 / 墨迹 / 彩云）的共性是
/// **标准纵向滚动 + 温度大字常驻首屏**，本文件现在只服务这一个结构：
/// 天空场景固定，内容在 `ScrollView` 里滚动，滚动进度只驱动「压暗 + 微放大」两个合成层属性。
enum SkyRoomMetrics {

    // MARK: - 页面布局

    enum Page {
        /// 地平线比例（弧顶占屏高）—— 3.11.0 起的初始档 0.58，被 3.13.0 固定为常量：
        /// 天空占 58%、地面占 42%，hero 区（温度大字）正好落在天幕里。
        static let horizon: CGFloat = 0.58

        /// hero 区高度（占屏高）。0.62 让卡片流从地平线略下方开始 ——
        /// 第一张卡片压在地面渐变上，读起来是"信息从大地里长出来"。
        static let heroHeightFraction: CGFloat = 0.62

        /// 窄档卡片流左右内缩
        static let compactInset: CGFloat = 20

        /// 宽档卡片流左右内缩
        static let wideInset: CGFloat = 32

        /// 宽档天空舞台 / 卡片列的最大宽度（iPad 横屏 1194 上封顶 880，
        /// 理由见 3.12.0：地平线弧拉满整屏会变成几乎水平的直线）。
        static let wideStageMaxWidth: CGFloat = 880

        /// 宽档字号倍率（与 `LayoutMetrics` 里 iPad 卡片的放大比例同族）
        static let wideFontScale: CGFloat = 1.18

        /// 卡片之间的纵向间距
        static let cardSpacing: CGFloat = 12

        /// 卡片流末尾的呼吸留白（Home Indicator 之上再多给一屏息）
        static let tailPadding: CGFloat = 28

        /// 固定顶栏在安全区之外再占的高度（hero 的内容从这行底下开始排）
        static let topbarReserve: CGFloat = 52

        /// 两侧暗角强度（只对宽档生效）。0.34 足够把视线收回舞台中心，
        /// 又不至于让边缘变成一条黑边。
        static let vignetteAlpha: Double = 0.34
    }

    // MARK: - 滚动反馈（只动 offset / scale / opacity）

    /// 滚动时背景的反馈量。全部是**常量目标值 + 进度插值**：
    /// 逐帧变化的只有 `scrollOffset` 的派生数，天幕 / 山脊 / 云的本体一个参数都不改
    /// —— 这是"滚动不卡"的前提（报告 §三：transform / opacity 走合成器线程）。
    enum Scroll {
        /// 归一化进度的行程（× 屏高）：滚过半屏，压暗到满值
        static let travel: CGFloat = 0.5

        /// 背景压暗的上限（叠一层 `sky.ground` 的黑色地面色）
        static let dimAlpha: Double = 0.45

        /// 顶栏切毛玻璃的滚动阈值（报告 §三：`scrollTop > 30`）
        static let topbarThreshold: CGFloat = 30

        /// hero 淡出的行程（报告 §三：`fade = y / 160`，160pt 走完）
        static let heroFadeTravel: CGFloat = 160

        /// hero 相对滚动的减速量：报告的绝对速度是 `-y * 0.55`，而 hero 本身
        /// 已经在 ScrollView 里以 1x 上移，所以再补 `+0.45y` 的向下偏移，净速度 0.55x
        static let heroLag: CGFloat = 0.45

        /// hero 缩小上限（报告 §三：`scale = 1 - fade * 0.3`）
        static let heroShrink: CGFloat = 0.30

        /// 视差钳制：滚过这个距离，背景就"停"——远处的山与太阳不能再往下沉了
        /// （HTML 版靠 `inset:-10%` 的天幕余量兜底，原生版用钳制更稳，不露底）
        static let parallaxClamp: CGFloat = 320

        /// 视差速率（报告 §三：太阳/天空 0.15、云取 0.10、星取 0.05）
        static let sunDepth: CGFloat = 0.15
        static let cloudDepth: CGFloat = 0.10
        static let starDepth: CGFloat = 0.05
    }

    // MARK: - 动态（克制：只走 offset / opacity）

    /// 太阳辉光呼吸周期 8s（设计铁律 §2 的下限就是 8s：再快就"看出来在动"了）
    static let breatheDuration: Double = 8
    /// 呼吸幅度：不透明度在 1.0 ↔ 0.92 之间，即 ±4%
    static let breatheFloor: Double = 0.92

    /// 云带漂移周期 40s、单程位移 6pt（设计铁律 §2：背景层 40s+）
    static let driftDuration: Double = 40
    static let driftDistance: CGFloat = 6

    /// 滚动提示 bob：周期 2s、幅度 4pt（报告 §三 的「上滑查看详情」呼吸）
    static let hintBobDuration: Double = 2
    static let hintBobDistance: CGFloat = 4

    // MARK: - 天空 / 地面几何

    /// 天幕网格（3.12.0，`MeshGradient`）。
    ///
    /// ## 为什么是 4×4 网格
    ///
    /// 线性渐变只有两个端点色，中间是**直线插值** —— 看上去永远是"一条平直的双色带"。
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
        /// 控制点横向位移幅度（相对画布宽度）。0.045 ≈ 393 屏上 18pt
        static let sway: Float = 0.045
        /// 控制点纵向位移幅度（相对画布高度）
        static let bob: Float = 0.035
        /// 第 2 行（中间偏上）上下浮动的基准位置
        static let midRow: Float = 0.46
        /// 天顶（第 1 行）的基准位置
        static let zenithRow: Float = 0.16

        // ── 四行的颜色权重（3.15.0 起全部改**实色混合**，不再用 opacity）──────────
        //
        // 三个数都是 `Color.blend(sky.top, 目标, 权重)` 的权重：
        //   0 = 完全是天顶色，1 = 完全是目标色。
        //
        // 为什么这么分：天空的亮度沿高度是非线性的 ——
        // 天顶到 40% 高度只掉一点点色，40%→地平线那一段才是暖色爆发区。
        // 均分四行会让"上半屏一片死平"，这也是 3.14.0 看起来像一块灰布的原因之一。

        /// 天顶行的压深权重（× `zenithDepth`，夜里更深、白天更浅）
        static let zenithMix: Double = 0.42
        /// 第二行往地平线暖色走多少
        static let row1Warmth: Double = 0.34
        /// 第三行往地平线暖色走多少（再往下就是纯暖色）
        static let row2Warmth: Double = 0.74
    }

    enum Ground {
        /// 地平线两端比弧顶低多少（占屏高）。0.07 ≈ 60pt @852：缓坡而不是圆边。
        static let sag: CGFloat = 0.07

        // ── 地面渐变（3.15.0：全部改实色混合）──────────────────────────────
        //
        // 3.14.0 是「horizon 55% 透明 → ground 实色」，两层叠在灰白天上，
        // 结果地平线以下是一大片暧昧的橙 —— 既不像大地，也不像天。
        // 现在是三段实色：地平线处的暖大地 → 中段的大地本色 → 底部再压深一档。

        /// 弧顶处混入大地的比例（0 = 纯天色，1 = 纯大地）。0.22 = 地平线上还留着夕阳的余温
        static let crestMix: Double = 0.22
        /// 过渡带结束的位置（相对地面自身高度）
        static let midStop: CGFloat = 0.30
        /// 过渡带末端混入大地的比例
        static let midMix: Double = 0.82
        /// 最底端再压深一档的比例（让卡片区有一个"安静的底"）
        static let bottomDarken: Double = 0.32

        /// 地平线亮边：雾化层（粗而淡）
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

    /// 地平线的"渐隐光带"
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
        /// 核心实心圆直径。20pt（3.15.0：16pt 在真机上只是一粒橙点，
        /// 太阳是这一页的主角之一，得看得出是"一个球"）
        static let coreDiameter: CGFloat = 20
        /// 内晕直径。贴着核心的亮边，把核心从天幕里"托"出来
        static let innerGlowDiameter: CGFloat = 110
        /// 内晕中心不透明度
        static let innerGlowAlpha: Double = 0.68
        /// 外晕直径（报告 §二：420px 光晕 → 折算到 pt 取 380）
        static let outerGlowDiameter: CGFloat = 380
        /// 外晕中心不透明度（0.42：实色天幕上再淡就只剩一个点，再浓会糊掉天色层次）
        static let outerGlowAlpha: Double = 0.42
        /// 核心外面那圈高光环线宽（内晕之上再压一圈，让核心"立"起来）
        static let ringWidth: CGFloat = 1.2
        /// 高光环的不透明度
        static let ringAlpha: Double = 0.55
    }

    /// 云：每朵由 3–4 个**模糊椭圆**叠加成不规则形状。
    /// `blur` 半径是**固定常量**（铁律：模糊是离屏渲染，逐帧变会掉帧）。
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

    /// 远山：三层山脊，每层用 `Path` 的 `quadCurve` 画起伏（正弦叠加 → 至少 4 个波峰），
    /// 峰高由**固定种子**决定（同一台设备每次进来看见的山完全一样）。
    enum Ridges {
        /// 山脚的**埋入深度**（相对屏高）：地平线之下再埋这么深，保证山体下缘被地面盖住。
        ///
        /// 3.14.0 的山是**悬空**的：远山矩形底落在 0.535H，而地面弧顶在 0.58H ——
        /// 中间那条 4.5% 的缝隙直接露出天空，真机上表现为"山脚下面还有一条橙色的天"。
        /// 现在三层山脚统一埋在 `horizon + buryDepth`，比地面最外端（0.65H）还低。
        static let buryDepth: CGFloat = 0.10

        /// 层数（远 / 中 / 近）。
        ///
        /// 峰顶三层分别落在 0.48H / 0.51H / 0.535H —— **远山最高、近山最低**，
        /// 这是视距造成的（远山能看到更高的山脊）。谷底都埋在地平线之下，
        /// 所以看不见"山的底边"。
        static let layers: [RidgeSpec] = [
            // 远山：宽、高、最淡（混入最多的天空色）
            RidgeSpec(crests: 2.6, widthRatio: 1.26, centerX: 0.50,
                      peakHeight: 0.20, haze: 0.58, density: 0.30,
                      parallaxDepth: 0.15, seed: 0x11_0001),
            // 中山：错开半个波长，峰顶比远山矮一档
            RidgeSpec(crests: 3.2, widthRatio: 1.12, centerX: 0.42,
                      peakHeight: 0.17, haze: 0.36, density: 0.55,
                      parallaxDepth: 0.25, seed: 0x22_0002),
            // 近山：最窄、最实、峰最低
            RidgeSpec(crests: 3.8, widthRatio: 0.98, centerX: 0.58,
                      peakHeight: 0.145, haze: 0.14, density: 0.85,
                      parallaxDepth: 0.40, seed: 0x33_0003)
        ]
        /// 曲线采样点数（72 段足够平滑，又不会在每帧重建时变贵）
        static let sampleCount: Int = 72
    }

    /// 一层山脊的形状参数
    struct RidgeSpec: Equatable {
        /// 主频（视野内大约几个波峰）
        let crests: Double
        /// 这一层宽度相对舞台宽的比例
        let widthRatio: CGFloat
        /// 水平中心（0…1 相对舞台宽）
        let centerX: CGFloat
        /// **峰高**（相对屏高）—— 山体矩形就是「峰顶到山脚」这一段，
        /// 渐变因此能精确铺满可见的山体（3.15.0 之前按 0.67H 的整块矩形铺，
        /// 可见部分只吃到渐变的尾巴，山全是黑的）
        let peakHeight: CGFloat
        /// 大气透视：混入天空色的比例（越远越大）
        let haze: Double
        /// 本体密度（不透明度）
        let density: Double
        /// 滚动视差深度（报告 §三：远 0.15 / 中 0.25 / 近 0.40 —— 越近沉得越快）
        let parallaxDepth: CGFloat
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
        /// 顶部"阶段名"12pt
        static let phaseSize: CGFloat = 12
        /// 顶部倒计时 12pt 等宽（秒在走，非等宽会左右跳）
        static let countdownSize: CGFloat = 12
        /// hero 底部日出日落 12pt 等宽
        static let sunTimeSize: CGFloat = 12
        /// hero 温度大字 104pt UltraLight rounded（3.14.0 按《iOS 端设计报告 v3 §二》定版：
        /// 104pt / 字重 200 —— 报告的视觉基准就是这么大，温度是这一页唯一的标题）
        static let heroTemperatureSize: CGFloat = 104
        /// hero 天气现象 22pt Medium（报告 §二）
        static let heroConditionSize: CGFloat = 22
        /// hero 高低温行 14pt（报告 §二：Regular，70% 白 → 走 `inkDim`）
        static let heroRangeSize: CGFloat = 14
        /// 滚动提示 11pt
        static let scrollHintSize: CGFloat = 11
        /// 卡片标题 13pt
        static let cardTitleSize: CGFloat = 13
        /// 卡片大数值 34pt rounded（风 / 云量；报告 §二「大数字 34pt SemiBold」）
        static let cardValueSize: CGFloat = 34
        /// 卡片数值单位 13pt
        static let cardUnitSize: CGFloat = 13
        /// 卡片细节行 12pt
        static let cardDetailSize: CGFloat = 12

        static func phase(_ scale: CGFloat) -> Font {
            return Font.system(size: phaseSize * scale, weight: .semibold)
        }

        static func countdown(_ scale: CGFloat) -> Font {
            return Font.system(size: countdownSize * scale, weight: .medium, design: .monospaced)
        }

        static func sunTime(_ scale: CGFloat) -> Font {
            return Font.system(size: sunTimeSize * scale, weight: .medium, design: .monospaced)
        }

        static func heroTemperature(_ scale: CGFloat) -> Font {
            return Font.system(size: heroTemperatureSize * scale, weight: .ultraLight, design: .rounded)
        }

        static func heroCondition(_ scale: CGFloat) -> Font {
            return Font.system(size: heroConditionSize * scale, weight: .medium)
        }

        static func heroRange(_ scale: CGFloat) -> Font {
            return Font.system(size: heroRangeSize * scale, weight: .medium)
        }

        static func scrollHint(_ scale: CGFloat) -> Font {
            return Font.system(size: scrollHintSize * scale, weight: .medium)
        }

        static func cardTitle(_ scale: CGFloat) -> Font {
            return Font.system(size: cardTitleSize * scale, weight: .semibold)
        }

        static func cardValue(_ scale: CGFloat) -> Font {
            return Font.system(size: cardValueSize * scale, weight: .semibold, design: .rounded)
        }

        static func cardUnit(_ scale: CGFloat) -> Font {
            return Font.system(size: cardUnitSize * scale, weight: .medium)
        }

        static func cardDetail(_ scale: CGFloat) -> Font {
            return Font.system(size: cardDetailSize * scale, weight: .medium)
        }
    }

    // MARK: - 一帧的几何结论

    /// 把「屏幕尺寸 + 是否宽档」折成几个派生数。
    ///
    /// 单独一个 struct 而不是在 `body` 里散着算：地面弧、hero、卡片列全都读同一组数，
    /// 只要有一个地方自己再算一遍宽度，层与层就会错位。
    struct Frame {

        /// 屏幕尺寸（含安全区外）
        let size: CGSize
        /// 是否宽档（iPad）
        let wide: Bool
        /// 地平线比例 0…1（弧顶，固定值 `Layout.horizon`）
        let horizon: CGFloat

        init(size: CGSize, wide: Bool) {
            self.size = size
            self.wide = wide
            self.horizon = SkyRoomMetrics.Page.horizon
        }

        var width: CGFloat { max(size.width, 1) }
        var height: CGFloat { max(size.height, 1) }

        /// 舞台宽度（宽档限宽居中，窄档满宽）
        var stageWidth: CGFloat {
            return wide ? min(width, SkyRoomMetrics.Page.wideStageMaxWidth) : width
        }

        /// 舞台列的横向起点（宽档时舞台居中，两侧留白）
        var stageOriginX: CGFloat {
            return (width - stageWidth) / 2
        }

        /// 字号倍率
        var fontScale: CGFloat {
            return wide ? SkyRoomMetrics.Page.wideFontScale : 1
        }

        /// hero 区高度
        var heroHeight: CGFloat {
            return height * SkyRoomMetrics.Page.heroHeightFraction
        }

        /// 地面弧的地平线两端高度
        var arcEdgeY: CGFloat {
            return horizon + SkyRoomMetrics.Ground.sag
        }

        /// 地平线下方那层暖色辉光占屏高的比例（= 20pt / 屏高，夹到 0.16）。
        ///
        /// 按 **20pt 的绝对高度**换算而不是写死比例：分屏时高度可能只有 400pt，
        /// 写死比例会让辉光在矮屏上突然变厚。
        var horizonGlowFraction: CGFloat {
            return min(0.16, SkyRoomMetrics.Horizon.glowHeight / height)
        }

        /// 卡片列宽度（舞台列再扣掉左右内缩）
        var cardColumnWidth: CGFloat {
            let inset = wide ? SkyRoomMetrics.Page.wideInset : SkyRoomMetrics.Page.compactInset
            return max(stageWidth - inset * 2, 0)
        }
    }
}
