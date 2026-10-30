import Foundation

/// 页面加载状态。
///
/// 刻意不用 `Result`：`Result` 没有「加载中」也没有「一条数据都没取过」，
/// 而这两个状态恰好决定了「显示骨架」还是「显示错误态」。
enum LoadState<Value> {
    /// 还没开始请求（首屏第一帧）
    case idle
    /// 请求进行中
    case loading
    /// 有数据（可能是缓存 / 上一次的结果）
    case loaded(Value)
    /// 失败且**没有任何可展示的内容**
    case failed(APIError)

    var value: Value? {
        switch self {
        case .loaded(let value):
            return value
        default:
            return nil
        }
    }

    var isLoading: Bool {
        switch self {
        case .loading:
            return true
        default:
            return false
        }
    }

    var error: APIError? {
        switch self {
        case .failed(let error):
            return error
        default:
            return nil
        }
    }

    /// 已经有内容了 —— 失败时可以继续展示旧内容，只弹 toast（PRD §7 硬要求）
    var hasContent: Bool {
        switch self {
        case .loaded(_):
            return true
        default:
            return false
        }
    }
}
