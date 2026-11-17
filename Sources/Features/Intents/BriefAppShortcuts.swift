import AppIntents

/// Siri / 快捷指令的三条短语。
///
/// ## 为什么**每一句**短语都带 `\(.applicationName)`
/// 苹果的校验规则比直觉严：`appintentsmetadataprocessor` 会对**每一条** utterance
/// 检查「是否恰好包含一个 `${applicationName}`」，缺一句就整包报错、
/// 元数据不导出、Siri 完全看不到这个意图 ——
/// 即 `error: Invalid Utterance. Every App Shortcut utterance should have one '${applicationName}' in it.`
///
/// 所以这里没有"短说法"可用，每句都必须是完整的一句「用某个 App 做某事」。
/// 不写死「FF 大王」四个字的好处仍在：改名 / 上架换名时这里一个字都不用动
/// （`applicationName` 由系统从 Bundle 里取）。
///
/// 同一 `AppShortcut` 内的短语之间不能重复，跨 `AppShortcut` 也不能撞 ——
/// 撞了系统只会随机命中其中一个，另一条等于白写。
///
/// ## 为什么这里什么都不用注册
/// `AppShortcutsProvider` 在编译期被 AppIntents 元数据收集器扫到就生效，
/// `FFWangApp` 里不需要任何一行代码 —— 这也是本批**不改动任何现有文件**的原因。
struct BriefAppShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayBriefIntent(),
            phrases: [
                "用\(.applicationName)看看今天的简报",
                "让\(.applicationName)念一下今日简报",
                "\(.applicationName)查今天简报",
                "问\(.applicationName)今天的日常简报"
            ],
            shortTitle: "今日简报",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: SkyVersionIntent(),
            phrases: [
                "用\(.applicationName)查光遇版本",
                "问\(.applicationName)光遇更新了吗",
                "\(.applicationName)看看光遇版本",
                "让\(.applicationName)查光遇有没有更新"
            ],
            shortTitle: "光遇版本",
            systemImageName: "gamecontroller"
        )
        AppShortcut(
            intent: RedstoneIntent(),
            phrases: [
                "用\(.applicationName)查最近红石",
                "问\(.applicationName)最近红石什么时候",
                "\(.applicationName)最近三场红石",
                "让\(.applicationName)念念红石排期"
            ],
            shortTitle: "最近红石",
            systemImageName: "flame"
        )
    }
}
