#!/usr/bin/env bash
#
# HIG 合规闸门（HIG-ITER-1）
#
# 把三条"肉眼难长期守住"的约定固化成文本检查，和 lint-theme.sh 一起在
# xcodegen 之前跑 —— CI 的 Linux gate 几毫秒就能挡住，不必等到 macOS 编译。
#
# 跑法：
#   bash scripts/lint-hig.sh        # 全绿 → 退出码 0；任一命中 → 退出码 1
#
# 三条规则：
#   1. 玻璃唯一入口：业务层禁止裸用 .glassEffect( / GlassEffectContainer
#   2. SF Symbols：图标必须是 Image(systemName:)（Image(uiImage:) 是真实图片，不算图标）
#   3. 触控叠加：IconGlassButton / CapsuleGlassButton 必须各有 .tapTarget(...) 命中区
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

SRC="Sources"

# 与 README §四 一致的白名单：只有这两个文件是玻璃 API 的定义处/容器处。
# GlassButtonStyles.swift 只走 glassSurface 唯一入口，没有裸玻璃 API，不进白名单。
ALLOW_GLASS='^Sources/DesignSystem/GlassCompat\.swift:|^Sources/DesignSystem/GlassGroup\.swift:'

fail=0

scan_glass() {
  grep -rn --include=*.swift -E "$1" "$SRC" 2>/dev/null \
    | grep -vE "$ALLOW_GLASS" \
    | grep -v 'lint:allow' \
    || true
}

echo "== HIG 闸门 · 3 条规则 =="

# 1) 玻璃唯一入口：全工程只能经 View.glassSurface 做真玻璃
hits="$(scan_glass '\.glassEffect\(|GlassEffectContainer')"
if [ -n "$hits" ]; then
  printf '\n[FAIL] 规则1 · 业务层裸用玻璃 API，请改走 glassSurface 唯一入口\n'
  printf '%s\n' "$hits"
  fail=1
fi

# 2) 图标必须是系统符号；Image(uiImage:) 用于真实图片，白名单过滤
hits="$(grep -rn --include=*.swift -E '(^|[^[:alnum:]_])Image\(' "$SRC" 2>/dev/null \
  | grep -v 'Image(systemName:' \
  | grep -v 'Image(uiImage:' \
  | grep -v 'lint:allow' \
  || true)"
if [ -n "$hits" ]; then
  printf '\n[FAIL] 规则2 · 图标构造不是 SF Symbols，请用 Image(systemName:)\n'
  printf '%s\n' "$hits"
  fail=1
fi

# 3) 触控命中区叠加：两个按钮各一处，共至少两处。
#    用 grep -n 输出行号后排除以 // 开头的注释行 —— 注释里写 .tapTarget( 不算数。
tap_count="$(grep -n '\.tapTarget(' "$SRC/DesignSystem/GlassButtonStyles.swift" 2>/dev/null \
  | grep -vE '^[0-9]+:[[:space:]]*//' \
  | wc -l | tr -d '[:space:]')"
if [ "$tap_count" -lt 2 ]; then
  printf '\n[FAIL] 规则3 · IconGlassButton / CapsuleGlassButton 缺少 .tapTarget(...) 命中区（找到 %s 处，需 ≥2）\n' "$tap_count"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  printf '\nHIG 闸门失败：按上面的 [FAIL] 修，玻璃请走 glassSurface、图标用系统符号、按钮补命中区。\n'
  exit 1
fi

printf '\n全部通过：玻璃只有唯一入口、图标全是 SF Symbols、玻璃按钮都有 44pt 命中区。\n'
exit 0
