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

        /// 两侧暗角强度（只对宽档生效）。0.34 足够把视线收回舞台中心，
        /// 又不至于让边缘变成一条黑边。
        static let vignetteAlpha: Double = 0.34
    }

    // MARK: - 滚动反馈（只动 offset / scale / opacity）

    /// 滚动时背景的三个反馈量。全部是**常量目标值 + 进度插值**：
    /// 逐帧变化的只有两个 `CGFloat` 状态（`scrollOffset` 的派生数），
    /// 天幕 / 山脊 / 云的本体一个参数都不改 —— 这是"滚动不卡"的前提。
    enum Scroll {
        /// 归一化进度的行程（× 屏高）：滚过半屏，压暗与放大都到满值
        static let travel: CGFloat = 0.5

        /// 背景压暗的上限（叠一层 `sky.ground` 的黑色地面色）
        static let dimAlpha: Double = 0.45

        /// 背景微放大的上限（1.0 → 1.07）：像把海报往眼前推一点，
        /// 只动 `scaleEffect`（合成层变换），不触发任何重绘。
        static let zoomScale: CGFloat = 0.07
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
        /// 地平线暖色带在天幕里的不透明度（贴着地平线那一行）
        static let horizonWarmth: Double = 0.92
        /// 中间行往地平线暖色过渡的比例（0.30 = 只染 30%，保住"天顶冷"）
        static let midWarmth: Double = 0.34
        /// 天顶那一行保留的天顶色不透明度（1.0 = 完全冷色，不掺暖）
        static let zenithAlpha: Double = 0.96
    }

    enum Ground {
        /// 地平线两端比弧顶低多少（占屏高）。0.07 ≈ 60pt @852：缓坡而不是圆边。
        static let sag: CGFloat = 0.07
        /// 地面渐变的最底端不透明度（留住一点天空的透，才像玻璃）
        static let bottomAlpha: Double = 0.90
        /// 地面渐变中段的位置：地平线以下先在**天色**里停一下，再压向深色。
        static let midStop: CGFloat = 0.42
        /// 地平线一带仍然是天空色的比例（从 1 落到 0 的那段起点）
        static let skyBleed: Double = 0.55
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
        /// 核心实心圆直径。12pt：手机屏上"一颗看得见的圆点"，
        /// 不是 14pt 那种"像一个按钮"，也不是 9pt 那种"像一颗星"。
        static let coreDiameter: CGFloat = 12
        /// 内晕直径（半径 20pt → 直径 40）。三层结构里的"第二层"
        static let innerGlowDiameter: CGFloat = 40
        /// 内晕中心不透明度
        static let innerGlowAlpha: Double = 0.55
        /// 外晕直径（半径 110pt → 直径 220）。这一层负责"整片天被照亮"的观感
        static let outerGlowDiameter: CGFloat = 220
        /// 外晕中心不透明度
        static let outerGlowAlpha: Double = 0.18
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
        /// 层间错位（pt）：三层加起来错开 16pt，山脊不会"叠成一条线"
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
        /// 顶部"阶段名"12pt
        static let phaseSize: CGFloat = 12
        /// 顶部倒计时 12pt 等宽（秒在走，非等宽会左右跳）
        static let countdownSize: CGFloat = 12
        /// hero 底部日出日落 12pt 等宽
        static let sunTimeSize: CGFloat = 12
        /// hero 温度大字 84pt rounded（3.13.0：从面板的 64 提到 84 ——
        /// 温度是这一页的标题，调研里所有主流天气 App 的首屏温度都远大于正文）
        static let heroTemperatureSize: CGFloat = 84
        /// hero 天气现象 20pt
        static let heroConditionSize: CGFloat = 20
        /// hero 高低温行 15pt
        static let heroRangeSize: CGFloat = 15
        /// 滚动提示 11pt
        static let scrollHintSize: CGFloat = 11
        /// 卡片标题 13pt
        static let cardTitleSize: CGFloat = 13
        /// 卡片大数值 32pt rounded（风 / 云量）
        static let cardValueSize: CGFloat = 32
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
            return Font.system(size: heroTemperatureSize * scale, weight: .bold, design: .rounded)
        }

        static func heroCondition(_ scale: CGFloat) -> Font {
            return Font.system(size: heroConditionSize * scale, weight: .semibold)
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
