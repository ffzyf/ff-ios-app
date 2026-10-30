import SwiftUI

/// 块流分发器：`switch block` → 对应块视图，块之间统一 `Spacing.blockGap`（20pt）。
///
/// 两条铁律：
/// 1. **8 类块全部有分支**（paragraph / heading / image / video / code / quote / list / divider）；
/// 2. `.unknown` **静默跳过**，不显示占位、不崩 —— 服务端以后加块类型时，
///    老版本 App 只是少画那一块，而不是整页白屏（`Block.init(from:)` 的对应约定）。
///
/// `ForEach` 用 `offset` 作 id：块流是只读快照，index 稳定，块里也没有 id 字段。
///
/// 视频单播：协调器在本视图持有（一个正文流一个），所有 `VideoBlock` 共享它，
/// 所以「同一时刻只有一个视频出声」是结构保证，不靠每个块自己自觉。
struct BlockListView: View {
    let blocks: [Block]

    @StateObject private var playback = VideoPlaybackCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.blockGap) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { entry in
                row(entry.element)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            ParagraphBlock(text: text)
        case .heading(let level, let text):
            HeadingBlock(level: level, text: text)
        case .image(let url, let alt):
            ImageBlock(url: url, alt: alt)
        case .video(let url):
            VideoBlock(url: url, playback: playback)
        case .code(let lang, let text):
            CodeBlockBlock(lang: lang, text: text)
        case .quote(let text):
            QuoteBlock(text: text)
        case .list(let ordered, let items):
            ListBlock(ordered: ordered, items: items)
        case .divider:
            DividerBlock()
        case .unknown:
            // 前向兼容：不认识的块什么都不画（连占位都不留，避免出现空白带）
            EmptyView()
        }
    }
}
