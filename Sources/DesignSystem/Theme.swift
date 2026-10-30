import SwiftUI

/// 颜色 token —— 全部逐字来自 PRD §4.1，不做二次调色。
///
/// 为什么用字符串 hex 而不是 UInt32：PRD 里的 hex 是评审依据，代码里必须能一眼对回去，
/// 也方便 QA 直接 grep `#6BDB5C`。`Color(hex:)` 见 Extensions.swift。
enum Theme {

    // MARK: - 背景（三层纵深）

    /// #0A0D14 最底层，屏幕底
    static let bgBase = Color(hex: "#0A0D14")
    /// #121826 大面积渐变上段
    static let bgRaise = Color(hex: "#121826")
    /// #171F2E 「比页面更前」的非玻璃块（视频未加载底等）
    static let bgElevated = Color(hex: "#171F2E")

    // MARK: - 玻璃层（PRD §4.1 玻璃层 6 条）

    /// rgba(255,255,255,0.06) 卡片底
    static let glassFill = Color.white.opacity(0.06)
    /// rgba(255,255,255,0.10) 弹层 / Tab 栏
    static let glassFillStrong = Color.white.opacity(0.10)
    /// rgba(255,255,255,0.18) 玻璃上缘描边（最关键的一条）
    static let glassStrokeTop = Color.white.opacity(0.18)
    /// rgba(255,255,255,0.04) 下缘描边
    static let glassStrokeBottom = Color.white.opacity(0.04)
    /// rgba(255,255,255,0.14) 内侧顶部 1pt 高光
    static let glassHighlight = Color.white.opacity(0.14)
    /// rgba(0,0,0,0.45) 外投影（y=8 / blur=24 见 GlassLevel）
    static let glassShadow = Color.black.opacity(0.45)
    /// rgba(107,219,92,0.08) 状态类卡片的青柠染色
    static let glassTintLime = Color(hex: "#6BDB5C").opacity(0.08)

    // MARK: - 品牌色

    /// #6BDB5C 主色：强调、状态、徽标、进度、可点击图标
    static let lime = Color(hex: "#6BDB5C")
    /// #D4F36E 高光段：渐变第二停靠点、「公告」徽标底（取自主站真实 --lime 值）
    static let limeBright = Color(hex: "#D4F36E")
    /// #3FA83A 按下态、渐变暗端
    static let limeDeep = Color(hex: "#3FA83A")
    /// rgba(107,219,92,0.35) 光晕
    static let limeGlow = Color(hex: "#6BDB5C").opacity(0.35)

    // MARK: - 文字（三级，PRD 已实测对比度）

    /// #F2F5FA 标题、正文强调
    static let textPrimary = Color(hex: "#F2F5FA")
    /// #E6EAF2 正文（比纯白柔和，长文不刺眼）
    static let textBody = Color(hex: "#E6EAF2")
    /// #A8B2C4 摘要、次级说明
    static let textSecondary = Color(hex: "#A8B2C4")
    /// #8A94A6 时间、元信息、图注
    static let textTertiary = Color(hex: "#8A94A6")

    // MARK: - 状态色

    /// #6BDB5C 有新版本
    static let statusNew = Color(hex: "#6BDB5C")
    /// #8A94A6 已是最新（中性灰；绿色只代表「有变化」）
    static let statusOk = Color(hex: "#8A94A6")
    /// #FFC24B 检查中 / 待确认
    static let statusWarn = Color(hex: "#FFC24B")
    /// #FF8F7A 接口失败
    static let statusError = Color(hex: "#FF8F7A")

    // MARK: - 其他

    /// rgba(255,255,255,0.08) 分割线
    static let divider = Color.white.opacity(0.08)
    /// #0D1117 代码块底
    static let codeBg = Color(hex: "#0D1117")
    /// rgba(255,255,255,0.07) 骨架块（骨架不是玻璃）
    static let skeleton = Color.white.opacity(0.07)

    // MARK: - 程序化封面的 4 组渐变（PRD §3.1.2）

    /// 0 青柠斜向
    static let coverLime: [Color] = [
        Color(hex: "#6BDB5C").opacity(0.55),
        Color(hex: "#3FA83A").opacity(0.85)
    ]
    /// 1 深空到青柠
    static let coverDeep: [Color] = [
        Color(hex: "#171F2E"),
        Color(hex: "#6BDB5C").opacity(0.40)
    ]
    /// 2 青柠到琥珀
    static let coverAmber: [Color] = [
        Color(hex: "#6BDB5C").opacity(0.42),
        Color(hex: "#B9803A").opacity(0.78)
    ]
    /// 3 冷灰到青柠
    static let coverCool: [Color] = [
        Color(hex: "#2A3446"),
        Color(hex: "#6BDB5C").opacity(0.34)
    ]

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
}
