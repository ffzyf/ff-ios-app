import SwiftUI

/// 桌面小组件的整卡玻璃罩（3.31.0）。
///
/// ## 为什么要它
///
/// 3.30.x 的天光卡是把文字**直接画在天空渐变上**——没有任何玻璃层，所以卡片与系统壁纸
/// 之间只有一条系统给的裁切边。App 里所有卡片都是厚玻璃，桌面这张却像一张贴纸。
/// 这个修饰符把 App 侧的同一套"四向斜面 + 内白外黑双轮廓"（`GlassBevel`）搬过来，
/// 于是同一个视觉语言在 App 与桌面上是连续的。
///
/// ## 只在 `.fullColor` 下加
///
/// 透明（vibrant）/ 着色（accented）模式下，系统会**拿走 `containerBackground` 换成自己的玻璃**：
/// 我们再叠一层，两层半透明边界叠在一起就会发脏；更糟的是 3.8.1 修过的
/// "开了透明之后只能看见字"——那一版正是靠"内容层保留半透明天空"才读得出天光，
/// 多一层实心斜面会把这条退路堵死。所以着色模式下整层关掉，只画系统要求的那些内容。
struct WidgetGlassCasing: ViewModifier {

    /// 是否画（由调用方按 `renderMode` 决定，本文件不读环境 —— 小组件里环境的来源要尽量单一）
    let enabled: Bool

    // MARK: - 强度表（小组件恒深色，不读环境）

    /// 小组件侧的固定强度 —— 对应 App 侧 `Theme.glassBevel*` / `Theme.glassOutline*` 的**深色档**。
    ///
    /// 为什么不直接用 `Theme` 的那六个 token：它们是随系统浅色 / 深色解析的动态色，
    /// 而桌面这张卡的"深"来自**天空渐变本身**（`Theme.sky(phase)` 的七档天色，与系统外观无关）。
    /// 用户开着浅色系统、桌面上却是一张夜间天光卡时，token 会解析成浅色档 ——
    /// 顶部 85% 的白斜面压在深蓝天光上就是一圈白边。所以这里写死，恒按深色给。
    ///
    /// 数值与深色档的差异只有一处：顶部 0.50 → 0.42 —— 小组件四周紧贴系统圆角，
    /// 50% 压在壁纸上会显得"镶了框"；0.42 在缩略尺寸（158pt 高）上刚好。
    ///
    /// 写法用 `Color(.sRGB, white:opacity:)` 而不是"白色再叠 opacity"那种就地造色：
    /// 主题闸门第 3 条把后者判违规（那会让浅色主题下的玻璃整块消失），
    /// 而这里的固定强度是**有意的例外**，用一个不触发闸门的构造方式表达，
    /// 既不破规则，也不需要 `lint:allow`。
    private enum Bevel {
        /// 顶部内斜面（最亮，接光）
        static let top = Color(.sRGB, white: 1.0, opacity: 0.42)
        /// 左侧内斜面（顺光侧）
        static let left = Color(.sRGB, white: 1.0, opacity: 0.20)
        /// 右侧内斜面（逆光侧）
        static let right = Color(.sRGB, white: 1.0, opacity: 0.10)
        /// 底缘暗边：没有它整卡贴在壁纸上
        static let bottom = Color(.sRGB, white: 0.0, opacity: 0.10)
        /// 0.5pt 内轮廓
        static let outlineInner = Color(.sRGB, white: 1.0, opacity: 0.26)
        /// 0.5pt 外轮廓
        static let outlineOuter = Color(.sRGB, white: 0.0, opacity: 0.16)
    }

    /// 组装成 `GlassBevel` 要的强度表（`static` 只算一次，15 分钟一帧的重绘不必反复构造）
    private static var palette: GlassBevelPalette {
        GlassBevelPalette(
            top: Bevel.top,
            left: Bevel.left,
            right: Bevel.right,
            bottom: Bevel.bottom,
            outlineInner: Bevel.outlineInner,
            outlineOuter: Bevel.outlineOuter
        )
    }

    // MARK: - 几何

    /// 桌面小组件的视觉圆角。
    ///
    /// **这是估算值**（iOS 桌面小组件约 20~22pt，随设备与尺寸档浮动，系统没有公开常量）。
    /// 内部再 `inset(by:)` 1pt，所以即使估算偏大 1~2pt，画出来的边线也在系统裁切**之内**，
    /// 只会显得略"往里收"，不会露出直角。
    /// 真机上若出现"边线被系统裁掉一半 / 圆角处断开"，把 `edgeInset` 调到 1.5 即可 ——
    /// 那是唯一需要调的旋钮，圆角值不必动。
    private static var cornerRadius: CGFloat { 20 }

    /// 罩子相对卡片边缘的内缩量。1pt 就够：系统裁切半径与我们的估算值之间有半个像素的差，
    /// 内缩 1pt 保证 0.5pt 的外轮廓整根都在可视区内（被裁掉一半的轮廓看起来是"掉色"）。
    private static var edgeInset: CGFloat { 1 }

    /// 内缩之后的圆角矩形。`inset(by:)` 会同步收小圆角，所以视觉半径仍是系统的那个值。
    private var casingShape: some InsettableShape {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .inset(by: Self.edgeInset)
    }

    // MARK: - body

    func body(content: Content) -> some View {
        content
            // `background` 而不是 `overlay`：罩子要**压在天空之上、文字之下**。
            //
            // 层级关系：`containerBackground`（天空渐变）画在整卡最底，`content` 自己的
            // background 栈在它之上、`content` 的文字之下 —— 正好是"光打在玻璃上、
            // 字坐在玻璃里"。若挂成 `.overlay`，顶端那条 42% 的白渐变会盖住上排的阶段名
            // （那行字离顶只有 sidePadding 那么远），浅色墨色下最先糊的就是它。
            .background {
                if enabled {
                    GlassBevel(shape: casingShape, palette: Self.palette)
                }
            }
    }
}
