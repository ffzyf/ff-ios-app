import SwiftUI

/// 问卷工作台的登录引导页（PRD P08 的「未登录 → 登录引导页」）。
///
/// 三条产品约束，逐条对应实现：
/// 1. **是页面，不是弹窗**：`MoreView` 里点「问卷工作台」时直接进这一页，
///    不弹 alert / 不压半屏 sheet —— 用户是想干活，不是点错了；
/// 2. **失败就地报错**：错误行放在输入框与按钮之间（`Theme.statusError`），
///    不弹 alert。alert 会盖住表单、逼用户点"好"，而"密码错了"的下一步动作明明是重输；
/// 3. **回车即提交**：`.submitLabel(.go)` + `.onSubmit`，符合密码框的用户预期。
struct LoginPromptView: View {
    @ObservedObject private var auth = SurveyAuth.shared

    @State private var password: String = ""
    /// 服务端说了什么（一句话，不出现错误码）
    @State private var errorText: String?
    @FocusState private var isFocused: Bool

    private let onClose: () -> Void
    private let onSuccess: () -> Void

    /// - Parameters:
    ///   - onClose: 关掉工作台 / 关闭这个 sheet（两种呈现方式都用到）
    ///   - onSuccess: 登录成功后的动作。默认什么都不做 —— 工作台靠 `auth.isLoggedIn`
    ///     自动从登录页切到列表，不需要回调；设置页的 sheet 需要自己关掉，才用得上它。
    init(onClose: @escaping () -> Void = {}, onSuccess: @escaping () -> Void = {}) {
        self.onClose = onClose
        self.onSuccess = onSuccess
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                header
                formCard
                footnote
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            // 列宽 640（表单页，§3.9）：这是全屏覆盖页，没有 Tab 栏兜底，
            // 不限宽的话 iPad 横屏那个密码框会拉到 1154 —— 一个输入框横跨整块屏幕，
            // 光标离"登录"按钮半米远。窄屏 393 < 640，`maxWidth` 不生效 → 零影响。
            .pageColumn(Layout.formMaxWidth)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            // 进来就聚焦：这一步的唯一任务就是输密码，不该让用户先点一下输入框
            isFocused = true
        }
    }

    // MARK: - 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 0)
                IconGlassButton(icon: "xmark", size: 36) {
                    onClose()
                }
                .accessibilityLabel("关闭")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("问卷工作台")
                    .font(Typography.display)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                Text("要用问卷站的管理密码才能进。")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - 表单

    private var formCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SurveySectionLabel(text: "管理密码")

                SecureField("输入管理密码", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($isFocused)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                            .fill(Theme.bgElevated)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                            .strokeBorder(Theme.divider, lineWidth: 1)
                    }
                    .onSubmit {
                        submit()
                    }
                    .accessibilityLabel("管理密码")

                // 就地报错：一条红字，不用 alert（PRD §7.2「不弹 alert」）
                if let errorText = errorText {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(errorText)
                            .font(Typography.footnote)
                            .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.statusError)
                    .accessibilityAddTraits(.isStaticText)
                }

                HStack(spacing: 12) {
                    Button(action: {
                        submit()
                    }) {
                        HStack(spacing: 6) {
                            if auth.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(auth.isBusy ? "登录中" : "登录")
                        }
                    }
                    .buttonStyle(PrimaryCTAStyle())
                    .disabled(auth.isBusy || password.isEmpty)
                    .opacity((auth.isBusy || password.isEmpty) ? 0.55 : 1)

                    if !password.isEmpty && !auth.isBusy {
                        Button(action: {
                            password = ""
                            errorText = nil
                            isFocused = true
                        }) {
                            Text("清空")
                        }
                        .buttonStyle(SecondaryCTAStyle())
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(Spacing.cardPadding)
        }
    }

    // MARK: - 说明

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("密码就是网页端问卷站的管理密码（服务端环境变量 ADMIN_PASSWORD）。")
            Text("登录后凭证只存在本机钥匙串里，App 不会把它写进日志或备份。")
        }
        .font(Typography.captionXS)
        .foregroundStyle(Theme.textTertiary)
        .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
        .padding(.horizontal, 4)
    }

    // MARK: - 动作

    private func submit() {
        guard !auth.isBusy else { return }
        let value = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorText = "先输入管理密码。"
            return
        }
        errorText = nil

        Task {
            do {
                try await auth.login(password: value)
                Haptics.success()
                password = ""
                onSuccess()
            } catch let authError as SurveyAuthError {
                Haptics.error()
                errorText = authError.userMessage
            } catch let apiError as APIError {
                // 取消（页面被关掉）不上屏：那不是一个"错误"
                if apiError.isCancelled { return }
                Haptics.error()
                errorText = apiError.userMessage
            } catch {
                Haptics.error()
                errorText = "登录没成功，稍后再试。"
            }
        }
    }
}
