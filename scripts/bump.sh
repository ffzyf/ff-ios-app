#!/usr/bin/env bash
# 构建号 +1（V3.2 起）
#
# 为什么要有这个脚本：project.yml 里 CURRENT_PROJECT_VERSION 出现**两处**
# （主 App + Widget），且必须与 MARKETING_VERSION 分开管 —— 前者是给用户看的版本号，
# 后者是「改一次 +1」的构建流水号。手动改必然漏一处，漏了 archive 就报
# bundle version mismatch，白烧一轮 macOS 额度。
#
# 版本号规则（用户定，2026-10-31 起生效）：
#   每出一个新版本   → 版本号末位 +1     3.0.0 → 3.0.1   （bash scripts/bump.sh patch）
#   大改（新功能/重做）→ 版本号次位 +1    3.0.1 → 3.1.0   （bash scripts/bump.sh minor）
#   CURRENT_PROJECT_VERSION 每一档都自动 +1，不需要单独给参数。
#
# 用法：
#   bash scripts/bump.sh          # 只把构建号 +1（不动对外的版本号）
#   bash scripts/bump.sh patch    # 小改：3.0.0 → 3.0.1，构建号 +1
#   bash scripts/bump.sh minor    # 大改：3.0.0 → 3.1.0，构建号 +1
#
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-build}"

# 取当前的 MARKETING_VERSION：优先顶层 settings 的那一行
marketing="$(grep -m1 -E '^\s*MARKETING_VERSION:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')"
# 取当前的 CURRENT_PROJECT_VERSION
current="$(grep -m1 -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*"([^"]+)".*/\1/')"

if [ -z "$marketing" ] || [ -z "$current" ]; then
  echo "bump: 没读到版本号，检查 project.yml 的 MARKETING_VERSION / CURRENT_PROJECT_VERSION" >&2
  exit 1
fi

next_build=$((current + 1))
next_marketing="$marketing"

if [ "$MODE" = "minor" ]; then
  # 3.0.0 → 3.1.0
  next_marketing="$(echo "$marketing" | awk -F. '{printf "%s.%d.0", $1, $2+1}')"
elif [ "$MODE" = "patch" ]; then
  # 3.0.0 → 3.0.1
  next_marketing="$(echo "$marketing" | awk -F. '{printf "%s.%s.%d", $1, $2, $3+1}')"
elif [ "$MODE" != "build" ]; then
  echo "bump: 未知模式 '$MODE'（可选 build / patch / minor）" >&2
  exit 1
fi

# 全局替换：两处 VERSION 一起更新，不可能再漏
sed -i.bak \
  -e "s|MARKETING_VERSION: \"${marketing}\"|MARKETING_VERSION: \"${next_marketing}\"|g" \
  -e "s|CURRENT_PROJECT_VERSION: \"${current}\"|CURRENT_PROJECT_VERSION: \"${next_build}\"|g" \
  project.yml
rm -f project.yml.bak

echo "bump: ${marketing} (build ${current}) → ${next_marketing} (build ${next_build})"
echo "verify:"
grep -nE 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' project.yml
