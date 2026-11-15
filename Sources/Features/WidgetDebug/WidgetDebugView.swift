import SwiftUI

/// 小组件调试控制面板（5.1.2 · R5，架构 §1.6 / AC5-1~8）。
///
/// **唯一实现 + 唯一呈现**：只有 `MoreView.toolsGroup` 的「小组件调试」这一行以
/// `.fullScreenCover` 打开本页（DESIGN-RULES §4 / Q3）。设置页只有一行静态指引，
/// 不呈现本页、不复制实现、不产生第二个调试会话生命周期。
///
/// 五区：① 组件 ② 尺寸 ③ 状态 ④ 预览 ⑤ 模拟数据与控制。
/// iPad rail 档：左 ①②③ 控制列（≤368 = `Layout.sideColumnWidth`），右 ④⑤ 主列，
/// 两列顶对齐；single / grid2 单列（AC5-8）。
struct WidgetDebugView: View {

    @StateObject private var session = WidgetDebugSession()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.layoutMetrics) private var metrics

    /// 自定义 JSON 的输入缓冲。会话里的 `customJSON` 是 `private(set)`，
    /// 这里只做「用户正在输入」的临时态，应用时才交给 Session（同样不落盘）。
    @State private var customText: String = ""

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground(glow: false)

            VStack(spacing: 0) {
                header
                debugBanner
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .bottom) {
            if let toast = session.toast {
                Text(toast)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        Capsule().fill(Theme.surfaceTint3)
                    }
                    .padding(.bottom, 20)
            }
        }
        // 退出即弃：调试态只存活于 App 进程内存，真实 Widget 从未被写入（AC5-7）
        .onDisappear {
            session.reset()
        }
        .task(id: session.toast) {
            guard session.toast != nil else { return }
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(Motion.glassOut) {
                session.clearToast()
            }
        }
    }

    // MARK: - 头部 / 常驻提示条

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("小组件调试")
                    .font(Typography.titleL)
                    .foregroundStyle(Theme.textPrimary)
                Text(session.descriptor?.displayName ?? "")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Text("关闭")
            }
            .buttonStyle(SecondaryCTAStyle())
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// 常驻提示条：`Theme.statusWarn` 只作底不作字（§7-4），字走 `textPrimary`。
    private var debugBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
            Text("当前为调试预览，不影响桌面上的小组件")
                .font(Typography.captionXS)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, Spacing.page)
        .padding(.vertical, 8)
        .background {
            Theme.statusWarn.opacity(0.35)
        }
    }

    // MARK: - 五区排布

    @ViewBuilder
    private var content: some View {
        if metrics.pageTier == .rail {
            ScrollView {
                HStack(alignment: .top, spacing: Layout.columnGap) {
                    VStack(spacing: Spacing.sectionGap) {
                        componentSection
                        familySection
                        stateSection
                    }
                    .frame(width: Layout.sideColumnWidth)

                    VStack(spacing: Spacing.sectionGap) {
                        previewSection
                        controlSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.page)
            }
            .scrollIndicators(.hidden)
        } else {
            ScrollView {
                VStack(spacing: Spacing.sectionGap) {
                    componentSection
                    familySection
                    stateSection
                    previewSection
                    controlSection
                }
                .padding(.horizontal, Spacing.page)
                .padding(.bottom, Spacing.page)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            content()
        }
    }

    // MARK: - ① 组件（8 个，与 SkyWidgetBundle 一一对应）

    private var componentSection: some View {
        section("组件") {
            GlassCard(level: .card, cornerRadius: Radius.smallCard) {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(WidgetDebugCatalog.all) { descriptor in
                        chip(
                            title: descriptor.displayName,
                            selected: descriptor.id == session.selectedComponentId,
                            enabled: true,
                            reason: nil
                        ) {
                            session.selectComponent(descriptor.id)
                        }
                    }
                }
                .padding(Spacing.cardPadding)
            }
        }
    }

    // MARK: - ② 尺寸（不支持档置灰并注原因）

    private var familySection: some View {
        section("尺寸") {
            GlassCard(level: .card, cornerRadius: Radius.smallCard) {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(session.familyAvailabilities, id: \.family) { item in
                        chip(
                            title: item.family.displayName,
                            selected: item.family == session.selectedFamily,
                            enabled: item.supported,
                            reason: item.supported ? nil : item.reason
                        ) {
                            session.selectFamily(item.family)
                        }
                    }
                }
                .padding(Spacing.cardPadding)
            }
        }
    }

    // MARK: - ③ 状态（不适用态置灰并注原因）

    private var stateSection: some View {
        section("状态") {
            GlassCard(level: .card, cornerRadius: Radius.smallCard) {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(session.stateAvailabilities, id: \.state) { item in
                        chip(
                            title: item.state.displayName,
                            selected: item.state == session.selectedState,
                            enabled: item.applicable,
                            reason: item.applicable ? nil : item.reason
                        ) {
                            session.selectState(item.state)
                        }
                    }
                }
                .padding(Spacing.cardPadding)
            }
        }
    }

    private var gridColumns: [GridItem] {
        return [GridItem(.adaptive(minimum: 96), spacing: 8)]
    }

    // MARK: - ④ 预览

    private var previewSection: some View {
        section("预览") {
            VStack(spacing: 8) {
                WidgetDebugPreviewContainer(session: session)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("数据来源：" + session.dataSource.label
                     + " · 预览时刻 " + Formatters.timeHHmm(session.previewNow) + "（北京时间）")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - ⑤ 模拟数据与控制

    private var controlSection: some View {
        section("模拟数据与控制") {
            GlassCard(level: .card, cornerRadius: Radius.smallCard) {
                VStack(alignment: .leading, spacing: 12) {
                    presetsBlock
                    timeTravelBlock
                    customJSONBlock
                    actionsBlock
                }
                .padding(Spacing.cardPadding)
            }
        }
    }

    private var presetsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("内置预设")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            if session.presets.isEmpty {
                Text("暂无预设")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(session.presets) { preset in
                    Button {
                        session.applyPreset(preset)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: preset.id == session.activePreset?.id
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(preset.id == session.activePreset?.id
                                                 ? Theme.limeInk : Theme.textTertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.displayName)
                                    .font(Typography.footnote)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(preset.summary)
                                    .font(Typography.captionXS)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private var timeTravelBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("时间旅行 · 预览时刻 " + Formatters.timeHHmm(session.previewNow) + "（北京时间）")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 8) {
                smallButton("−1 小时") { session.shiftPreview(byMinutes: -60) }
                smallButton("+1 小时") { session.shiftPreview(byMinutes: 60) }
                smallButton("+1 天") { session.shiftPreview(byMinutes: 1440) }
                smallButton("回到现在") { session.resetPreviewNow() }
            }
            Text("红石阶段按预览时刻走 RedstoneTimeline.phase(in:now:)，与桌面同一套逻辑。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var customJSONBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("自定义 JSON（字段 → 字符串值）")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            TextEditor(text: $customText)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textPrimary)
                .frame(height: 68)
                .padding(6)
                .background {
                    RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                        .fill(Theme.glassStaticFill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: 1)
                }
            HStack(alignment: .top, spacing: 8) {
                smallButton("应用") { session.inject(json: customText) }
                if let error = session.customError {
                    Text(error)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var actionsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                smallButton("刷新当前 Timeline") { session.reloadCurrentTimeline() }
                smallButton("全部刷新") { session.reloadAllTimelines() }
            }
            HStack(spacing: 8) {
                smallButton("复制诊断") { session.copyDiagnostics() }
                smallButton("重置为真实数据") {
                    session.reset()
                    customText = ""
                }
            }
            Text("刷新 Timeline 只让桌面小组件重新自取数据，不注入调试数据；调试态仅在本页内存，退出即弃。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 通用小组件（零颜色字面量）

    private func chip(title: String,
                      selected: Bool,
                      enabled: Bool,
                      reason: String?,
                      action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if enabled {
                Button {
                    Haptics.selection()
                    action()
                } label: {
                    chipLabel(title: title, selected: selected)
                }
                .buttonStyle(PressableStyle())
            } else {
                // 置灰项不给 Button：VoiceOver 不会聚焦到一个按不动的控件
                chipLabel(title: title, selected: false)
                    .opacity(0.45)
            }
            if let reason, !reason.isEmpty {
                Text(reason)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chipLabel(title: String, selected: Bool) -> some View {
        Text(title)
            .font(Typography.footnoteMedium)
            .foregroundStyle(selected ? Theme.onLime : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(selected ? Theme.lime : Theme.glassStaticFill)
            }
            .overlay {
                Capsule().strokeBorder(Theme.divider, lineWidth: 1)
            }
            .contentShape(Capsule())
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Text(title)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background {
                    Capsule().fill(Theme.surfaceTint3)
                }
                .overlay {
                    Capsule().strokeBorder(Theme.divider, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}
