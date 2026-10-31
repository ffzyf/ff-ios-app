import SwiftUI

/// 卡片 / 按钮的通用按压反馈（PRD §4.6：scale 0.97 + 亮度 −3%）。
/// 两端一致，不依赖任何系统按钮样式。
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .brightness(configuration.isPressed ? -0.03 : 0.0)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// 主 CTA：青柠实心胶囊。
///
/// 刻意**不用** `glassProminent`：设计文档 §5.5 有明确的混用禁令 ——
/// 同一屏内不允许「系统玻璃按钮」与「手工青柠胶囊」并排，否则同一页会出现两种玻璃语言。
/// 空态 / 错误页只有 1 个主 CTA，用青柠实心既能全版本一致，也守住「青柠是唯一强调色」。
struct PrimaryCTAStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.footnoteMedium)
            .foregroundStyle(Theme.onLime)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .background {
                Capsule().fill(Theme.lime)
            }
            .overlay {
                Capsule().strokeBorder(Theme.glassStrokeTop, lineWidth: 1)
            }
            .shadow(color: Theme.limeGlow, radius: 14, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// 次级按钮：玻璃胶囊 + 青柠描边（用于「返回列表」「换个时间再看」这类非主路径动作）
struct SecondaryCTAStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.footnoteMedium)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .glassSurface(.floating, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// 通用玻璃胶囊按钮（快捷入口三连 / 底部操作条的次要动作）。
/// 内部仍然走 `glassSurface` 唯一入口，所以 iOS 26 拿原生材质、18–25 拿手工配方。
struct CapsuleGlassButton: View {
    let title: String
    var icon: String? = nil
    var level: GlassLevel = .floating
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.limeInk)
                }
                Text(title)
                    .font(Typography.footnoteMedium)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassSurface(level, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// 圆形图标玻璃按钮（浮动返回 / 设置齿轮 / 回到顶部 / 全屏图右上角关闭）
///
/// `shortcut` 是**可选**的 ⌘ 主键，默认 `nil`（= 不挂快捷键），所以老调用点一位都不用改。
struct IconGlassButton: View {
    let icon: String
    var size: CGFloat = 36
    var level: GlassLevel = .floating
    /// ⌘ + 这个键（`KeyEquivalent` 有字素簇字面量，调用处直接写 `shortcut: "["`）。
    ///
    /// 为什么放在 `action` **之前**而不是存储属性表的最后：`action` 必须留在参数表末尾，
    /// 否则调用点惯用的尾随闭包（`IconGlassButton(icon:) { … }`）会匹配到 `shortcut` 上编译不过。
    /// 也就是说"加在末尾"实际只能加到"最后一个非闭包参数"之后。
    ///
    /// 为什么要这个参数：`.keyboardShortcut` 的语义是"assigns it to the **modified control**"，
    /// 挂在包了一层的自定义 View 上不保证被注册进快捷键表（三处调用点就是这么写的）。
    /// 快捷键只有挂到真正吃点击的那个 `Button` 上才算数，而那个 `Button` 只有本文件能碰到 ——
    /// 所以能力必须从这里开口，而不是继续在页面层对包装 View 加修饰器。
    var shortcut: KeyEquivalent? = nil
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: size, height: size)
                .glassSurface(level, in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        // 修饰器紧贴 `Button`（`buttonStyle` 不改变"被修饰的控件"是谁），
        // 条件挂在修饰器内部完成 —— 用一个空分支包住 Button 会让它多一层容器，
        // 而多出来的容器在 HStack 里会影响对齐。
        .modifier(OptionalCommandShortcut(shortcut: shortcut))
    }
}

/// 把「可选快捷键」收成一条修饰器：`nil` 时**原样返回**，不注册任何键。
///
/// 为什么不直接写 `if let` 包一层：那样 `nil` 分支要么重复整段 Button、要么留一个
/// `if` 的空分支视图，两者都会改变视图树形状；修饰器的两个分支返回的都是"同一块内容"，
/// 布局与身份都不受影响。
private struct OptionalCommandShortcut: ViewModifier {
    let shortcut: KeyEquivalent?

    func body(content: Content) -> some View {
        if let shortcut = shortcut {
            content.keyboardShortcut(shortcut, modifiers: .command)
        } else {
            content
        }
    }
}
