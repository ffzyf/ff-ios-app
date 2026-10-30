import Foundation
import AVFoundation
import Combine

/// 视频播放协调器：**整页同时只允许一个视频出声**（PRD §3.3 video 行）。
///
/// 为什么必须有一个页面级的对象：`AVPlayer` 挂在每个 `VideoBlock` 自己的 `@State` 里时，
/// 同时播两个视频完全没有约束。这里把「谁在播」收成单一事实来源：
/// 换播之前先 `pause()` 旧的，播放器实例也只留一个，所以「最多一个在播」是结构保证。
@MainActor
final class VideoPlaybackCoordinator: ObservableObject {

    /// 当前占用播放器的视频地址（nil = 没有视频在播）
    @Published private(set) var activeURL: URL?
    /// 当前唯一的播放器实例（由 `VideoPlayer` 持有显示）
    @Published private(set) var player: AVPlayer?

    /// 开始播一个视频：先把旧的停掉再换播放器，保证同一时刻只有一个音轨
    func play(_ url: URL) {
        if activeURL == url, let existing = player {
            existing.play()
            return
        }
        player?.pause()
        let next = AVPlayer(url: url)
        player = next
        activeURL = url
        next.play()
    }

    /// 暂停但保留播放器（页面暂时滚走时用；再滚回来可以接着播）
    func pause() {
        player?.pause()
    }

    /// 彻底释放某个视频：地址对不上就不动，避免 A 块消失时把 B 块正在播的停掉
    func stop(_ url: URL?) {
        guard let url = url, activeURL == url else { return }
        player?.pause()
        player = nil
        activeURL = nil
    }
}
