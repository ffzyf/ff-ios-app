import SwiftUI
import Combine

/// 全局轻提示 Store（B 批次从 `AppModel` 拆出）。
///
/// 为什么独立：toast 是「刷新失败 / 复制成功」这类**瞬时反馈**，与 `AppModel` 的
/// feed / brief 数据毫无关系。拆出来之后，`@Published` 的全局订阅点从 `AppModel` 移到这里，
/// 只有真正订阅 `ToastStore` 的视图（ToastView）才会在 toast 变化时重算 `body`，
/// 不再连累所有 `@EnvironmentObject model` 的页面（性能点 B3.3：toast 变更触发的 body 重算
/// 从「所有 model 页面」收敛到「仅 ToastView」）。
@MainActor
final class ToastStore: ObservableObject {
    /// 单例：视图与 `AppModel` 都通过 `ToastStore.shared` 读写，状态只有一份。
    static let shared = ToastStore()

    @Published private(set) var message: String?
    private var clearTask: Task<Void, Never>?

    private init() {}

    /// 弹一条 toast，2.5s 后自动清零（PRD §5.2）。
    ///
    /// 先取消旧任务：否则旧任务会按自己的节奏把新 toast 清掉。
    /// 清理前比对文案 —— 已换一条或已被清空就不动手（避免误清刚弹出的新 toast）。
    func show(_ message: String) {
        clearTask?.cancel()
        self.message = message
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            guard let self = self else { return }
            if self.message == message {
                self.message = nil
            }
        }
    }

    /// 立即清空（一般不用，留给需要时主动收起）。
    func dismiss() {
        clearTask?.cancel()
        clearTask = nil
        message = nil
    }
}
