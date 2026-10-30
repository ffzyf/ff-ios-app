import SwiftUI

/// 设置页的「问卷管理」分组（PRD P14 第 3 条：密码 → 登录 / 退出）。
///
/// 为什么用 `@ObservedObject` 直接观察单例，而不是 `@EnvironmentObject`：
/// 设置页会从两处弹出（概览右上齿轮 / 更多 → 设置），模态呈现不保证继承环境对象；
/// 直接观察单例可以彻底绕开这条依赖（`AppearanceSection` 已用同一套办法）。
///
/// 登录表单本身复用 `LoginPromptView`（sheet 呈现）：密码框、回车提交、就地报错
/// 都已经在里面做对了，这一组只负责"状态 + 入口"。
struct AccountSection: View {
    @ObservedObject private var auth = SurveyAuth.shared
    @ObservedObject private var store = SurveyStore.shared

    @State private var showsLogin: Bool = false
    @State private var showsLogoutConfirm: Bool = false

    init() {}

    var body: some View {
        VStack(spacing: 8) {
            GlassListRow(
                icon: auth.isLoggedIn ? "checkmark.seal" : "person.badge.key",
                title: "问卷工作台",
                detail: auth.isLoggedIn ? "已连接" : "未连接",
                showsChevron: !auth.isLoggedIn
            ) {
                guard !auth.isLoggedIn else { return }
                showsLogin = true
            }

            if auth.isLoggedIn {
                GlassListRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "退出问卷登录",
                    detail: nil,
                    showsChevron: false
                ) {
                    showsLogoutConfirm = true
                }
            } else {
                GlassListRow(
                    icon: "key",
                    title: "用管理密码登录",
                    detail: nil,
                    showsChevron: false
                ) {
                    showsLogin = true
                }
            }

            Text(auth.isLoggedIn
                 ? "凭证存在本机钥匙串，30 天后过期。退出会把这份凭证和问卷缓存一起删掉。"
                 : "问卷列表、结果看板和推送监控都要管理密码；密码就是网页端问卷站的 ADMIN_PASSWORD。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showsLogin) {
            LoginPromptView(onClose: {
                showsLogin = false
            }, onSuccess: {
                showsLogin = false
            })
        }
        // 退出是"数据可见性"变更，必须二次确认（R20：退出后不能再看到上一个账号的数据）
        .confirmationDialog(
            Text("退出问卷登录？"),
            isPresented: $showsLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button("退出", role: .destructive) {
                signOut()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后问卷列表、结果和已下载的缓存都会被删除，要重新输密码才能进。")
        }
    }

    private func signOut() {
        Haptics.light()
        Task {
            await store.signOut()
        }
    }
}
