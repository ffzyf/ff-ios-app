import SwiftUI

/// 每条 assistant 气泡下方的常驻动作行（5.1.2 · R4b / R4c，架构 §1.4）。
///
/// 四个动作：朗读 / 暂停·继续 / 停止 / 复制。
/// · 朗读复用 `SpeechStore`（`POST /api/app/tts`，本期不改后端、不引入新音频通道），
///   `speak()` 内部已按 600 字夹好稿（与后端 `MAX_CHARS` 一致），这里只传原文；
/// · `message.status == .streaming` 时**整行置灰并给明确不可用态**（AC4-4），
///   `== .done` 才可用；历史会话消息走同一气泡渲染路径 → 天然全覆盖；
/// · 失败时沿用 `SpeechStore.failureText` 的人话，不自己编；
/// · `SpeechStore` 是全局单例，同一时刻只有一段在播：任意气泡的「暂停 / 停止」
///   都作用于当前那一段，语义一致，不需要为每条消息再存一份「谁在播」。
struct AIChatMessageActions: View {

    @ObservedObject private var speech = SpeechStore.shared

    let text: String

    /// 仅 `.done` 可用：流式中 / 半截 / 失败都置灰（AC4-4）。
    let isAvailable: Bool

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                action(icon: "speaker.wave.2", title: "朗读") {
                    Task { await speech.speak(text) }
                }
                .disabled(!isAvailable || speech.isBusy)

                action(icon: speech.isPaused ? "play.fill" : "pause.fill",
                       title: speech.isPaused ? "继续" : "暂停") {
                    if speech.isPaused { speech.resume() } else { speech.pause() }
                }
                .disabled(!isAvailable || !speech.isBusy)

                action(icon: "stop.fill", title: "停止") {
                    speech.stop()
                }
                .disabled(!isAvailable || !speech.isBusy)

                action(icon: copied ? "checkmark" : "doc.on.doc",
                       title: copied ? "已复制" : "复制") {
                    copy()
                }
                .disabled(!isAvailable)

                Spacer(minLength: 0)
            }
            .opacity(isAvailable ? 1 : 0.45)

            if !isAvailable {
                Text("回答完成后可朗读、复制")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            } else if let failure = speech.failureText {
                Text(failure)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func action(icon: String,
                        title: String,
                        perform: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            perform()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(Typography.captionXS)
            }
            .foregroundStyle(Theme.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}
