import SwiftUI

/// 首页的「今天穿什么」AI 建议卡（3.28.0）。
///
/// 位置：**首屏「此刻」那一组的最后一张，紧跟天气卡**（见 `OverviewView.topGroup`）。
/// 理由：这张卡回答的是"今天穿什么、要不要带伞"，与红石倒计时、今天的天气是同一个
/// 时间尺度 —— 它属于"此刻"，不属于下面那组"今日一览 / 继续读 / 快捷"。
/// 组内 12pt、组间 32pt 的节奏因此不用动，它天然落在天气卡下面 12pt 处。
///
/// 三条不能破的规矩：
/// 1. **卡片永远在**。没有建议、正在加载、请求失败 —— 三种情况都只换中间那几行字，
///    卡片本身不消失。首页忽然少一块，比一行灰字难解释得多（用户会以为功能被砍了）。
/// 2. **不自己发请求、不自己判缓存**。6 小时窗口、换地方作废、温差 >5℃ 作废，
///    全部在 `AIOutfitStore` 里（与 `WeatherStore` 同一套尺度）。这里只调 `load()`，
///    它在窗口内会直接返回 —— 所以"多调几次"是安全的。
/// 3. **失败保留旧建议**。失败时 Store 把旧建议标 `stale = true`，这里加一句「稍早的建议」。
///    用一次网络抖动换掉用户眼前一段好好的话，是最没道理的做法。
struct AIOutfitCard: View {

    @ObservedObject private var store = AIOutfitStore.shared

    /// 只为了拿"天气变了没有"这个信号（`weatherStamp` 变化 → 重新问一次）。
    /// 卡片不显示任何天气数字 —— 那是它上面那张天气卡的事。
    @ObservedObject private var weather = WeatherStore.shared

    /// 回前台补一次：6 小时窗口意味着缓存可能已经很旧，而回到 App 的那一刻
    /// 正是"今天要不要加件外套"最需要准确的时刻。
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // 淡青柠染色：与效果图第 5 屏那张 AI 卡同一个意思（"这块不是报表，是建议"）。
        // 走 `GlassCard` 的 tint 口子，不改 `GlassCard` 的任何默认行为。
        GlassCard(tint: Theme.lime.opacity(0.05)) {
            VStack(alignment: .leading, spacing: 10) {
                header
                bodyContent
                footer
            }
            .padding(Spacing.cardPadding)
        }
        // 天气一变就重新问一次。Store 自己按 6 小时窗口短路，所以它大多数时候什么都不做。
        .task(id: weatherStamp) {
            await store.load()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.load() }
        }
    }

    /// 天气指纹：**任何一项**变了就重新问一次。
    ///
    /// 为什么不是一个 `updatedAt`：它在服务端是可选字段，缺省时永远 nil ——
    /// 那样这张卡的 task 只在首次出现时跑过一次，而"天气已经到了、建议还没出来"
    /// 是最难解释的一种状态（卡片一直停在"拿到今天的天气后…"）。
    /// 用温度区间 + 天气文字一起做指纹，与 `AIOutfitStore` 判"要不要作废"用的是同一批字段。
    private var weatherStamp: String {
        guard let now = weather.current else { return "none" }

        let temp = now.temp.map { String($0) } ?? "-"
        let low = now.tMin.map { String($0) } ?? "-"
        let high = now.tMax.map { String($0) } ?? "-"
        let text = now.text ?? "-"
        let updated = now.updatedAt.map { String($0.timeIntervalSince1970) } ?? "-"

        return temp + "|" + low + "|" + high + "|" + text + "|" + updated
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.limeInk)

            // 眉题而不是标题：这张卡是"顺带一句"，不该和分区标题（22pt）抢层级
            Eyebrow(text: "今天穿什么", color: Theme.limeInk)

            Spacer(minLength: 8)

            refreshButton
        }
    }

    /// 手边那个小刷新：失败后要能重来，成功时用户也可能想"再问一次"。
    /// 不放在失败态里单独一个按钮 —— 那样成功态就没有手动入口了，两个状态两套控件。
    private var refreshButton: some View {
        Button {
            Haptics.light()
            Task { await store.load(force: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isLoading)
        .opacity(store.isLoading ? 0.35 : 1.0)
        .accessibilityLabel("重新生成穿搭建议")
    }

    // MARK: - 正文（四态：有建议 / 加载中 / 失败 / 没条件）

    @ViewBuilder
    private var bodyContent: some View {
        if let text = store.adviceText {
            // 有建议时优先显示建议 —— 哪怕同时在刷新（旧的那份仍比空白有用）
            Text(text)
                .font(Typography.bodySmall)
                .foregroundStyle(Theme.textBody)
                .lineSpacing(Typography.lineSpacing(fontSize: 16, multiple: 1.6))
                // 3~4 行：这是首页的摘要，不是阅读页。多出来的在聊天页里问
                .lineLimit(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else if store.isLoading {
            loadingLine
        } else if let error = store.lastError {
            errorLine(error)
        } else {
            // 既没建议、没在加载、也没报错 = 缺条件（没有定位 / 天气还没到）。
            // 说清"等什么"，而不是显示一个空壳
            Text("拿到今天的天气后，这里会给一句穿搭建议。")
                .font(Typography.footnote)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loadingLine: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.limeInk)
            Text("正在看今天的天气…")
                .font(Typography.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func errorLine(_ error: AIError) -> some View {
        HStack(spacing: 10) {
            Text(error.userMessage)
                .font(Typography.footnote)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.5))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                Haptics.light()
                // force: 用户在明确要求"再试一次"，不该被 6 小时窗口挡回来
                Task { await store.load(force: true) }
            } label: {
                Text("重试")
            }
            .buttonStyle(SecondaryCTAStyle())
        }
    }

    // MARK: - 脚注（模型 + 时间）

    @ViewBuilder
    private var footer: some View {
        if let text = footerText {
            Text(text)
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
    }

    /// 「DeepSeek · 2 小时前更新 · 稍早的建议」
    ///
    /// 为什么不写服务端生成时间而写"多久前"：用户关心的是这句话有多旧，
    /// 而不是它具体在几点几分生成 —— 后者还要他自己做减法。
    private var footerText: String? {
        guard let advice = store.advice else { return nil }

        var parts: [String] = []
        if let label = AIModelNaming.label(advice.model, models: []) {
            parts.append(label)
        }
        parts.append(Formatters.relative(advice.generatedAt) + "更新")
        if advice.stale {
            parts.append("稍早的建议")
        }
        return parts.joined(separator: " · ")
    }
}
