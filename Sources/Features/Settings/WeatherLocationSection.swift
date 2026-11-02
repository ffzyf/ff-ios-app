import SwiftUI

/// 设置页的「天气」组（3.7.0）：一行开关 + 一句脚注。
///
/// 职责很窄：把「用我的位置」这个偏好交给 `LocationStore`（由它申请「使用期间」权限、取坐标），
/// 自己不做请求。天气请求仍由 `WeatherStore` 走 `API.weather(lat:lon:)`。
///
/// 三条刻意的行为：
/// 1. **权限被拒时不弹任何自定义 UI**：副标题换成"去系统设置打开"，天气静默回落到默认城市。
///    多一个弹窗只会让用户在"我只是想看一眼天气"的时候多按一次确认。
/// 2. **拒绝态不置灰开关**：用户完全可能先去系统设置里打开，再回来切这个开关。
///    置灰会让人以为"这个 App 里永远开不了了"，然后放弃。
/// 3. **行样式复用现有设置行**：与 `LiveActivitySection` 的开关行同一套 metric
///    （22pt 图标列 + `Typography.callout` 标题 + `Typography.captionXS` 副标题 +
///    `Spacing.cardPadding` / `Spacing.listItemMinHeight` / `Radius.smallCard`），
///    不新造一套行样式。
struct WeatherLocationSection: View {

    /// 与 `MonitorStore` / `ToastStore` 一样直接观察单例：设置页是模态呈现，
    /// `@ObservedObject` 不依赖环境对象是否被继承（`AppearanceSection` 同一个理由）。
    @ObservedObject private var store = LocationStore.shared

    /// 显式空 init：与 `LiveActivitySection` 一致 —— 所有存储属性都是 private，
    /// 不写的话 memberwise init 会被降级成 private，跨文件 `WeatherLocationSection()` 编译不过。
    init() {}

    var body: some View {
        VStack(spacing: 8) {
            toggleRow

            // 3.17.0 修：小组件不再"始终用默认城市"。App 定位一拿到就把坐标上报到
            // `/api/app/home`，小组件读**同一条**记录（服务端只有一条，不需要设备标识，
            // 见 `Shared/Domain/HomeCoordinate.swift`）。这条脚注必须跟着改，
            // 否则界面在骗用户 —— 而"两边不是同一个地方"正是这次要修的那个问题。
            Text("App 与桌面小组件用同一个位置：定位成功后会上报一次，小组件读同一份记录。关闭后两者都沿用上次的位置。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.5))
                .padding(.horizontal, 4)
        }
        .onChange(of: store.status) { _, newValue in
            // 坐标刚就绪：作废天气内存缓存并立刻重拉一次，卡片才会当场换成当地天气
            // （`WeatherStore` 里也有一层"坐标变了就作废"的判断，这里只是把时机提前）
            guard newValue == .ready else { return }
            Task { await WeatherStore.shared.load(force: true) }
        }
    }

    // MARK: - 开关行

    private var toggleRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "location")
                .font(.system(size: 15, weight: .medium))
                // 关着时退到中性色：青柠图标配关闭的开关，会读成"已经生效了"
                .foregroundStyle(store.isEnabled ? Theme.limeInk : Theme.textTertiary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text("用我的位置")
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
                    // 拒绝态那句比正常态长一倍：允许自然换行。
                    // 截断会把"怎么打开"这半句吞掉，而它正是这条文案存在的理由。
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            // 刻意**不** `.disabled(...)`：见类型注释第 2 条
            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .tint(Theme.lime)
                .accessibilityLabel("用我的位置")
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: Spacing.listItemMinHeight)
        .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
    }

    /// 开关只负责写偏好：申请权限、取坐标、清缓存全在 `LocationStore.setEnabled(_:)` 里，
    /// 这样"关掉时必须一并清坐标"这件事只有一处实现。
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.isEnabled },
            set: { newValue in
                Haptics.light()
                store.setEnabled(newValue)
            }
        )
    }

    /// 副标题：正常态说"能做什么"，拒绝态说"为什么没生效 + 怎么修"
    ///
    /// 两处都必须与上面那条脚注同一套说法（"关闭后沿用上次的位置"）。
    /// 写"关闭时用默认城市"就是自相矛盾 —— 而且假的是副标题：
    /// `WeatherStore.resolvedCoordinate()` 在定位关着时用的是 `HomeCoordinate.cached()`。
    private var subtitle: String {
        guard store.status != .denied else {
            return "定位权限被关闭，去 系统设置 › 隐私与安全性 › 定位服务 打开，或先沿用上次的位置。"
        }
        return "用当前定位取当地天气；关闭后沿用上次的位置。"
    }
}
