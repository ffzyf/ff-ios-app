import SwiftUI

/// 首次启动的法律告知（3.32.0）。
///
/// 为什么必须有这一屏：《App 违法违规收集使用个人信息行为认定方法》把
/// 「首次运行时未通过弹窗等明显方式提示用户阅读隐私政策」直接列为「未公开收集使用规则」。
/// 现在的 App 打开即进主界面，等于把这条踩满。
///
/// 三条实现纪律：
/// 1. **同意之前不初始化任何采集** —— 这一屏只是文本，不触发定位、不写 Bark、不发请求；
/// 2. 同意状态存 `@AppStorage`，只在**本机**记，不上报（否则就成了"收集同意状态"本身）；
/// 3. 入口给两级：这里是扼要版，「查看完整」打开 `PrivacyLegalSheet`——
///    完整文本随时可达，满足「易于访问」。
struct LegalConsentView: View {
    /// 点「同意并继续」之后做什么，由调用方决定（往 `@AppStorage` 里写标记）。
    let onAgree: () -> Void

    @State private var showsPolicy = false

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground(glow: true)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("开始之前")
                        .font(Typography.display)
                        .tracking(Typography.trackingLarge)
                        .foregroundStyle(Theme.textPrimary)
                    Text("这个 App 会用到少量和你有关的信息，先说清楚。")
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                }

                Spacer(minLength: 20)

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        consentRow(
                            icon: "location",
                            title: "位置",
                            detail: "只用于查当地天气与日出日落，可拒绝；拒绝后可在设置里手动选城市。"
                        )
                        Rectangle().fill(Theme.divider).frame(height: 1)
                        consentRow(
                            icon: "bubble.left.and.bubble.right",
                            title: "AI 对话",
                            detail: "你输入的提问会发给 DeepSeek 生成回答，记录存放在云端数据库。"
                        )
                        Rectangle().fill(Theme.divider).frame(height: 1)
                        consentRow(
                            icon: "bell",
                            title: "推送",
                            detail: "只在你自己填了 Bark Key 时才有推送，Key 加密存储、回显打码。"
                        )
                    }
                    .padding(Spacing.cardPadding)
                }

                Spacer(minLength: 16)

                Text("本应用为非官方个人工具，与网易公司、thatgamecompany 无关。完整条款与数据处理说明见下方链接。")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.6))

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    Button {
                        Haptics.light()
                        onAgree()
                    } label: {
                        Text("同意并继续")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryCTAStyle())

                    Button {
                        showsPolicy = true
                    } label: {
                        Text("查看完整隐私政策与声明")
                            .font(Typography.footnote)
                            .foregroundStyle(Theme.limeInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    Text("若不同意，请卸载本应用。")
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.page)
        }
        .sheet(isPresented: $showsPolicy) {
            PrivacyLegalSheet()
        }
    }

    private func consentRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
            }
        }
    }
}

/// 首次启动的同意门（挂在 `RootView` 外面）。
///
/// 用 `.fullScreenCover` 而不是 overlay：这一屏不该被 Tab 栏、下拉手势或返回手势穿透——
/// 同意之前用户还没有进入应用，也没有"返回"可去。
///
/// `@AppStorage` 的键带版本号（`v1`）：将来条款有实质变更时改成 `v2`，
/// 老用户会被重新问一次，而不是永远默认同意。
struct LegalConsentGate: ViewModifier {
    @AppStorage("legal.consent.v1") private var consented = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(
                isPresented: Binding(
                    get: { !consented },
                    set: { presented in
                        // 只处理"被关闭"：同意与否由按钮显式写入，不靠手势关闭。
                        if !presented { consented = true }
                    }
                )
            ) {
                LegalConsentView {
                    consented = true
                }
            }
    }
}

extension View {
    /// 首次启动的法律告知门。挂在根视图外侧，位置与更新弹层同级。
    func legalConsentGate() -> some View {
        modifier(LegalConsentGate())
    }
}
