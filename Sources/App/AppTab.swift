import SwiftUI

/// 5 个一级 Tab（PRD §2.2 方案 A：概览 / 红石 / 简报 / 文章 / 更多）。
///
/// 为什么从 `RootView.swift` 抽出来单独一个文件：
/// 1. `RootView` 已经承担"常驻 5 页 + 详情全屏 + Tab 桥接"三件事，再塞一个含图标/标题/顺序的
///    枚举会顶到 200 行；
/// 2. Tab 顺序是**产品决策**（PRD §2.1 的对比表），把它放独立文件里，评审时一眼能看见顺序被改过。
///
/// 顺序不可随意调整：红石必须在第 2 位（小组件 / 实时活动的深链目标），简报在第 3 位（V2 承诺），
/// 文章降到第 4 位是可接受的代价（概览保留「最近文章 + 查看全部」兜住断点）。
enum AppTab: Int, CaseIterable, Identifiable {
    /// 概览：今日红石倒计时、今日状态、简报摘要、最近文章、快捷工具
    case overview = 0
    /// 红石：月历 / 当日场次 / 规律说明 / 攻略（批次 2 已落地 `RockCalendarView`）
    case rock = 1
    /// 简报：今日简报全文 + 光遇版本
    case brief = 2
    /// 收益：收益工作站（V3.2 新增，顶替原「文章」的 Tab 位）
    case earnings = 3
    /// 更多：问卷 / 监控 / 设置 / 关于（批次 3 落地，本批占位）
    case more = 4
    /// 文章：列表 + 详情。
    ///
    /// **不再占 Tab 位**（V3.2：用户要求把第 4 格换成收益工作站），但页面保留 ——
    /// 概览页的「查看全部文章」仍跳到这里。rawValue 取 5 是为了让前 5 个枚举值与
    /// Tab 栏位置 0…4 对齐，`allCases` 的顺序不会把「文章」插进可见的 5 格里。
    case articles = 5

    var id: Int { rawValue }

    /// Tab 栏显示的 5 项（顺序即视觉顺序）。`articles` 不在其中。
    static let tabBarTabs: [AppTab] = [.overview, .rock, .brief, .earnings, .more]

    var title: String {
        switch self {
        case .overview: return "概览"
        case .rock: return "红石"
        case .brief: return "简报"
        case .earnings: return "收益"
        case .articles: return "文章"
        case .more: return "更多"
        }
    }

    /// SF Symbol（PRD §2.2 定稿，不要换成其他符号：图标是 Tab 唯一可被记住的身份）
    var icon: String {
        switch self {
        case .overview: return "sparkles"
        case .rock: return "moon.stars"
        case .brief: return "bell.badge"
        case .earnings: return "chart.line.uptrend.xyaxis"
        case .articles: return "doc.text"
        case .more: return "square.grid.2x2"
        }
    }

    /// DesignSystem 不认识 AppTab（分层要求），只认识这个纯数据描述。
    ///
    /// `badge` 本批恒为 nil：「更多」的红色徽标要等「有新版本 / 未读答卷」两类数据源
    /// 都到位后才有意义（现在先留出入口，避免以后再回来改 `FloatingTabBar`）。
    var spec: TabSpec {
        TabSpec(id: rawValue, title: title, icon: icon)
    }
}
