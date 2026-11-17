import SwiftUI

/// 三个 Intent 共用的**纯文案工具**（无状态、无 IO，便于将来单测）。
enum IntentCopy {

    /// Siri 念白的字数预算。
    ///
    /// 80 字是"一口气能听完"的上限；再长系统会在句子中间硬切，
    /// 听感比主动少念一句差得多。
    static let spokenLimit = 80

    /// 按字数预算选一档文案。
    ///
    /// `candidates` 的**顺序即优先级**：每一档是"一组句子"，从第一档开始试，
    /// 第一档拼起来不超限就用它 —— 所以"丢什么、按什么顺序丢"全部表达在调用点，
    /// 本函数只管数长度。这样简报（丢降雨 → 丢天气 → 丢宜忌）和红石
    /// （丢倍率 → 只留日期与首个时刻）可以共用同一套预算逻辑，不用各写一份。
    ///
    /// 全部超限时返回**最后一档**：本函数不比较各档长度、只取 `candidates.last`，
    /// 所以**调用点必须按"由长到短"排列候选**（这也是"降级"的含义所在）。
    /// 宁可念长一点，也不能念半句。
    static func fit(_ candidates: [[String?]], limit: Int = IntentCopy.spokenLimit) -> String {
        for candidate in candidates {
            let text = candidate.compactMap { $0 }.joined()
            if text.count <= limit { return text }
        }
        return candidates.last?.compactMap { $0 }.joined() ?? ""
    }
}

/// 用户在 Siri 说完之前划走卡片时的极简占位。
///
/// 刻意与错误视图区分开：没有"失败了"的措辞、没有重试暗示 ——
/// 用户是主动取消的，听到「站点连不上」属于把用户的动作说成了故障。
struct IntentCancelledSnippet: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.wave")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("已取消")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
