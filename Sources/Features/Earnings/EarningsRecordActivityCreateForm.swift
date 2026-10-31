import SwiftUI

/// 「新建活动」表单（**内联**在记账弹页里，不跳第二个 sheet）。
///
/// 为什么内联：建活动是记账的前置动作，跳一层 sheet 意味着"填完 → 关掉 → 回来 → 再选"，
/// 三次往返只为填两个字符串。内联之后是「填名字 → 选平台 → 创建 → 自动选中 → 直接记一笔」一条线。
///
/// 三个字段的规则全部照服务端（`validateActivityInput`）与网页端 `addActivity`：
/// · 活动名 ≤ 30 字（输入时就截断，不弹错）；
/// · 归属平台：固定 5 个 + 已存在的自定义 + 「新平台」；
/// · 平台名 ≤ 12 字；
/// · 同平台重名由服务端判（409），文案原样显示在表单下方 —— 重名不是输入错误，
///   是"这个平台下已经有一条了"，弹 alert 打断录入没有意义。
struct EarningsRecordActivityCreateForm: View {

    /// 活动名称（≤30 字）
    @Binding var name: String
    /// 选中的平台：固定平台名 / 已存在的自定义平台 / `EarningsRecordPlatformPicker.newPlatformToken`
    @Binding var platform: String
    /// 「新平台」时填的名字（≤12 字）
    @Binding var customPlatform: String

    /// 可选平台（固定 5 个在前，自定义按首次出现 —— 与服务端聚合同序）
    let platformOptions: [String]
    let isSubmitting: Bool
    /// 可直接上屏的错误（409 的重名文案 / 离线 / 401）
    let errorText: String?
    /// 名称与平台都填好了才允许提交（由上层算好，避免两处各判一遍）
    let canSubmit: Bool

    let onSubmit: () -> Void
    let onCancel: () -> Void

    /// 表单里只有两个输入框（名称 / 新平台名），枚举比两个 Bool 好读
    private enum Field: Hashable {
        case name
        case customPlatform
    }

    @FocusState private var focusedField: Field?

    /// 显式 init（不是啰嗦）：本结构里有一个 `private` 的 `@FocusState`，
    /// 编译器推导出的 memberwise init 会跟着降级成 `private`，跨文件调用就编不过。
    /// 本 View 被 `EarningsRecordSheet` 跨文件构造，所以必须写清楚这个入口。
    init(
        name: Binding<String>,
        platform: Binding<String>,
        customPlatform: Binding<String>,
        platformOptions: [String],
        isSubmitting: Bool,
        errorText: String?,
        canSubmit: Bool,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._name = name
        self._platform = platform
        self._customPlatform = customPlatform
        self.platformOptions = platformOptions
        self.isSubmitting = isSubmitting
        self.errorText = errorText
        self.canSubmit = canSubmit
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            nameBlock
            platformBlock

            if let errorText {
                Text(errorText)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.statusError)
                    .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
            }

            actionRow

            Text("活动会立刻写进服务端，网页端刷新就能看到；平台不需要提前创建，填个新名字就是新平台。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.smallCardPadding)
        .background {
            RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                .fill(Theme.surfaceTint1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        }
        .onAppear {
            // 展开表单就是为了填名字，直接把焦点放过去
            focusedField = .name
        }
    }

    // MARK: - 名称

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.gridUnit) {
            EarningsRecordFieldLabel(
                text: "活动名称",
                accessory: "\(name.count)/\(EarningsPlatformPreset.maxActivityNameLength)"
            )

            TextField("如「9 月星图结算」", text: $name)
                .font(Typography.callout)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .focused($focusedField, equals: .name)
                .lineLimit(1)
                .earningsRecordInputSurface()
                .onChange(of: name) { _, newValue in
                    // 超出直接截断：服务端也会拒，但没必要让人打完再被退回来
                    if newValue.count > EarningsPlatformPreset.maxActivityNameLength {
                        name = String(newValue.prefix(EarningsPlatformPreset.maxActivityNameLength))
                    }
                }
        }
    }

    // MARK: - 平台

    private var platformBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.gridUnit) {
            EarningsRecordFieldLabel(
                text: "归属平台",
                accessory: isNewPlatform ? "自定义 ≤\(EarningsPlatformPreset.maxNameLength) 字" : "点选或新建"
            )

            EarningsRecordPlatformPicker(text: $platform, options: platformOptions)

            if isNewPlatform {
                TextField("新平台名称", text: $customPlatform)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .customPlatform)
                    .lineLimit(1)
                    .earningsRecordInputSurface()
                    .onChange(of: customPlatform) { _, newValue in
                        if newValue.count > EarningsPlatformPreset.maxNameLength {
                            customPlatform = String(newValue.prefix(EarningsPlatformPreset.maxNameLength))
                        }
                    }
            }
        }
    }

    private var isNewPlatform: Bool {
        return platform == EarningsRecordPlatformPicker.newPlatformToken
    }

    // MARK: - 按钮

    private var actionRow: some View {
        HStack(spacing: Spacing.cardGap) {
            Button {
                onSubmit()
            } label: {
                if isSubmitting {
                    ProgressView().controlSize(.small).tint(Theme.onLime)
                } else {
                    Text("创建")
                }
            }
            .buttonStyle(PrimaryCTAStyle())
            .opacity(canSubmit ? 1 : 0.55)
            .disabled(canSubmit == false || isSubmitting)

            Button {
                onCancel()
            } label: {
                Text("取消")
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background { Capsule().fill(Theme.surfaceTint2) }
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())

            Spacer(minLength: 0)
        }
    }
}
