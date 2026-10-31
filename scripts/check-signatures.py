#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Swift 静态签名核对器（离线近似编译器的第一道闸门）。

本机没有 Swift 编译器，CI 一次只报第一个错误，一轮往返 10 分钟。这个脚本把
「调用点签名 vs 定义点签名」的一致性一次性核完，目标是**零误报**：
只报确定的冲突，宁可漏报也不刷屏。

核对项：
  1. `static func` / `func` 定义与 `enum case` 关联值的参数标签序列 vs
     `Type.method(...)` / `Self.method(...)` 调用点的实参标签序列
     （区分 `_ x` 与 `label x`）。
  2. 参数个数（带默认值的参数记为可选，允许调用时省略）。
  3. 把 `static let` 属性当函数调用（`Spacing.card()` 这类「cannot call value」）。
  4. View 的显式 init 与调用点是否匹配；私有存储属性却漏写显式 init。
  5. `@EnvironmentObject` 是否有对应注入点。
  6. `Sources/Shared/` 下的 `import UIKit` 是否被 `#if canImport(UIKit)` 包裹。

降噪策略（这些情况一律不报）：
  · 同名重载：只要任一重载能匹配就不再往下查。
  · 尾随闭包：`foo(a: 1) { ... }` 与 `if foo(a: 1) {` 无法在文本层区分，
    两种解释都试一遍，只有在「带闭包」解释能匹配、或两种都不匹配时才判定。
  · 闭包字面量实参、`\\.method` keypath、`#if` 分支里的重复定义。
  · 外部类型（SwiftUI / Foundation 的 `Color`、`Animation`、`View` 等）完全排除。

已知不覆盖（宁可漏报，避免刷屏）：
  · 静态/实例错用（`Type.instanceMethod()`）—— 只看标签，不看 static 修饰。
  · 不带类型限定的裸调用（`method(...)`，调用方与定义同作用域）。
  · `@EnvironmentObject` 只做「根层级或同文件有注入」的相对检查，不做完整
    SwiftUI 视图树可达性分析。
  · 泛型约束、协议见证、`@ViewBuilder` 泛型推断。

用法：
    python3 scripts/check-signatures.py            # 人读报告
    python3 scripts/check-signatures.py --quiet    # 只输出结论（给 CI 用）
    python3 scripts/check-signatures.py --sources Sources

退出码：0 = 无冲突；1 = 有冲突；2 = 路径不存在。
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Set, Tuple

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

#: 任务点名的命名空间，报告里单独统计覆盖情况。
REQUIRED_NAMESPACES: Tuple[str, ...] = (
    "Formatters",
    "RedstoneClock",
    "RedstoneTimeline",
    "ThemeMetrics",
    "Haptics",
    "Spacing",
    "Typography",
    "Radius",
    "Motion",
    "API",
    "RockPhaseText",
    "RockMarkStyle",
    "CoverSeed",
    "ShareSheet",
)

#: 外部框架类型：它们的成员由 SDK 提供，文本层看不到定义，必须整体排除。
EXTERNAL_TYPES: Set[str] = {
    "String", "Substring", "Character", "Int", "Int8", "Int16", "Int32", "Int64",
    "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Double", "Float", "Bool",
    "Array", "Set", "Dictionary", "Optional", "Result", "Range", "ClosedRange",
    "Date", "URL", "UUID", "Data", "Error", "Calendar", "TimeZone", "Locale",
    "DateFormatter", "ISO8601DateFormatter", "NumberFormatter", "Bundle",
    "JSONDecoder", "JSONEncoder", "Timer", "Notification", "NotificationCenter",
    "Color", "Font", "Animation", "View", "Text", "Image", "VStack", "HStack",
    "ZStack", "Group", "AnyView", "AnyShapeStyle", "AnyTransition",
    "ShapeStyle", "AngularGradient", "LinearGradient", "RadialGradient",
    "Material", "EnvironmentValues", "EnvironmentKey", "AnimationTimingCurve",
    "UIView", "UIColor", "UIFont", "UIScreen", "UIImage", "UIActivityViewController",
    "UIViewController", "UIImpactFeedbackGenerator", "UINotificationFeedbackGenerator",
    "UISelectionFeedbackGenerator", "NSObject", "CGRect", "CGSize", "CGPoint",
    "CGFloat", "CGColor", "EdgeInsets", "Alignment", "Axis", "HorizontalAlignment",
    "VerticalAlignment", "UnitPoint", "Angle", "Path", "GraphicsContext",
    "ImageRenderer", "Charts", "ScrollView", "Spacer", "Divider", "Button",
    "Binding", "State", "StateObject", "EnvironmentObject", "ObservedObject",
    "Published", "ObservableObject", "ViewBuilder", "ViewModifier", "App", "Scene",
    "WindowGroup", "Task", "MainActor", "Never", "Void", "Protocol", "Self",
}

#: 属性包装器里具备 `init(wrappedValue:)` 的，会参与 memberwise init。
WRAPPERS_IN_MEMBERWISE: Set[str] = {
    "State", "Binding", "StateObject", "ObservedObject", "FocusState",
    "AppStorage", "SceneStorage", "GestureState",
}

#: 控制流关键字：`if foo(x: 1) {` 里的 `{` 不是尾随闭包。
CONTROL_KEYWORDS: Tuple[str, ...] = ("if", "guard", "while", "switch", "for", "case")

IDENT = r"[A-Za-z_][A-Za-z0-9_]*"

UNKNOWN = "<unknown>"  #: 参数标签无法解析时的哨兵，命中即放弃该定义


# ---------------------------------------------------------------------------
# 数据结构
# ---------------------------------------------------------------------------


@dataclass
class Param:
    """一个形参的解析结果。"""

    label: Optional[str]  # None = 无标签（`_ x`），UNKNOWN = 解析失败
    name: str
    has_default: bool
    raw: str

    @property
    def optional(self) -> bool:
        """调用时是否可以省略。"""
        return self.has_default


@dataclass
class FuncDef:
    """一个函数定义。"""

    type_name: str  # "" = 全局函数
    name: str
    params: List[Param]
    is_static: bool
    file: str
    line: int
    start: int  #: 在原文中的起始偏移，用于排序输出

    @property
    def labels(self) -> List[str]:
        return [("_" if p.label is None else str(p.label)) for p in self.params]

    @property
    def ident_label(self) -> str:
        """形如 `a:_:b:` 的紧凑标签串，用于报告。"""
        return "".join(
            ("_:" if p.label is None else f"{p.label}:") for p in self.params
        ) or "(无参数)"

    @property
    def type_signature(self) -> str:
        """形参类型指纹（去空白后的类型段拼接）。

        只看标签（`ident_label`）不足以判断重复定义：`resolve(_ status: SkyStatus?)`
        与 `resolve(_ app: SkyAppVersion?)` 是合法重载，Swift 不会报
        invalid redeclaration；反过来，仅内部名不同、类型相同的两个定义才会真的重名。
        所以重复定义判定必须把类型段纳入 key。
        """
        parts: List[str] = []
        for p in self.params:
            if ":" in p.raw:
                parts.append(re.sub(r"\s+", "", p.raw.split(":", 1)[1]))
            else:
                parts.append(re.sub(r"\s+", "", p.raw))
        return "|".join(parts)

    @property
    def where(self) -> str:
        return f"{self.file}:{self.line}"


@dataclass
class CallSite:
    """一个 `Type.method(...)` 调用点。"""

    qualifier: str
    name: str
    args: List[Tuple[str, str]]  # (label 或 "_", 原文)
    has_trailing_brace: bool
    file: str
    line: int
    enclosing_type: str = ""

    @property
    def labels(self) -> List[str]:
        return [a[0] for a in self.args]

    @property
    def ident_label(self) -> str:
        return "".join(f"{lb}:" for lb in self.labels) or "(无实参)"

    @property
    def where(self) -> str:
        return f"{self.file}:{self.line}"


@dataclass
class Conflict:
    """一处确定的签名冲突。"""

    kind: str
    call: CallSite
    detail: str
    defs: List[FuncDef] = field(default_factory=list)


# ---------------------------------------------------------------------------
# 第一步：把注释与字符串字面量抹成空格（保留换行，偏移不变）
# ---------------------------------------------------------------------------


def _skip_balanced_paren(text: str, i: int) -> int:
    """从 `text[i] == '('` 起跳过一段配对括号，返回闭括号之后的位置。

    用于字符串插值 `\\(...)`：内部可能再嵌字符串，这里粗暴地跳过引号。
    """
    n = len(text)
    depth = 0
    while i < n:
        c = text[i]
        if c == "(":
            depth += 1
            i += 1
        elif c == ")":
            depth -= 1
            i += 1
            if depth == 0:
                return i
        elif c == '"':
            i = _skip_string(text, i)
        elif c == "\\":
            i += 2
        else:
            i += 1
    return n


def _skip_string(text: str, i: int) -> int:
    """从 `text[i]` 起跳过一段字符串字面量（支持原始串 / 多行串），返回之后的位置。"""
    n = len(text)
    hash_count = 0
    j = i
    while j < n and text[j] == "#":
        hash_count += 1
        j += 1
    if j >= n or text[j] != '"':
        return i + 1  # 不是字符串开头，别卡死
    terminator = '"' + "#" * hash_count
    triple = text.startswith('"""', j)
    if triple:
        terminator = '"""' + "#" * hash_count
        j += 3
    else:
        j += 1
    while j < n:
        if text.startswith(terminator, j):
            return j + len(terminator)
        c = text[j]
        if c == "\\" and hash_count == 0:
            if text.startswith("\\(", j):
                j = _skip_balanced_paren(text, j + 1)
                continue
            j += 2
            continue
        if not triple and c == "\n":
            return j  # 未闭合的单行串，止损
        j += 1
    return n


def mask_source(text: str) -> str:
    """把注释与字符串字面量替换为空格，保持长度与换行不变。

    Args:
        text: 原始 Swift 源码。

    Returns:
        与入参等长的「结构骨架」文本，可安全用正则做结构分析。
    """
    out = list(text)
    n = len(text)
    i = 0

    def blank(a: int, b: int) -> None:
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if c == "/" and nxt == "/":
            j = text.find("\n", i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif c == "/" and nxt == "*":
            depth, j = 1, i + 2
            while j < n and depth > 0:
                if text.startswith("/*", j):
                    depth += 1
                    j += 2
                elif text.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            blank(i, j)
            i = j
        elif c == '"':
            j = _skip_string(text, i)
            blank(i, j)
            i = j
        elif c == "#" and re.match(r"#+\"", text[i:i + 8] or ""):
            j = _skip_string(text, i)
            blank(i, j)
            i = j
        else:
            i += 1
    return "".join(out)


def build_depth_map(masked: str) -> List[int]:
    """返回每个偏移处的花括号深度（`{` 之后深度立即 +1）。"""
    depths = [0] * (len(masked) + 1)
    depth = 0
    for idx, ch in enumerate(masked):
        depths[idx] = depth
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
    depths[len(masked)] = depth
    return depths


def line_of(text: str, pos: int) -> int:
    """偏移 → 1 基行号。"""
    return text.count("\n", 0, pos) + 1


# ---------------------------------------------------------------------------
# 第二步：找类型作用域
# ---------------------------------------------------------------------------


@dataclass
class TypeScope:
    """一个 `struct` / `class` / `enum` / `extension` / `actor` / `protocol` 的作用域。"""

    kind: str
    name: str
    brace_start: int
    brace_end: int
    body_depth: int  #: 成员所在的深度
    file: str
    line: int
    qual_name: str = ""  #: 带父级路径的名字（`ArticleResponse.CodingKeys`），用于区分同名嵌套类型


TYPE_DECL_RE = re.compile(rf"\b(struct|class|enum|actor|extension|protocol)\s+({IDENT})")


def find_type_scopes(masked: str, depths: List[int], file: str, raw: str) -> List[TypeScope]:
    """扫描全部类型声明并计算其花括号区间。"""
    scopes: List[TypeScope] = []
    n = len(masked)
    for m in TYPE_DECL_RE.finditer(masked):
        kind, name = m.group(1), m.group(2)
        brace = masked.find("{", m.end())
        if brace < 0:
            continue
        # 花括号可能属于 `where` 子句之后的体，直接配对
        depth, j = 0, brace
        end = -1
        while j < n:
            ch = masked[j]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = j
                    break
            j += 1
        if end < 0:
            continue
        scopes.append(
            TypeScope(
                kind=kind,
                name=name,
                brace_start=brace,
                brace_end=end,
                body_depth=depths[brace] + 1,
                file=file,
                line=line_of(raw, m.start()),
            )
        )
    _assign_qualified_names(scopes)
    return scopes


def _assign_qualified_names(scopes: List[TypeScope]) -> None:
    """给每个作用域补上带父级路径的名字。

    `ArticleResponse.CodingKeys` 与 `BriefResponse.CodingKeys` 是两个不同的类型，
    只用裸名会把它们当成重复定义（误报）。
    """
    by_start = sorted(scopes, key=lambda s: s.brace_start)
    for sc in by_start:
        parent: Optional[TypeScope] = None
        for cand in by_start:
            if cand is sc:
                continue
            if cand.brace_start < sc.brace_start < cand.brace_end:
                if parent is None or cand.brace_start > parent.brace_start:
                    parent = cand
        sc.qual_name = f"{parent.qual_name}.{sc.name}" if parent else sc.name


def enclosing_type(scopes: Sequence[TypeScope], pos: int) -> Optional[TypeScope]:
    """返回包含 pos 的最内层类型作用域。"""
    best: Optional[TypeScope] = None
    for sc in scopes:
        if sc.brace_start < pos < sc.brace_end:
            if best is None or sc.brace_start > best.brace_start:
                best = sc
    return best


# ---------------------------------------------------------------------------
# 第三步：解析参数列表
# ---------------------------------------------------------------------------


def find_matching_paren(masked: str, open_idx: int) -> int:
    """返回与 `masked[open_idx] == '('` 配对的 `)` 下标（找不到返回 -1）。"""
    depth = 0
    j = open_idx
    n = len(masked)
    while j < n:
        c = masked[j]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return -1


def split_top_level(text: str) -> List[str]:
    """按顶层逗号切分（忽略 `()` `[]` `{}` `<>` 内部以及函数类型里的逗号）。"""
    parts: List[str] = []
    depth = 0
    angle = 0
    start = 0
    n = len(text)
    for i, c in enumerate(text):
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "<" and depth == 0:
            prev = text[i - 1] if i > 0 else ""
            nxt = text[i + 1] if i + 1 < n else ""
            # 只在「紧贴标识符」的位置当作泛型开括号，避开 `a < b`
            if prev and (prev.isalnum() or prev in "_])>" ) and nxt != "=":
                angle += 1
        elif c == ">" and depth == 0:
            prev = text[i - 1] if i > 0 else ""
            if prev == "-":
                continue  # 箭头 `->`，不是泛型闭括号
            if angle > 0:
                angle -= 1
        elif c == "," and depth == 0 and angle == 0:
            parts.append(text[start:i])
            start = i + 1
    tail = text[start:]
    if tail.strip() or parts:
        parts.append(tail)
    return [p for p in parts if p.strip()]


ATTR_RE = re.compile(r"@[A-Za-z_][A-Za-z0-9_]*(?:\([^()]*\))?")


def parse_param(seg: str) -> Param:
    """解析单个形参 / 实参片段。

    Args:
        seg: 形如 `_ dayKey: String` / `dayKey: String = ""` / `for id: String`。

    Returns:
        Param；`label` 为 None 表示无标签，为 UNKNOWN 表示无法解析。
    """
    raw = seg.strip()
    # 去掉 `@escaping` / `@ViewBuilder` 之类的属性前缀
    body = ATTR_RE.sub(" ", raw).strip()
    # 切掉默认值
    head, has_default = body, False
    depth = 0
    for i, c in enumerate(body):
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "=" and depth == 0:
            prev = body[i - 1] if i > 0 else ""
            nxt = body[i + 1] if i + 1 < len(body) else ""
            if prev not in "=<>!" and nxt != "=":
                head = body[:i]
                has_default = True
                break
    head = head.strip()

    m = re.match(rf"^({IDENT})\s+({IDENT})\s*:", head)
    if m:
        first = m.group(1)
        return Param(
            label=None if first == "_" else first,
            name=m.group(2),
            has_default=has_default,
            raw=raw,
        )
    m = re.match(rf"^({IDENT})\s*:", head)
    if m:
        return Param(label=m.group(1), name=m.group(1), has_default=has_default, raw=raw)
    # `_ x` 但 sep 不是 `:` 的情况，或纯位置参数
    m = re.match(rf"^({IDENT})\s+({IDENT})", head)
    if m:
        first = m.group(1)
        return Param(
            label=None if first == "_" else first,
            name=m.group(2),
            has_default=has_default,
            raw=raw,
        )
    return Param(label=UNKNOWN, name=head, has_default=has_default, raw=raw)


def parse_params(inside: str) -> List[Param]:
    """解析一整段参数列表文本。"""
    return [parse_param(seg) for seg in split_top_level(inside)]


def parse_call_args(inside: str) -> List[Tuple[str, str]]:
    """解析实参列表，返回 [(label 或 "_", 原文)]。"""
    result: List[Tuple[str, str]] = []
    for seg in split_top_level(inside):
        s = seg.strip()
        if not s:
            continue
        if s.startswith("{") or s.startswith("\\"):
            result.append(("_", s))
            continue
        m = re.match(rf"^({IDENT})\s*:(?!:)", s)
        if m and not re.match(rf"^{IDENT}\s*\?", s):
            result.append((m.group(1), s))
        else:
            result.append(("_", s))
    return result


# ---------------------------------------------------------------------------
# 第四步：收集定义
# ---------------------------------------------------------------------------

FUNC_RE = re.compile(rf"\bfunc\s+({IDENT})\s*(?:<[^{{}}]*>)?\s*\(")
STATIC_PROP_RE = re.compile(
    rf"^[ \t]*(?:(?:public|internal|fileprivate|package)\s+)?static\s+"
    rf"(?:let|var)\s+({IDENT})\s*:",
    re.MULTILINE,
)
CASE_LINE_RE = re.compile(r"^[ \t]*(?:indirect[ \t]+)?case[ \t]+(.+)$", re.MULTILINE)
CASE_ITEM_RE = re.compile(rf"^({IDENT})\s*(?:\((.*)\))?$", re.DOTALL)


def parse_case_params(inside: str) -> List[Param]:
    """解析 enum case 的关联值列表（`server(code: Int, message: String)`）。

    与函数形参的区别：裸类型 `case paragraph(String)` 是**无标签**关联值，
    而 `case heading(level: Int, text: String)` 是带标签的。
    """
    params: List[Param] = []
    for seg in split_top_level(inside):
        s = seg.strip()
        if not s:
            continue
        m = re.match(rf"^({IDENT})\s+({IDENT})\s*:", s)
        if m:
            params.append(Param(label=m.group(1), name=m.group(2), has_default=False, raw=s))
            continue
        m = re.match(rf"^({IDENT})\s*:", s)
        if m:
            params.append(
                Param(label=m.group(1), name=m.group(1), has_default=False, raw=s)
            )
            continue
        params.append(Param(label=None, name=s, has_default=False, raw=s))
    return params


def collect_enum_cases(
    masked: str, raw: str, file: str, depths: List[int], scopes: Sequence[TypeScope]
) -> List[FuncDef]:
    """收集 enum 的 case 声明，把它们当成「构造器」参与签名比对。"""
    defs: List[FuncDef] = []
    for m in CASE_LINE_RE.finditer(masked):
        pos = m.start()
        scope = enclosing_type(scopes, pos)
        if scope is None or scope.kind != "enum":
            continue
        if depths[pos] != scope.body_depth:
            continue
        for item in split_top_level(m.group(1)):
            im = CASE_ITEM_RE.match(item.strip())
            if not im:
                continue
            payload = im.group(2)
            defs.append(
                FuncDef(
                    type_name=scope.qual_name,
                    name=im.group(1),
                    params=parse_case_params(payload) if payload else [],
                    is_static=True,
                    file=file,
                    line=line_of(raw, pos),
                    start=pos,
                )
            )
    return defs


def collect_defs(
    masked: str, raw: str, file: str, depths: List[int], scopes: Sequence[TypeScope]
) -> Tuple[List[FuncDef], Dict[str, Set[str]]]:
    """收集一个文件里的全部函数定义与 static 属性名。"""
    defs: List[FuncDef] = []
    props: Dict[str, Set[str]] = {}
    for m in FUNC_RE.finditer(masked):
        pos = m.start()
        scope = enclosing_type(scopes, pos)
        if scope is not None:
            if depths[pos] != scope.body_depth:
                continue  # 嵌套函数 / 闭包里的函数，不是成员
            type_name = scope.qual_name
        else:
            if depths[pos] != 0:
                continue  # 函数体内的局部函数
            type_name = ""
        open_idx = masked.find("(", m.end() - 1)
        close_idx = find_matching_paren(masked, open_idx)
        if close_idx < 0:
            continue
        params = parse_params(masked[open_idx + 1:close_idx])
        # 判断是否静态：本行或前几行里有 `static`
        line_start = masked.rfind("\n", 0, pos) + 1
        prefix = masked[line_start:pos]
        is_static = bool(re.search(r"\bstatic\b", prefix)) or bool(
            re.search(r"\bclass\b", prefix) and type_name != ""
        )
        defs.append(
            FuncDef(
                type_name=type_name,
                name=m.group(1),
                params=params,
                is_static=is_static,
                file=file,
                line=line_of(raw, pos),
                start=pos,
            )
        )
    for m in STATIC_PROP_RE.finditer(masked):
        scope = enclosing_type(scopes, m.start())
        if scope is None:
            continue
        props.setdefault(scope.qual_name, set()).add(m.group(1))
    return defs, props


# ---------------------------------------------------------------------------
# 第五步：收集调用点
# ---------------------------------------------------------------------------

CALL_RE = re.compile(rf"(?<![A-Za-z0-9_.\\])([A-Z][A-Za-z0-9_]*)\.({IDENT})\s*(?=\()")
SELF_CALL_RE = re.compile(rf"(?<![A-Za-z0-9_.\\])Self\.({IDENT})\s*(?=\()")


def collect_calls(
    masked: str, raw: str, file: str, scopes: Sequence[TypeScope]
) -> List[CallSite]:
    """收集 `Type.method(...)` 与 `Self.method(...)` 调用点。"""
    calls: List[CallSite] = []
    for regex, is_self in ((CALL_RE, False), (SELF_CALL_RE, True)):
        for m in regex.finditer(masked):
            open_idx = m.end()
            if masked[open_idx] != "(":
                continue
            close_idx = find_matching_paren(masked, open_idx)
            if close_idx < 0:
                continue
            if is_self:
                scope = enclosing_type(scopes, m.start())
                qualifier = scope.qual_name if scope else "Self"
                name = m.group(1)
            else:
                qualifier = m.group(1)
                name = m.group(2)
            args = parse_call_args(masked[open_idx + 1:close_idx])
            # 尾随闭包探测：`)` 之后（可跨行）紧跟 `{`
            k = close_idx + 1
            while k < len(masked) and masked[k] in " \t\r\n":
                k += 1
            trailing = k < len(masked) and masked[k] == "{"
            if trailing and _preceded_by_control_keyword(masked, m.start()):
                trailing = False
            calls.append(
                CallSite(
                    qualifier=qualifier,
                    name=name,
                    args=args,
                    has_trailing_brace=trailing,
                    file=file,
                    line=line_of(raw, m.start()),
                    enclosing_type=(enclosing_type(scopes, m.start()) or TypeScope(
                        "", "", 0, 0, 0, "", 0
                    )).name,
                )
            )
    return calls


def _preceded_by_control_keyword(masked: str, pos: int) -> bool:
    """调用点是否处在 `if` / `guard` / `while` 等条件表达式里。"""
    line_start = masked.rfind("\n", 0, pos) + 1
    # 向前看两行，够覆盖 `guard let a = foo(` 这类换行写法
    prev_break = masked.rfind("\n", 0, max(0, line_start - 1))
    window = masked[max(0, prev_break + 1):pos]
    return bool(re.search(r"\b(" + "|".join(CONTROL_KEYWORDS) + r")\b", window))


# ---------------------------------------------------------------------------
# 第六步：签名匹配
# ---------------------------------------------------------------------------


def match_formal_to_actual(
    formal: Sequence[str], optional: Sequence[bool], actual: Sequence[str]
) -> bool:
    """形参标签序列能否吃下这组实参标签（Swift 允许省略任意带默认值的形参）。

    规则：实参与形参保持声明顺序，形参可以跳过的前提是它有默认值。

    Args:
        formal: 形参外部标签序列（`_` 表示无标签）。
        optional: 与 `formal` 等长，True 表示该形参可省略。
        actual: 实参标签序列。

    Returns:
        是否匹配。
    """
    if len(actual) > len(formal):
        return False
    i = 0  # 形参游标
    j = 0  # 实参游标
    while j < len(actual):
        if i >= len(formal):
            return False
        if formal[i] == actual[j]:
            i += 1
            j += 1
        elif optional[i]:
            i += 1
        else:
            return False
    # 剩下的形参必须都能省略
    return all(optional[k] for k in range(i, len(formal)))


def match_formal_with_closure(
    formal: Sequence[str], optional: Sequence[bool], actual: Sequence[str]
) -> bool:
    """带尾随闭包的匹配：尾随闭包额外吃掉一个形参，且**会丢掉实参标签**。

    Swift 的尾随闭包绑定到「显式实参之后的第一个非可选形参」，所以
    `GlassCard(level: .card) { ... }` 能匹配 `init(level:cornerRadius:tint:content:)`
    —— `content:` 的标签被尾随闭包语法丢掉。这是本脚本最容易误报的地方。

    Args:
        formal: 形参外部标签序列。
        optional: 与 `formal` 等长，True 表示可省略。
        actual: 显式写出的实参标签序列（不含尾随闭包）。

    Returns:
        是否匹配。
    """
    i = 0
    j = 0
    while j < len(actual):
        if i >= len(formal):
            return False
        if formal[i] == actual[j]:
            i += 1
            j += 1
        elif optional[i]:
            i += 1
        else:
            return False
    # 尾随闭包落到「下一个非可选形参」；全是可选就落到最后一个
    while i < len(formal) and optional[i]:
        i += 1
    if i >= len(formal):
        return True
    return all(optional[k] for k in range(i + 1, len(formal)))


def labels_match(defn: FuncDef, labels: Sequence[str]) -> bool:
    """实参标签序列能否匹配该函数定义（考虑默认值省略）。"""
    if any(p.label == UNKNOWN for p in defn.params):
        return False
    return match_formal_to_actual(
        defn.labels, [p.optional for p in defn.params], list(labels)
    )


def labels_match_with_closure(defn: FuncDef, labels: Sequence[str]) -> bool:
    """带尾随闭包时能否匹配该函数定义。"""
    if any(p.label == UNKNOWN for p in defn.params):
        return False
    return match_formal_with_closure(
        defn.labels, [p.optional for p in defn.params], list(labels)
    )


def check_calls(
    defs: Sequence[FuncDef],
    calls: Sequence[CallSite],
    static_props: Dict[str, Set[str]],
) -> Tuple[List[Conflict], int]:
    """逐调用点比对，返回 (冲突列表, 实际核对过的调用数)。"""
    by_key: Dict[Tuple[str, str], List[FuncDef]] = {}
    by_bare: Dict[Tuple[str, str], List[FuncDef]] = {}
    for d in defs:
        by_key.setdefault((d.type_name, d.name), []).append(d)
        by_bare.setdefault((d.type_name.split(".")[-1], d.name), []).append(d)

    conflicts: List[Conflict] = []
    checked = 0

    for call in calls:
        # 先按全名找，再按裸名回退（调用点只写得出裸名，如 `Formatters.x`）
        candidates = by_key.get((call.qualifier, call.name)) or by_bare.get(
            (call.qualifier, call.name)
        )
        if not candidates:
            if call.name in static_props.get(call.qualifier, set()):
                conflicts.append(
                    Conflict(
                        kind="属性当函数调用",
                        call=call,
                        detail=(
                            f"`{call.qualifier}.{call.name}` 是 static 存储属性，"
                            f"不能加括号调用"
                        ),
                    )
                )
            # 方法不存在：可能是 SDK 提供，文本层无法判定，不报
            continue

        checked += 1
        labels = call.labels
        if any(labels_match(d, labels) for d in candidates):
            continue
        # 尾随闭包解释：闭包会额外吃掉一个形参，且丢掉它的标签
        if call.has_trailing_brace and any(
            labels_match_with_closure(d, labels) for d in candidates
        ):
            continue

        # 走到这里 = 没有任何重载能接受这组实参
        formal_set = sorted({d.ident_label for d in candidates})
        detail = (
            f"`{call.qualifier}.{call.name}` 实参 {call.ident_label} "
            f"({len(labels)} 个) 与定义 {', '.join(formal_set)} 不匹配"
        )
        if call.has_trailing_brace:
            detail += "（已排除尾随闭包解释）"
        conflicts.append(
            Conflict(kind="标签/个数不符", call=call, detail=detail, defs=list(candidates))
        )

    return conflicts, checked


# ---------------------------------------------------------------------------
# 第七步：View init 核对
# ---------------------------------------------------------------------------

VIEW_DECL_RE = re.compile(rf"\bstruct\s+({IDENT})\s*(?:<[^{{}}]*>)?\s*:\s*[^{{}}]*\bView\b")
STORED_PROP_RE = re.compile(
    rf"^[ \t]*(?P<prefix>(?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^()\n]*\))?|"
    rf"(?:private|public|internal|fileprivate|package)(?:\(set\))?|"
    rf"static|class|lazy|weak|unowned|nonisolated)\s+)*)"
    rf"(?:let|var)\s+(?P<name>{IDENT})\s*:",
    re.MULTILINE,
)
INIT_DECL_RE = re.compile(rf"\binit\s*\??\s*\(")


def _property_shape(masked: str, name_end: int) -> Tuple[bool, bool, bool]:
    """判断一个 `let`/`var` 声明的形态。

    只看类型标注之后的第一个「有意义字符」：
    `{` 说明是计算属性 / 带观察器的属性（不是存储属性，不参与 memberwise init）；
    `=` 说明有默认值。注释与字符串已被抹成空格，所以可以直接扫。

    Optional 类型（`URL?` / `Int!`）在 memberwise init 里等价于有 `nil` 默认值，
    所以也计入 `has_default`，否则会把 `@State private var x: URL?` 误判成必填。

    Args:
        masked: 掩码后的源码。
        name_end: 属性名之后（`:` 之后）的偏移。

    Returns:
        (是否计算属性, 是否有默认值, 是否 Optional)
    """
    n = len(masked)
    j = name_end
    computed = False
    while j < n:
        c = masked[j]
        if c == "{":
            computed = True
            break
        if c == "=" or c in "\n}":
            break
        j += 1
    if computed:
        return True, False, False
    type_text = masked[name_end:j].strip()
    is_optional = type_text.endswith("?") or type_text.endswith("!")
    has_default = (j < n and masked[j] == "=") or is_optional
    return False, has_default, is_optional


def collect_inits(
    masked: str, depths: List[int], scopes: Sequence[TypeScope]
) -> Dict[str, List[Param]]:
    """收集一个文件里所有显式 `init(...)` 的形参（含写在 extension 里的）。"""
    out: Dict[str, List[Param]] = {}
    for m in INIT_DECL_RE.finditer(masked):
        scope = enclosing_type(scopes, m.start())
        if scope is None or depths[m.start()] != scope.body_depth:
            continue
        open_idx = m.end() - 1
        close_idx = find_matching_paren(masked, open_idx)
        if close_idx < 0:
            continue
        out.setdefault(scope.qual_name, parse_params(masked[open_idx + 1:close_idx]))
    return out


def collect_views(
    masked: str,
    raw: str,
    file: str,
    depths: List[int],
    scopes: Sequence[TypeScope],
    inits_by_type: Dict[str, List[Param]],
) -> List[ViewInfo]:
    """找出文件里所有 `struct X: View`，提取 init / 存储属性 / @EnvironmentObject。"""
    views: List[ViewInfo] = []
    for scope in scopes:
        if scope.kind != "struct":
            continue
        decl = None
        for m in VIEW_DECL_RE.finditer(masked, max(0, scope.brace_start - 400)):
            if m.group(1) == scope.name and m.start() < scope.brace_start:
                decl = m
        if decl is None:
            continue

        store_props: List[Param] = []
        private_props: List[str] = []
        private_required: List[str] = []
        env_objects: List[str] = []

        for m in STORED_PROP_RE.finditer(masked, scope.brace_start, scope.brace_end):
            if depths[m.start()] != scope.body_depth:
                continue
            prefix = m.group("prefix") or ""
            if re.search(r"\bstatic\b", prefix):
                continue
            name = m.group("name")
            computed, has_default, _ = _property_shape(masked, m.end())
            if computed:
                continue  # `var body: some View {` 这类是计算属性
            wrappers = re.findall(r"@([A-Za-z_][A-Za-z0-9_]*)", prefix)
            is_private = bool(re.search(r"\b(private|fileprivate)\b", prefix))
            if "EnvironmentObject" in wrappers:
                env_objects.append(name)
            participates = not wrappers or any(
                w in WRAPPERS_IN_MEMBERWISE for w in wrappers
            )
            if not participates:
                continue
            if is_private:
                private_props.append(name)
                if not has_default:
                    private_required.append(name)
            store_props.append(
                Param(label=name, name=name, has_default=has_default, raw=name)
            )

        explicit = inits_by_type.get(scope.qual_name)
        views.append(
            ViewInfo(
                name=scope.name,
                file=file,
                line=scope.line,
                has_explicit_init=explicit is not None,
                init_params=explicit if explicit is not None else store_props,
                private_props=private_props,
                private_required=private_required,
                injected_env_objects=env_objects,
                scope=scope,
            )
        )
    return views


@dataclass
class ViewInfo:
    """一个 View 类型的构造信息。"""

    name: str
    file: str
    line: int
    has_explicit_init: bool
    init_params: List[Param]
    private_props: List[str]
    private_required: List[str]
    injected_env_objects: List[str]
    scope: TypeScope


VIEW_CALL_RE = re.compile(rf"(?<![A-Za-z0-9_.\\])([A-Z][A-Za-z0-9_]*)\s*\(")


def check_view_calls(
    views: Dict[str, ViewInfo], masked_by_file: Dict[str, str], raw_by_file: Dict[str, str]
) -> Tuple[List[str], List[str], int]:
    """核对 View 构造点实参。

    Returns:
        (确定冲突, 约定偏差（不致命）, 无显式 init 且含无默认值私有属性的 View, 核对过的构造点数)
    """
    problems: List[str] = []
    convention: List[str] = []
    missing_init: List[str] = []
    checked = 0

    for name, info in sorted(views.items()):
        if not info.private_props or info.has_explicit_init:
            continue
        if info.private_required:
            # `private let x: T`（无默认值）会让 memberwise init 变成 private，
            # 跨文件构造一定报 "initializer is inaccessible due to 'private' protection level"
            missing_init.append(
                f"{info.file}:{info.line}  `struct {name}` 含无默认值的私有存储属性 "
                f"{info.private_required} 却未写显式 init → memberwise init 被降级为 private，"
                f"跨文件构造编译不过"
            )
        else:
            convention.append(
                f"{info.file}:{info.line}  `struct {name}` 私有存储属性 {info.private_props} "
                f"全部带默认值，未写显式 init（批次 1/2 约定要求补，但当前不影响编译）"
            )

    for file, masked in masked_by_file.items():
        raw = raw_by_file[file]
        for m in VIEW_CALL_RE.finditer(masked):
            name = m.group(1)
            info = views.get(name)
            if info is None:
                continue
            open_idx = m.end() - 1
            close_idx = find_matching_paren(masked, open_idx)
            if close_idx < 0:
                continue
            checked += 1
            args = parse_call_args(masked[open_idx + 1:close_idx])
            labels = [a[0] for a in args]
            params = info.init_params
            formal = [("_" if p.label is None else str(p.label)) for p in params]
            if any(p.label == UNKNOWN for p in params):
                continue
            if match_formal_to_actual(formal, [p.optional for p in params], labels):
                continue
            # 尾随闭包 / @ViewBuilder 内容用花括号传：补一个无标签实参再试
            k = close_idx + 1
            while k < len(masked) and masked[k] in " \t\r\n":
                k += 1
            if k < len(masked) and masked[k] == "{":
                if match_formal_with_closure(
                    formal, [p.optional for p in params], labels
                ):
                    continue
            problems.append(
                f"{file}:{line_of(raw, m.start())}  `{name}({', '.join(labels)})` "
                f"与 init 形参 ({', '.join(formal)}) 不匹配"
            )
    return problems, convention, missing_init, checked


# ---------------------------------------------------------------------------
# 第八步：@EnvironmentObject 注入核对
# ---------------------------------------------------------------------------

ENV_OBJ_DECL_RE = re.compile(
    rf"@EnvironmentObject\s+(?:(?:private|public|internal|fileprivate)\s+)*"
    rf"var\s+({IDENT})\s*:\s*({IDENT})"
)
STATE_OBJ_DECL_RE = re.compile(
    rf"@(?:StateObject|ObservedObject|State)\s+(?:(?:private|public|internal|fileprivate)\s+)*"
    rf"var\s+({IDENT})\s*(?::\s*({IDENT}))?"
)
ENV_OBJ_INJECT_RE = re.compile(rf"\.environmentObject\s*\(\s*({IDENT})\s*\)")


def check_environment_objects(
    masked_by_file: Dict[str, str], raw_by_file: Dict[str, str]
) -> Tuple[List[str], List[str], List[str]]:
    """核对每个 `@EnvironmentObject` 是否有「够用」的注入点。

    判定规则（比"全工程存在注入"严格，比完整作用域分析保守）：
    某个视图消费类型 T，必须满足下列任一条件，否则视作注入缺失：
      1. `FFWangApp.swift` / `RootView.swift`（根层级）里注入了 T；
      2. 消费该类型的那一行所在的文件自己注入了 T（局部重新注入，如 sheet 内容）。

    Returns:
        (确定缺少注入的清单, 注入点清单, 在用的类型列表)
    """
    root_basenames = {"FFWangApp.swift", "RootView.swift"}

    # 变量名 → 类型（跨文件，取声明处）
    var_types: Dict[str, str] = {}
    needed: List[Tuple[str, str, str, int]] = []  # (文件, 变量, 类型, 行)
    for file, masked in masked_by_file.items():
        raw = raw_by_file[file]
        for m in STATE_OBJ_DECL_RE.finditer(masked):
            if m.group(2):
                var_types.setdefault(m.group(1), m.group(2))
        for m in ENV_OBJ_DECL_RE.finditer(masked):
            needed.append((file, m.group(1), m.group(2), line_of(raw, m.start())))
            var_types.setdefault(m.group(1), m.group(2))

    injections: List[str] = []
    root_injected: Set[str] = set()
    file_injected: Dict[str, Set[str]] = {}
    for file, masked in masked_by_file.items():
        raw = raw_by_file[file]
        for m in ENV_OBJ_INJECT_RE.finditer(masked):
            var = m.group(1)
            typ = var_types.get(var, "?")
            file_injected.setdefault(file, set()).add(typ)
            if Path(file).name in root_basenames:
                root_injected.add(typ)
            injections.append(
                f"{file}:{line_of(raw, m.start())}  .environmentObject({var}) → {typ}"
            )

    missing: List[str] = []
    used: Set[str] = set()
    for file, var, typ, line in needed:
        used.add(typ)
        if typ in root_injected or typ in file_injected.get(file, set()):
            continue
        missing.append(
            f"{file}:{line}  `@EnvironmentObject {var}: {typ}` 既没在 FFWangApp/RootView "
            f"注入，也没在同文件局部注入 → 运行期崩溃（编译不报）"
        )
    return missing, injections, sorted(used)


# ---------------------------------------------------------------------------
# 第九步：Shared 目录 import UIKit 必须被 #if canImport(UIKit) 包裹
# ---------------------------------------------------------------------------


def check_uikit_guard(root: Path) -> Tuple[List[str], List[str]]:
    """检查 `Sources/Shared/` 下每个 `import UIKit` 是否处在 canImport 条件编译块内。"""
    offenders: List[str] = []
    ok: List[str] = []
    shared = root / "Shared"
    if not shared.is_dir():
        return offenders, ok
    for path in sorted(shared.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        stack: List[str] = []
        for lineno, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("#if"):
                stack.append(stripped)
            elif stripped.startswith("#elseif"):
                if stack:
                    stack[-1] = stripped
            elif stripped.startswith("#endif"):
                if stack:
                    stack.pop()
            elif re.match(r"^import\s+UIKit\b", stripped):
                guarded = any("canImport(UIKit)" in frame for frame in stack)
                rel = f"{path.relative_to(root)}:{lineno}"
                if guarded:
                    ok.append(rel)
                else:
                    offenders.append(
                        f"{rel}  `import UIKit` 未被 `#if canImport(UIKit)` 包裹"
                        f"（Widget target 复用会编译失败）"
                    )
    return offenders, ok


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------


def load_sources(sources_dir: Path) -> Tuple[Dict[str, str], Dict[str, str]]:
    """读取全部 .swift，返回 (原文, 掩码后文本)，键为相对路径。"""
    raw_by_file: Dict[str, str] = {}
    masked_by_file: Dict[str, str] = {}
    for path in sorted(sources_dir.rglob("*.swift")):
        rel = str(path.relative_to(sources_dir.parent))
        text = path.read_text(encoding="utf-8")
        raw_by_file[rel] = text
        masked_by_file[rel] = mask_source(text)
    return raw_by_file, masked_by_file


def main(argv: Optional[Sequence[str]] = None) -> int:
    """脚本入口。"""
    parser = argparse.ArgumentParser(description="Swift 调用签名 × 定义签名 静态核对")
    parser.add_argument(
        "--sources",
        default=None,
        help="Sources 目录（默认：脚本所在工程的 Sources）",
    )
    parser.add_argument("--quiet", action="store_true", help="只输出结论")
    args = parser.parse_args(argv)

    root = Path(args.sources).resolve() if args.sources else (
        Path(__file__).resolve().parent.parent / "Sources"
    )
    if not root.is_dir():
        print(f"[ERROR] 找不到 Sources 目录: {root}", file=sys.stderr)
        return 2

    raw_by_file, masked_by_file = load_sources(root)
    if not quiet(args):
        print(f"扫描：{root}")
        print(f"文件：{len(raw_by_file)} 个 .swift")

    all_defs: List[FuncDef] = []
    all_calls: List[CallSite] = []
    all_views: Dict[str, ViewInfo] = {}
    static_props: Dict[str, Set[str]] = {}
    declared_types: Set[str] = set()

    per_file: Dict[str, Tuple[List[int], List[TypeScope]]] = {}
    inits_by_type: Dict[str, List[Param]] = {}

    # 第一遍：作用域 / 定义 / init（init 可能写在 extension 里，必须全局聚合后再核对 View）
    for file, masked in masked_by_file.items():
        raw = raw_by_file[file]
        depths = build_depth_map(masked)
        scopes = find_type_scopes(masked, depths, file, raw)
        per_file[file] = (depths, scopes)
        for sc in scopes:
            declared_types.add(sc.name)
        defs, props = collect_defs(masked, raw, file, depths, scopes)
        all_defs.extend(defs)
        all_defs.extend(collect_enum_cases(masked, raw, file, depths, scopes))
        for k, v in props.items():
            static_props.setdefault(k, set()).update(v)
        all_calls.extend(collect_calls(masked, raw, file, scopes))
        for name, params in collect_inits(masked, depths, scopes).items():
            inits_by_type.setdefault(name, params)

    # 第二遍：View 构造信息（需要上面聚合好的 init 表）
    for file, masked in masked_by_file.items():
        depths, scopes = per_file[file]
        for view in collect_views(
            masked, raw_by_file[file], file, depths, scopes, inits_by_type
        ):
            all_views.setdefault(view.name, view)

    # 只核对「本项目自有类型」，外部框架类型整体排除
    own_bare = {q.split(".")[-1] for q in declared_types} - EXTERNAL_TYPES
    checked_calls = [c for c in all_calls if c.qualifier in own_bare]
    conflicts, n_checked = check_calls(all_defs, checked_calls, static_props)

    # 三类高风险问题先算完，--quiet 也要有结论
    view_problems, view_convention, missing_init, n_view_calls = check_view_calls(
        all_views, masked_by_file, raw_by_file
    )
    env_missing, injections, used_env = check_environment_objects(
        masked_by_file, raw_by_file
    )
    uikit_bad, uikit_ok = check_uikit_guard(root)
    dup = _duplicate_defs(all_defs)

    # ---- 报告 ----
    if not quiet(args):
        print()
        print("== 1. 统计 ==")
        print(f"  函数定义：{len(all_defs)}")
        print(f"  调用点（限定本项目类型）：{len(checked_calls)}（其中 {n_checked} 个能找到同名定义并已比对）")
        print(f"  涉及的命名空间：{len(own_bare)}")
        covered = [ns for ns in REQUIRED_NAMESPACES if ns in declared_types]
        uncovered = [ns for ns in REQUIRED_NAMESPACES if ns not in declared_types]
        print(f"  点名的 {len(REQUIRED_NAMESPACES)} 个命名空间覆盖：{len(covered)}/{len(REQUIRED_NAMESPACES)}")
        if uncovered:
            print(f"  未找到声明：{uncovered}")

        if dup:
            print()
            print("== 1b. 同签名重复定义（会报 invalid redeclaration）==")
            for line in dup:
                print(f"  {line}")

        print()
        if conflicts:
            print(f"== 2. 签名冲突：{len(conflicts)} 处 ==")
            for c in conflicts:
                print(f"  [FAIL] {c.kind}  {c.call.where}")
                print(f"         {c.detail}")
                for d in c.defs[:4]:
                    print(f"         定义 → {d.where}  {d.ident_label}")
        else:
            print("== 2. 签名冲突：0 处 ==")

        # View init
        print()
        print(f"== 3a. View init 核对（{len(all_views)} 个 View，{n_view_calls} 个构造点）==")
        if missing_init or view_problems:
            for line in missing_init + view_problems:
                print(f"  [FAIL] {line}")
        else:
            print("  构造点实参与 init 形参全部匹配；无「私有属性无默认值却漏写 init」的 View")
        if view_convention:
            print(f"  （约定提示，不致命：{len(view_convention)} 个 View 私有属性全带默认值、未写显式 init）")

        # EnvironmentObject
        print()
        print(f"== 3b. @EnvironmentObject 注入（在用类型：{used_env}）==")
        if env_missing:
            for line in env_missing:
                print(f"  [FAIL] {line}")
        else:
            print(f"  全部有注入点（{len(injections)} 处）")
        for line in injections:
            print(f"    {line}")

        # UIKit guard
        print()
        print(f"== 3c. Sources/Shared 的 import UIKit 守卫（{len(uikit_ok)} 处已包裹）==")
        if uikit_bad:
            for line in uikit_bad:
                print(f"  [FAIL] {line}")
        else:
            print("  Shared 下所有 import UIKit 都在 #if canImport(UIKit) 内")

        print()

    failed = bool(conflicts) or bool(missing_init) or bool(view_problems) or bool(env_missing) or bool(uikit_bad)
    print(f"签名冲突 {len(conflicts)} 处 · View init 冲突 {len(missing_init) + len(view_problems)} 处 · "
          f"EnvironmentObject 缺失 {len(env_missing)} 处 · UIKit 守卫 {len(uikit_bad)} 处 · "
          f"约定提示 {len(view_convention)} 处")
    if failed:
        print("结果：FAIL")
        return 1
    print("结果：全部通过")
    return 0


def _duplicate_defs(defs: Sequence[FuncDef]) -> List[str]:
    """找出完全同签名的重复定义（Swift 会直接报 invalid redeclaration）。"""
    seen: Dict[Tuple[str, str, str, str, bool], FuncDef] = {}
    out: List[str] = []
    for d in defs:
        key = (d.type_name, d.name, d.ident_label, d.type_signature, d.is_static)
        first = seen.get(key)
        if first is None:
            seen[key] = d
        elif first.file != d.file or first.line != d.line:
            out.append(
                f"{d.type_name}.{d.name}{d.ident_label}  重复定义：{first.where} 与 {d.where}"
            )
    return out


def quiet(args: argparse.Namespace) -> bool:
    """是否静默模式。"""
    return bool(getattr(args, "quiet", False))


if __name__ == "__main__":
    sys.exit(main())
