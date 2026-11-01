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

    /// 每一层对 `lift`（天空扩张的绝对位移）的响应比例。
    ///
    /// 数字越大 = 动得越多 = 看起来越**近**。排序按"近大远小"：
    /// 太阳（1.0，贴在地平线上）> 远山（0.55）> 云带（0.38）> 星点（0.18，最远）。
    enum Parallax {
        static let sun: CGFloat = 1.0
        static let mountain: CGFloat = 0.55
        static let cloud: CGFloat = 0.38
        static let star: CGFloat = 0.18
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

    enum Sky {
        /// 上滑时的"提亮一档"：在天幕之上叠一层 `sky.horizon`，不透明度随 expand 从 0 到 0.16。
        ///
        /// **为什么不是改渐变颜色**：设计铁律要求"只改 offset/scale/opacity，不逐帧改色"。
        /// 叠一层固定色的半透明面，颜色是常量、只有不透明度在动 —— 观感等价于"天亮了"，
        /// 但每次重绘都不需要重新插值整块渐变。
        static let liftAlpha: Double = 0.16
    }

    enum Ground {
        /// 地平线两端比弧顶低多少（占屏高）。0.07 ≈ 60pt @852：缓坡而不是圆边。
        /// 卡片上这组数是 `HorizonSky`（弧顶 0.62 / 两端 0.74，落差 0.12），
        /// 这一页故意取 0.07（更平）—— 屏宽远大于卡宽，同样的落差会显得"翘得夸张"。
        static let sag: CGFloat = 0.07
        /// 地面渐变的最底端不透明度（留住一点天空的透，才像玻璃）
        static let bottomAlpha: Double = 0.90
        /// 地平线亮边：雾化层（粗而淡）+ 实线层，与桌面小组件同一套"无 blur"配方
        static let edgeWidth: CGFloat = 1.6
        static let edgeHazeWidth: CGFloat = 3.6
        static let edgeHazeAlpha: Double = 0.30
        static let edgeCoreAlpha: Double = 0.88
        /// 夜里那条"极细的冷光"
        static let nightEdgeWidth: CGFloat = 1.0
        static let nightEdgeAlpha: Double = 0.55
    }

    enum Sun {
        /// 辉光点本体直径（基准，随 expand 放大）
        static let coreDiameter: CGFloat = 14
        /// 光晕直径（基准）
        static let glowDiameter: CGFloat = 190
        /// 上滑到顶时，太阳本体与光晕一起放大的比例（1 + 0.45 = 1.45 倍）
        static let grow: CGFloat = 0.45
        /// 光晕中心不透明度
        static let glowAlpha: Double = 0.42
        /// 高光环线宽
        static let ringWidth: CGFloat = 1.5
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
