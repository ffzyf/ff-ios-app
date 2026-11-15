import Foundation

/// 预警刷新的**唯一收敛闸门**（R1 · 架构 §1.1-3 / §3.2，QA 用 `refresh-policy.mjs` 镜像）。
///
/// ## 为什么要有这道闸门
/// `SkyRoomView` 是 `fullScreenCover`，每次呈现 `@State` 归零，页面会重新发一发预警。
/// 10 分钟内连续进出 10 次，旧实现就是 10 次请求；而后端 `s-maxage=300`、
/// `qw:warning:*` TTL 300s —— 后面 9 次拿到的都是同一份边缘缓存，纯属浪费。
/// 现在所有入口（进场 / 回前台 / 下拉 / 换城市）都先过 `shouldRefresh`，
/// 10 分钟内只有「进场 1 + 回前台 1」≤ 2 次（AC1-4）。
///
/// ## 两个数字的分工
/// · `pollCheckInterval = 60`：轮询 tick，只是「多久看一眼该不该发」；
/// · `minFetchInterval = 300`：真正两次网络请求之间的最小间隔，
///   与后端 `Cache-Control: s-maxage=300` / `qw:warning:*` TTL 300s 对齐。
/// tick 比窗口短是刻意的：换城市、下拉这些用户显式动作不受窗口限制，
/// 但也不该等到下一次 5 分钟 tick 才被处理。
enum AlertRefreshPolicy {

    /// 轮询检查间隔（秒）：`AlertStore.startPolling()` 的 `Task.sleep` 用它
    static let pollCheckInterval: TimeInterval = 60

    /// 两次请求的最小间隔（秒）：与后端 300 秒缓存同频
    static let minFetchInterval: TimeInterval = 300

    /// 四种刷新入口。
    ///
    /// `force` / `coordinateChanged` 是**用户显式动作**，恒发；
    /// `enter` / `foreground` 是系统触发，受 300 秒窗口约束。
    enum Policy: Equatable, Sendable {
        /// 进入天光页
        case enter
        /// 回到前台
        case foreground
        /// 用户下拉 / 点重试
        case force
        /// 坐标（城市）变了：旧城市的预警必须立刻换掉
        case coordinateChanged
    }

    /// 该不该真的发这一发。
    ///
    /// - Parameters:
    ///   - lastFetchAt: 上一次**真正发出请求**的时刻；nil = 从没发过
    ///   - now: 参照时刻（显式传入，方便 QA 用固定时间序列做镜像）
    ///   - policy: 本次入口
    ///   - coordinateChanged: 额外的坐标变化标记（调用方已经知道换了城市但没换 policy 时用）
    /// - Returns: `true` 才发请求
    static func shouldRefresh(lastFetchAt: Date?,
                              now: Date,
                              policy: Policy,
                              coordinateChanged: Bool = false) -> Bool {
        // 用户显式动作恒 true：下拉就是要立刻看到结果，换城市更是一秒都不能拖
        if policy == .force || policy == .coordinateChanged || coordinateChanged {
            return true
        }

        // 从没成功发过：必须发一次，否则首帧永远停在 loadingFirst
        guard let last = lastFetchAt else {
            return true
        }

        // 其余（进场 / 回前台）按 300 秒窗口收敛。
        // 时钟回拨（now < last）会得到负数，按「还没到窗口」处理 —— 不猜、不补发。
        return now.timeIntervalSince(last) >= minFetchInterval
    }
}
