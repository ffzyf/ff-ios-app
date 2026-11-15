import Foundation

// MARK: - 尺寸档 / 状态 / entry 种类

/// 调试面板可选的八种尺寸 / 形态（架构 §3.2）。
///
/// 前六档是 `WidgetFamily`（桌面三档 + 锁屏三形态），后两档是给两个
/// LiveActivity 用的**伪 family** —— 调试面板按同一套选择器驱动所有组件，
/// 真实呈现时由 `WidgetDebugPreviewContainer` 分派到锁屏 / 灵动岛视图。
enum WidgetDebugFamily: String, CaseIterable, Equatable, Sendable {
    case systemSmall
    case systemMedium
    case systemLarge
    case accessoryRectangular
    case accessoryInline
    case accessoryCircular
    case activityLockScreen
    case activityDynamicIsland

    var displayName: String {
        switch self {
        case .systemSmall:           return "小号"
        case .systemMedium:          return "中号"
        case .systemLarge:           return "大号"
        case .accessoryRectangular:  return "锁屏矩形"
        case .accessoryInline:       return "锁屏单行"
        case .accessoryCircular:     return "锁屏圆形"
        case .activityLockScreen:    return "锁屏实时活动"
        case .activityDynamicIsland: return "灵动岛"
        }
    }
}

/// 八种预览状态（架构 §1.6.3）。
///
/// 不适用的态**置灰且不渲染空壳**，理由由 `applicableStates(for:)` 给出，
/// 不为凑数硬塞一个「看起来像有数据」的空帧。
enum WidgetDebugState: String, CaseIterable, Equatable, Sendable {
    case hasData
    case noData
    case loading
    case error
    case finished
    case ongoing
    case notGenerated
    case needsCheck

    var displayName: String {
        switch self {
        case .hasData:      return "有数据"
        case .noData:       return "无数据"
        case .loading:      return "加载中"
        case .error:        return "错误"
        case .finished:     return "收官"
        case .ongoing:      return "进行中"
        case .notGenerated: return "未生成"
        case .needsCheck:   return "待确认"
        }
    }
}

/// 该组件要造哪种 TimelineEntry / ContentState。
///
/// 只表达「种类」，**不引用任何 `*Entry` 类型** —— 那些类型定义在
/// `Sources/Widget` 的 Provider 文件里，主 App target 并不编译它们。
/// 组装 entry 是 T03 `WidgetDebugSession` / `WidgetDebugPreviewContainer` 的事。
enum WidgetDebugEntryKind: String, CaseIterable, Equatable, Sendable {
    case redstone
    case brief
    case sunEventActivity
    case daylightActivity
    case skyLight
    case sunArc
    case moonPhase
    case wind
}

// MARK: - 支持矩阵

/// 一个尺寸档的支持结论。
struct FamilyAvailability: Equatable, Sendable {
    let family: WidgetDebugFamily
    let supported: Bool

    /// 不支持时**必须非空**（AC5-3）；支持时为 nil
    let reason: String?

    init(family: WidgetDebugFamily, supported: Bool, reason: String? = nil) {
        self.family = family
        self.supported = supported
        self.reason = reason
    }
}

/// 一个状态是否适用的结论。
struct StateAvailability: Equatable, Sendable {
    let state: WidgetDebugState
    let applicable: Bool

    /// 不适用时**必须非空**（AC5-4）；适用时为 nil
    let reason: String?

    init(state: WidgetDebugState, applicable: Bool, reason: String? = nil) {
        self.state = state
        self.applicable = applicable
        self.reason = reason
    }
}

/// 一个组件的注册项。
struct WidgetDebugDescriptor: Equatable, Sendable, Identifiable {

    /// 与 `SkyWidgetBundle.body` 的注册项一一对应（附录 B `catalogIds`）
    let id: String

    let displayName: String

    /// `WidgetCenter.reloadTimelines(ofKind:)` 用的 kind，与注册类型名同源
    let widgetKind: String

    /// **支持的**尺寸档；其余档由 `supportedFamilies(for:)` 补成置灰项
    let families: [WidgetDebugFamily]

    /// **适用的**状态；其余态由 `applicableStates(for:)` 补成置灰项
    let states: [WidgetDebugState]

    let entryKind: WidgetDebugEntryKind

    /// 不支持档的定制理由（key = `WidgetDebugFamily.rawValue`）；没写的用通用理由
    let familyReasons: [String: String]

    /// 不适用态的定制理由（key = `WidgetDebugState.rawValue`）；没写的用通用理由
    let stateReasons: [String: String]

    init(id: String,
         displayName: String,
         widgetKind: String,
         families: [WidgetDebugFamily],
         states: [WidgetDebugState],
         entryKind: WidgetDebugEntryKind,
         familyReasons: [String: String] = [:],
         stateReasons: [String: String] = [:]) {
        self.id = id
        self.displayName = displayName
        self.widgetKind = widgetKind
        self.families = families
        self.states = states
        self.entryKind = entryKind
        self.familyReasons = familyReasons
        self.stateReasons = stateReasons
    }
}

// MARK: - 注册表（唯一真相源）

/// 小组件调试面板的组件注册表（R5 · 架构 §1.6.3 / §3.2）。
///
/// 纯数据 + 纯函数，`import Foundation` 而已：既不依赖 SwiftUI / WidgetKit，
/// 也不依赖任何 `*Entry` / `*Face` 类型，因此 `Sources/Shared` 两个 target
/// 都能编译，QA 也能把 `ids` 与 `SkyWidgetBundle.body` 静态比对（AC5-2）。
///
/// 「调试看到的 = 桌面看到的」靠的是**同一份渲染层**：T03 把模拟 entry 交给
/// 既有 `*Face`，面板自己不画第二套组件。这里只决定「能选什么」。
enum WidgetDebugCatalog {

    /// 八个组件，顺序与附录 B `catalogIds` 逐字一致。
    /// 与 `SkyWidgetBundle.body` 的八个注册项一一对应，漏一个就是漏一个组件。
    static let all: [WidgetDebugDescriptor] = [
        WidgetDebugDescriptor(
            id: "Redstone",
            displayName: "红石",
            widgetKind: "RedstoneWidget",
            families: [.systemSmall, .systemMedium, .systemLarge],
            states: [.hasData, .noData, .loading, .error, .finished,
                     .ongoing, .notGenerated, .needsCheck],
            entryKind: .redstone,
            familyReasons: [
                WidgetDebugFamily.accessoryRectangular.rawValue: "红石卡只声明了桌面小 / 中 / 大三档，没有锁屏 accessory 形态",
                WidgetDebugFamily.accessoryCircular.rawValue: "红石卡没有锁屏圆形形态",
                WidgetDebugFamily.activityLockScreen.rawValue: "红石是桌面小组件，不是实时活动",
                WidgetDebugFamily.activityDynamicIsland.rawValue: "红石是桌面小组件，不占灵动岛"
            ]
        ),
        WidgetDebugDescriptor(
            id: "Brief",
            displayName: "今日简报",
            widgetKind: "BriefWidget",
            families: [.systemSmall, .systemMedium, .systemLarge],
            states: [.hasData, .noData, .loading, .error],
            entryKind: .brief,
            stateReasons: [
                WidgetDebugState.finished.rawValue: "简报是「今天有什么事」的静态快照，没有收官 / 进行中的时态",
                WidgetDebugState.ongoing.rawValue: "简报不是倒计时组件，没有进行中这一态",
                WidgetDebugState.notGenerated.rawValue: "简报没有排期生成流程，缺数据时走「无数据」而不是「未生成」",
                WidgetDebugState.needsCheck.rawValue: "简报内容由服务端定稿，没有玩家待核对态"
            ]
        ),
        WidgetDebugDescriptor(
            id: "SunEventLiveActivity",
            displayName: "红石实时活动",
            widgetKind: "SunEventLiveActivity",
            families: [.activityLockScreen, .activityDynamicIsland],
            states: [.hasData, .noData, .ongoing, .finished, .loading],
            entryKind: .sunEventActivity,
            familyReasons: [
                WidgetDebugFamily.systemSmall.rawValue: "实时活动只在锁屏 / 灵动岛呈现，没有桌面小组件档",
                WidgetDebugFamily.systemMedium.rawValue: "实时活动只在锁屏 / 灵动岛呈现，没有桌面小组件档",
                WidgetDebugFamily.systemLarge.rawValue: "实时活动只在锁屏 / 灵动岛呈现，没有桌面小组件档",
                WidgetDebugFamily.accessoryRectangular.rawValue: "实时活动用 ActivityKit 呈现，不是锁屏 accessory 小组件",
                WidgetDebugFamily.accessoryInline.rawValue: "实时活动用 ActivityKit 呈现，不是锁屏 accessory 小组件",
                WidgetDebugFamily.accessoryCircular.rawValue: "实时活动用 ActivityKit 呈现，不是锁屏 accessory 小组件"
            ],
            stateReasons: [
                WidgetDebugState.notGenerated.rawValue: "实时活动只在已有场次时启动，没有「排期未生成」这一态",
                WidgetDebugState.needsCheck.rawValue: "实时活动展示的是已确认场次，没有待核对态",
                WidgetDebugState.error.rawValue: "实时活动结束即消失，没有错误态画面"
            ]
        ),
        WidgetDebugDescriptor(
            id: "DaylightLiveActivity",
            displayName: "天光实时活动",
            widgetKind: "DaylightLiveActivity",
            families: [.activityLockScreen, .activityDynamicIsland],
            states: [.hasData, .noData, .ongoing, .finished],
            entryKind: .daylightActivity,
            familyReasons: [
                WidgetDebugFamily.systemSmall.rawValue: "实时活动只在锁屏 / 灵动岛呈现，没有桌面小组件档",
                WidgetDebugFamily.systemMedium.rawValue: "实时活动只在锁屏 / 灵动岛呈现，没有桌面小组件档",
                WidgetDebugFamily.systemLarge.rawValue: "实时活动只在锁屏 / 灵动岛呈现，没有桌面小组件档",
                WidgetDebugFamily.accessoryRectangular.rawValue: "实时活动用 ActivityKit 呈现，不是锁屏 accessory 小组件",
                WidgetDebugFamily.accessoryInline.rawValue: "实时活动用 ActivityKit 呈现，不是锁屏 accessory 小组件",
                WidgetDebugFamily.accessoryCircular.rawValue: "实时活动用 ActivityKit 呈现，不是锁屏 accessory 小组件"
            ],
            stateReasons: [
                // 架构 §1.3 / AC5-4 点名的「不适用」：天光实时活动不含红石场次时间
                WidgetDebugState.notGenerated.rawValue: "天光实时活动不含红石场次时间，没有「未生成」这一态，不硬塞",
                WidgetDebugState.needsCheck.rawValue: "天光实时活动按天文时刻推进，没有玩家待核对态",
                WidgetDebugState.loading.rawValue: "实时活动结束即消失，不画加载骨架",
                WidgetDebugState.error.rawValue: "实时活动结束即消失，没有错误态画面"
            ]
        ),
        WidgetDebugDescriptor(
            id: "SkyLight",
            displayName: "天光",
            widgetKind: "SkyLightWidget",
            families: [.systemSmall, .systemMedium, .systemLarge,
                       .accessoryRectangular, .accessoryInline],
            states: [.hasData, .noData, .loading, .error, .needsCheck],
            entryKind: .skyLight,
            stateReasons: [
                WidgetDebugState.finished.rawValue: "天光是「此刻」的连续阶段，没有收官态",
                WidgetDebugState.ongoing.rawValue: "天光整张卡就是此刻状态，不再分进行中 / 未开始",
                WidgetDebugState.notGenerated.rawValue: "天光由天文时刻现算，不依赖排期生成"
            ]
        ),
        WidgetDebugDescriptor(
            id: "SunArc",
            displayName: "日弧",
            widgetKind: "SunArcWidget",
            families: [.systemSmall, .systemMedium, .systemLarge,
                       .accessoryRectangular, .accessoryInline],
            states: [.hasData, .noData, .loading, .error],
            entryKind: .sunArc,
            stateReasons: [
                WidgetDebugState.finished.rawValue: "日弧画的是今天整条太阳轨迹，没有收官态",
                WidgetDebugState.ongoing.rawValue: "日弧不分场次，没有进行中这一态",
                WidgetDebugState.notGenerated.rawValue: "日弧由日出日落现算，不依赖排期生成",
                WidgetDebugState.needsCheck.rawValue: "日弧数据来自天气接口，没有玩家待核对态"
            ]
        ),
        WidgetDebugDescriptor(
            id: "MoonPhase",
            displayName: "月相",
            widgetKind: "MoonPhaseWidget",
            // 架构 §1.6.3：小 / 大 + 锁屏三形态（这里用三个 accessory 档对应）
            families: [.systemSmall, .systemLarge,
                       .accessoryRectangular, .accessoryInline, .accessoryCircular],
            states: [.hasData, .noData, .loading, .error],
            entryKind: .moonPhase,
            stateReasons: [
                WidgetDebugState.finished.rawValue: "月相是当日快照，没有收官态",
                WidgetDebugState.ongoing.rawValue: "月相不分场次，没有进行中这一态",
                WidgetDebugState.notGenerated.rawValue: "月相由日期现算，不依赖排期生成",
                WidgetDebugState.needsCheck.rawValue: "月相数据来自天文计算，没有玩家待核对态"
            ]
        ),
        WidgetDebugDescriptor(
            id: "Wind",
            displayName: "风",
            widgetKind: "WindWidget",
            families: [.systemSmall, .systemLarge,
                       .accessoryRectangular, .accessoryInline],
            states: [.hasData, .noData, .loading, .error],
            entryKind: .wind,
            stateReasons: [
                WidgetDebugState.finished.rawValue: "风卡是实时观测，没有收官态",
                WidgetDebugState.ongoing.rawValue: "风卡不分场次，没有进行中这一态",
                WidgetDebugState.notGenerated.rawValue: "风卡的数据来自天气接口，不依赖排期生成",
                WidgetDebugState.needsCheck.rawValue: "风卡数据来自天气接口，没有玩家待核对态"
            ]
        )
    ]

    /// 八个 id 的集合。QA 用静态脚本与 `SkyWidgetBundle.body` 里的类型名比对（AC5-2）。
    static var ids: Set<String> {
        return Set(all.map(\.id))
    }

    /// 按 id 取注册项；未知 id 返回 nil（调用方走「全档置灰」而不是崩）
    static func descriptor(for id: String) -> WidgetDebugDescriptor? {
        return all.first { $0.id == id }
    }

    /// 八档全量结论：支持的 `reason == nil`，不支持的**必定非空**（AC5-3）。
    static func supportedFamilies(for id: String) -> [FamilyAvailability] {
        guard let descriptor = descriptor(for: id) else {
            return WidgetDebugFamily.allCases.map { family in
                FamilyAvailability(family: family,
                                   supported: false,
                                   reason: "未注册的组件「\(id)」，没有可用尺寸档")
            }
        }
        return WidgetDebugFamily.allCases.map { family in
            let supported = descriptor.families.contains(family)
            let reason: String? = supported ? nil : defaultFamilyReason(descriptor, family)
            return FamilyAvailability(family: family, supported: supported, reason: reason)
        }
    }

    /// 八态全量结论：适用的 `reason == nil`，不适用的**必定非空**（AC5-4）。
    static func applicableStates(for id: String) -> [StateAvailability] {
        guard let descriptor = descriptor(for: id) else {
            return WidgetDebugState.allCases.map { state in
                StateAvailability(state: state,
                                  applicable: false,
                                  reason: "未注册的组件「\(id)」，没有适用状态")
            }
        }
        return WidgetDebugState.allCases.map { state in
            let applicable = descriptor.states.contains(state)
            let reason: String? = applicable ? nil : defaultStateReason(descriptor, state)
            return StateAvailability(state: state, applicable: applicable, reason: reason)
        }
    }

    // MARK: - 通用兜底理由（保证「非空」这条永远成立）

    private static func defaultFamilyReason(_ descriptor: WidgetDebugDescriptor,
                                            _ family: WidgetDebugFamily) -> String {
        if let custom = descriptor.familyReasons[family.rawValue],
           !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        return "\(descriptor.displayName) 未在「\(family.displayName)」档声明 supportedFamilies，置灰不渲染空壳"
    }

    private static func defaultStateReason(_ descriptor: WidgetDebugDescriptor,
                                           _ state: WidgetDebugState) -> String {
        if let custom = descriptor.stateReasons[state.rawValue],
           !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        return "\(descriptor.displayName) 没有「\(state.displayName)」这一态，置灰不渲染空壳"
    }
}
