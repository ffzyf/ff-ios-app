import SwiftUI

/// 光遇版本状态卡的四种呈现（PRD §3.1 四态 / 设计文档 T05）。
///
/// **只 switch 服务端 `status`，绝不自己比较版本号**（设计文档 §3.5）：
/// `SkyAppVersion.previous` 在推送成功后即丢失，拿它判状态会把「有新版本」误判成「已是最新」。
/// 颜色铁律同样来自 PRD §4.1：**绿色只代表「有变化」**，已是最新用中性灰。
enum SkyCardPhase {
    /// A 有新版本
    case newVersion
    /// B 已是最新
    case upToDate
    /// C 尚未检查（`init` / `unknown` / 整段缺失）
    case unchecked
    /// D 检查失败
    case failed

    static func resolve(_ status: SkyStatus?) -> SkyCardPhase {
        guard let status = status else { return .unchecked }
        return phase(for: status.status)
    }

    /// 单服版本 → 四态（首页「今日一览」两张 tile 用）。
    ///
    /// 走同一个私有映射函数而不是再抄一遍 switch：四态表是业务规则，
    /// 复制一份迟早会出现"整卡说有新版本、tile 说已是最新"。
    static func resolve(_ app: SkyAppVersion?) -> SkyCardPhase {
        guard let app = app else { return .unchecked }
        return phase(for: app.status)
    }

    /// `SkyState` → 卡面四态。**全工程唯一一张映射表。**
    private static func phase(for state: SkyState) -> SkyCardPhase {
        switch state {
        case .newVersion:
            return .newVersion
        case .noChange:
            return .upToDate
        case .fetchFailed:
            return .failed
        case .initial, .unknown:
            return .unchecked
        }
    }

    /// 卡内主字（20pt Semibold）
    var title: String {
        switch self {
        case .newVersion:
            return "有新版本"
        case .upToDate:
            return "已是最新"
        case .unchecked:
            return "尚未检查"
        case .failed:
            return "暂时查不到"
        }
    }

    var titleColor: Color {
        switch self {
        case .newVersion:
            return Theme.statusNew
        case .upToDate, .unchecked:
            return Theme.textPrimary
        case .failed:
            return Theme.statusError
        }
    }

    var pillKind: StatusPillKind {
        switch self {
        case .newVersion:
            return .newVersion
        case .upToDate:
            return .upToDate
        case .unchecked:
            return .pending
        case .failed:
            return .failed
        }
    }

    var pillText: String {
        switch self {
        case .newVersion:
            return "NEW"
        case .upToDate:
            return "已是最新"
        case .unchecked:
            return "未检查"
        case .failed:
            return "检查失败"
        }
    }

    /// 只有 A 态给卡片染青柠 8%；B/C/D 一律不染（染了就等于用颜色撒谎）
    var tint: Color? {
        switch self {
        case .newVersion:
            return Theme.glassTintLime
        case .upToDate, .unchecked, .failed:
            return nil
        }
    }
}
