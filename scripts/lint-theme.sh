#!/usr/bin/env bash
#
# 主题闸门（批次 1，PRD §3.4 硬性约束的机器版）
#
# 为什么用 grep 而不是 Xcode 单测 target：CI 是无签名编译，多一个 test target =
# 多一套 signing / bundle 配置风险；而下面 4 条规则都是"文本可见"的，grep 能 100% 覆盖，零编译成本。
#
# 跑法：
#   bash scripts/lint-theme.sh      # 全绿 → 退出码 0；任一命中 → 退出码 1
#
# 白名单两种：
#   1. 文件级：`ALLOW_FILES` 里的三个文件（token 定义处 / Color(hex:) 实现 / 全屏看图黑画布）
#   2. 行级：命中行行尾写 `lint:allow`（用于个别必须破例的位置）
#
set -uo pipefail

# 允许从任意目录调用：以脚本自身位置定位工程根目录
cd "$(dirname "$0")/.." || exit 1

SRC="Sources"

# 文件级白名单：
#   Theme.swift       —— token 定义处，全工程的 hex 都只能出现在这里
#   Extensions.swift  —— Color(hex:) 的实现本身
#   ThemeMetrics.swift—— PRD §3.4-2 的唯一豁免：`ThemeScope` 在这里读 colorScheme，
#                        `ThemeMetrics.resolve(_:)` 在这里把 ColorScheme 翻成两个数值
#   ImageViewer.swift —— 全屏看图必须是纯黑画布（PRD 明确例外）
ALLOW_FILES='^Sources/Shared/Theme/Theme\.swift:|^Sources/Shared/UI/Extensions\.swift:|^Sources/Shared/Theme/ThemeMetrics\.swift:|^Sources/Features/Article/Blocks/ImageViewer\.swift:'

fail=0

# 收集命中行：排掉文件级白名单 + 行尾 lint:allow
scan() {
  grep -rn --include=*.swift -E "$1" "$SRC" 2>/dev/null \
    | grep -vE "$ALLOW_FILES" \
    | grep -v 'lint:allow' \
    || true
}

# $1 = 正则  $2 = 说明（失败了要能一眼看出该改什么）
chk() {
  local pattern="$1"
  local desc="$2"
  local hits
  hits="$(scan "$pattern")"
  if [ -n "$hits" ]; then
    printf '\n[FAIL] %s\n' "$desc"
    printf '%s\n' "$hits"
    fail=1
  fi
}

echo "== 主题闸门 · 4 条规则 =="

# 1) 硬编码颜色：View 层不许出现 hex（改了 hex 就等于绕过 PRD 的颜色表）
chk 'Color\(hex:' \
    '规则1 · View 层出现 Color(hex:)，颜色必须走 Theme token'

# 2) 深浅判断：只有 ThemeScope 能读 colorScheme ==，别处一律走数值 token
chk 'colorScheme[[:space:]]*==[[:space:]]*\.(dark|light)' \
    '规则2 · 出现 colorScheme == .dark/.light，深浅差异只能通过 ThemeMetrics 表达'

# 3) 就地造色：玻璃 / 描边 / 高光必须用 token（浅色下白叠白会整块消失）
chk 'Color\.white\.opacity' \
    '规则3 · 出现 Color.white.opacity(...)，请改用 glassFill / glassStrokeTop / surfaceTint1~4 / skeletonShimmer*'

# 4) 面/字分离：lime 只做面，文字与图标必须 limeInk（浅色下 lime 当字是 1.76:1，读不清）
chk 'foregroundStyle\((Theme\.)?lime\)|foregroundColor\((Theme\.)?lime\)' \
    '规则4 · lime 被当作文字色，请改用 Theme.limeInk'

if [ "$fail" -ne 0 ]; then
  printf '\n主题闸门失败：请按上面的 [FAIL] 逐条修，不要用 lint:allow 绕过（除 PRD 明确例外）。\n'
  exit 1
fi

printf '\n全部通过：没有硬编码颜色、没有深浅判断、没有就地造色、lime 只做面。\n'
exit 0
