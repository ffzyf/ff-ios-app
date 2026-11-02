import CoreLocation
import SwiftUI

/// 设置页的「天气」组（3.7.0）：一行开关 + 一行位置 + 一句脚注。
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
///
/// ## 3.26.0：多了一行「天气位置」
/// 开关只能表达"要不要用设备位置"，表达不了"我要看另一座城市的天"。
/// 而用户在郑州与登封之间往返，两地的天经常完全不一样 —— 没有指定城市的入口，
/// 他唯一的办法是关掉开关，而关掉之后天气会回落到 `HomeCoordinate.cached()`
/// （上次上报的坐标），那是个他看不见也控制不了的地址。
///
/// 所以这一行的语义是**另一条轴**：开关管"读不读设备"，这一行管"看哪儿的天"。
/// 两者可以同时成立（跟随定位 + 什么都不指定），也可以分开（不读设备 + 固定登封）。
struct WeatherLocationSection: View {

    /// 与 `MonitorStore` / `ToastStore` 一样直接观察单例：设置页是模态呈现，
    /// `@ObservedObject` 不依赖环境对象是否被继承（`AppearanceSection` 同一个理由）。
    @ObservedObject private var store = LocationStore.shared

    /// 城市选择弹层是否呈现（3.26.0）
    @State private var showsPicker = false

    /// 显式空 init：与 `LiveActivitySection` 一致 —— 所有存储属性都是 private，
    /// 不写的话 memberwise init 会被降级成 private，跨文件 `WeatherLocationSection()` 编译不过。
    init() {}

    var body: some View {
        VStack(spacing: 8) {
            toggleRow
            cityRow

            // 3.17.0 修：小组件不再"始终用默认城市"。App 定位一拿到就把坐标上报到
            // `/api/app/home`，小组件读**同一条**记录（服务端只有一条，不需要设备标识，
            // 见 `Shared/Domain/HomeCoordinate.swift`）。这条脚注必须跟着改，
            // 否则界面在骗用户 —— 而"两边不是同一个地方"正是这次要修的那个问题。
            //
            // 3.26.0 补后半句：指定城市时同样会报一次，否则 App 显示登封、
            // 桌面小组件一直是郑州，用户会在同一块屏幕上看到两座城市。
            Text("App 与桌面小组件用同一个位置：定位或指定城市之后会上报一次，小组件读同一份记录。关闭定位后两者都沿用上次的位置。")
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
        .sheet(isPresented: $showsPicker) {
            // 关 sheet 的动作留在这一层：弹层自己不该知道它是怎么被呈现的
            WeatherCityPickerSheet(store: store) { showsPicker = false }
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

    // MARK: - 天气位置行（3.26.0）

    /// 「天气位置」：左边是**当前实际用的地名**，右边一个箭头进选择弹层。
    ///
    /// 为什么这里不显示"跟随定位 / 指定城市"这种模式词：用户问的是"我的天是哪儿的"，
    /// 模式只是实现细节。`displayName` 在跟随模式下就是反查出的地名，
    /// 指定模式下就是他自己选的那个 —— 一行字回答同一个问题，不需要他翻译。
    private var cityRow: some View {
        Button {
            Haptics.light()
            showsPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: store.mode == .fixed ? "mappin.and.ellipse" : "scope")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(store.mode == .fixed ? Theme.limeInk : Theme.textTertiary)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(placeTitle)
                        .font(Typography.callout)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(cityRowDetail)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Spacing.cardPadding)
            .padding(.vertical, 10)
            .frame(minHeight: Spacing.listItemMinHeight)
            .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("天气位置，" + placeTitle)
        .accessibilityHint("点按可指定城市")
    }

    /// 行首那行字：有名字就用名字（跟随模式是反查出的地名，指定模式是用户选的城）。
    ///
    /// 没名字时按开关分两种说法：**开着**是"还在等反查"（与天光页顶栏同一句），
    /// **关着**是"沿用上次的位置"（与下面那条脚注同一句）——
    /// 一律说"跟随定位"会在关掉开关时变成一句假话。
    private var placeTitle: String {
        if let name = store.displayName { return name }
        return store.isEnabled ? "定位中…" : "上次的位置"
    }

    /// 「天气位置」行的第二行：说清此刻**天气到底是怎么定位的**。
    ///
    /// 开关关着时不能说"跟随设备定位"（此时天气用的是 `HomeCoordinate.cached()`，
    /// 与上面 `subtitle` 同一个理由，两处必须同一套说法）。
    private var cityRowDetail: String {
        if store.mode == .fixed {
            return "指定城市 · 设备移动不影响天气"
        }
        return store.isEnabled ? "跟随设备定位，点按可指定城市" : "未使用设备定位，点按可指定城市"
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

    /// 副标题：先说**当前位置是怎么定的**（3.26.0），再处理拒绝态的补救办法。
    ///
    /// 顺序不能反：`fixed` 模式下即使定位权限被拒，天气照样有数据（用的是指定坐标），
    /// 这时挂一句"定位权限被关闭，去系统设置打开"就是在报一个不存在的问题。
    ///
    /// 两处都必须与上面那条脚注同一套说法（"关闭定位后沿用上次的位置"）。
    /// 写"关闭时用默认城市"就是自相矛盾 —— 而且假的是副标题：
    /// `WeatherStore.resolvedCoordinate()` 在定位关着时用的是 `HomeCoordinate.cached()`。
    private var subtitle: String {
        if store.mode == .fixed {
            return "固定在 " + (store.fixedName ?? "指定城市") + "；设备移动不会改变天气位置。"
        }
        // 开关关着：说"跟随设备定位"就是假话 —— 此时天气用的是 `HomeCoordinate.cached()`
        // （上次上报的位置），与上面那条脚注的"关闭定位后两者都沿用上次的位置"同一套说法。
        guard store.isEnabled else {
            return "未使用设备定位，天气沿用上次的位置；也可以直接指定城市。"
        }
        guard store.status != .denied else {
            return "定位权限被关闭，去 系统设置 › 隐私与安全性 › 定位服务 打开，或先沿用上次的位置。"
        }
        // "定位于 N 分钟前"回答的是"这个位置有多新"：15 分钟一轮的重定位是这次修复的核心，
        // 用户得能看见它在动，否则"天气跟着走"依然只是个说法。
        //
        // 拼成"N 分钟前定过位"而不是"定位于 N 分钟前"：`Formatters.relative` 在 60 秒内
        // 返回「刚刚」，套进后者会变成"定位于 刚刚"这种读不通的句子。
        var text = "跟随设备定位，移动超过 2 公里会自动更新。"
        if let last = store.lastFixedAt {
            let age = Formatters.relative(last)
            if age == "刚刚" {
                text += "刚刚定过位。"
            } else {
                text += age + "定过位。"
            }
        }
        return text
    }
}

// MARK: - 城市选择弹层（3.26.0）

/// 一个可选地点（快捷项与查询结果共用一个形状）
private struct WeatherPlace: Identifiable {

    let name: String
    let lat: Double
    let lon: Double

    /// `ForEach` 只需要"这行是谁"，名字 + 坐标已经唯一
    var id: String { "\(name)|\(lat),\(lon)" }
}

/// 指定天气位置的弹层。
///
/// 为什么做成同文件里的 `private struct` 而不是新文件：
/// 它是「位置偏好」这一个概念的第二个出口，逻辑不到 30 行；
/// 拆出去只会让"谁在改天气位置"散成两处，而这个 section 本来就该是唯一入口。
///
/// 三条交互决定：
/// 1. **输入 + 查询**而不是只给几个城市：用户可能在任何城市，硬编码列表一定不够；
/// 2. **给三个快捷项**：这次的需求就发生在郑州与登封之间，先给能省掉打字，
///    也避免地理编码把"登封"解析到别的省（同名地名不止一个）；
/// 3. **查询失败就地报错**（`Theme.statusError`），不弹 alert：alert 会盖住输入框，
///    而用户下一步动作明明是改写关键词。
private struct WeatherCityPickerSheet: View {

    @ObservedObject var store: LocationStore

    /// 选中 / 关闭后的收尾。关 sheet 由调用方做 —— 本 View 不认识自己是 sheet 还是页面
    let onClose: () -> Void

    @State private var query: String = ""
    @State private var isSearching = false
    /// 服务端（地理编码）说了什么，一句话，不出现错误码
    @State private var errorText: String?
    @FocusState private var isFocused: Bool

    /// 快捷项。坐标是点位中心，与天气的公里级网格精度匹配（不需要更细）
    private static let presets: [WeatherPlace] = [
        WeatherPlace(name: "登封", lat: 34.4553, lon: 113.0494),
        WeatherPlace(name: "郑州 · 惠济区", lat: 34.8670, lon: 113.6170),
        WeatherPlace(name: "郑州 · 金水区", lat: 34.7750, lon: 113.6600)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                header
                searchCard
                presetList
                restoreButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 18)
            .padding(.bottom, Spacing.sectionGap)
        }
        .scrollIndicators(.hidden)
        // `.medium` 放得下输入框 + 三个快捷项；要看完整列表再往上拖到 `.large`
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 头

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
                Text("天气位置")
                    .font(Typography.titleL)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                Text(stateLine)
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var stateLine: String {
        if store.mode == .fixed {
            return "当前固定在 " + fixedTitle + "；设备移动不会改变天气位置。"
        }
        return "当前跟随设备定位；选一个城市可以把它固定下来。"
    }

    /// `fixed` 模式下用户选的城市名（理论上不会缺，缺了也不该出现半个空句子）
    private var fixedTitle: String {
        return store.fixedName ?? "指定城市"
    }

    // MARK: - 输入

    private var searchCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("输入城市名")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)

                TextField("例如「洛阳」「郑州 · 金水区」", text: $query)
                    .font(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .submitLabel(.search)
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    // 回车即查询：这一步的唯一任务就是说出一个地名，不该还要求点一下按钮
                    .onSubmit { search() }

                if let message = errorText {
                    Text(message)
                        .font(Typography.captionXS)
                        .foregroundStyle(Theme.statusError)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer(minLength: 0)
                    Button(isSearching ? "查询中…" : "查询") {
                        search()
                    }
                    .buttonStyle(PrimaryCTAStyle())
                    .disabled(isSearching || trimmedQuery.isEmpty)
                }
            }
            // `GlassCard` 只画底板、不给内边距（全工程同一约定：内容自己 `.padding(Spacing.cardPadding)`），
            // 少了这一行输入框会贴着玻璃边缘
            .padding(Spacing.cardPadding)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 快捷项

    private var presetList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("常用地点")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
            VStack(spacing: 8) {
                ForEach(Self.presets) { place in
                    placeRow(place)
                }
            }
        }
    }

    private func placeRow(_ place: WeatherPlace) -> some View {
        Button {
            apply(place)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.limeInk)
                    .frame(width: 22, alignment: .center)
                Text(place.name)
                    .font(Typography.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                // 当前已经是这个城市：给一个勾，免得用户点了之后以为没生效
                if store.mode == .fixed, store.fixedName == place.name {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.limeInk)
                }
            }
            .padding(.horizontal, Spacing.cardPadding)
            .padding(.vertical, 10)
            .frame(minHeight: Spacing.listItemMinHeight)
            .glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 恢复跟随

    /// 用次级按钮样式：一屏里出现两个青柠胶囊，用户会以为两个都是"确认"。
    ///
    /// 已经在跟随模式下时置灰（不是隐藏）：这个动作的位置要稳定，
    /// 消失会让"我刚才选的那个城市怎么取消"变成一个要重新找的问题。
    private var restoreButton: some View {
        Button {
            store.clearFixed()
            onClose()
        } label: {
            Text("恢复跟随定位")
        }
        .buttonStyle(SecondaryCTAStyle())
        .disabled(store.mode != .fixed)
        .opacity(store.mode == .fixed ? 1 : 0.45)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - 动作

    /// 按城市名查坐标。
    ///
    /// 只取第一个 placemark：用户输入的是一个地名，返回一串同名地点让他在弹层里再选一次，
    /// 等于把问题原样丢回去。第一个结果通常是行政区中心，对"看哪儿的天气"足够。
    private func search() {
        let text = trimmedQuery
        guard !text.isEmpty, !isSearching else { return }
        Haptics.light()
        isSearching = true
        errorText = nil
        isFocused = false

        Task {
            defer { isSearching = false }
            do {
                let marks = try await CLGeocoder().geocodeAddressString(text)
                guard let mark = marks.first, let location = mark.location else {
                    errorText = "没找到「\(text)」，试试加上省或市"
                    return
                }
                let name = Self.label(from: mark) ?? text
                apply(WeatherPlace(name: name,
                                   lat: location.coordinate.latitude,
                                   lon: location.coordinate.longitude))
            } catch {
                // 网络失败 / 配额 / 该地址没有行政区划都走这里。不区分原因：
                // 对用户来说下一步都是"改一下关键词再试"
                errorText = "查询失败，检查网络后重试"
            }
        }
    }

    /// 选中即生效并关掉弹层（`setFixed` 内部会写盘、上报、重拉天气）
    private func apply(_ place: WeatherPlace) {
        store.setFixed(name: place.name, lat: place.lat, lon: place.lon)
        Haptics.success()
        onClose()
    }

    /// 从 `CLPlacemark` 拼两级地名，与 `LocationStore.placeLabel` 同一套规则：
    /// 「市」优先 `locality`，缺了退 `administrativeArea`；`subLocality` 有就再拼一级；
    /// 两级同名只留一级；都没有 → nil（交给调用方用用户输入的原文）。
    ///
    /// 这份规则在 `LocationStore` 里是 `private`，不为了复用而放开访问级别 ——
    /// 那会让"地名长什么样"多一个对外入口，而它本来就该由一个地方决定。
    private static func label(from mark: CLPlacemark) -> String? {
        let city = cleaned(mark.locality) ?? cleaned(mark.administrativeArea)
        let district = cleaned(mark.subLocality)

        switch (city, district) {
        case let (city?, district?):
            return city == district ? city : city + " · " + district
        case let (city?, nil):
            return city
        case let (nil, district?):
            return district
        case (nil, nil):
            return nil
        }
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value = value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
