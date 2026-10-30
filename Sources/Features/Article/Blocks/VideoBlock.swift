import SwiftUI
import AVKit
import AVFoundation

/// 视频块（PRD §3.3 video 行）：16:9、未播放时深色底 + 中央玻璃播放钮、离开页面自动暂停。
///
/// 三条降级 + 一条结构约束：
/// · 非 https 链接 → 只提示，不发请求（ATS）；
/// · `AVURLAsset.isPlayable == false` → 「这个格式手机放不了。」（当前管线只产 mp4/H.264）；
/// · 探测失败（`try?` 为 nil）按**可播**处理 —— 宁可偶尔多给一次播放器，
///   也不要把能播的片子判成不能播；
/// · 播放器由 `VideoPlaybackCoordinator` 统一持有，本视图只在「轮到我播」时才挂
///   `VideoPlayer`，所以同页永远只有一个视频出声。
struct VideoBlock: View {
    let url: String
    @ObservedObject var playback: VideoPlaybackCoordinator

    @State private var resolvedURL: URL?
    @State private var isUnplayable: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if trimmedURL.isEmpty {
                EmptyView()
            } else if resolvedURL == nil {
                BlockNoticeRow(icon: "exclamationmark.triangle", text: "这个视频的链接不安全，先不播。")
            } else if isUnplayable {
                BlockNoticeRow(icon: "play.slash", text: "这个格式手机放不了。")
            } else if playback.activeURL == resolvedURL, let player = playback.player {
                VideoPlayer(player: player)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.inlineImage, style: .continuous))
            } else {
                posterButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: url) {
            await prepare()
        }
        // 滚出页面就停：否则正文读完、页面已关，声音还在
        .onDisappear {
            playback.stop(resolvedURL)
        }
    }

    /// 未播放态：16:9 深色底 + 中央 56pt 玻璃播放钮（PRD §3.3）
    private var posterButton: some View {
        Button(action: {
            guard let target = resolvedURL else { return }
            Haptics.light()
            playback.play(target)
        }) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    Theme.bgElevated
                }
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(Typography.titleM)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 56, height: 56)
                            .glassSurface(.floating, in: Circle(), interactive: true)
                        Text("点一下播放")
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.inlineImage, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Radius.inlineImage, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 解析与探测

    @MainActor
    private func prepare() async {
        isUnplayable = false
        guard let target = secureURL else {
            resolvedURL = nil
            return
        }
        resolvedURL = target
        // 先探测可播性：不可播时给出降级文案，而不是让用户对着黑屏点半天
        let asset = AVURLAsset(url: target)
        let playable = (try? await asset.load(.isPlayable)) ?? true
        if playable == false {
            isUnplayable = true
        }
    }

    private var trimmedURL: String {
        return url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var secureURL: URL? {
        guard let parsed = URL(string: trimmedURL) else { return nil }
        guard parsed.scheme?.lowercased() == "https" else { return nil }
        return parsed
    }
}
