import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 颜色 token —— 一套名字，两套值（PRD §3.1 第 1 条）。
///
/// 三条不可动摇的规则：
/// 1. **深色值逐字沿用 V2**（`dyn(dark:)` 那一位），一个 hex 都没改 —— 这是「切回深色与 V2 逐像素一致」的保证；
/// 2. **浅色值逐字来自 PRD §3.2 表格**，代码里能用 grep 直接对回评审表，不做二次调色；
/// 3. **透明度只允许出现在本文件的 `dyn` / `dyna` 里**（PRD §3.4 第 1 条）。View 层要「更淡一点」时
///    只能写 `Theme.<token>.opacity(n)`（`opacity` 作用在已解析的动态色外层，不破坏随外观切换），
///    绝不允许再出现 `Color.white.opacity(n)` 这种"就地造色"。
///
/// 为什么用动态 `UIColor` 而不是 EnvironmentKey 注入：见设计文档 §1.1.1 的对照表 ——
/// 84 个文件的 `Theme.*` 调用点零改动、切换外观不重建视图树（滚动位置与分页数据都留住）、
/// Widget 扩展可以跨进程复用同一份 token。`UIColor(dynamicProvider:)` 的闭包在**每次解析 trait** 时执行，
/// 所以 `Color(uiColor:)` 包一层之后依然是动态的。
enum Theme {

    // MARK: - 背景三层（同一条规则：越靠前越亮，浅色下越靠前越白）

    /// 屏幕最底（窗口底、Tab 栏外侧）
    static let bgBase = dyn(dark: "#0A0D14", light: "#EDF1EC")
    /// 页面大面积渐变主段
    static let bgRaise = dyn(dark: "#121826", light: "#F7F9F6")
    /// 比页面更前的非玻璃块（视频未加载底、输入框底）
    static let bgElevated = dyn(dark: "#171F2E", light: "#FFFFFF")
    /// 弹层遮罩
    static let scrim = dyna(dark: ("#000000", 0.45), light: ("#0F1A26", 0.28))

    // MARK: - 玻璃层（PRD §3.2 玻璃层 7 条）

    /// 卡片底
    static let glassFill = dyna(dark: ("#FFFFFF", 0.06), light: ("#FFFFFF", 0.72))
    /// 弹层 / Tab 栏
    static let glassFillStrong = dyna(dark: ("#FFFFFF", 0.10), light: ("#FFFFFF", 0.88))
    /// 上缘描边：深色「接光」，浅色「提亮」。深色下这是玻璃与背景唯一的分界线，不能省
    static let glassStrokeTop = dyna(dark: ("#FFFFFF", 0.18), light: ("#FFFFFF", 0.90))
    /// 下缘描边
    static let glassStrokeBottom = dyna(dark: ("#FFFFFF", 0.04), light: ("#0F1A26", 0.08))
    /// 内侧顶部 1pt 高光（模拟折射）
    static let glassHighlight = dyna(dark: ("#FFFFFF", 0.14), light: ("#FFFFFF", 0.95))
    /// 高光 / 渐变的「透明端」。深色浅色都是 0 —— 它存在的唯一意义是让渐变两端都是 token，
    /// View 层因此不必再写 `.opacity(0)`（设计文档 §1.1.2 第 3 行）。
    static let glassHighlightFade = dyna(dark: ("#FFFFFF", 0.00), light: ("#FFFFFF", 0.00))
    /// 玻璃顶部向内渐亮（V2 手工玻璃里写死的 white 3.5%）
    static let glassSheen = dyna(dark: ("#FFFFFF", 0.035), light: ("#FFFFFF", 0.30))
    /// 外投影（弹层 / Tab 栏 / 导航条）
    static let glassShadow = dyna(dark: ("#000000", 0.45), light: ("#1B2E3F", 0.10))
    /// 卡片层级的外投影比弹层轻一档（V2 `GlassLevel.card.shadowOpacity = 0.35`）。
    /// 单独一个 token 而不是在 View 里乘 0.35，是为了让深色像素零变化。
    static let glassShadowSoft = dyna(dark: ("#000000", 0.35), light: ("#1B2E3F", 0.08))
    /// 浅色专属「近场接触影」。深色下全透明 → 画了等于没画，深色零变化。
    /// PRD §3.1 第 4 条：浅色不能靠黑影做投影（发灰、显脏），必须双层灰蓝。
    static let glassShadowNear = dyna(dark: ("#000000", 0.00), light: ("#1B2E3F", 0.05))
    /// 状态类卡片的青柠染色
    static let glassTintLime = dyna(dark: ("#6BDB5C", 0.08), light: ("#3FA83A", 0.08))

    // MARK: - 二级玻璃（静态配方，不采样背景，B 批次新增）

    /// 静态玻璃填充：比真玻璃更深一档的实色感（深 白 8% / 浅 白 78%），
    /// 不采样背景也能立住（列表卡用，单屏几十张也不重）。
    static let glassStaticFill = dyna(dark: ("#FFFFFF", 0.08), light: ("#FFFFFF", 0.78))
    /// 顶缘 1pt 半透高光：深底白 12% / 浅底黑 8%（任务 B1 指定的反向配色）。
    static let glassStaticHighlight = dyna(dark: ("#FFFFFF", 0.12), light: ("#0F1A26", 0.08))
    /// 1pt 描边（与高光反向）：深底黑 8% / 浅底白 12%，保证深浅双主题都"有边"。
    static let glassStaticStroke = dyna(dark: ("#0F1A26", 0.08), light: ("#FFFFFF", 0.12))

    // MARK: - 品牌青柠（面 / 字 / 面上字 三分，PRD §3.2）

    /// 【面】只允许出现在 `fill` / `strokeBorder` / `LinearGradient` / 徽标底 / 进度条填充。
    /// **禁止** `foregroundStyle(Theme.lime)` —— 需要"青柠色的字"请用 `limeInk`。
    /// 浅色 `#3FA83A` 作为面 ≥3:1，配 `onLime` 文字 5.4:1。
    static let lime = dyn(dark: "#6BDB5C", light: "#3FA83A")
    /// 【字】≤17pt 的青柠色文字、可点击图标、状态标签。深色与 `lime` 同值（`#6BDB5C`），
    /// 所以全项目"把文字色从 lime 改成 limeInk"在深色下**零像素变化** —— 这是无回归的保证。
    /// 浅色 `#1F6B22`，6.2:1。
    static let limeInk = dyn(dark: "#6BDB5C", light: "#1F6B22")
    /// 【面上的字】只与 `Theme.lime` 背景成对出现。深色 `#0A0D14` 9.3:1 / 浅色 `#0F2410` 5.4:1
    static let onLime = dyn(dark: "#0A0D14", light: "#0F2410")
    /// 渐变第二停靠点（仅作面，不承载文字）
    static let limeBright = dyn(dark: "#D4F36E", light: "#A8E88F")
    /// 按下态、渐变暗端
    static let limeDeep = dyn(dark: "#3FA83A", light: "#2F7A2C")
    /// 光晕。浅色必须减半，否则整屏发绿
    static let limeGlow = dyna(dark: ("#6BDB5C", 0.35), light: ("#6BDB5C", 0.16))
    /// 图表柱（Swift Charts 的 `BarMark`）。值与 `lime` 完全相同，单独命名的唯一理由：
    /// lint 规则 4 会把 `foregroundStyle(Theme.lime)` 判成「lime 当文字色」，
    /// 而图表柱是**面**。给它一个独立 token，View 层既不用写 hex，也不用 `lint:allow` 破例。
    static let chartBar = dyn(dark: "#6BDB5C", light: "#3FA83A")

    // MARK: - 文字三级 + 元信息（PRD 已实测对比度）

    /// 标题、正文强调。浅色 16.6:1
    static let textPrimary = dyn(dark: "#F2F5FA", light: "#0F1A26")
    /// 正文（比纯白柔和，长文不刺眼）。浅色 11.4:1
    static let textBody = dyn(dark: "#E6EAF2", light: "#2A3947")
    /// 摘要、次级说明。浅色 6.2:1
    static let textSecondary = dyn(dark: "#A8B2C4", light: "#4F5F6E")
    /// 时间、元信息、图注。浅色 4.7:1 —— 12pt 的底线，不再更浅
    static let textTertiary = dyn(dark: "#8A94A6", light: "#64727F")

    // MARK: - 状态色

    /// 有新版本。与 `limeInk` 两个值都相同，是**有意合并**的（设计文档 §1.1.3），评审时不要"修回去"
    static let statusNew = dyn(dark: "#6BDB5C", light: "#1F6B22")
    /// 已是最新（中性灰；绿色只代表「有变化」）
    static let statusOk = dyn(dark: "#8A94A6", light: "#64727F")
    /// 检查中 / 待确认的**文字与图标**。`#FFC24B` 在白底只有 1.6:1，所以浅色压到 `#8A5B00`
    static let statusWarn = dyn(dark: "#FFC24B", light: "#8A5B00")
    /// 待确认徽标的**填充块**底色（PRD 明确：浅色下 `#FFC24B` 只能当底色，不能当字色）
    static let statusWarnFill = dyn(dark: "#FFC24B", light: "#FFC24B")
    /// 接口失败。浅色 5.0:1
    static let statusError = dyn(dark: "#FF8F7A", light: "#C43B22")

    // MARK: - 其他

    /// 分割线
    static let divider = dyna(dark: ("#FFFFFF", 0.08), light: ("#0F1A26", 0.08))
    /// 代码块底（比页面更深一档 / 更浅一档）
    static let codeBg = dyn(dark: "#0D1117", light: "#F1F4EF")
    /// 骨架块。**浅色下绝不能沿用深色的白 7%，否则完全看不见，等于没有加载态**（PRD §4 #6）
    static let skeleton = dyna(dark: ("#FFFFFF", 0.07), light: ("#0F1A26", 0.06))
    /// 图片 / 视频首帧的 1pt 描边。浅色下图片边缘与白底粘连，是最常见的"显廉价"来源（PRD §3.4 第 3 条）
    static let imageHairline = dyna(dark: ("#FFFFFF", 0.10), light: ("#0F1A26", 0.10))
    /// 骨架微光带的暗段
    static let skeletonShimmerLow = dyna(dark: ("#FFFFFF", 0.08), light: ("#0F1A26", 0.06))
    /// 骨架微光带的高光段
    static let skeletonShimmerMid = dyna(dark: ("#FFFFFF", 0.18), light: ("#0F1A26", 0.12))
    /// 二维码等**机器可读图形**的专用底色（批次 3 增补）。
    ///
    /// 唯一一个"两种外观同值"的 token，原因是物理限制而不是偷懒：
    /// 二维码的 quiet zone 必须是浅色，否则相机在深色底上识别率骤降。
    /// 它不属于界面配色，所以不参与明暗切换；给它一个 token 名只是为了守住
    /// 「View 层不出现裸颜色字面量」这条闸门（PRD §3.4 第 1 条）。
    static let qrCanvas = dyn(dark: "#FFFFFF", light: "#FFFFFF")

    // MARK: - 微底 4 档（把 V2 里随手写的 0.02 / 0.04 / 0.06 / 0.08 收敛成有名字的档位）
    //
    // 为什么必须有名字：浅色模式要为这 4 个不透明度各补一个值，如果留在 View 里就地写透明度，
    // 就会出现 4 个没人审过的浅色值（设计文档 §1.1.2 第 5 行）。

    static let surfaceTint1 = dyna(dark: ("#FFFFFF", 0.02), light: ("#0F1A26", 0.03))
    static let surfaceTint2 = dyna(dark: ("#FFFFFF", 0.04), light: ("#0F1A26", 0.05))
    static let surfaceTint3 = dyna(dark: ("#FFFFFF", 0.06), light: ("#0F1A26", 0.07))
    static let surfaceTint4 = dyna(dark: ("#FFFFFF", 0.08), light: ("#0F1A26", 0.09))

    // MARK: - 程序化封面的 4 组渐变（PRD §3.2 末表，逐行照抄）
    //
    // 浅色统一规律：第一停靠点换到浅色域、第二停靠点换到 `limeDeep` 级别的深色，
    // 否则封面在白底上会"飘"起来。每个停靠点各自是动态色，渐变会随外观整体重解析。

    /// 0 青柠斜向
    static let coverLime: [Color] = [
        dyna(dark: ("#6BDB5C", 0.55), light: ("#6BDB5C", 0.85)),
        dyna(dark: ("#3FA83A", 0.85), light: ("#2F7A2C", 0.95))
    ]
    /// 1 深空到青柠
    static let coverDeep: [Color] = [
        dyna(dark: ("#171F2E", 1.00), light: ("#E4EBE3", 1.00)),
        dyna(dark: ("#6BDB5C", 0.40), light: ("#3FA83A", 0.55))
    ]
    /// 2 青柠到琥珀
    static let coverAmber: [Color] = [
        dyna(dark: ("#6BDB5C", 0.42), light: ("#6BDB5C", 0.60)),
        dyna(dark: ("#B9803A", 0.78), light: ("#9A6420", 0.88))
    ]
    /// 3 冷灰到青柠
    static let coverCool: [Color] = [
        dyna(dark: ("#2A3446", 1.00), light: ("#C9D3D2", 1.00)),
        dyna(dark: ("#6BDB5C", 0.34), light: ("#3FA83A", 0.50))
    ]

    /// 封面标题首字水印（V2 是 white 12%）。浅色封面第一停靠点仍是亮绿，
    /// 白 12% 在上面几乎消失，所以浅色提到 42%（同一色相、只调"看得见"这一件事）。
    static let coverWatermark = dyna(dark: ("#FFFFFF", 0.12), light: ("#FFFFFF", 0.42))
    /// 封面噪点（V2 是 white 5%，`.blendMode(.overlay)`）
    static let coverGrain = dyna(dark: ("#FFFFFF", 0.05), light: ("#FFFFFF", 0.08))

    /// seed → 4 组渐变（seed 由服务端 fnv1a(id) % 4 给出）。
    static func coverColors(seed: Int) -> [Color] {
        let index = ((seed % 4) + 4) % 4
        switch index {
        case 0: return coverLime
        case 1: return coverDeep
        case 2: return coverAmber
        default: return coverCool
        }
    }

    // MARK: - 唯一构造入口（透明度只允许出现在这两个函数里，PRD §3.4 第 1 条）

    /// 不透明动态色。
    ///
    /// `.unspecified`（离屏渲染 / Widget 首次快照等场景）按**深色**兜底：
    /// 深色是 V2 的基线，兜底到深色最坏也只是"没换成浅色"，而不是闪一下白。
    private static func dyn(dark: String, light: String) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { trait in
            let hex = (trait.userInterfaceStyle == .light) ? light : dark
            return UIColor(Color(hex: hex))
        })
        #else
        // 非 UIKit 平台（本工程只有 iOS target，走不到这里）退回深色静态值，绝不 crash
        return Color(hex: dark)
        #endif
    }

    /// 带透明度的动态色 —— 这一条替代了全项目 30 处 `Color.white.opacity(...)`。
    ///
    /// 注意透明度是在**闭包内部**算进 UIColor 的：同一份 alpha 对两种外观各自生效，
    /// 不会出现"先 `.opacity()` 再包动态色"导致动态性丢失的写法。
    private static func dyna(dark: (String, Double), light: (String, Double)) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { trait in
            let spec = (trait.userInterfaceStyle == .light) ? light : dark
            return UIColor(Color(hex: spec.0)).withAlphaComponent(CGFloat(spec.1))
        })
        #else
        return Color(hex: dark.0).opacity(dark.1)
        #endif
    }
}
