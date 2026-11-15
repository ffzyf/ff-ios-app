import SwiftUI
import WidgetKit

/// 小组件调试会话（5.1.2 · R5，架构 §1.6.4）。
///
/// **只存活于 App 进程内存**：不做任何持久化写入（不落盘、不碰跨进程容器），
/// 不改任何 Provider；`reset()` 在面板 `onDisappear` 自动跑，退出即恢复，
/// 真实 Widget 从未被写入（AC5-7 / S8）。
///
/// 唯一系统副作用是用户**显式**点「刷新 Timeline」时的
/// `WidgetCenter.reloadTimelines(ofKind:)` / `reloadAllTimelines()` —— 那是让真实
/// Widget 重新取自己的数据，**不是注入调试数据**（Q8：调试数据不可跨进程注入）。
///
/// 为什么 `deinit` 里不调 `reset()`：本类是 `@MainActor`，`deinit` 里写 `@Published`
/// 会踩 actor 隔离；而 fullScreenCover 关闭时 `onDisappear` 必定触发，清理语义完全等价。
@MainActor
final class WidgetDebugSession: ObservableObject {

    // MARK: - 选择态（全在内存，退出即弃）

    @Published private(set) var selectedComponentId: String
    @Published private(set) var selectedFamily: WidgetDebugFamily
    @Published private(set) var selectedState: WidgetDebugState

    /// 时间旅行的「当前时刻」。所有预览 entry 都用它当 `date`，
    /// 红石阶段走 `RedstoneTimeline.phase(in:now:)` 按它重算 —— 与真实 Widget 同一套逻辑。
    @Published private(set) var previewNow: Date

    @Published private(set) var dataSource: WidgetDebugDataSource
    @Published private(set) var customJSON: String
    @Published private(set) var customError: String?

    /// 当前生效的预设（自定义注入成功时换成一条临时预设，字段来自注入的 JSON）
    @Published private(set) var activePreset: WidgetDebugPreset?

    /// 一次性提示（复制诊断 / 刷新 Timeline）
    @Published private(set) var toast: String?

    private let initialComponentId: String

    init() {
        let first = WidgetDebugCatalog.all.first
        let componentId = first?.id ?? "Redstone"
        self.initialComponentId = componentId
        self.selectedComponentId = componentId
        self.selectedFamily = first?.families.first ?? .systemSmall
        self.selectedState = first?.states.first ?? .hasData
        self.previewNow = Date()
        self.dataSource = .debugPreset
        self.customJSON = ""
        self.customError = nil
        self.activePreset = WidgetDebugPresets.preset(componentId: componentId, state: .hasData)
        self.toast = nil
    }

    // MARK: - 派生（只读注册表 / 预设表的纯数据）

    var descriptor: WidgetDebugDescriptor? {
        return WidgetDebugCatalog.descriptor(for: selectedComponentId)
    }

    var familyAvailabilities: [FamilyAvailability] {
        return WidgetDebugCatalog.supportedFamilies(for: selectedComponentId)
    }

    var stateAvailabilities: [StateAvailability] {
        return WidgetDebugCatalog.applicableStates(for: selectedComponentId)
    }

    var presets: [WidgetDebugPreset] {
        return WidgetDebugPresets.presets(for: selectedComponentId)
    }

    var selectedFamilyReason: String? {
        return familyAvailabilities.first { $0.family == selectedFamily }?.reason
    }

    var selectedStateReason: String? {
        return stateAvailabilities.first { $0.state == selectedState }?.reason
    }

    var isCurrentFamilySupported: Bool {
        return familyAvailabilities.first { $0.family == selectedFamily }?.supported == true
    }

    var isCurrentStateApplicable: Bool {
        return stateAvailabilities.first { $0.state == selectedState }?.applicable == true
    }

    /// 真实 Widget 的下一次刷新时刻由系统跨进程决定，App 进程拿不到 → 一律 nil。
    /// 「复制诊断」里 `WidgetDebugPresets.diagnosticsText` 会因此整行不写，绝不编一个时刻。
    var nextRefreshAt: Date? { nil }

    // MARK: - 选择

    /// 切组件：把 family / state 收敛到该组件**支持 / 适用**的第一档，
    /// 避免停在上一组件支持、这一组件不支持的档上（那就得渲染一个空壳）。
    func selectComponent(_ id: String) {
        guard let descriptor = WidgetDebugCatalog.descriptor(for: id) else { return }
        selectedComponentId = id
        selectedFamily = descriptor.families.first ?? .systemSmall
        selectedState = descriptor.states.first ?? .hasData
        dataSource = .debugPreset
        customError = nil
        activePreset = WidgetDebugPresets.preset(componentId: id, state: selectedState)
    }

    /// 置灰档不允许选中（UI 也不给可点按钮，双保险）
    func selectFamily(_ family: WidgetDebugFamily) {
        guard familyAvailabilities.first(where: { $0.family == family })?.supported == true else { return }
        selectedFamily = family
    }

    func selectState(_ state: WidgetDebugState) {
        guard stateAvailabilities.first(where: { $0.state == state })?.applicable == true else { return }
        selectedState = state
        dataSource = .debugPreset
        customError = nil
        activePreset = WidgetDebugPresets.preset(componentId: selectedComponentId, state: state)
    }

    func applyPreset(_ preset: WidgetDebugPreset) {
        selectedState = preset.state
        dataSource = .debugPreset
        customError = nil
        activePreset = preset
    }

    // MARK: - 时间旅行

    /// 按分钟平移预览时刻。负数是往前拨；不动真实时间，也不写任何持久化状态。
    func shiftPreview(byMinutes minutes: Int) {
        previewNow = previewNow.addingTimeInterval(Double(minutes) * 60)
    }

    func resetPreviewNow() {
        previewNow = Date()
    }

    // MARK: - 自定义 JSON 注入

    /// 注入一段字段字典 JSON（形如 `{"time":"11:08","map":"…"}`），覆盖当前预设的字段值。
    ///
    /// 为什么解成 `[String: String]` 而不是 `*Entry`：`RedstoneEntry.phase` 是 `RockPhase`、
    /// `BriefEntry.weather` 是 `WeatherNow` —— 这些不是纯 JSON 原语，直接用解码器解 entry
    /// 必然失败（而「解不开给明确错误态」不等于「永远解不开」）。与 §1.6.3「预设只放
    /// 字段字典」同一形状：注入的是字段值，由 `WidgetDebugPreviewContainer` 组装成 entry。
    ///
    /// 坏 JSON / 不是对象 / 空对象 → 写 `customError`，**不切换数据源、不渲染空壳**。
    func inject(json: String) {
        customJSON = json
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            customError = "没有可注入的内容"
            return
        }
        guard let fields = try? JSONDecoder().decode([String: String].self, from: data),
              !fields.isEmpty else {
            customError = "JSON 解析失败：需要一段 { \"字段\": \"字符串值\" } 形式的对象"
            return
        }
        customError = nil
        dataSource = .custom
        activePreset = WidgetDebugPreset(
            componentId: selectedComponentId,
            state: selectedState,
            displayName: "自定义 JSON",
            summary: "自定义字段 \(fields.count) 项",
            fields: fields
        )
        toast = "已应用自定义字段"
    }

    // MARK: - 控制（AC5-6）

    /// 只刷当前选中组件的 kind（catalog descriptor 的 `widgetKind` 与 `SkyWidgetBundle` 同源）。
    func reloadCurrentTimeline() {
        guard let kind = descriptor?.widgetKind else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        toast = "已刷新 \(kind) 的 Timeline"
    }

    func reloadAllTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
        toast = "已刷新全部小组件 Timeline"
    }

    /// 「复制诊断」：入口、时刻、组件、数据来源、下次刷新（拿不到就不写）写进剪贴板。
    func copyDiagnostics() {
        let text = WidgetDebugPresets.diagnosticsText(
            preset: activePreset,
            dataSource: dataSource,
            now: previewNow,
            nextRefreshAt: nextRefreshAt
        )
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        toast = "诊断已复制"
    }

    func clearToast() {
        toast = nil
    }

    /// 「重置为真实数据」= 清空整个调试会话（内存态回初始），真实 Widget 从未被写入。
    func reset() {
        selectedComponentId = initialComponentId
        selectedFamily = WidgetDebugCatalog.all.first?.families.first ?? .systemSmall
        selectedState = WidgetDebugCatalog.all.first?.states.first ?? .hasData
        previewNow = Date()
        dataSource = .realSnapshot
        customJSON = ""
        customError = nil
        activePreset = WidgetDebugPresets.preset(componentId: initialComponentId, state: .hasData)
        toast = nil
    }
}
