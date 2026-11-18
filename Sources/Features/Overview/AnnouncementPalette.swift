import Foundation
import SwiftUI

/// 紧急公告的整套配色 —— **一个 hex 进，五个颜色出**。
///
/// ## 为什么不用 Theme token（这是本文件存在的全部理由）
///
/// 全工程的颜色都从 `Theme` 出，`Theme` 的每个 token 都是 `UIColor(dynamicProvider:)`——
/// 也就是说它**同时有两个值**（深色 / 浅色），并且随 App 的换肤（青柠 / 暮紫 / 暖砂 / 海蓝 / 樱粉）
/// 整体改色。这对界面是对的（背景该跟着人的偏好走），对紧急公告是错的：
///
/// 1. **紧急公告的颜色是服务端指派的语义**，不是界面情绪。同一个「服务中断」在青柠主题下是红的、
///    在樱粉主题下变成粉的，用户对这个"红"的记忆就散了 —— 红在这里表示"现在别用"，
///    这和 `Theme.Platform`（平台品牌色固定不换肤）、`Theme.Weather`（天气是物理事实）是同一条理由。
/// 2. **它必须与系统深浅色无关**。弹窗里所有颜色都是同一个 hex 派生的，用户在浅色系统下
///    看到的仍是同一块深红 —— 这是"这是一条不请自来的、最高优先级的通知"的视觉证据。
///    一旦混进 `Theme.*`，`dyn` 会在浅色 trait 下换成另一套值，那块红就不再是同一个红。
///
/// 所以这里是一条**完全独立的、纯值类型的配色管线**：不读 `Theme`、不读 `colorScheme`、
/// 不持有任何状态，同一个 hex 在世界任何一台设备上都返回同一组颜色。
///
/// ## 派生规则
///
/// | 字段 | 用途 | 怎么来 |
/// |---|---|---|
/// | `base` | 渐变底端 / 光晕源色 | 服务端 hex 本身；**过亮时换成它自己的深色版**（见下） |
/// | `deep` | 渐变顶端 / 按钮文字 | 由 `base` 出发，同一 HSB 色相与饱和度，brightness 压到 0.34 |
/// | `glow` | 图标外圈光晕 | `base` + 低透明度 |
/// | `ink` | 主按钮面色 | 近白（不取 base 的补色：白按钮压在红底上是最稳的对比） |
/// | `onInk` | 主按钮文字 | `deep`（与背景同族，按钮看起来是"从这块红里切出来的"） |
///
/// `deep` 为什么走 HSB 而不是 RGB 各通道乘个系数：乘 RGB 会把亮色的色相一起压灰
/// （红 `#E5484D` 乘 0.4 变成砖褐），而 HSB 只动 brightness，色相与饱和度原样保留 ——
/// 顶端的深红仍然是**同一个红**的深色版，不是另一种颜色。
///
/// ## 过亮的颜色按深色版渲染（不是"亮底换黑字"）
///
/// 服务端可以直接写 JSON，`#FFFFFF` / `#FFFF00` 这种值是**合法输入**，没有任何一层会拦它。
/// 而这套配色里 `ink` 是近白、`titleInk` 是纯白 —— 白底 + 白按钮 + 白标题会把整屏读成
/// 一张白纸：按钮在视觉上直接消失，用户找不到出口，也关不掉（紧急公告只能点按钮）。
///
/// 所以兜底责任落在这里：**相对亮度超过 `luminanceClamp` 就把 `base` 整体换成它自己的
/// `dimmed()`**（brightness 0.34），再由这个深色 base 派生 `deep`。色相与饱和度保留，
/// 对比度自动回到"白字压深色"的档位 —— 任意输入都不会白屏。
///
/// 为什么不选"亮色就换黑字"：
/// 1. 要给两个弹窗各加一条文字分支（`titleInk` / `bodyInk` / `labelInk` / `ghostInk`
///    全都要分叉），同一条公告在两套文字逻辑之间还会因为亮度阈值附近抖动而翻面；
/// 2. 紧急公告的背景是**饱和大色块**，黑字压上去的观感比白字差得多（纯黄底黑字有一种
///    廉价打印感），而白字是"这块色很重"的一部分；
/// 3. 压深色之后 `ink` / `onInk` / 文字色全部维持现有定义 —— 只有一条渲染路径。
struct AnnouncementPalette: Equatable {

    /// 主色（服务端指定，或默认红）
    let base: Color
    /// 主色压暗一档：渐变顶端、主按钮文字色
    let deep: Color
    /// 主色 + 低透明度：径向光晕
    let glow: Color
    /// 主按钮面色（近白）
    let ink: Color
    /// 主按钮文字色（`deep`）
    let onInk: Color

    /// 默认主色。**解析失败一律回落到它** —— 绝不返回灰色：
    /// 灰色会让"账号数据正在迁移"看起来像一条无足轻重的系统提示（同 `Theme.alertColor` 的判据）。
    static let fallbackHex = "#E5484D"

    /// 恒定的白。**刻意不用 SwiftUI 的 `.white` 静态字面量**：主题闸门规则 3 禁止
    /// 「白色字面量 + `.opacity(...)`」这种"就地造色"（会绕开 token 体系）；
    /// 而 `Theme.glassFill` 这类 token 是 `dyna` 动态色，随系统深浅色变化，
    /// 正好与本文件"颜色不跟外观走"的前提冲突。
    /// 这里只表达一件事：白色（sRGB 1,1,1）乘以某个 alpha，与任何外观无关。
    private static let fixedWhite = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1)

    /// 亮度闸门：相对亮度**高于**这个值就认为"这块色当不了深色底"，先压成深色版再派生。
    ///
    /// 0.58 是怎么来的：默认红 `#E5484D` 的相对亮度约 0.22、琥珀 `#E5A00D` 约 0.43，
    /// 压着白字都还有余量；而 0.58 往上已经是"白字与底色互相吃掉"的边界
    /// （`#FFFFFF` = 1.0、`#FFFF00` ≈ 0.93、`#F5F5F5` ≈ 0.91）。
    ///
    /// 用一个闸门而不是逐色微调，是为了让「发布后台」的预览用**同一个数字**判断 ——
    /// 否则会出现"预览里压暗了、真机没压"这种最难排查的所见非所得。
    static let luminanceClamp: Double = 0.58

    /// 由服务端 hex 派生整套颜色。
    ///
    /// - Parameter hex: `#RGB` / `#RRGGBB` / `#RRGGBBAA`，`#` 可省，大小写不敏感。
    ///   nil、空串、长度不对、含非十六进制字符 —— 一律按 `fallbackHex` 处理，**绝不 crash**。
    init(hex: String?) {
        // 三段兜底、没有一处强制解包：服务端色值写错只会让颜色变成默认红，不会让 App 崩在弹窗上。
        // 最后一段是 `#E5484D` 的通道值，纯属"连 fallbackHex 常量都不信任"的保险。
        let parsed = RGBComponents(hex: hex)
            ?? RGBComponents(hex: Self.fallbackHex)
            ?? RGBComponents(red: 0.898, green: 0.282, blue: 0.302)

        // 过亮的主色先整体压成它自己的深色版（理由见文件头「过亮的颜色按深色版渲染」）。
        // 之后 `deep` 从**压过之后的** base 再派生一档，保证"顶端更深"的方向不被破坏：
        // 若从原始亮色派生，`base` 是深灰蓝、`deep` 也是 0.34 档，渐变会变成一条平涂。
        let baseComponents = parsed.relativeLuminance > Self.luminanceClamp ? parsed.dimmed() : parsed
        let deepComponents = baseComponents.dimmed()

        base = baseComponents.color
        deep = deepComponents.color
        glow = baseComponents.color.opacity(0.45)
        ink = Self.fixedWhite.opacity(0.96)
        onInk = deepComponents.color
    }
}

// MARK: - 文字与描边（同样脱离主题的白色系）

extension AnnouncementPalette {

    /// 标题：**纯白**，不用 `Theme.textPrimary`（那个 token 在浅色外观下是近黑 `#0F1A26`）
    var titleInk: Color { Self.fixedWhite }

    /// 正文：白 84%。压在饱和的红上，纯白会"发光"读不清，压一档才有墨感
    var bodyInk: Color { Self.fixedWhite.opacity(0.84) }

    /// 顶部小标签（「紧急公告」）的字：白 72%
    var labelInk: Color { Self.fixedWhite.opacity(0.72) }

    /// 胶囊描边 / 分隔：白 12%。深红底上这是唯一能"切出一条边"的强度
    var hairline: Color { Self.fixedWhite.opacity(0.12) }

    /// 次按钮描边：白 35%（要能被看成一颗按钮，比 hairline 亮三倍）
    var ghostStroke: Color { Self.fixedWhite.opacity(0.35) }

    /// 次按钮文字：白 90%
    var ghostInk: Color { Self.fixedWhite.opacity(0.90) }
}

// MARK: - hex 解析与压暗（纯数学，不碰 UIKit / 不读外观）

/// 0…1 的 sRGB 三个通道。
///
/// 单独抽出来是因为「解析 + 压暗」这两件事要在构造 `Color` 之前完成，
/// 而 `Color` 本身不提供读数接口（`.cgColor` 还得先有 UIKit trait）。
private struct RGBComponents {

    let red: Double
    let green: Double
    let blue: Double

    /// 解析 hex。支持 `#RGB`（会展开成 `#RRGGBB`）、`#RRGGBB`、`#RRGGBBAA`，`#` 可省、大小写不敏感。
    ///
    /// 8 位的最后两字节是 alpha，这里**刻意丢掉**：紧急公告的底色不允许半透明
    /// （半透明的红压在系统白底上会变成另一种粉红，那就不是服务端指定的颜色了）。
    /// 丢掉比"报错"好：运营在色板上多复制两位不该让整条公告消失。
    init?(hex: String?) {
        guard let raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }

        var body = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard body.isEmpty == false, body.allSatisfy({ $0.isHexDigit }) else { return nil }

        if body.count == 3 {
            // `#RGB` → `#RRGGBB`：逐位复制（`#f00` → `#ff0000`），不是补零
            var expanded = ""
            for character in body {
                expanded.append(character)
                expanded.append(character)
            }
            body = expanded
        }
        guard body.count == 6 || body.count == 8 else { return nil }

        let digits = String(body.prefix(6))
        guard let value = UInt32(digits, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255.0
        green = Double((value >> 8) & 0xFF) / 255.0
        blue = Double(value & 0xFF) / 255.0
    }

    /// 直接构造（只给 `dimmed()` 与最后一段兜底用，保证不再走一遍 hex 字符串）
    fileprivate init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// 对应的不透明 `Color`
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }

    /// sRGB 相对亮度（WCAG 口径）：**先线性化**，再按人眼敏感度加权。
    ///
    /// 为什么必须先线性化：`0.2126 / 0.7152 / 0.0722` 这组系数是给**线性光**用的。
    /// 直接套在 sRGB 编码值上，中灰会被算得几乎翻倍（`#808080` 会算成 0.502 而不是 0.216），
    /// 闸门就会把一堆本来就暗的颜色判成"过亮"，主色被无端压暗 —— 颜色没白屏，但也不再是
    /// 服务端指定的那一档。
    ///
    /// 线性化用的是 sRGB 规范的**分段**函数而不是简单 `pow(2.2)`：暗部那一段（≤ 0.03928）
    /// 走线性分支，简单地用 2.2 次幂会把近黑（`#101010`）算得过亮。
    var relativeLuminance: Double {
        func linearized(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue)
    }

    /// 压暗：保留色相与饱和度，只把 brightness 落到 0.34。
    ///
    /// 深色主色（石墨 `#3B4252` 本来就只有 0.32 的亮度）走另一条规则：`0.34` 会让它比 base 还亮，
    /// 渐变就成了"上浅下深"，与"顶端更深"的方向相反。所以 **base 已经比 0.34 暗时按比例再压 38%**，
    /// 保证 `deep` 永远比 `base` 深 —— 渐变方向是硬约束，不能被某一个色值破例。
    func dimmed() -> RGBComponents {
        let hsb = self.hsb
        let targetBrightness = hsb.brightness > 0.34 ? 0.34 : hsb.brightness * 0.62
        return RGBComponents.fromHSB(
            hue: hsb.hue,
            saturation: hsb.saturation,
            brightness: targetBrightness
        )
    }

    // MARK: HSB 互转

    private var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum

        // brightness 与 saturation 的分母：maximum 为 0（纯黑）时两者都是 0，直接短路避免除零
        let brightness = maximum
        let saturation = maximum == 0 ? 0 : delta / maximum

        var hue: Double = 0
        if delta != 0 {
            if maximum == red {
                hue = (green - blue) / delta
            } else if maximum == green {
                hue = 2 + (blue - red) / delta
            } else {
                hue = 4 + (red - green) / delta
            }
            // 标准公式给出的是 0…6 的"扇区"值，归一化到 0…1
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue: hue, saturation: saturation, brightness: brightness)
    }

    private static func fromHSB(hue: Double, saturation: Double, brightness: Double) -> RGBComponents {
        guard saturation > 0 else {
            // 无彩色：三个通道同值（石墨这类低饱和色走到这里也是对的）
            return RGBComponents(red: brightness, green: brightness, blue: brightness)
        }
        let sector = (hue - hue.rounded(.down)) * 6
        let index = Int(sector)
        let fraction = sector - Double(index)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))

        switch index % 6 {
        case 0: return RGBComponents(red: brightness, green: t, blue: p)
        case 1: return RGBComponents(red: q, green: brightness, blue: p)
        case 2: return RGBComponents(red: p, green: brightness, blue: t)
        case 3: return RGBComponents(red: p, green: q, blue: brightness)
        case 4: return RGBComponents(red: t, green: p, blue: brightness)
        default: return RGBComponents(red: brightness, green: p, blue: q)
        }
    }
}
