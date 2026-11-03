import SwiftUI

/// 5 个一级 Tab。
///
/// 为什么从 `RootView.swift` 抽出来单独一个文件：
/// 1. `RootView` 已经承担"常驻 7 页（底栏 5 项 + 文章 / 收益）+ 详情全屏 + Tab 桥接"三件事，再塞一个含图标/标题/顺序的
///    枚举会顶到 200 行；
/// 2. Tab 顺序是**产品决策**，把它放独立文件里，评审时一眼能看见顺序被改过。
///
/// ## 顺序（3.28.0 产品决策变更，替换 V2 时代那句承诺）
///
/// `[.overview, .rock, .ai, .brief, .more]`
///
/// · 红石仍在第 2 位 —— 小组件与实时活动的深链都指向它，动它等于让桌面点进来落到别的页；
/// · **AI 占第 3 格**（3.28.0 用户要求）。这句必须写清楚：V2 时代这里写着"简报在第 3 位
///   （V2 承诺）"，那条承诺**到此为止** —— 不是被忘了，是被新的产品决定覆盖了。
///   简报退到第 4 位不是被降级：「今日简报」仍是概览首屏第二张整卡（点进去是天光页），
///   简报页的内容一个字没少；让位的是"每天看一眼"的格子，给"随时要问"的入口；
/// · **收益移出底栏**（页面还在，入口并入「更多」）。它是"一个月看两次"的账，
///   占着一个一天点五次的格子不值 —— 与当初"文章"让位是同一个判断。
///
/// ## rawValue 为什么不能重排
///
/// `rawValue` 同时是三样东西：Tab 栏的选中值（`FloatingTabBar.selection`）、
/// `TabSpec.id`、以及深链的落点。已有的值一个都不许动（有状态按它存过），
/// 所以新增的 `.ai` 只能拿序列里的下一个空位 `6`，不能插进 2 与 3 之间。
///
/// **⌘ 快捷键按「栏内位置」生成，不是按 `rawValue`**（3.28.0 修正）：`FloatingTabBar` /
/// `WideTabStrip` 现在用 `TabSpec` 在 `tabs` 数组里的下标 + 1 生成键位，于是 iPad 外接键盘上是
/// ⌘1 概览 / ⌘2 红石 / ⌘3 AI / ⌘4 简报 / ⌘5 更多 —— 与视觉顺序一致。
/// 上一版用 `tab.id + 1`，`.ai` 的 rawValue 是 6，AI 会落到 ⌘7（跳号、且与第 3 格矛盾）。
/// 修的是"取哪个数"，`rawValue` 一个都没动 —— 它仍然是选中值 / `TabSpec.id` / 深链落点。
enum AppTab: Int, CaseIterable, Identifiable {
    /// 概览：今日红石倒计时、今日天气、AI 穿搭建议、简报摘要、最近文章、快捷工具
    case overview = 0
    /// 红石：月历 / 当日场次 / 规律说明 / 攻略
    case rock = 1
    /// 简报：今日简报全文 + 光遇版本（3.28.0 起从第 3 格退到第 4 格）
    case brief = 2
    /// 收益：收益工作站。
    ///
    /// **3.28.0 起不在底栏**（第 3 格让给 AI），但页面与 rawValue 原样保留 ——
    /// 入口只剩「更多」页里那一行。rawValue 动不了：它是 Tab 选中值与 `TabSpec.id`。
    case earnings = 3
    /// 更多：问卷 / 推送监控 / 检查更新 / 收益 / 设置 / 关于
    case more = 4
    /// 文章：列表 + 详情。
    ///
    /// **不在 Tab 栏里**（V3.2 起第 4 格换成收益工作站），但页面保留 ——
    /// 概览页的「查看更多」仍跳到这里。rawValue 取 5 是为了让前 5 个枚举值与
    /// Tab 栏位置 0…4 对齐，`allCases` 的顺序不会把「文章」插进可见的 5 格里。
    case articles = 5
    /// AI：沉浸式聊天（3.28.0 新增，占第 3 格）。
    ///
    /// rawValue 6 = "序列里的下一个空位"，理由见类型注释最后一节。
    case ai = 6

    var id: Int { rawValue }

    /// Tab 栏显示的 5 项（顺序即视觉顺序）。`articles` 与 `earnings` 都不在其中。
    static let tabBarTabs: [AppTab] = [.overview, .rock, .ai, .brief, .more]

    var title: String {
        switch self {
        case .overview: return "概览"
        case .rock: return "红石"
        case .ai: return "AI"
        case .brief: return "简报"
        case .earnings: return "收益"
        case .articles: return "文章"
        case .more: return "更多"
        }
    }

    /// SF Symbol（定稿，不要换成其他符号：图标是 Tab 唯一可被记住的身份）。
    ///
    /// `.ai` 用对话气泡（`bubble.left.and.bubble.right`）而不是 `sparkles` ——
    /// 后者已经被 `.overview` 占了，两个 Tab 同一个图标等于两个都没有。
    var icon: String {
        switch self {
        case .overview: return "sparkles"
        case .rock: return "moon.stars"
        case .ai: return "bubble.left.and.bubble.right"
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
