import SwiftUI

/// 问卷工作台的**页内路由**。
///
/// 为什么手写一个 `[SurveyRoute]` 栈，而不是用 `NavigationStack`：
/// 1. 根视图（`RootView`）刻意没有导航栈（`OverviewView` / `RockGuideView` 都写过原因：
///    硬塞一个会把 5 个常驻 Tab 页面重新包一层容器，Tab 栏与页面层级会打架）；
/// 2. 问卷的四页需要**同一套玻璃页头**（返回钮 + 大标题 + 右侧动作），
///    系统导航条做不到（不能与浮动 Tab 栏、青柠光斑共存）；
/// 3. 栈里只有 3 种页面、没有手势返回需求，30 行就够，比引一套导航容器更可控。
///
/// 呈现方式：`MoreView` 用 `fullScreenCover` 打开本视图 —— 工作台是"接管屏幕的活儿"，
/// 用户在里面看答卷明细时不该被底部 Tab 栏切走。
enum SurveyRoute: Equatable, Identifiable {
    case detail(String)
    case fill(String)
    case result(String)

    var id: String {
        switch self {
        case .detail(let id): return "detail-" + id
        case .fill(let id): return "fill-" + id
        case .result(let id): return "result-" + id
        }
    }
}

/// 问卷工作台容器：登录引导 ↔ 列表 ↔ 详情 ↔ 填答 / 结果。
///
/// 单例 Store + `@ObservedObject`（不是 `@EnvironmentObject`）：工作台是用
/// `fullScreenCover` 打开的，模态呈现不保证继承环境对象，用单例可以彻底绕开这条依赖。
struct SurveyWorkspaceView: View {
    @ObservedObject private var store = SurveyStore.shared
    @ObservedObject private var auth = SurveyAuth.shared
    @Environment(\.dismiss) private var dismiss

    /// 页面栈。空 = 根（已登录看列表 / 未登录看登录引导）
    @State private var stack: [SurveyRoute] = []

    /// 显式空 init：`@State` / `@ObservedObject` 都是 private 存储属性，
    /// 会把自动生成的 memberwise init 降级成 private，跨文件 `SurveyWorkspaceView()` 就调不到。
    init() {}

    var body: some View {
        ZStack {
            // 工作台是"干活的页面"，不加青柠光斑（与文章页同一条规则：大面积彩色干扰阅读）
            PageBackground(glow: false)
            content
        }
        .task {
            // 进工作台先验一次凭证：30 天有效期内也可能已经被改密码 / 手动过期。
            // 失败（401）会把 `isLoggedIn` 翻成 false，下面的 `content` 自动回到登录引导。
            await store.verifySession()
        }
        .onChange(of: auth.isLoggedIn) { _, _ in
            // 登录态一变就清空页面栈 + 内存：绝不能把上一个会话的详情 / 结果留在屏上（R20）
            stack = []
            store.resetMemory()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let route = stack.last {
            switch route {
            case .detail(let id):
                SurveyDetailView(
                    surveyId: id,
                    onBack: pop,
                    onFill: { push(.fill($0)) },
                    onSeeResult: { push(.result($0)) }
                )
            case .fill(let id):
                SurveyFillView(surveyId: id, onBack: pop)
            case .result(let id):
                SurveyResultView(surveyId: id, onBack: pop)
            }
        } else if auth.isLoggedIn {
            SurveyListView(onBack: closeWorkspace, onOpenSurvey: { push(.detail($0)) })
        } else {
            LoginPromptView(onClose: closeWorkspace)
        }
    }

    // MARK: - 栈操作

    private func push(_ route: SurveyRoute) {
        withAnimation(Motion.push) {
            stack.append(route)
        }
    }

    private func pop() {
        withAnimation(Motion.pop) {
            if !stack.isEmpty {
                stack.removeLast()
            }
        }
    }

    private func closeWorkspace() {
        dismiss()
    }
}

// MARK: - 统一页头

/// 问卷四页共用的页头：返回钮 + 大标题（+ 副标题）+ 可选的右侧动作。
///
/// 抽出来而不是每页各写一遍：四个页面的间距、字号、返回钮尺寸只要有一处不同，
/// 用户来回翻页时就会觉得"界面在跳"。也顺手保证动效一致（都走 `Motion` 常量）。
struct SurveyPageHeader: View {
    let title: String
    /// 副标题（一句话说明，拿不到就传 nil —— 绝不显示"未知"）
    var subtitle: String? = nil
    /// 右侧动作的文字（与 `trailingIcon` 二选一，都没有就只显示返回钮）
    var trailingTitle: String? = nil
    var trailingIcon: String? = nil
    var onTrailing: (() -> Void)? = nil
    let onBack: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        trailingTitle: String? = nil,
        trailingIcon: String? = nil,
        onTrailing: (() -> Void)? = nil,
        onBack: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailingTitle = trailingTitle
        self.trailingIcon = trailingIcon
        self.onTrailing = onTrailing
        self.onBack = onBack
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconGlassButton(icon: "chevron.left", size: 36) {
                onBack()
            }
            .accessibilityLabel("返回")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.titleL)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let onTrailing = onTrailing {
                Button(action: {
                    Haptics.light()
                    onTrailing()
                }) {
                    HStack(spacing: 5) {
                        if let icon = trailingIcon {
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        if let trailingTitle = trailingTitle {
                            Text(trailingTitle)
                                .font(Typography.footnoteMedium)
                        }
                    }
                    .foregroundStyle(Theme.limeInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassSurface(.floating, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(trailingTitle ?? "更多操作")
            }
        }
    }
}

// MARK: - 小节标题

/// 页内小节标签（11pt，与设置页的分组标题同一口径）
struct SurveySectionLabel: View {
    let text: String

    /// 用带标签的 init 而不是 `init(_:)`：调用点写 `SurveySectionLabel(text:)` 时，
    /// 形参与实参的对应关系在文本层就一目了然（本工程的签名核对脚本也只认标签形式）。
    init(text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Typography.captionXS)
            .foregroundStyle(Theme.textTertiary)
    }
}
