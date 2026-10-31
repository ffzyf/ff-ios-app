import SwiftUI
import WidgetKit

// MARK: - 简报卡自己的度量
//
// 为什么单独一个 `BriefMetrics`：Widget target 只编译 `Sources/Widget` + `Sources/Shared`，
// **看不到** `DesignSystem/Typography` / `Radius` / `Spacing`。所以这张卡的每一档字号、
// 每一个间距都必须写在 Widget 自己家里；散在 View 里的话，下次想整体调一档就得满文件找数字。
//
// 尺寸只有两种：中号 338×158、小号 158×158。小号整体收一档（字号不动、行数与内边距收），
// 因为小号是正方形，横向只有 158pt —— 内边距留着中号的 14pt 会让正文只剩 130pt 宽。
enum BriefMetrics {

    // MARK: 字号

    /// 11pt semibold：顶行日期 / 星期（eyebrow 层）
    static let eyebrow = Font.system(size: 11, weight: .semibold)
    /// 9pt semibold：右上角「简报」胶囊 —— 它只是标记，不能和标题抢字重
    static let tag = Font.system(size: 9, weight: .semibold)
    /// 20pt bold：卡名「每日简报」。一句话的卡不需要 28pt，但必须明显高于正文
    static let title = Font.system(size: 20, weight: .bold)
    /// 13pt：正文首句（中号 2 行 / 小号 1 行）
    static let body = Font.system(size: 13, weight: .regular)
    /// 正文行距：中文字面高、行距为 0 会糊成一团
    static let bodyLineSpacing: CGFloat = 2
    /// 11pt：底部注脚（宜忌）
    static let footnote = Font.system(size: 11, weight: .medium)
    /// 11pt 等宽：底部右端的日出 / 日落（数字必须对齐，否则两帧之间会左右跳）
    static let footnoteTime = Font.system(size: 11, weight: .medium, design: .monospaced)

    // MARK: 内边距

    /// 中号左右内边距
    static let mediumSidePadding: CGFloat = 14
    /// 中号上下内边距（158pt 高，去掉 24pt 还剩 134pt 给四行）
    static let mediumVerticalPadding: CGFloat = 12
    /// 小号左右内边距（方形画布，收到 11pt 免得正文被圆角切）
    static let smallSidePadding: CGFloat = 11
    /// 小号上下内边距
    static let smallVerticalPadding: CGFloat = 12

    // MARK: 行距

    /// 顶行 → 标题
    static let titleGap: CGFloat = 6
    /// 标题 → 正文
    static let bodyGap: CGFloat = 4
    /// 轨迹 → 底部注脚
    static let footerGap: CGFloat = 6

    // MARK: 轨迹

    /// 普通刻度点直径（2pt —— 比 1pt 的线"有质感"，又不至于变成一串珠子）
    static let dotDiameter: CGFloat = 2
    /// 「今天过了多少」那颗光点直径（5pt：明显大于刻度点，但小于任何字号）
    static let markerDiameter: CGFloat = 5
    /// 光点外面那圈柔光的直径。**不用模糊滤镜** —— 模糊在 Widget 里每帧重绘太贵，
    /// 柔度由 `RadialGradient` 的两档不透明度伪造（见 `BriefTrack`）。
    static let markerHaloDiameter: CGFloat = 26
    /// 轨迹占的高度（含光点溢出，不写死会被上层 VStack 压扁）
    static let trackHeight: CGFloat = 12
    /// 中号刻度点数量
    static let mediumDotCount: Int = 24
    /// 小号刻度点数量（画布只有 136pt 可用宽，24 颗会挤成一条实线）
    static let smallDotCount: Int = 20

    // MARK: 胶囊

    /// 胶囊左右内边距
    static let tagHorizontalPadding: CGFloat = 7
    /// 胶囊上下内边距
    static let tagVerticalPadding: CGFloat = 2
    /// 胶囊描边线宽
    static let tagStrokeWidth: CGFloat = 0.7

    // MARK: 纸面光晕

    /// 中心那层主题色径向光的半径（pt）。只做面，不承载文字
    static let canvasGlowRadius: CGFloat = 132
    /// 中心径向光的峰值不透明度 —— 只有 0.10：纸面上一点"被打亮"的感觉，不是一块绿斑
    static let canvasGlowAlpha: Double = 0.10

    // MARK: 按尺寸取档

    /// 左右内边距
    static func sidePadding(_ family: WidgetFamily) -> CGFloat {
        return family == .systemSmall ? smallSidePadding : mediumSidePadding
    }

    /// 上下内边距
    static func verticalPadding(_ family: WidgetFamily) -> CGFloat {
        return family == .systemSmall ? smallVerticalPadding : mediumVerticalPadding
    }

    /// 刻度点数量
    static func dotCount(_ family: WidgetFamily) -> Int {
        return family == .systemSmall ? smallDotCount : mediumDotCount
    }

    /// 正文行数：小号只放得下 1 行（2 行会把轨迹顶出画布）
    static func bodyLineLimit(_ family: WidgetFamily) -> Int {
        return family == .systemSmall ? 1 : 2
    }
}

// MARK: - 卡面

/// 每日简报的卡面 —— 「纸面 + 一条轨道」，没有插画、没有天空。
///
/// 用户原话："现在我这里有两个天际线的效果小组件……要不然两个一模一样的小组件看着有点烦"。
/// 上一版这张卡是"天空渐变 + 地平线弧 + 太阳"，和天光组件（`SkyLightFace`）摆在同一屏上
/// 就是两块几乎一样的图。天光那套是用户自己挑的参考，保持不动；**这张卡换语言**：
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │ 10月31日 周六                     简报   │ ← 11pt semibold + 9pt 胶囊
/// │                                          │
/// │ 每日简报                                 │ ← 20pt bold
/// │ 今天的第一句正文，最多 2 行，超出截断……    │ ← 13pt，行距 2
/// │                                          │
/// │  · · · · · · · · ● · · · · · · · · ·     │ ← 24 颗 2pt 刻度 + 1 颗 5pt 光点
/// │ 宜 打猎          忌 店铺开业   06:44 17:33│ ← 11pt，两端对齐
/// └─────────────────────────────────────────┘
/// ```
///
/// 三条不能破的规矩：
/// 1. **底色只有两个停靠点**，取自 `Theme.sky(.night)` 的 `top` / `ground` ——
///    这一档本来就是近黑的深蓝，压得住白字，也永远不会"变成一张天空图"。
///    中间再叠一层 `Theme.lime` 的极淡径向光（α=0.10）给卡片一个"中心"，`lime` 只做面。
/// 2. **没有的字段整行不画**：宜忌为空就不画左下、日出算不出就不画右下、
///    正文为空就明说"今天还没有简报"，绝不编内容。
/// 3. **零模糊滤镜、零颜色字面量**：柔光用 `RadialGradient`，颜色全部走 `Theme` token。
struct BriefFace: View {

    @Environment(\.widgetFamily) private var family

    private let entry: BriefEntry

    init(entry: BriefEntry) {
        self.entry = entry
    }

    private var isSmall: Bool {
        return family == .systemSmall
    }

    /// 纸面基色。固定取 `.night` 这一档（不随 `entry.date` 换档）：
    /// 这张卡讲的是"今天"，不画"此刻"，底色该是稳定的一张纸，而不是会随时间变色的天。
    private var paper: Theme.SkyColors {
        return Theme.sky(.night)
    }

    var body: some View {
        content
            // 整卡可点：落到 `skyapp://brief`（深链契约见 `WidgetDeepLink`）
            .widgetURL(WidgetDeepLink.brief)
            .containerBackground(for: .widget) {
                BriefCanvas()
            }
    }

    // MARK: - 版式骨架

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            titleRow
                .padding(.top, BriefMetrics.titleGap)

            bodyRow
                .padding(.top, BriefMetrics.bodyGap)

            // 唯一的弹性留白：把小号也"钉"成上文字下轨迹的两段式，
            // 其余间距全是固定 PT —— 正文多少都不会把轨迹挤出画布。
            Spacer(minLength: 0)

            BriefTrack(progress: dayProgress,
                       dotCount: BriefMetrics.dotCount(family),
                       ink: paper)

            if hasFooter {
                footer
                    .padding(.top, BriefMetrics.footerGap)
            }
        }
        .padding(.horizontal, BriefMetrics.sidePadding(family))
        .padding(.vertical, BriefMetrics.verticalPadding(family))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - 顶行：日期 · 星期 · 胶囊

    private var header: some View {
        HStack(spacing: 6) {
            Text(entry.dateText)
                .font(BriefMetrics.eyebrow)
                .foregroundStyle(paper.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if !entry.weekdayText.isEmpty {
                Text(entry.weekdayText)
                    .font(BriefMetrics.eyebrow)
                    .foregroundStyle(paper.inkDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // 小号不放胶囊：158pt 宽，胶囊会和"10月31日 周六"抢位置
            if !isSmall {
                Text("简报")
                    .font(BriefMetrics.tag)
                    .foregroundStyle(paper.ink)
                    .padding(.horizontal, BriefMetrics.tagHorizontalPadding)
                    .padding(.vertical, BriefMetrics.tagVerticalPadding)
                    .background {
                        // 面用天色 token 的半透白（`ink` 压一档），不是新造颜色
                        Capsule().fill(paper.ink.opacity(0.10))
                    }
                    .overlay {
                        Capsule().strokeBorder(paper.ink.opacity(0.28),
                                               lineWidth: BriefMetrics.tagStrokeWidth)
                    }
            }
        }
    }

    // MARK: - 标题

    private var titleRow: some View {
        Text("每日简报")
            .font(BriefMetrics.title)
            .foregroundStyle(paper.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 正文首句

    @ViewBuilder
    private var bodyRow: some View {
        if let text = bodyText {
            Text(text)
                .font(BriefMetrics.body)
                .foregroundStyle(paper.inkDim)
                .lineLimit(BriefMetrics.bodyLineLimit(family))
                .lineSpacing(BriefMetrics.bodyLineSpacing)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // 早上简报还没生成是**正常业务状态**，不是错误：说清楚"还没有"，不吓人、不编内容
            Text("今天还没有简报")
                .font(BriefMetrics.body)
                .foregroundStyle(paper.inkDim)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 今天的第一句。
    ///
    /// 服务端 `body` 不是纯正文，而是带 emoji 小标题的分段文本（`🗓 每日简报` /
    /// `🎁 距离生日还有 253 天` / 正文若干段）。直接取第一行会把"栏目头"当正文显示，
    /// 所以先按行拆开、滤掉栏目头，剩下的第一行才是"今天的第一句"。
    /// 判据与 App 内 `TodayBriefTrackCard.bodyParts` 同一套（emoji 开头 / 过短无句读）。
    private var bodyText: String? {
        let rows = entry.paragraphs
            .joined(separator: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !BriefFace.isHeading($0) }
        return rows.first
    }

    /// 判断某一行是不是"栏目头"：emoji 开头，或短到不可能是一句话
    private static func isHeading(_ line: String) -> Bool {
        if let scalar = line.unicodeScalars.first, scalar.properties.isEmojiPresentation {
            return true
        }
        let hasPunctuation = line.contains("，") || line.contains("。")
            || line.contains("！") || line.contains("？") || line.contains("、")
        return line.count <= 6 && !hasPunctuation
    }

    // MARK: - 底部：宜忌 + 日出日落

    /// 底部这一行有没有内容。两头都空时整行不画（比留一行空白诚实）。
    private var hasFooter: Bool {
        // 小号不放这一行：正方形画布上它会和轨迹挤成一团
        guard !isSmall else { return false }
        if entry.ritualText != nil { return true }
        let sun = entry.sunTexts()
        return sun.rise != nil || sun.set != nil
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let ritual = entry.ritualText {
                Text(ritual)
                    .font(BriefMetrics.footnote)
                    .foregroundStyle(paper.inkDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
            }

            Spacer(minLength: 4)

            // 右端 = 日出 + 日落，用主字色（`ink`）压在深纸上：它们是"时刻"，
            // 比左边的历书注脚更重要，所以不压暗。
            if let rise = sunTexts.rise {
                Text(rise)
                    .font(BriefMetrics.footnoteTime)
                    .foregroundStyle(paper.ink)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            if let set = sunTexts.set {
                Text(set)
                    .font(BriefMetrics.footnoteTime)
                    .foregroundStyle(paper.ink)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }

    /// 日出 / 日落文案（服务端值优先，缺了回落 `SunClock`，两头都没有就是 nil）
    private var sunTexts: (rise: String?, set: String?) {
        return entry.sunTexts()
    }

    // MARK: - 轨迹进度

    /// 今天已经过去的比例（00:00 → 0，24:00 → 1）。
    ///
    /// 用 `entry.date` 而不是 `Date()`：entry 的 `date` 就是"这一帧被渲染的时刻"，
    /// 它是 Timeline 预渲染的；渲染时现取 `Date()` 会让光点位置和卡片的时间错位
    /// （典型症状：光点比桌面上其它小组件慢一拍）。
    ///
    /// 分母取 `startOfDay(明天) - startOfDay(今天)` 而不是写死 86400：
    /// 夏令时切换那天一天不是 24 小时，写死会让光点在凌晨 3 点就跑到 25%。
    private var dayProgress: Double {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: entry.date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let passed = entry.date.timeIntervalSince(start)
        return min(max(passed / total, 0), 1)
    }
}

// MARK: - 轨迹

/// 一条横贯卡宽的点线 + 一颗"今天过了多少"的光点。
///
/// 参考图里那条虚线轨迹是整张卡唯一的图形元素 —— 它承担"进度"，不承担装饰。
/// 所以这里没有任何曲线、没有任何插画：一排 **2pt 圆点** 等距铺满可用宽度，
/// 其中一颗 **5pt 光点** 按 `progress` 落在两点之间（不是"落在第 N 颗点上"，
/// 那样一天只跳 24 次，看不出时间在走）。
///
/// 圆点间距由 `GeometryReader` 量出来的真实宽度决定（`span / (count - 1)`），
/// 中号 310pt 宽 ≈ 13pt 一颗、小号 136pt 宽 ≈ 7pt 一颗 —— 同一份代码两种密度都不会挤。
private struct BriefTrack: View {

    /// 0…1：今天已过的比例
    let progress: Double
    /// 刻度点数量（中号 24 / 小号 20）
    let dotCount: Int
    /// 纸面色组（只取 `ink`，本组件自己不再造色）
    let ink: Theme.SkyColors

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = BriefMetrics.trackHeight
            // 两端各留一个点的半径：第一颗和最后一颗都不会被画布边缘切掉一半
            let inset = BriefMetrics.dotDiameter / 2
            let span = max(width - BriefMetrics.dotDiameter, 0)
            let clamped = min(max(progress, 0), 1)

            ZStack(alignment: .topLeading) {
                ForEach(0..<dotCount, id: \.self) { index in
                    Circle()
                        .fill(dotFill(at: index))
                        .frame(width: BriefMetrics.dotDiameter,
                               height: BriefMetrics.dotDiameter)
                        .position(x: inset + span * fraction(of: index),
                                  y: height / 2)
                }

                // 柔光：一团径向渐变，中心 α 高、外圈 α 归零。
                // **零模糊滤镜** —— Widget 每帧重绘，模糊是这里最贵的一笔。
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.lime.opacity(0.42), Theme.lime.opacity(0.0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: BriefMetrics.markerHaloDiameter / 2
                        )
                    )
                    .frame(width: BriefMetrics.markerHaloDiameter,
                           height: BriefMetrics.markerHaloDiameter)
                    .position(x: inset + span * clamped, y: height / 2)

                // 光点本体：品牌青柠**当面**（lime 只做面，不做字色）
                Circle()
                    .fill(Theme.lime)
                    .frame(width: BriefMetrics.markerDiameter,
                           height: BriefMetrics.markerDiameter)
                    .position(x: inset + span * clamped, y: height / 2)
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .frame(height: BriefMetrics.trackHeight)
    }

    /// 第 `index` 颗点在 0…1 上的位置
    private func fraction(of index: Int) -> Double {
        guard dotCount > 1 else { return 0 }
        return Double(index) / Double(dotCount - 1)
    }

    /// 已过的点亮一些、未到的点暗一些 —— 光点两侧因此读得出"前后"。
    /// 两支都是 `Theme.sky(.night).ink` 压不透明度，没有新颜色。
    private func dotFill(at index: Int) -> Color {
        return fraction(of: index) <= progress
            ? ink.ink.opacity(0.55)
            : ink.ink.opacity(0.20)
    }
}

// MARK: - 纸面底色

/// 卡片的底色层。
///
/// 两个停靠点的线性渐变（`Theme.sky(.night)` 的 `top` → `ground`，深蓝近黑），
/// 再叠一层 `Theme.lime` 的极淡径向光（α = 0.10，只在上三分之一处）。
///
/// 为什么不用 `.night` 以外的档：日出、日落那几档的 `top` 是橙红，
/// 铺满 338×158 之后又是"一张天空图"，两张卡摆一起就回到了用户抱怨的那个状态。
/// 纸面必须稳定 —— 时间信息由轨迹上那颗光点承担，而不是由底色承担。
private struct BriefCanvas: View {

    var body: some View {
        ZStack {
            LinearGradient(colors: [paper.top, paper.ground],
                           startPoint: .top,
                           endPoint: .bottom)

            RadialGradient(
                colors: [Theme.lime.opacity(BriefMetrics.canvasGlowAlpha), Theme.lime.opacity(0.0)],
                center: UnitPoint(x: 0.5, y: 0.22),
                startRadius: 0,
                endRadius: BriefMetrics.canvasGlowRadius
            )
        }
    }

    private var paper: Theme.SkyColors {
        return Theme.sky(.night)
    }
}
