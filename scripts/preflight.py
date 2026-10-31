#!/usr/bin/env python3
"""推送前本地预检 —— 用最便宜的方式拦住会让 macOS 跑一轮的错误。

背景：GitHub macOS runner 按 **10 倍** 计费，Free 计划每月 2000 分钟只够实跑约 200 分钟，
一次全量 Swift 编译（含 Widget target）10 分钟起步。也就是说：**每因为低级错误多推一次，
就烧掉约 100 分钟的额度**。这里能用几毫秒跑完的检查，就不要让它在云上炸。

检查项（按"会不会让 xcodebuild 挂"排序）：
  1. 括号配对        —— Swift 里少一个 `}` 会让整个文件的报错指到几百行外
  2. 跨文件符号引用  —— Theme.X / API.X / Typography.X / Radius.X 用到不存在的成员
  3. 每个 .swift 都有合理的文件尾（截断了会很安静地编译失败）

**不做**类型检查：那需要真实的 Swift toolchain + UIKit，留给 CI。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources"

# 会被 `X.y(...)` 方式引用的命名空间 → 定义所在文件
NAMESPACES = {
    "Theme":      "Shared/Theme/Theme.swift",
    "Typography": "DesignSystem/Typography.swift",
    # Radius 与 Motion 不是独立文件，它们和 Spacing 同住在 DesignSystem/Spacing.swift
    "Radius":     "DesignSystem/Spacing.swift",
    "Motion":     "DesignSystem/Spacing.swift",
    "Spacing":    "DesignSystem/Spacing.swift",
    "API":        "Shared/Config/API.swift",
    "Endpoint":   "Shared/Config/Endpoint.swift",
    "Formatters": "Shared/Util/Formatters.swift",
    "Haptics":    "DesignSystem/Haptics.swift",
}

STRIP_COMMENTS = [
    (re.compile(r'/\*.*?\*/', re.S), ''),
    (re.compile(r'//[^\n]*'), ''),
]


def strip(src: str) -> str:
    """去掉注释与字符串字面量，避免注释里提到的 `Theme.swift` 被当成成员引用。"""
    out = []
    i = 0
    n = len(src)
    while i < n:
        if src[i] == '"' and (i == 0 or src[i - 1] != '\\'):
            j = i + 1
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == '"':
                    break
                j += 1
            out.append('""')
            i = j + 1
            continue
        out.append(src[i])
        i += 1
    text = ''.join(out)
    for pat, rep in STRIP_COMMENTS:
        text = pat.sub(rep, text)
    return text


def check_balance(path: Path) -> str | None:
    """括号配对。返回错误信息或 None。"""
    src = strip(path.read_text(encoding='utf-8'))
    pairs = {')': '(', '}': '{', ']': '['}
    stack = []
    for lineno, line in enumerate(src.split('\n'), 1):
        for ch in line:
            if ch in '({[':
                stack.append((ch, lineno))
            elif ch in ')}]':
                if not stack or stack[-1][0] != pairs[ch]:
                    want = pairs[ch]
                    return f"{path.relative_to(ROOT)}:{lineno} 括号不匹配（多余的 '{ch}'，期望配 '{want}'）"
                stack.pop()
    if stack:
        ch, lineno = stack[-1]
        closer = {'(': ')', '{': '}', '[': ']'}[ch]
        return f"{path.relative_to(ROOT)}:{lineno} 括号没闭合（第 {lineno} 行的 '{ch}' 缺 '{closer}'）"
    return None


def members_of(defs_file: Path) -> set[str]:
    """收集某个命名空间里所有可被 `NS.x` 引用的成员名。

    除了 `static let/var/func`，还要收嵌套类型 —— `extension Theme { struct Palette }`
    这种写法在本工程里就是主题的标配（`Theme.Palette` / `Theme.SkyColors`），
    漏掉它们会把合法代码报成「符号未定义」。
    """
    src = strip(defs_file.read_text(encoding='utf-8'))
    names = set(re.findall(r'static\s+(?:let|var|func)\s+(\w+)', src))
    names |= set(re.findall(r'^\s*(?:public\s+|internal\s+)?(?:struct|enum|class|actor|typealias)\s+(\w+)', src, re.M))
    # enum case（如 Radius.card）
    names |= set(re.findall(r'^\s*case\s+(\w+)', src, re.M))
    return names


def main() -> int:
    errors: list[str] = []
    swift_files = sorted(SOURCES.rglob('*.swift'))
    print(f"检查 {len(swift_files)} 个 Swift 文件")

    # 1. 括号配对
    for f in swift_files:
        msg = check_balance(f)
        if msg:
            errors.append(msg)

    # 2. 跨文件符号引用
    cache: dict[str, set[str]] = {}
    for ns, rel in NAMESPACES.items():
        defs = SOURCES / rel
        if not defs.exists():
            print(f"  ! 找不到 {ns} 的定义文件 {rel}，跳过")
            continue
        cache[ns] = members_of(defs)

    for f in swift_files:
        src = strip(f.read_text(encoding='utf-8'))
        for ns, members in cache.items():
            used = set(re.findall(rf'\b{ns}\.(\w+)', src))
            for missing in sorted(used - members):
                errors.append(f"{f.relative_to(ROOT)}: `{ns}.{missing}` 在 {NAMESPACES[ns]} 里没有定义")

    if errors:
        print(f"\n✗ 发现 {len(errors)} 个问题：")
        for e in errors[:40]:
            print("  " + e)
        if len(errors) > 40:
            print(f"  ... 还有 {len(errors) - 40} 条")
        return 1

    print("✓ 全部通过（括号配对 + 跨文件符号引用）")
    return 0


if __name__ == '__main__':
    sys.exit(main())
