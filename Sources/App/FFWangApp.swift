import SwiftUI

/// App 入口。
///
/// 采用 SwiftUI 生命周期（`App` + `WindowGroup`），**没有** UIApplicationDelegate / SceneDelegate，
/// 因此 Info.plist 里也不写 `UIApplicationSceneManifest`（写了反而可能让 SwiftUI 找不到 scene）。
///
/// 外观（批次 1 改动，PRD §3.4 第 4 条）：
/// V2 这里写死了 `.preferredColorScheme(.dark)`，并且 `Info.plist` 里还有
/// `UIUserInterfaceStyle = Dark` —— 两条一起把整个 App 的 trait 钉在深色上，
/// 设置里的三态开关会"点了没反应且编译器不报错"。现在：
///   · 写死的 `.dark` 换成 `AppearanceStore.shared.scheme`（`ColorScheme?`，nil = 跟随系统）；
///   · `Info.plist` 里那两条 key 已删除（见 Resources/Info.plist）；
///   · 根视图外面套 `ThemeScope`，把"生效后的外观"翻译成数值 token（光斑半径/强度）往下传。
///
/// 为什么 `preferredColorScheme` 挂在根视图而不是每个页面：
/// 它是窗口级偏好，值一变，整棵树用新的 trait **重新解析动态色**（不重建视图树，Tab 选中、
/// 滚动位置、已加载分页全部保留）。绝对不能用 `.id(appearance)` 强制重建 ——
/// 那会把 5 个常驻页面销毁，等于每次切外观都"重启一次 App"。
@main
struct FFWangApp: App {
    /// 全局唯一的只读数据容器，向下用 environmentObject 注入。
    @StateObject private var model: AppModel
    /// 外观三态的唯一状态源。用 `@StateObject` 包住单例，是为了让 App 的 body 订阅它的变化。
    @StateObject private var appearance: AppearanceStore
    /// 红石日程与规律（批次 2）。放在 App 层而不是页面里：概览卡与红石日历都要用，
    /// 页面级持有会导致"切一次 Tab 重建一次 Store、缓存白存"。
    @StateObject private var rock: RockStore
    /// 攻略流（批次 2）。单独一个 Store：它的生命周期与日历不同（二级入口、24h 缓存）
    @StateObject private var rockGuide: RockGuideStore
    /// 推送监控（批次 4）。放在 App 层：监控页、简报页底部那一行、「更多」行的状态字都要读它
    @StateObject private var monitor: MonitorStore
    /// 云控更新（3.8.0）。放在 App 层只有一个理由：**更新弹层要挂在 `RootView()` 外面**
    /// （见 `body` 里的注释），而它跟 `RootView` 一样由 App 持有最自然 ——
    /// 监控页那一行与冷启动检查读的是同一个单例，不需要走环境对象。
    @StateObject private var update: UpdateStore
    /// 场景阶段：实时活动**只在 `.active` 期间**评估（PRD §5.4 硬规则 + 决策 3）
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 协议缓存必须在第一个请求之前配好：靠服务端 ETag 白拿 304，App 侧不手写 If-None-Match。
        ImageCache.configure()
        _model = StateObject(wrappedValue: AppModel())
        _appearance = StateObject(wrappedValue: AppearanceStore.shared)
        _rock = StateObject(wrappedValue: RockStore())
        _rockGuide = StateObject(wrappedValue: RockGuideStore())
        _monitor = StateObject(wrappedValue: MonitorStore.shared)
        _update = StateObject(wrappedValue: UpdateStore.shared)
    }

    var body: some Scene {
        WindowGroup {
            // 注入顺序有讲究：ThemeScope 必须在 preferredColorScheme 的子树里才拿得到"生效后"的外观；
            // LayoutMetricsScope 必须在 ThemeScope **内部** —— 它不是要靠外观，而是"越靠近 RootView
            // 越能保证量到的就是 RootView 真正拿到的容器尺寸"。反过来套（Scope 在外）也能量，
            // 但一旦将来 ThemeScope 自身引入 padding 就会量偏，所以按"由外到内 = 由粗到细"排列。
            ThemeScope {
                LayoutMetricsScope {
                    RootView()
                        // 更新弹层挂在 `LayoutMetricsScope` **内部**、`RootView()` **外面**
                        // （设计文档 §5 T7 的 iPhone 回归风险点）：
                        // · 不进 `RootView` 的 body → 不动它那两条 `.transaction { $0.animation = nil }`，
                        //   也不动 B3 的条件渲染；
                        // · 在 `LayoutMetricsScope` 内部 → 弹层里读得到 `@Environment(\.layoutMetrics)`，
                        //   与页面里同一套宽/窄判定。
                        //
                        // 用 `.sheet(item:)` 而不是 `.sheet(isPresented:)`：内容闭包拿到的是
                        // **非可选**的 `AppRelease`，弹层里不需要再判空，也就没有"空弹层"这种中间态。
                        .sheet(item: $update.presentedRelease) { release in
                            UpdateSheet(release: release)
                        }
                }
            }
            .environmentObject(model)
            .environmentObject(rock)
            .environmentObject(rockGuide)
            .environmentObject(monitor)
            .preferredColorScheme(appearance.scheme)
            // 实时活动的前台循环（PRD §5.4 硬规则「仅前台」）：
            // · scenePhase == .active → 这个 task 开始跑，协调器每 60 秒评估一次
            //   （进窗口就启动 / 落地换文案 / 到点结束）；
            // · scenePhase 变化 → `.task(id:)` 取消旧任务 → 协调器的 defer 收尾，
            //   把仍在跑的活动按 `endAt` 交给系统移除（R19 保险，不依赖进程存活）。
            //
            // 排期数组每次 tick 现取（`rock.allLoadedDays`），不把它钉在闭包里 ——
            // 否则用户翻月 / 下拉刷新之后，活动判定用的还是启动那一刻的数据。
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await LiveActivityCoordinator.shared.monitorForeground {
                    rock.allLoadedDays
                }
            }
            // 天光实时活动（第二个实时活动）：同样挂在 scenePhase 上。
            // 两个 `.task(id: scenePhase)` 是允许的 —— 同一个 id 的两个 task 各自独立
            // 启动、各自独立取消，这正是 SwiftUI 给"一个信号多个消费者"的写法；
            // 天光不吃排期数据（日出日落在 `SunClock` 里现算），所以连闭包参数都没有。
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await DaylightActivityCoordinator.shared.monitorForeground()
            }
            // 远程配置（3.9.0）：挂在云控更新**之前**的第四个同 id task ——
            // 配置（minBuild / installGuideURL）是更新判定的输入，先到先备好。
            // 1 小时闸门在 `refreshIfNeeded()` 内部；失败静默、不清空旧值。
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await RemoteConfigStore.shared.refreshIfNeeded()
            }
            // 云控更新（3.8.0）：同样挂在 scenePhase 上，第三个同 id 的 task
            // （与上面两个各自独立启动、独立取消，这是 SwiftUI 给"一个信号多个消费者"的写法）。
            //
            // **不要**每次回前台都真发请求 —— `checkIfNeeded()` 内部有 6 小时闸门，
            // 一天最多 4 次；它同时保证"有新版本"的弹层不会反复弹出来烦人。
            // 冷启动这一次会在里面延后 3 秒，避开首屏那批并发请求。
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await UpdateStore.shared.checkIfNeeded()
            }
        }
    }
}
