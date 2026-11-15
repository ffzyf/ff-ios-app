import Foundation

// MARK: - 数据来源

/// 「复制诊断」里的数据来源三选一（架构 §1.6.3）。
///
/// 真实 Widget 从未被写入调试数据：`realSnapshot` 只是「重置为真实数据」后
/// 面板读自己的快照，不是跨进程注入 —— 不引入 App Group（Q8 / S8）。
enum WidgetDebugDataSource: String, Equatable, Sendable {
    case debugPreset
    case custom
    case realSnapshot

    var label: String {
        switch self {
        case .debugPreset:   return "内置预设"
        case .custom:        return "自定义 JSON"
        case .realSnapshot:  return "真实快照"
        }
    }
}

// MARK: - 预设条目

/// 一条内置预设样例。
///
/// ## 为什么只放字符串字典，不放 `*Entry`
/// 5.1.2 / T03 已把 6 个 `*Entry` 值类型下沉到
/// `Sources/Shared/WidgetDebug/WidgetEntries.swift`，两个 target 现在都编得到它们，
/// 主 App 里引用 Entry 不再是编译问题。这里仍只冻结**字段值**（键名与后端契约一致），
/// 是为了让预设表保持纯数据、不依赖 WidgetKit 的 `TimelineEntry`，且「时间旅行 /
/// 阶段重算」等判定都走 Shared 纯函数；由 T03 的 `WidgetDebugSession` 在 App 进程里
/// 把字典组装成对应 entry 再交给 `*Face`。
struct WidgetDebugPreset: Equatable, Sendable, Identifiable {

    /// 稳定 id：`"<componentId>.<state.rawValue>"`
    let id: String

    let componentId: String
    let state: WidgetDebugState
    let displayName: String

    /// 一行摘要，进「复制诊断」
    let summary: String

    /// 交给 `WidgetDebugSession` 组装 entry 的字段值（键名与后端契约一致）
    let fields: [String: String]

    /// 「内置样例（非真实数据）」——每条都带，避免被当成真实观测读走
    let disclaimer: String

    init(componentId: String,
         state: WidgetDebugState,
         displayName: String,
         summary: String,
         fields: [String: String] = [:]) {
        self.id = componentId + "." + state.rawValue
        self.componentId = componentId
        self.state = state
        self.displayName = displayName
        self.summary = summary
        self.fields = fields
        self.disclaimer = "内置样例（非真实数据），仅用于调试预览"
    }
}

// MARK: - 预设表

/// 各组件的内置预设样例（R5 · 架构 §1.6.3）。
///
/// 样例值沿用既有 `RedstoneEntry.preview` 的占位数据（`"11:08"` /
/// `"暮土·失落方舟"` / `2.5`），不引入新的数值口径；且每条都显式标注
/// `disclaimer`，面板顶部另有常驻「当前为调试预览」提示条（T03）。
///
/// **不落盘**：这里全是编译期常量，不写 UserDefaults / KV / 文件 / App Group，
/// 退出调试页即随内存态一起消失（AC5-7 / S8）。
enum WidgetDebugPresets {

    static let all: [WidgetDebugPreset] = buildAll()

    /// 附录 B 冻结的八个 id（QA 静态比对用同一份表，不另写一遍）
    static var catalogIds: [String] {
        return WidgetDebugCatalog.all.map(\.id)
    }

    /// 某组件的全部预设；未注册组件返回空数组（调用方显示「暂无预设」）
    static func presets(for componentId: String) -> [WidgetDebugPreset] {
        return all.filter { $0.componentId == componentId }
    }

    /// 按「组件 + 状态」取一条；不适用态返回 nil（UI 置灰，不造空壳）
    static func preset(componentId: String, state: WidgetDebugState) -> WidgetDebugPreset? {
        return all.first { $0.componentId == componentId && $0.state == state }
    }

    /// 「复制诊断」的整段文本（架构 §1.6.3：entry 摘要 / 数据来源 / 下次刷新时刻）。
    ///
    /// 时间一律 `Formatters.timeHHmm`（北京 UTC+8）；拿不到下次刷新时刻就整行不写，
    /// 绝不编一个「5 分钟后」出来。
    static func diagnosticsText(preset: WidgetDebugPreset?,
                                dataSource: WidgetDebugDataSource,
                                now: Date,
                                nextRefreshAt: Date?) -> String {
        var lines: [String] = [
            "小组件调试预览",
            "预览时刻：\(Formatters.timeHHmm(now))（北京时间）",
            "数据来源：\(dataSource.label)"
        ]
        if let preset = preset {
            lines.append("组件：\(preset.componentId) · \(preset.state.displayName)")
            lines.append("当前 entry 摘要：\(preset.summary)")
            lines.append(preset.disclaimer)
        } else {
            lines.append("当前 entry 摘要：没有可预览的内容")
        }
        if let next = nextRefreshAt {
            lines.append("下次刷新：\(Formatters.timeHHmm(next))")
        }
        lines.append("提示：调试预览不影响桌面上的小组件")
        return lines.joined(separator: "\n")
    }

    // MARK: - 表数据

    private static func buildAll() -> [WidgetDebugPreset] {
        var result: [WidgetDebugPreset] = []

        // ① 红石：八态全适用（它是状态最全的组件）
        result.append(WidgetDebugPreset(
            componentId: "Redstone", state: .hasData,
            displayName: "有数据 · 下一场", summary: "有排期，下一场 90 分钟后",
            fields: ["time": "11:08", "map": "暮土·失落方舟", "rate": "2.5",
                     "todayCount": "3", "dateText": "今天"]
        ))
        result.append(WidgetDebugPreset(
            componentId: "Redstone", state: .noData,
            displayName: "无数据", summary: "没有排期数据，整卡切天光面",
            fields: ["hasData": "false"]
        ))
        result.append(WidgetDebugPreset(
            componentId: "Redstone", state: .loading,
            displayName: "加载中", summary: "正在取排期",
            fields: ["hasData": "false"]
        ))
        result.append(WidgetDebugPreset(
            componentId: "Redstone", state: .error,
            displayName: "错误", summary: "取排期失败，保留上一帧",
            fields: ["hasData": "false"]
        ))
        result.append(WidgetDebugPreset(
            componentId: "Redstone", state: .ongoing,
            displayName: "进行中", summary: "正在落地，显示结束时间",
            fields: ["time": "11:08", "endAt": "12:00", "map": "暮土·失落方舟"]
        ))
        result.append(WidgetDebugPreset(
            componentId: "Redstone", state: .finished,
            displayName: "收官", summary: "今日场次已全部结束",
            fields: ["hasData": "true", "todayCount": "3"]
        ))
        result.append(WidgetDebugPreset(
            componentId: "Redstone", state: .notGenerated,
            displayName: "未生成", summary: "排期未生成，不显示任何时间",
            fields: ["hasData": "false"]
        ))
        result.append(WidgetDebugPreset(
            componentId: "Redstone", state: .needsCheck,
            displayName: "待确认", summary: "场次待玩家核对",
            fields: ["time": "11:08", "map": "待确认", "needsCheck": "true"]
        ))

        // ② 今日简报：有数据 / 无数据 / 加载中 / 错误
        appendStandard(to: &result, componentId: "Brief", dataSummary: "有简报正文与宜忌",
                       dataFields: ["dateText": "今天", "paragraphs": "内置样例正文",
                                    "yi": "散步", "ji": "熬夜", "pushedToday": "true"])

        // ③ 天光：额外带「待确认」
        appendStandard(to: &result, componentId: "SkyLight", dataSummary: "有天光阶段与日出日落",
                       dataFields: ["phase": "白天", "sunrise": "06:44", "sunset": "17:33"])
        result.append(WidgetDebugPreset(
            componentId: "SkyLight", state: .needsCheck,
            displayName: "待确认", summary: "天气判定拿不到，只说纯时间的词",
            fields: ["phase": "白天"]
        ))

        // ④ 日弧 / 月相 / 风
        appendStandard(to: &result, componentId: "SunArc", dataSummary: "有今日日出日落轨迹",
                       dataFields: ["sunrise": "06:44", "sunset": "17:33"])
        appendStandard(to: &result, componentId: "MoonPhase", dataSummary: "有当日月相",
                       dataFields: ["moonPhase": "内置样例"])
        appendStandard(to: &result, componentId: "Wind", dataSummary: "有实时风速",
                       dataFields: ["wind": "内置样例"])

        // ⑤ 两个实时活动：进行中 / 收官 / 有数据 / 无数据
        for (componentId, label) in [("SunEventLiveActivity", "红石实时活动"),
                                     ("DaylightLiveActivity", "天光实时活动")] {
            result.append(WidgetDebugPreset(
                componentId: componentId, state: .ongoing,
                displayName: "进行中", summary: "\(label)正在呈现",
                fields: ["hasData": "true", "endAt": "12:00"]
            ))
            result.append(WidgetDebugPreset(
                componentId: componentId, state: .finished,
                displayName: "收官", summary: "\(label)已结束",
                fields: ["hasData": "true"]
            ))
            result.append(WidgetDebugPreset(
                componentId: componentId, state: .hasData,
                displayName: "有数据", summary: "\(label)有可展示的内容",
                fields: ["hasData": "true"]
            ))
            result.append(WidgetDebugPreset(
                componentId: componentId, state: .noData,
                displayName: "无数据", summary: "\(label)没有可展示的内容",
                fields: ["hasData": "false"]
            ))
            // 红石实时活动另有「加载中」
            if componentId == "SunEventLiveActivity" {
                result.append(WidgetDebugPreset(
                    componentId: componentId, state: .loading,
                    displayName: "加载中", summary: "\(label)正在取内容",
                    fields: ["hasData": "false"]
                ))
            }
        }

        return result
    }

    /// 桌面型组件共用的四态样例（有数据 / 无数据 / 加载中 / 错误）
    private static func appendStandard(to result: inout [WidgetDebugPreset],
                                       componentId: String,
                                       dataSummary: String,
                                       dataFields: [String: String]) {
        result.append(WidgetDebugPreset(
            componentId: componentId, state: .hasData,
            displayName: "有数据", summary: dataSummary, fields: dataFields
        ))
        result.append(WidgetDebugPreset(
            componentId: componentId, state: .noData,
            displayName: "无数据", summary: "没有数据，不画空壳",
            fields: ["hasData": "false"]
        ))
        result.append(WidgetDebugPreset(
            componentId: componentId, state: .loading,
            displayName: "加载中", summary: "正在取数据",
            fields: ["hasData": "false"]
        ))
        result.append(WidgetDebugPreset(
            componentId: componentId, state: .error,
            displayName: "错误", summary: "取数据失败，保留上一帧",
            fields: ["hasData": "false"]
        ))
    }
}
