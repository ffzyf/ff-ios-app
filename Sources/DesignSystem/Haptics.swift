import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 触觉

/// 触觉反馈封装。PRD §4.6：卡片按压 .light、刷新完成 / 复制 .success、错误 .error。
/// 全部走系统生成器，不申请任何权限。
///
/// **为什么放在 `DesignSystem/` 而不是 `Shared/`**（批次 4 搬家）：
/// `Shared/` 是被 Widget 扩展复用的目录，而 Widget target 开了
/// `APPLICATION_EXTENSION_API_ONLY = YES`。触觉生成器属于"宿主 App 才确定安全"的一类 API，
/// 放在 Shared 里等于让小组件跟着一起编译这段代码 —— 一旦某个 SDK 版本把它标成
/// extension-unavailable，整个 Widget target 会直接编译失败，而小组件压根不需要触觉。
///
/// 搬家对主 App 是零影响的：同一个 module，`Haptics.light()` 的 30+ 个调用点一个都不用改。
enum Haptics {
    /// 轻触（卡片按压、Tab 切换）。
    static func light() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    /// 成功（刷新完成、复制完成）。
    static func success() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    /// 选择（翻月、切换分段控件）。PRD §4 #7 单独一层：翻月是"在同一页里移动"，比 Tab 切换更轻
    static func selection() {
        #if canImport(UIKit)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }

    /// 失败（刷新失败、请求报错）。
    static func error() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        #endif
    }
}
