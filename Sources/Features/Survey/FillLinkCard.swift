import SwiftUI
import CoreImage
#if canImport(UIKit)
import UIKit
#endif

/// 填答链接卡：链接文字 + 复制 + 二维码（PRD P09 / P11「分享链接」）。
///
/// 二维码为什么自己画：V3 的硬约束是零第三方依赖，而 `CIFilter.qrCodeGenerator()`
/// 是系统自带的能力（`CoreImage`），30 行就能出图 —— 引一个 QR 库换这 30 行不划算，
/// 还多一份要跟着 Xcode 更新的依赖。
struct FillLinkCard: View {
    let fillUrl: String

    /// 复制后的短提示（就地显示 1.8 秒，不弹 toast —— 它就在按钮旁边）
    @State private var justCopied: Bool = false

    init(fillUrl: String) {
        self.fillUrl = fillUrl
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SurveySectionLabel(text: "填答链接")

                HStack(alignment: .top, spacing: 14) {
                    qrCode
                    VStack(alignment: .leading, spacing: 10) {
                        Text(displayUrl)
                            .font(Typography.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .accessibilityLabel("填答链接")

                        HStack(spacing: 10) {
                            Button(action: copyLink) {
                                HStack(spacing: 5) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("复制")
                                        .font(Typography.footnoteMedium)
                                }
                                .foregroundStyle(Theme.limeInk)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .glassSurface(.floating, in: Capsule())
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("复制填答链接")

                            if justCopied {
                                Text("已复制")
                                    .font(Typography.captionXS)
                                    .foregroundStyle(Theme.limeInk)
                                    .transition(.opacity)
                            }
                        }

                        Text("谁拿到这个链接都能填，不需要登录。")
                            .font(Typography.captionXS)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(Spacing.cardPadding)
        }
    }

    // MARK: - 二维码

    @ViewBuilder
    private var qrCode: some View {
        #if canImport(UIKit)
        if let image = QRCodeRenderer.image(from: fillUrl, scale: 10) {
            Image(uiImage: image)
                // 二维码不能插值：双线性插值会把模块边缘糊成灰边，扫描识别率直接掉下来
                .interpolation(.none)
                .resizable()
                .frame(width: 96, height: 96)
                // 四周留白是二维码规范里的 quiet zone，去掉就扫不动
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                        .fill(Theme.qrCanvas)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
                        .strokeBorder(Theme.imageHairline, lineWidth: 1)
                }
                .accessibilityLabel("填答二维码")
        } else {
            qrFallback
        }
        #else
        qrFallback
        #endif
    }

    private var qrFallback: some View {
        RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous)
            .fill(Theme.surfaceTint3)
            .frame(width: 96, height: 96)
            .overlay {
                Image(systemName: "qrcode")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
            .accessibilityLabel("二维码没生成出来，请用复制链接")
    }

    // MARK: - 数据与动作

    private var displayUrl: String {
        let trimmed = fillUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "链接还没生成出来" : trimmed
    }

    private func copyLink() {
        guard !fillUrl.isEmpty else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = fillUrl
        #endif
        Haptics.success()
        withAnimation(Motion.glassIn) {
            justCopied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(Motion.glassOut) {
                justCopied = false
            }
        }
    }
}

// MARK: - 二维码生成

#if canImport(UIKit)
/// 用 CoreImage 生成二维码位图（零第三方依赖）。
///
/// 两条务实选择：
/// 1. 纠错级别用 `M`（15%）：`L` 省密度但脏屏/逆光下扫不出，`H` 会让码点变密、
///    小尺寸下模块粘连 —— 填答链接是"贴在屏幕上给别人扫"的场景，`M` 是折中点；
/// 2. 先把 CIImage 放大再导出 CGImage（不是让 `Image` 去缩放）：
///    位图放大是硬像素，交给视图缩放会被抗锯齿抹糊。
enum QRCodeRenderer {
    /// - Parameters:
    ///   - text: 要编码的内容（这里是填答链接）
    ///   - scale: 放大倍数（10 ≈ 250pt 级别的位图，缩到 96pt 显示仍然锐利）
    static func image(from text: String, scale: CGFloat = 10) -> UIImage? {
        guard !text.isEmpty else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
#endif
