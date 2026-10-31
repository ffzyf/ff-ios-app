import SwiftUI

// MARK: - 金额输入的解析规则（全程整数分）

/// 金额输入的**唯一**解析 / 过滤入口。
///
/// 为什么输入过程只存字符串：`"12."` 这种中间态用 `Double` 存会变成 `12`，
/// 光标与用户意图都被改掉；而 `0.1 + 0.2` 这类二进制误差会让「记成 12.30」显示成 12.29。
/// 所以字符串是输入阶段唯一的真相，**提交那一刻**才 `cents(from:)` 转成整数分。
///
/// 展示侧不做任何格式化：金额一律走 `EarningsMoney.formatCents`（全工程唯一的
/// `¥ + 千分位 + 两位小数` 实现，即需求里的那个 `money()`）。
/// 这里只多一个「输入框里那串字」的形态（去掉 `¥`、可再拆回无分组），
/// 且它是**从 `EarningsMoney` 派生**的，不另起一套格式化。
enum EarningsRecordAmount {

    /// 服务端 `MAX_CENTS`：¥1,000,000.00 = 100_000_000 分
    static let maxCents: Int = 100_000_000
    /// 整数位最多 7 位（1,000,000）
    private static let maxIntegerDigits: Int = 7
    /// 小数位硬限 2 位
    static let maxFractionDigits: Int = 2

    /// 输入框里该显示的那串字（带千分位、两位小数、**不带 `¥`**）。
    ///
    /// 实现刻意从 `EarningsMoney.formatCents` 去掉货币符号：全工程只有它在算
    /// 「分 → 元 + 分组 + 两位小数」，输入框不复制一份规则。
    static func editingText(cents: Int) -> String {
        let full = EarningsMoney.formatCents(cents)          // 形如 "¥1,234.50"
        return full.hasPrefix("¥") ? String(full.dropFirst()) : full
    }

    /// 无分组的纯数字文本（内部用：上限回填 / 与 `cents(from:)` 对得上）
    private static func plainText(cents: Int) -> String {
        return editingText(cents: cents).replacingOccurrences(of: ",", with: "")
    }

    /// 输入过程中的过滤（每次键盘变化都跑一遍）。
    ///
    /// 规则（都是"静默修正"，**不报错**）：
    /// · 只留 ASCII 数字与小数点，其余字符（空格、逗号、字母、汉字）直接丢弃；
    /// · 多余的小数点只认第一个；
    /// · 小数位超两位就拒绝后续输入；
    /// · 整数位去掉多余前导零（`"007"` → `"7"`，`"0.5"` 保持原样）；
    /// · 超过 `maxCents` 就回填上限 `"1000000.00"`（服务端会拒，没必要让用户按到才发现）。
    ///
    /// `""` / `"."` / `"12."` 都是**合法中间态**：这里原样放行，由 `cents(from:)` 决定语义。
    static func sanitize(_ raw: String) -> String {
        var integer = ""
        var fraction = ""
        var sawDot = false

        for character in raw {
            if character.isASCII && character.isNumber {
                if sawDot {
                    if fraction.count < maxFractionDigits {
                        fraction.append(character)
                    }
                } else if integer.count < maxIntegerDigits {
                    integer.append(character)
                }
            } else if character == "." {
                if sawDot == false {
                    sawDot = true
                }
            }
            // 其余字符：丢弃（非法字符直接过滤，不弹错）
        }

        while integer.count > 1 && integer.hasPrefix("0") {
            integer.removeFirst()
        }

        let body = sawDot ? integer + "." + fraction : integer
        if body.isEmpty {
            return sawDot ? "0." : ""
        }
        if let cents = cents(from: body), cents > maxCents {
            return plainText(cents: maxCents)
        }
        return body
    }

    /// 输入文本 → 整数分。解析不出来返回 `nil`（调用方据此禁用保存）。
    ///
    /// `""` / `"."` 返回 `nil`，`"0"` / `"12."` 返回 `0` / `1200` —— 中间态一律不算错误。
    /// **千分位逗号先去掉**：失焦后框里是 `"1,234.50"`（见 `editingText`），
    /// 若这里不认逗号，用户一失焦保存按钮就会莫名变灰。
    static func cents(from text: String) -> Int? {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard trimmed.isEmpty == false else { return nil }

        let parts = trimmed.components(separatedBy: ".")
        guard parts.count <= 2 else { return nil }

        let integerPart = parts[0]
        let fractionPart = parts.count == 2 ? parts[1] : ""
        guard integerPart.allSatisfy({ $0.isASCII && $0.isNumber }),
              fractionPart.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        // `Int(...)` 会在大数上溢出崩掉，先卡死位数（sanitize 已经把整数位限成 7 位）
        guard integerPart.count <= 9, fractionPart.count <= maxFractionDigits else { return nil }

        let integerValue = integerPart.isEmpty ? 0 : (Int(integerPart) ?? 0)
        let paddedFraction = String((fractionPart + "00").prefix(maxFractionDigits))
        let fractionValue = Int(paddedFraction) ?? 0
        return integerValue * 100 + fractionValue
    }
}

// MARK: - 金额输入框

/// 金额输入框：`decimalPad` + 两位小数硬限 + **失焦才插千分位**。
///
/// 三条交互约定（照网站版验证过的行为）：
/// 1. 输入过程中**不插**千分位 —— 每次插都会顶光标，输到第 5 位就跟打地鼠一样；
/// 2. 失焦时才把 `1234.5` 整成 `1,234.50`，让人一眼看出这不是 12,345；
/// 3. 重新聚焦时先把千分位去掉，之后打字不会因为逗号位置而跳光标。
struct EarningsRecordAmountField: View {

    @Binding private var text: String
    @FocusState.Binding private var isFocused: Bool
    /// 由上层用 `EarningsRecordAmount.cents(from:)` 算好传下来，避免两处各解析一次
    private let cents: Int?

    /// 显式 init：`@FocusState.Binding` 的属性包装类型不进 memberwise init 的推导，
    /// 写清楚比让编译器猜更安全（也让调用点一眼能看出这是「把焦点借进来」的字段）。
    init(text: Binding<String>, isFocused: FocusState<Bool>.Binding, cents: Int?) {
        self._text = text
        self._isFocused = isFocused
        self.cents = cents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EarningsRecordFieldLabel(text: "金额", accessory: "上限 " + EarningsMoney.formatCents(EarningsRecordAmount.maxCents))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textTertiary)
                TextField("0.00", text: $text)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .font(Typography.display)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .focused($isFocused)
                    .accessibilityLabel("金额")
                Spacer(minLength: 0)
            }
            .earningsRecordInputSurface()

            hint
        }
        .onChange(of: text) { _, newValue in
            // 只在输入过程中过滤；失焦后写进来的分组文本不再被改写
            guard isFocused else { return }
            let cleaned = EarningsRecordAmount.sanitize(newValue)
            if cleaned != newValue {
                text = cleaned
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                // 重新聚焦：去掉千分位，否则光标会被逗号一路往右顶
                text = text.replacingOccurrences(of: ",", with: "")
            } else if let cents, cents > 0 {
                // 失焦：统一成 1,234.50 的形态（0 / 空 不动，留着占位符）
                text = EarningsRecordAmount.editingText(cents: cents)
            }
        }
    }

    @ViewBuilder
    private var hint: some View {
        if let cents, cents > 0 {
            Text("记作 " + EarningsMoney.formatCents(cents))
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        } else {
            Text("小数最多两位，整数最多 7 位。")
                .font(Typography.captionXS)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
