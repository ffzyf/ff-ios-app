import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 预警数据源诊断（R1 · AC1-5 / Q7）

/// 预警区下方那行**低视觉权重**的诊断小字：接口、最近结果、请求/成功时刻、缓存兜底。
///
/// 为什么不新增一级卡片（架构 §1.1-4）：这是一条给「较真的人」核对用的元信息，
/// 和 `SkyRoomSourceFooter` 同一处理原则 —— 一旦给它底板/标题/图标，它就从
/// 「脚注」升格成「第六块卡」，用户会以为预警分两种数据来源。这里只用
/// `Theme.textTertiary` 的小字，权重压到最低。
///
/// 单一数据源：接口一栏固定 `Endpoint.alertsEndpointText`（预警只认这一条上游），
/// 诊断区不出现第二个地址；「上次成功的时刻」也不会被写成「现在的数据」。
struct SkyRoomAlertDiagnosticsView: View {

    let diagnostics: AlertDiagnostics
    let scale: CGFloat

    /// 点一下/长按复制后的短提示。不是动画驱动：`Task.sleep` 只负责把状态复位，
    /// 不用 `Timer`（DESIGN-RULES §2 禁止 Timer 驱动任何东西）。
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // ① 接口：如实显示，不缩写、不隐藏
            Text(diagnostics.endpoint)
                .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()

            // ② 最近结果 + 时刻 + 缓存头，逐项可缺（缺就整项不写，绝不补占位）
            HStack(spacing: 8) {
                Text("结果 " + diagnostics.lastResult)
                    .foregroundStyle(Theme.textTertiary)
                if let attempt = diagnostics.lastAttemptAt {
                    Text("请求 " + Formatters.timeHHmm(attempt))
                        .foregroundStyle(Theme.textTertiary)
                }
                if let success = diagnostics.lastSuccessAt {
                    Text("成功 " + Formatters.timeHHmm(success))
                        .foregroundStyle(Theme.textTertiary)
                }
                if let header = diagnostics.cacheHeader, !header.isEmpty {
                    Text("缓存 " + header)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .monospacedDigit()

            // ③ 当前显示是否来自缓存兜底；复制反馈只在这行尾部短暂出现
            HStack(spacing: 6) {
                Text(diagnostics.cacheUsed ? "显示的是缓存" : "实时结果")
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 4)
                Text(copied ? "已复制" : "点按/长按复制")
                    .foregroundStyle(Theme.textTertiary)
            }
            .font(SkyRoomMetrics.TextStyle.cardDetail(scale))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 整块可点：点一下复制、长按同样复制（两种习惯都覆盖）
        .contentShape(Rectangle())
        .onTapGesture { copy() }
        .onLongPressGesture(minimumDuration: 0.4) { copy() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(diagnostics.copyText)
        .accessibilityHint("点按或长按复制诊断信息")
    }

    /// 复制整段诊断文本。时间格式、缺项省略全由 `AlertDiagnostics.copyText` 决定，
    /// View 不重算、不拼第二份口径。
    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = diagnostics.copyText
        #endif
        copied = true
        Task { @MainActor in
            // reduceMotion 用户也不需要这段提示「动」起来：它只是一行会消失的字，
            // 没有位移/缩放/透明度动画，不受 DESIGN-RULES §2 的动效约束。
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}
