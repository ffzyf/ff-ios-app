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

    // MARK: - 当前配色（V3.2 主题系统）

    /// 当前生效的一套配色。改它 → 下一次视图重算就换肤。
    ///
    /// 为什么用 `static var` 而不是 Environment 注入：全工程 100+ 处 `Theme.xxx` 调用点
    /// **一处都不用改** —— 这是主题化能做到的最低风险路径。代价是 SwiftUI 感知不到
    /// 这个变量的变化，所以 `RootView` 在切换时给内容区换 `.id(themeId)` 强制重建子树。
    ///
    /// 默认 `.lime`：与 V2 逐像素一致，也是 Widget 进程里读不到 App 偏好时的兜底。
    static var active: Palette = .lime

    // MARK: - 背景三层（同一条规则：越靠前越亮，浅色下越靠前越白）

    /// 屏幕最底（窗口底、Tab 栏外侧）
    static var bgBase: Color { dyn(active.bgBase) }
    /// 页面大面积渐变主段
    static var bgRaise: Color { dyn(active.bgRaise) }
    /// 页面渐变的**最底段**。
    ///
    /// 只给 `PageBackground` 的 `LinearGradient` 当第三个停靠点用（`bgRaise → bgBase → bgDeep`），
    /// **不是窗口底色、不替代 `bgBase`**：窗口底、Tab 栏外侧、安全区外露出的那块仍然必须是 `bgBase`，
    /// 因为 `bgBase` 是全工程（含 Widget）对齐过的基线，换掉它等于让"顶部未滚动"那一帧也变。
    ///
    /// 它存在的唯一理由：`bgRaise` 与 `bgBase` 只差一档，浅色下（`#F7F9F6` → `#EDF1EC`）
    /// 整页看起来就是"一片白"，越往下滑越没有沉下去的感觉。压暗 5–6% 的第三段
    /// 让页脚有一点重量，滚动光影"沉下去"才有承托。
    ///
    /// 浅色这一档是"用户说背景太白"的直接回应 —— 底部要比 `bgBase` 明显深一档（约 L\* 差 5–6），
    /// 不然从顶到底还是一张白纸；但不能压到 8% 以上，否则页脚与白玻璃卡的对比会翻过来
    /// （卡比底还暗）。
    static var bgDeep: Color { dyn(active.bgDeep) }
    /// 比页面更前的非玻璃块（视频未加载底、输入框底）
    static var bgElevated: Color { dyn(active.bgElevated) }
    /// 弹层遮罩
    static var scrim: Color { dyna(active.scrim) }

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
    static var glassTintLime: Color { dyna(active.glassTint) }

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
    static var lime: Color { dyn(active.lime) }
    /// 【字】≤17pt 的青柠色文字、可点击图标、状态标签。深色与 `lime` 同值（`#6BDB5C`），
    /// 所以全项目"把文字色从 lime 改成 limeInk"在深色下**零像素变化** —— 这是无回归的保证。
    /// 浅色 `#1F6B22`，6.2:1。
    static var limeInk: Color { dyn(active.limeInk) }
    /// 【面上的字】只与 `Theme.lime` 背景成对出现。深色 `#0A0D14` 9.3:1 / 浅色 `#0F2410` 5.4:1
    static var onLime: Color { dyn(active.onLime) }
    /// 渐变第二停靠点（仅作面，不承载文字）
    static var limeBright: Color { dyn(active.limeBright) }
    /// 按下态、渐变暗端
    static var limeDeep: Color { dyn(active.limeDeep) }
    /// 光晕。浅色必须减半，否则整屏发绿
    static var limeGlow: Color { dyna(active.limeGlow) }
    /// 图表柱（Swift Charts 的 `BarMark`）。值与 `lime` 完全相同，单独命名的唯一理由：
    /// lint 规则 4 会把 `foregroundStyle(Theme.lime)` 判成「lime 当文字色」，
    /// 而图表柱是**面**。给它一个独立 token，View 层既不用写 hex，也不用 `lint:allow` 破例。
    static var chartBar: Color { dyn(active.lime) }

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

    // MARK: - 涨跌（设计报告 §5 第 5 项）

    /// 涨（中国习惯：涨红）。
    ///
    /// 为什么不能直接借 `statusError`：那是"出错了"的红，`+12%` 用它会读成报错。
    /// 像素值与现有红色家族**刻意相同**（深 `#FF6B5A` / 浅 `#C43B22`），所以本 token 落地时
    /// 不产生任何视觉漂移，只是把正确的语义名补上；Widget target 也编译本文件，故与其它 token
    /// 一样走 `dyn`，不引入任何只在 App 可用的类型。
    static let riseRed = dyn(dark: "#FF6B5A", light: "#C43B22")
    /// 跌（跌绿）。同理不借 `statusNew` —— 那是"有新版本"的绿
    static let fallGreen = dyn(dark: "#6BDB5C", light: "#1F6B22")

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
    // MARK: - 轨迹卡（V3.1 返工：首页卡与桌面小组件共用同一套配色）
    //
    // 这 4 个 token 是"卡片自己的底色"，不能复用 `bgRaise`：页面底色是偏绿的深空，
    // 而参考设计里的轨迹卡是偏蓝的深靛 —— 压在页面玻璃层上才有"一块独立的夜"的感觉。
    // 浅色下反过来：卡片要比页面白，靠描边而不是靠阴影立起来。

    /// 轨迹卡渐变起始（左上）
    static let trackTop = dyn(dark: "#182131", light: "#FFFFFF")
    /// 轨迹卡渐变结束（右下）
    static let trackBottom = dyn(dark: "#0C111C", light: "#EDF1F6")
    /// 轨迹卡的那条光轨 / 发光节点（参考图里的淡蓝紫）
    static let trackArc = dyn(dark: "#AFC2EE", light: "#5C74A8")
    /// 轨迹卡上的次要文字（比 textSecondary 更淡一点，压在渐变上才不抢戏）
    static let trackTextDim = dyna(dark: ("#F2F5FA", 0.62), light: ("#0F1A26", 0.55))
    /// 轨迹卡右侧列表的竖向分割线
    static let trackDivider = dyna(dark: ("#FFFFFF", 0.12), light: ("#0F1A26", 0.10))
    /// Tab 栏右上角的红色徽标（面）。深色下提亮一档，压在半透玻璃上才看得见
    static let badgeRed = dyn(dark: "#FF6B5A", light: "#E03A22")
    /// 徽标上的数字（面上的字）。与 `badgeRed` 成对出现，实测 ≥4.5:1
    static let badgeRedInk = dyn(dark: "#2A0B06", light: "#FFFFFF")

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

    /// `dyn` 的配色对重载：`Palette` 里存的是 `(dark, light)` 字面量，
    /// 用这个入口让 12 个主题 token 的写法保持一行（不必在 body 里拆两次调用）。
    private static func dyn(_ spec: (dark: String, light: String)) -> Color {
        dyn(dark: spec.dark, light: spec.light)
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

    /// `dyna` 的配色对重载（带 alpha 的版本），与 `dyn(_:)` 同理。
    private static func dyna(_ spec: (dark: (String, Double), light: (String, Double))) -> Color {
        dyna(dark: spec.dark, light: spec.light)
    }
}

// MARK: - 主题配色（V3.2 新增）

extension Theme {

    /// 一套主题配色。
    ///
    /// 只包含**品牌色 + 背景三层**。文字 / 玻璃 / 状态 / 骨架 / 封面这些中性 token
    /// 五套主题共用 —— 换主题不该让任何一处的对比度失守，PRD 里那批实测值继续有效。
    ///
    /// 每个值都是 `(深色, 浅色)` 一对：**深色模式不是"另一套主题"**，而是同一套的第二个值。
    /// 所以每套主题天然自带深色版本，不需要单独维护 5×2 份配色。
    struct Palette: Identifiable {
        let id: String
        let name: String
        let bgBase: (dark: String, light: String)
        let bgRaise: (dark: String, light: String)
        /// 页面渐变最底段（压暗 5–6%）。**只给页面渐变用**，不做窗口底色 —— 理由见 `Theme.bgDeep`
        let bgDeep: (dark: String, light: String)
        let bgElevated: (dark: String, light: String)
        let scrim: (dark: (String, Double), light: (String, Double))
        /// 品牌面色
        let lime: (dark: String, light: String)
        /// 品牌字色
        let limeInk: (dark: String, light: String)
        /// 面上的字
        let onLime: (dark: String, light: String)
        let limeBright: (dark: String, light: String)
        let limeDeep: (dark: String, light: String)
        let limeGlow: (dark: (String, Double), light: (String, Double))
        let glassTint: (dark: (String, Double), light: (String, Double))
    }
}

extension Theme.Palette {

    /// 五套主题（设置页按这个顺序排）
    static let all: [Theme.Palette] = [.lime, .violet, .sand, .ocean, .sakura]

    /// 按 id 取主题；认不出就退回青柠（**绝不崩**，旧版本写入的 id 也能开机）
    static func with(id: String) -> Theme.Palette {
        all.first { $0.id == id } ?? .lime
    }
}

extension Theme.Palette {

    /// 色板预览用的品牌面。
    ///
    /// 放在这里而不是设置页里，是为了守住「hex 只出现在 Theme.swift」这条闸门：
    /// View 层只需要 `palette.swatch`，不碰任何颜色字面量。
    /// 跟随外观取值（浅色用浅色那一档），所以设置页在深色下看到的就是深色下的观感。
    var swatch: Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { trait in
            let hex = (trait.userInterfaceStyle == .light) ? lime.light : lime.dark
            return UIColor(Color(hex: hex))
        })
        #else
        return Color(hex: lime.dark)
        #endif
    }

    /// 0 青柠 —— 品牌原色，V2 至今的基线（深色值逐字沿用，零像素变化）
    static let lime = Theme.Palette(
        id: "lime", name: "青柠",
        bgBase: ("#0A0D14", "#EDF1EC"),
        bgRaise: ("#121826", "#F7F9F6"),
        // 在 bgBase 基础上压暗 5–6%：浅色靠它把白压住、深色靠它给页脚一点重量
        bgDeep: ("#080B11", "#DFE6DD"),
        bgElevated: ("#171F2E", "#FFFFFF"),
        scrim: (("#000000", 0.45), ("#0F1A26", 0.28)),
        lime: ("#6BDB5C", "#3FA83A"),
        limeInk: ("#6BDB5C", "#1F6B22"),
        onLime: ("#0A0D14", "#0F2410"),
        limeBright: ("#D4F36E", "#A8E88F"),
        limeDeep: ("#3FA83A", "#2F7A2C"),
        limeGlow: (("#6BDB5C", 0.35), ("#6BDB5C", 0.16)),
        glassTint: (("#6BDB5C", 0.08), ("#3FA83A", 0.08))
    )

    /// 1 暮紫 —— 夜航感，背景往靛紫压（不是把绿换成紫就完事）
    static let violet = Theme.Palette(
        id: "violet", name: "暮紫",
        bgBase: ("#0B0912", "#F3F1F8"),
        bgRaise: ("#14101F", "#FAF9FC"),
        // 在 bgBase 基础上压暗 5–6%：浅色靠它把白压住、深色靠它给页脚一点重量
        bgDeep: ("#080611", "#E6E3EF"),
        bgElevated: ("#1A1528", "#FFFFFF"),
        scrim: (("#000000", 0.45), ("#1A1528", 0.28)),
        lime: ("#A78BFA", "#7C5CE0"),
        limeInk: ("#A78BFA", "#5B3FB8"),
        onLime: ("#120E1F", "#FFFFFF"),
        limeBright: ("#C4B5FD", "#A78BFA"),
        limeDeep: ("#7C3AED", "#5B3FB8"),
        limeGlow: (("#A78BFA", 0.38), ("#7C5CE0", 0.16)),
        glassTint: (("#A78BFA", 0.10), ("#7C5CE0", 0.08))
    )

    /// 2 暖砂 —— 米纸 + 琥珀，长文阅读最不刺眼的一套
    static let sand = Theme.Palette(
        id: "sand", name: "暖砂",
        bgBase: ("#12100C", "#F6F2EA"),
        bgRaise: ("#1B1813", "#FBF8F2"),
        // 在 bgBase 基础上压暗 5–6%：浅色靠它把白压住、深色靠它给页脚一点重量
        bgDeep: ("#0E0C09", "#EBE5D9"),
        bgElevated: ("#221E17", "#FFFFFF"),
        scrim: (("#000000", 0.45), ("#221E17", 0.28)),
        lime: ("#E8B96A", "#B37D2A"),
        limeInk: ("#E8B96A", "#7A5212"),
        onLime: ("#1A1206", "#2A1C05"),
        limeBright: ("#F5D89A", "#D9AE6A"),
        limeDeep: ("#C4913F", "#8F6120"),
        limeGlow: (("#E8B96A", 0.32), ("#B37D2A", 0.15)),
        glassTint: (("#E8B96A", 0.10), ("#B37D2A", 0.08))
    )

    /// 3 海蓝 —— 冷调，配红石/夜空的卡最协调
    static let ocean = Theme.Palette(
        id: "ocean", name: "海蓝",
        bgBase: ("#060D14", "#EDF3F7"),
        bgRaise: ("#0D1822", "#F7FAFC"),
        // 在 bgBase 基础上压暗 5–6%：浅色靠它把白压住、深色靠它给页脚一点重量
        bgDeep: ("#050A11", "#DCE7EE"),
        bgElevated: ("#13202C", "#FFFFFF"),
        scrim: (("#000000", 0.45), ("#0D1822", 0.28)),
        lime: ("#4FC3F7", "#1E88C7"),
        limeInk: ("#4FC3F7", "#0F5C8A"),
        onLime: ("#04141C", "#04202E"),
        limeBright: ("#9CE4FF", "#7FD0F0"),
        limeDeep: ("#2196C9", "#14688F"),
        limeGlow: (("#4FC3F7", 0.36), ("#1E88C7", 0.16)),
        glassTint: (("#4FC3F7", 0.10), ("#1E88C7", 0.08))
    )

    /// 4 樱粉 —— 唯一一套"面浅字深"的：浅色下粉底必须压深字，白字对比不够
    static let sakura = Theme.Palette(
        id: "sakura", name: "樱粉",
        bgBase: ("#100A0E", "#F9EFF3"),
        bgRaise: ("#191016", "#FDF8FA"),
        // 在 bgBase 基础上压暗 5–6%：浅色靠它把白压住、深色靠它给页脚一点重量
        bgDeep: ("#0B0709", "#EDE1E9"),
        bgElevated: ("#20141B", "#FFFFFF"),
        scrim: (("#000000", 0.45), ("#20141B", 0.28)),
        lime: ("#F79BB8", "#D9598A"),
        limeInk: ("#F79BB8", "#A3325C"),
        onLime: ("#1F0A12", "#3A0D1E"),
        limeBright: ("#FFC2D6", "#F2A7C0"),
        limeDeep: ("#E07A9E", "#B04068"),
        limeGlow: (("#F79BB8", 0.32), ("#D9598A", 0.15)),
        glassTint: (("#F79BB8", 0.10), ("#D9598A", 0.08))
    )
}

// MARK: - 天际线配色（V3.2 简报卡）

extension Theme {

    /// 天空卡的五段色。
    ///
    /// 这些是**物理天空色**，不随 App 的深浅外观切换 —— 你开了浅色模式，天空也不会变白。
    /// 所以这里用固定 hex（不走 `dyn`），由卡片自己保证文字对比度：
    /// 天空底上永远压浅色字，地面底上永远压半透浅字。
    struct SkyColors {
        /// 天空顶
        let top: Color
        /// 地平线附近的天色
        let horizon: Color
        /// 地面（弧线以下）
        let ground: Color
        /// 地平线亮边
        let edge: Color
        /// 卡上的主文字
        let ink: Color
        /// 卡上的次要文字
        let inkDim: Color
    }

    /// 按时段取天空色（七档，逐档手调，不用公式插值 —— 插值出来的中间色总是发灰）
    static func sky(_ phase: SkyPhase) -> SkyColors {
        let ink = Color(hex: "#F5F8FF")
        let inkDim = Color(hex: "#F5F8FF").opacity(0.72)

        switch phase {
        case .night:
            return SkyColors(top: Color(hex: "#05070E"), horizon: Color(hex: "#101A2C"),
                             ground: Color(hex: "#02040A"), edge: Color(hex: "#2E4068"),
                             ink: ink, inkDim: inkDim)
        case .blueDawn:
            return SkyColors(top: Color(hex: "#16204A"), horizon: Color(hex: "#6E4E7A"),
                             ground: Color(hex: "#0A0710"), edge: Color(hex: "#C08BD0"),
                             ink: ink, inkDim: inkDim)
        case .sunrise:
            return SkyColors(top: Color(hex: "#E8894A"), horizon: Color(hex: "#FFD9A0"),
                             ground: Color(hex: "#2A1608"), edge: Color(hex: "#FFEBC8"),
                             ink: ink, inkDim: inkDim)
        case .golden:
            return SkyColors(top: Color(hex: "#5FB6EA"), horizon: Color(hex: "#FFC46B"),
                             ground: Color(hex: "#1C1106"), edge: Color(hex: "#FFD89A"),
                             ink: ink, inkDim: inkDim)
        case .day:
            return SkyColors(top: Color(hex: "#3E8FD6"), horizon: Color(hex: "#BFE4FF"),
                             ground: Color(hex: "#0B1620"), edge: Color(hex: "#EAF7FF"),
                             ink: ink, inkDim: inkDim)
        case .sunset:
            return SkyColors(top: Color(hex: "#DD5530"), horizon: Color(hex: "#FFB067"),
                             ground: Color(hex: "#180A05"), edge: Color(hex: "#FFD0A0"),
                             ink: ink, inkDim: inkDim)
        case .blueDusk:
            return SkyColors(top: Color(hex: "#C9486F"), horizon: Color(hex: "#7A4E86"),
                             ground: Color(hex: "#0E0713"), edge: Color(hex: "#E89AC0"),
                             ink: ink, inkDim: inkDim)
        }
    }
}

// MARK: - 天气氛围色（V3.7 简报卡按当天天气换一套氛围）

extension Theme {

    /// 「今天的天气」的八档氛围色 —— 简报卡的底色 + 中心柔光。
    ///
    /// **为什么不用 `Palette`、不走 `dyn`（不参与换肤）**：
    /// 换肤改的是界面自己的情绪（青柠 / 暮紫 / 暖砂 / 海蓝 / 樱粉），而天气是**物理事实**——
    /// 切到樱粉主题时把「下雨」染成粉色，这张卡就不再是天气报表，而是一张装饰插画了。
    /// 所以八档用固定 hex：五套主题下同一场雨永远是同一种蓝。
    /// 它们**只做面**（底色 / 柔光 / 粒子），文字一律走 `sky(.night).ink`，
    /// 因此换主题也不会让任何一处对比度失守（`ink` = `#F5F8FF`，与八档顶色的对比度都在 15:1 以上）。
    ///
    /// **为什么八档全是深色**：简报卡要压住近白的白字。底色一浅，白字立刻读不清，
    /// 而"换一天天气就得换一套字色"是这套系统里最容易漏掉、又最难在评审时发现的错误。
    /// 于是明度全部贴着 `sky(.night)`（`#05070E`）走，**只靠色相区分天气**：
    /// 晴是暖褐、雨是深蓝、雷是近黑紫 —— 用户扫一眼读到的是"今天是暖的还是冷的"，
    /// 而不是"今天卡片亮还是暗"。
    enum Weather {

        /// 天气 → (底色, 柔光)。
        ///
        /// - 底色 `top`：最暗的一档，铺满整卡的线性渐变**起点**（终点固定是 `sky(.night).ground`，
        ///   也就是下面那张"夜纸"），所以八档的卡片下沿都是同一块近黑，只有上半张在变天。
        /// - 柔光 `glow`：比底色亮一档，**必须靠 `opacity` 压成光**再叠上去（0.12~0.30，
        ///   由云量反向决定，见 `BriefMetrics.glowAlpha(cloudiness:)`）—— 直接用会变成一块色斑。
        ///
        /// - Parameter kind: 天气类型。**`nil` 时返回现有纸面的两个色**（`sky(.night)` 的
        ///   `top` / `ground`）：没拿到天气就回到现在这张卡的样子，绝不用晴天兜底
        ///   （与 `WeatherKind.from(code:)` 拒绝兜底是同一条原则）。
        static func of(_ kind: WeatherKind?) -> (top: Color, glow: Color) {
            // 没有天气数据：退回现有"夜纸"，一个像素都不变
            guard let kind = kind else {
                let night = Theme.sky(.night)
                return (night.top, night.ground)
            }

            switch kind {
            case .clear:
                // 晒过太阳的纸：暖褐黑 + 暖金。云量 0，所以柔光最亮的一档
                return (Color(hex: "#1A1510"), Color(hex: "#6B4E22"))
            case .partly:
                // 深蓝灰 + 银蓝：还是蓝调，只是被云压暗了一档
                return (Color(hex: "#131A22"), Color(hex: "#3A4E63"))
            case .overcast:
                // 冷灰 + 灰蓝：无色彩倾向，正是"阴天没有光照方向"的感觉
                return (Color(hex: "#15181C"), Color(hex: "#3B434E"))
            case .fog:
                // 灰青：比阴略微发青，让人想到湿度而不是雨
                return (Color(hex: "#161B1D"), Color(hex: "#445155"))
            case .drizzle:
                // 深青 + 青：毛毛雨的青是"空气里的水汽"，不是大雨那种蓝
                return (Color(hex: "#0F191C"), Color(hex: "#2E5459"))
            case .rain:
                // 深蓝 + 蓝：最"正"的雨天色，与 drizzle 的青拉开一档
                return (Color(hex: "#0C1420"), Color(hex: "#2A4A72"))
            case .snow:
                // 冷青白：雪天要"冷"，但不许"亮" —— 底色仍是深的，亮的是落下来的点
                return (Color(hex: "#121820"), Color(hex: "#5A7080"))
            case .thunder:
                // 近黑紫：雷暴的电是紫的（闪电本身用 `glow` 画，见 `BriefFace`）
                return (Color(hex: "#100E18"), Color(hex: "#463466"))
            }
        }
    }
}

// MARK: - 平台品牌色（收益页「平台」网格，A+B 混合方案）

extension Theme {

    /// 平台品牌色：**固定色相，不参与主题换肤**。
    ///
    /// 为什么不放进 `Palette`（和其他品牌色一起换）：
    /// 换肤改的是「面」—— 背景 / 玻璃 / 强调色，那是**界面自己的情绪**；
    /// 而平台身份是**数据自带的属性**，必须稳定。五套主题（青柠 / 暮紫 / 暖砂 / 海蓝 / 樱粉）
    /// 里如果平台色也跟着走，切到樱粉主题时抖音、快手、小红书、网易全变成一片粉，
    /// 用户就认不出哪张卡是哪个平台了 —— 那正是这五个颜色存在的唯一理由。
    ///
    /// 所以这里走固定 hex（不经 `dyn` / `dyna`）：深色与浅色下同一个平台永远是同一种红。
    /// 代价是浅色底上的对比度不如中性 token 稳，因此**颜色只做圆点与小细条**（面），
    /// 平台名与金额一律用 `textPrimary` —— 文字不依赖品牌色也能读，
    /// 这同时也是「抖音 / 快手 / 小红书 三张红卡并排」不糊掉的办法。
    enum Platform {

        /// 抖音（品牌红）
        static let douyin = Color(hex: "FE2C55")
        /// 快手（品牌橙红）
        static let kuaishou = Color(hex: "FF5000")
        /// 小红书（品牌红）
        static let xiaohongshu = Color(hex: "FF2442")
        /// 网易创作酱（品牌红）
        static let netease = Color(hex: "E60026")
        /// 网易光遇追光计划（品牌蓝）
        static let neteaseSky = Color(hex: "2E9BFF")
        /// 兜底：自定义平台（用户能自己填平台名，见 `EarningsPlatformPreset`）。
        ///
        /// 刻意选一档中性灰蓝而不是随手一个亮色：五个固定平台里有四个是红/橙，
        /// 兜底如果也偏红，"自定义平台"就会被误读成某个大平台。灰蓝的意思是"这个平台没有品牌色"。
        static let fallback = Color(hex: "8A94A6")

        /// 平台名 → 品牌色（含模糊匹配）。
        ///
        /// 为什么必须容错：平台名是**用户/服务端自由填的字符串**，不是枚举 ——
        /// 同一次响应里既可能出现预设的「网易光遇追光计划」，也可能出现用户自己建的「光遇」，
        /// 甚至「抖音星图」。精确相等会让一半平台掉到兜底灰，所以这里用 `contains`。
        ///
        /// 判定顺序有讲究：**长名先于短名** —— 「网易光遇追光计划」同时含「网易」与「光遇」，
        /// 若先判「网易」它会拿到创作酱的红色，和短名「光遇」的蓝色对不上，同一个平台两种色。
        /// - Parameter name: 服务端返回的平台名（可为空 / 带空格）
        /// - Returns: 品牌色；认不出的平台返回 `fallback`
        static func of(_ name: String) -> Color {
            let text = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard text.isEmpty == false else { return fallback }

            // 1. 光遇系列（长名先判：覆盖「网易光遇追光计划」「光遇」「追光计划」）
            if text.contains("光遇") || text.contains("追光") || text.contains("sky") {
                return neteaseSky
            }
            // 2. 抖音 / TikTok
            if text.contains("抖音") || text.contains("douyin") || text.contains("tiktok") {
                return douyin
            }
            // 3. 快手
            if text.contains("快手") || text.contains("kuaishou") {
                return kuaishou
            }
            // 4. 小红书
            if text.contains("小红书") || text.contains("xiaohongshu") || text.contains("redbook") {
                return xiaohongshu
            }
            // 5. 网易系（创作酱是网易的另一个计划，放在光遇之后判）
            if text.contains("网易") || text.contains("创作酱") || text.contains("netease") {
                return netease
            }
            return fallback
        }
    }
}
