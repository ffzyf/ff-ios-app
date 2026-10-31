import SwiftUI

/// 眉题（设计报告 §2 R7 / §5 新组件）。
///
/// 职责任务只有一句话：说清"这是什么栏目"，然后闭嘴。所以它比正文小、比正文宽、
/// 用最淡的一档色 —— 读者扫过时它不抢注意力，但少了它，每块内容都会显得"没有出处"。
///
/// `color` 可覆写的原因：压在轨迹卡/天空这类自带底色的卡上时，
/// `textTertiary` 是照着页面底色挑的，卡上要用这张卡自己的淡色 token（如 `trackTextDim`）。
struct Eyebrow: View {
    let text: String
    /// 前置圆点（简报卡「● 日出」那种）。
    ///
    /// 刻意只画点不画线：一个 5pt 的点就够标记，多一条线就变成"列表项"。
    var showsDot: Bool = false
    /// 默认 `textTertiary`：页面上最淡的一档，眉题不该和元信息争同一级
    var color: Color = Theme.textTertiary

    var body: some View {
        HStack(spacing: 5) {
            if showsDot {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }
            Text(text)
                .font(Typography.eyebrow)
                .tracking(Typography.trackingEyebrow)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}
