import CoreGraphics

/// Widget 画布的字号缩放（设计文档 §5.2）。
///
/// 为什么需要它：三张卡的全部字号都是按 **158pt 见方**（`.systemSmall` 的 iPhone 画布）调的。
/// iPad 的小号画布约 170pt、中号约 364×170 —— 四周各多出 12pt，卡不会坏，但字会显得偏小、
/// 边会显得偏空。7.6% 的差值是"可做可不做"的分界，所以做成**可选增量**：
/// `minSide = 158` 时比例恒为 1.0，iPhone 逐像素不变。
///
/// 三条纪律（漏一条就是一轮 CI 或一次观感回归）：
/// 1. **纯函数**：不读 `UIScreen`、不读 `widgetFamily`、不持有状态。Widget 进程里
///    `UIScreen.main.bounds` 返回的是**屏幕**而不是画布，iPad 竖屏会算出 1024/158 ≈ 6.5 倍；
///    而 `widgetFamily` 在 iPhone 与 iPad 上完全一样，区分不了设备。画布尺寸是唯一可用的量。
/// 2. **上限 1.15**：再大就会把 `.systemMedium` 的两行正文挤掉第三行（`bodyLineLimit` 是硬约束）。
/// 3. **只缩放字号，一律不缩放几何**：padding / 弧高 / 节点直径全部按 158 配平过，
///    缩放会让弧压字；170 画布多出的 12pt 由 `frame(maxWidth: .infinity)` 的余量吸收。
enum WidgetCanvas {

    /// 158 是现有全部字号的调校基准（`RedstoneMetric` 文件头、`BriefMetrics` 尺寸注释都写着这个数）
    static let referenceMinSide: CGFloat = 158

    /// 字号缩放上限
    static let maxTextScale: CGFloat = 1.15

    /// 画布短边 → 字号比例。
    ///
    /// 用 `min(width, height)` 而不是 `width`：`.systemMedium` 是 338×158（iPad 364×170），
    /// 拿宽度算会得到 338/158 ≈ 2.14 再被 clamp 到 1.15 —— iPhone 上所有 medium 档的字号
    /// 一次跳 15%，肉眼立刻可见。短边在两档里都等于 158，才是真正的"画布尺度"。
    ///
    /// `minSide <= 1`（首帧 `.zero`、布局异常）返回 1：降级到今天的字号，绝不放大也绝不缩小。
    static func textScale(minSide: CGFloat) -> CGFloat {
        guard minSide > 1 else { return 1 }
        let raw = minSide / referenceMinSide
        return min(max(raw, 1), maxTextScale)
    }
}
