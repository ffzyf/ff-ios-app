import SwiftUI

/// 全屏看图（P06 的"点图片全屏"）。
///
/// 转场实现：`matchedGeometryEffect`（iOS 14+）。**不用** iOS 26 才引入的整屏缩放转场符号：
/// 本机没有该 SDK，签名无法编译验证，一旦写错就是 CI 红。
/// `matchedGeometryEffect` 只要「来源与目标共享一个 Namespace + 一个 id」，就能从卡片位置
/// 平滑放大到全屏，关闭时原路缩回去（"回位不丢"）。
///
/// 视觉：纯黑画布 + 下滑关闭。纯黑是有意的例外（与正文 `ImageViewer` 同例）：
/// 看图时任何页面底色都会干扰对图片明暗的判断，黑底是唯一中性选择。
struct GuideZoomView: View {
    let item: GuideItem
    let transitionID: Int
    let namespace: Namespace.ID
    /// 关闭回调（由 `RockGuideView` 用 `withAnimation` 清状态，转场才动）
    let onClose: () -> Void

    @State private var dragOffset: CGFloat = 0

    /// 显式 init：`@State` 是 private 存储属性，memberwise init 会被降级成 private，
    /// 跨文件构造（`RockGuideView` 里）就调不到。
    init(item: GuideItem, transitionID: Int, namespace: Namespace.ID, onClose: @escaping () -> Void) {
        self.item = item
        self.transitionID = transitionID
        self.namespace = namespace
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            backdrop
            image
                .offset(y: dragOffset)
                .gesture(dragGesture)
        }
        .ignoresSafeArea()
        // 点空白（或点图本身）也能关：全屏看图里"返回"应该是零思考成本的
        .onTapGesture { close() }
        .accessibilityAction(named: "关闭") { close() }
    }

    // MARK: - 底

    private var backdrop: some View {
        // 全屏看图必须是纯黑画布（与 ImageViewer 同例，PRD 明确例外）：任何页面底色都会干扰对图片明暗的判断
        Color.black
            .opacity(backdropOpacity)
            .ignoresSafeArea()
    }

    /// 下滑越多底越透，给"正在拖走"一个视觉反馈
    private var backdropOpacity: Double {
        let distance = abs(dragOffset)
        let ratio = Double(distance / 320)
        return max(0.35, 1 - ratio)
    }

    // MARK: - 图

    @ViewBuilder
    private var image: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .matchedGeometryEffect(id: transitionID, in: namespace, isSource: false)
            case .failure:
                Text("这张图暂时取不到。")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(24)
            default:
                ProgressView()
            }
        }
    }

    private var imageURL: URL? {
        guard let raw = item.displayURL else { return nil }
        return URL(string: raw)
    }

    // MARK: - 手势

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // 只跟手纵向：横向滑动留给系统（左右滑不该误触关闭）
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    close()
                } else {
                    withAnimation(Motion.imageResize) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func close() {
        withAnimation(Motion.imageResize) {
            onClose()
        }
    }
}
