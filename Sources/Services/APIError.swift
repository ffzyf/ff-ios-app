import Foundation

// MARK: - 错误

/// 网络层错误，归一成 4 个 case（每个 case 都带可直接上屏的中文文案）。
///
/// 刻意不把 `URLError` 的十几种 code 全暴露给 UI：用户不需要知道 `-1009` 和 `-1001` 的区别，
/// 需要的是「一句现象 + 一句出路」（PRD 文案原则）。
enum APIError: Error, Equatable {
    /// 连接失败 / 离线 / 超时
    case network
    /// 解码失败（字段对不上、时间格式异常）
    case decoding
    /// 服务端 4xx / 5xx，带 HTTP 状态码与服务端中文 message
    case server(code: Int, message: String)
    /// 请求被取消（页面销毁 / 快速切 Tab），UI 不应展示
    case cancelled

    /// 可直接上屏的一句话
    var userMessage: String {
        switch self {
        case .network:
            return "网络好像断了一下。"
        case .decoding:
            return "数据格式对不上，先不展示了。"
        case .server(_, let message):
            return message.isEmpty ? "服务器打了个喷嚏。" : message
        case .cancelled:
            return "请求已取消。"
        }
    }

    /// 标题（错误态大标题用）
    var title: String {
        switch self {
        case .network:
            return "网络好像断了一下。"
        case .decoding:
            return "数据没读懂。"
        case .server(let code, _):
            if code == 404 {
                return "这篇文章找不到了。"
            }
            return "服务器打了个喷嚏。"
        case .cancelled:
            return "请求已取消。"
        }
    }

    /// 副文案（第二句：给出路）
    var hint: String {
        switch self {
        case .network:
            return "下拉重试一次，或者待会儿再来。"
        case .decoding:
            return "是我们的问题，不是你。稍后再试。"
        case .server(let code, _):
            if code == 404 {
                return "可能被删了，或者链接不对。"
            }
            return "是我们的问题，不是你。稍后再试。"
        case .cancelled:
            return "换个页面再看看。"
        }
    }

    /// 错误态图标（SF Symbols）
    var icon: String {
        switch self {
        case .network:
            return "wifi.slash"
        case .decoding:
            return "exclamationmark.triangle"
        case .server(let code, _):
            return code == 404 ? "doc.questionmark" : "exclamationmark.triangle"
        case .cancelled:
            return "clock.badge.exclamationmark"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .cancelled:
            return false
        default:
            return true
        }
    }

    var isCancelled: Bool {
        if case .cancelled = self {
            return true
        }
        return false
    }
}

// MARK: - 错误信封

/// 服务端统一的错误形状：`{ ok: false, error: { code, message } }`（设计文档 §3.2）
struct APIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String?
        let message: String?
    }

    let error: Payload?

    /// 从响应体里抽出可上屏的中文；抽不出就给空串，由 `APIError` 兜底文案接管。
    static func message(from data: Data) -> String {
        guard !data.isEmpty else { return "" }
        guard let envelope = try? APIJSON.decoder.decode(APIErrorEnvelope.self, from: data) else {
            return ""
        }
        guard let payload = envelope.error else { return "" }
        guard let message = payload.message else { return "" }
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
