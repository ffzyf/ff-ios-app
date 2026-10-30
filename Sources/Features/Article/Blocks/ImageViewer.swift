import SwiftUI
import UIKit

/// 全屏看图（简单版）：黑底 + 等比完整显示 + 点任意位置或右上角关闭。
///
/// 刻意不做双指缩放与下滑关闭的位移跟随：这两样要 `MagnificationGesture` +
/// `DragGesture` + `matchedGeometryEffect` 三件套一起调，收益（缩放细节）远小于
/// 引入的手势冲突风险。P1 要放大看细节时再补，本轮先把「能看清全图」做稳。
struct ImageViewer: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 8)

            VStack {
                HStack {
                    Spacer(minLength: 8)
                    IconGlassButton(icon: "xmark", size: 36) {
                        dismiss()
                    }
                    .accessibilityLabel("关闭")
                }
                .padding(.horizontal, Spacing.page)
                .padding(.top, Spacing.gridUnit)
                Spacer(minLength: 0)
            }
        }
        // 点空白处关闭：图片本身不拦截，所以点图也算点背景
        .contentShape(Rectangle())
        .onTapGesture {
            dismiss()
        }
    }
}
