import SwiftUI

// MARK: - 表单零件（全部走 Theme / Typography / Radius / Spacing 四套 token）

/// 字段标签：左侧名字，右侧可选的状态话术（字数 / 上限 / "下一笔沿用"）。
struct EarningsRecordFieldLabel: View {
    let text: String
    var accessory: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
            if let accessory {
                Text(accessory)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

/// 输入框的统一外观（底 + 1pt 描边）。
///
/// 表单里有 4 种输入形态（金额 / 类型 / 日期 / 备注），内间距与圆角各抄一遍迟早漂移 ——
/// 收成一个 modifier，改只改这一处。
///
/// 刻意**没有**「错误态」参数：记账表单里所有输入都是"静默修正"（非法字符直接过滤、
/// 超长直接截断、金额中间态不算错），没有哪种输入该被标红 —— 标红只会让人以为记错了账。
struct EarningsRecordInputSurface: ViewModifier {

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                    .fill(Theme.surfaceTint1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            }
    }
}

extension View {
    /// 记账表单输入框外观（`EarningsRecord*` 专用，别的页面别用）。
    func earningsRecordInputSurface() -> some View {
        modifier(EarningsRecordInputSurface())
    }
}

/// 可选胶囊（活动 / 最近用过的类型）。
///
/// 「面 + 面上的字」成对出现：选中是 `lime` 面配 `onLime` 字，未选中是
/// `surfaceTint2` 面配 `textSecondary` 字 —— 绝不用 `lime` 当字色（浅色下只有 1.76:1）。
struct EarningsRecordChip: View {
    let title: String
    var subtitle: String? = nil
    var selected: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(selected ? Theme.onLime : Theme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.captionXS)
                        .foregroundStyle(selected ? Theme.onLime.opacity(0.72) : Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, subtitle == nil ? 8 : 7)
            .background {
                Capsule().fill(selected ? Theme.lime : Theme.surfaceTint2)
            }
            .overlay {
                Capsule().strokeBorder(selected ? Theme.glassStrokeTop : Theme.divider, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 类型

/// 类型（必选，≤12 字）：输入框 + 「最近用过的类型」置顶胶囊。
///
/// 为什么有胶囊：一个活动通常连着记好几笔同类型的奖励，让最近用过的类型可一点即填，
/// 比每次重新打字快得多 —— 这也是网站版连续录入时的实际用法。
/// 「最近用过」全部来自服务端数据（`EarningsStore.activities` 里的 entry），不做本地存储。
struct EarningsRecordTypeField: View {

    @Binding var text: String
    let recent: [String]

    /// 硬限 12 字（服务端 `type` 的显示宽度按 12 字设计）
    static let maxLength = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EarningsRecordFieldLabel(text: "类型", accessory: "\(text.count)/\(Self.maxLength)")

            TextField("如「广告分成」", text: $text)
                .font(Typography.callout)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .earningsRecordInputSurface()
                .onChange(of: text) { _, newValue in
                    // 超出直接截断，不弹错（表单里不该为"多打了一个字"打断录入）
                    if newValue.count > Self.maxLength {
                        text = String(newValue.prefix(Self.maxLength))
                    }
                }

            if recent.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recent, id: \.self) { name in
                            EarningsRecordChip(title: name, selected: name == text) {
                                text = name
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - 待发 / 已发（只做展示说明）

/// 「待发 / 已发」分段：**只展示，不可点**。
///
/// 服务端 `buildNewEntry` 自己决定新条目的 `paid`（恒为 `false`），而
/// `POST /api/app/earnings/entry` 的请求体里**没有** `paid` 字段（见 `EarningsEntryInput`）。
/// 所以这里绝不伪装成一个可切换的分段控件 —— 那只会让用户以为勾了「已发」就真的到账了，
/// 而实际落库的仍是待发，App 与网页端立刻不一致。到账状态只在网页端勾选。
struct EarningsRecordPaidRow: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EarningsRecordFieldLabel(text: "状态", accessory: "服务端决定")

            HStack(spacing: 8) {
                Text("待发")
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.onLime)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background { Capsule().fill(Theme.lime) }

                Text("已发")
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background { Capsule().fill(Theme.surfaceTint1) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("新记的条目固定为待发")

            Text("新记的默认待发，到账后在网页端勾选「已发」。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
        }
    }
}

// MARK: - 日期

/// 日期行：只要日期不要时间。
///
/// 「下一笔沿用」不是提示语而是真实行为：保存成功后走 `EarningsRecordDraft.remember(_:)`，
/// **同一天**的下一笔默认就是这个日期（月底补记几笔时不用反复改）；隔天再打开会回到今天。
struct EarningsRecordDateRow: View {

    @Binding var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EarningsRecordFieldLabel(text: "日期", accessory: "下一笔沿用")

            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.textTertiary)
                DatePicker(
                    "日期",
                    selection: $date,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .tint(Theme.lime)
                Spacer(minLength: 0)
            }
            .earningsRecordInputSurface()
        }
    }
}

// MARK: - 备注

/// 备注（单行，≤40 字）：超出截断，不报错。
struct EarningsRecordNoteField: View {

    @Binding var text: String

    static let maxLength = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EarningsRecordFieldLabel(text: "备注", accessory: "\(text.count)/\(Self.maxLength)")

            TextField("一句话说明（可选）", text: $text)
                .font(Typography.callout)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .lineLimit(1)
                .earningsRecordInputSurface()
                .onChange(of: text) { _, newValue in
                    if newValue.count > Self.maxLength {
                        text = String(newValue.prefix(Self.maxLength))
                    }
                }
        }
    }
}
