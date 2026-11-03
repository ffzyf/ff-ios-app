import SwiftUI

/// 模型选择半屏（点顶栏那个模型名打开）。
///
/// 结构照效果图第 4 屏：第一项永远是「自动选择」（带服务端给的理由），其后是服务端
/// `GET /api/ai/models` 给的清单；`available == false` 的项**置灰且不可点**，
/// `note` 就是原因（"云端未配置 SecretId / SecretKey"）。
///
/// 三条规矩：
/// 1. **不可点的项不给 `Button`**，而不是 `.disabled(true)`。`disabled` 的按钮在
///    VoiceOver 里仍然可聚焦、仍然会"点一下没反应"，而这里要传达的是"这一项今天不存在"。
///    代价是它拿不到按压反馈 —— 但那正是"不可用"该有的手感。
/// 2. **`auto` 不来自清单**。哪怕服务端在 `models` 里也回了一条 `auto`，这里也过滤掉：
///    它不是一个"模型"，是面板第一行（有自己的副标题、推荐标与判据）。
/// 3. **选中即返回**。选模型不是配置页，是"换个口径，继续聊"，选完就该回去。
struct AIModelPickerSheet: View {

    @ObservedObject private var chat = AIChatStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    autoRow

                    ForEach(otherModels) { option in
                        modelRow(option)
                    }

                    footnote
                }
                .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            PageBackground(glow: false)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // 打开面板时补一次清单：配额与 auto 判据都是会变的（别的设备也在用同一天额度）
        .task {
            await chat.loadModels()
        }
    }

    // MARK: - 头部

    private var header: some View {
        Text("选择模型")
            .font(Typography.titleL)
            .tracking(Typography.trackingLarge)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, 10)
    }

    // MARK: - 清单

    /// 服务端清单里去掉 `auto`（理由见类型注释第 2 条）
    private var otherModels: [AIModelOption] {
        return chat.models.filter { $0.id != "auto" }
    }

    private var autoRow: some View {
        Button {
            select("auto")
        } label: {
            rowShell(
                letter: "A",
                title: "自动选择",
                subtitle: autoSubtitle,
                selected: chat.selectedModel == "auto",
                badge: "推荐"
            )
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private func modelRow(_ option: AIModelOption) -> some View {
        if option.available {
            Button {
                select(option.id)
            } label: {
                rowShell(
                    letter: letter(for: option),
                    title: option.label,
                    // 服务端没给"这个模型擅长什么"的字段，就不编一句介绍：
                    // 副标题留空，比写一句我们并不确定的话好
                    subtitle: nil,
                    selected: chat.selectedModel == option.id,
                    badge: nil
                )
            }
            .buttonStyle(PressableStyle())
        } else {
            rowShell(
                letter: letter(for: option),
                title: option.label,
                // `note` 就是置灰的原因，原样上屏（服务端写的中文）
                subtitle: option.note ?? "云端还没配好，暂时用不了",
                selected: false,
                badge: nil
            )
            .opacity(0.45)
        }
    }

    /// 面板底部说明：说清"为什么有灰的"，以及今天还剩多少条。
    ///
    /// 配额是**乐观提示**：权威判定只认服务端 429（多设备同时用，本地数一定偏）。
    private var footnote: some View {
        Text(footnoteText)
            .font(Typography.captionXS)
            .foregroundStyle(Theme.textTertiary)
            .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.6))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 14)
            .padding(.bottom, 30)
    }

    private var footnoteText: String {
        let base = "密钥只存在云端，手机里不留。灰掉的项是云端还没配好，不是手机的问题。"
        guard let remaining = chat.quotaRemaining else { return base }
        return "今天还剩 " + String(remaining) + " 条。" + base
    }

    // MARK: - 行壳

    /// 一行：字母块 + 名称（可带标）+ 副标题 + 右侧对勾。
    ///
    /// 用字母块而不是各家 logo：不引入图片资源、也不去冒充品牌色；
    /// 一个字母在 34pt 的圆角块里，比一个 16pt 的彩色小图标更好认。
    private func rowShell(letter: String,
                          title: String,
                          subtitle: String?,
                          selected: Bool,
                          badge: String?) -> some View {
        HStack(spacing: 12) {
            Text(letter)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(selected ? Theme.onLime : Theme.textSecondary)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(selected ? Theme.lime : Theme.surfaceTint3)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Typography.callout)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    badgeView(badge)
                }
                subtitleView(subtitle)
            }

            Spacer(minLength: 8)

            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.limeInk)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Spacing.page)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        // 分隔线用 overlay 而不是真的 `Divider`：它要左边缩进 46（避开字母块），
        // `Divider` 只能整行宽
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
                .padding(.leading, Spacing.page + 46)
        }
    }

    @ViewBuilder
    private func badgeView(_ badge: String?) -> some View {
        if let badge = badge {
            Text(badge)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.limeInk)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: Radius.badge, style: .continuous)
                        .fill(Theme.lime.opacity(0.12))
                }
        }
    }

    @ViewBuilder
    private func subtitleView(_ subtitle: String?) -> some View {
        // 不用中间 `let`：本项目在 ViewBuilder 里写 `let` 出过两次编译错误，
        // 需要中间值就抽成 `private func` / `private var`（这里直接用表达式）。
        if let subtitle = subtitle,
           subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            Text(subtitle.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                // 副标题允许两行（`note` 可能是一整句），不能被压成一条省略号
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 派生

    /// 「自动选择」的副标题：服务端给的理由优先。
    ///
    /// `AIChatStore.lastReason` 是**上一轮末帧**给的理由（`auto.reason` 只随流下发），
    /// 所以刚装好、还没聊过时它是 nil —— 那时退一句固定说明，
    /// **不编**一个"短问题走便宜模型"（用户会以为这一次也这么判过）。
    private var autoSubtitle: String {
        if let reason = chat.lastReason {
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let picked = pickedLabel {
            return "按问题自动挑，这次的判据偏向 " + picked
        }
        return "按问题自动挑：闲聊走轻量，长文与推理走增强"
    }

    /// `auto.picked` 的显示名（查不到就返回 nil，不外露 id —— 这一行是给用户看的判据）
    private var pickedLabel: String? {
        guard let picked = chat.autoPicked else { return nil }
        guard let match = chat.models.first(where: { $0.id == picked }) else { return nil }
        let label = match.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    /// 字母块里的那个字：取名称首字（"DeepSeek" → D / "腾讯混元" → 腾）
    private func letter(for option: AIModelOption) -> String {
        let trimmed = option.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "·" }
        return String(first)
    }

    // MARK: - 动作

    private func select(_ id: String) {
        Haptics.selection()
        chat.selectModel(id)
        dismiss()
    }
}
