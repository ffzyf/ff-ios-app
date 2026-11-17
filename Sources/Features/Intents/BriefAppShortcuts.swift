import AppIntents

/// Siri / 快捷指令的三条短语。
///
/// ## 为什么每条都要一句带 `\(.applicationName)`
/// 苹果的校验规则是：每个 `AppShortcut` **至少要有一句短语包含 App 名**，
/// 否则系统在"念全名"这条最常用的路径上匹配不到意图。所以三条各自都补了
/// `用\(.applicationName)…` 那一句 —— 不写死「FF 大王」四个字，
/// 改名 / 上架换名时这里一个字都不用动（`applicationName` 由系统从 Bundle 里取）。
///
/// 另外几句是用户懒省事时的短说法："今天简报"、"光遇版本"、"最近红石"。
///
/// ## 为什么这里什么都不用注册
/// `AppShortcutsProvider` 在编译期被 AppIntents 元数据收集器扫到就生效，
/// `FFWangApp` 里不需要任何一行代码 —— 这也是本批**不改动任何现有文件**的原因。
struct BriefAppShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayBriefIntent(),
            phrases: [
                "看看今天的简报",
                "今天简报",
                "今日日常简报",
                "用\(.applicationName)看看今天的简报"
            ],
            shortTitle: "今日简报",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: SkyVersionIntent(),
            phrases: [
                "光遇版本",
                "看看光遇版本",
                "光遇更新了吗",
                "用\(.applicationName)查光遇版本"
            ],
            shortTitle: "光遇版本",
            systemImageName: "gamecontroller"
        )
        AppShortcut(
            intent: RedstoneIntent(),
            phrases: [
                "最近红石",
                "最近三场红石",
                "红石什么时候",
                "用\(.applicationName)查最近红石"
            ],
            shortTitle: "最近红石",
            systemImageName: "flame"
        )
    }
}
