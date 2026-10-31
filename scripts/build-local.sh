#!/usr/bin/env bash
# 本地出 IPA —— 不经过 GitHub Actions，一分钱额度都不花。
#
# 什么时候用它：GitHub Actions 的 macOS 配额按 10 倍计费，一旦用完就只能等下个月。
# 而你自己就有台 Mac：装一次 Xcode，之后每次出包都是本地 CPU，零成本、无限次。
#
# 前置（只做一次）：
#   xcode-select --install
#   brew install xcodegen
#
# 用法：
#   bash scripts/build-local.sh              # 出未签名 IPA
#   bash scripts/build-local.sh simulator    # 顺带起模拟器装上看一眼
#
# 产物落在 build-local/SkyApp.ipa。未签名的包不能直接装到未越狱的真机，
# 但可以给自己签名：装 Xcode 后在 Organizer 里签，或自己有开发者账号用
# `xcrun codesign` 重签 —— 这一步本仓库不代劳，因为它需要你的私钥。
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-ipa}"
OUT="build-local"
DERIVED="$OUT/DerivedData"

echo "== 1/4 生成 Xcode 工程 =="
command -v xcodegen >/dev/null 2>&1 || { echo "缺 xcodegen：brew install xcodegen" >&2; exit 1; }
xcodegen generate

echo "== 2/4 编译（Release / 免签名）=="
rm -rf "$DERIVED"
xcodebuild \
  -project SkyApp.xcodeproj \
  -scheme SkyApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "== 3/4 打包 =="
APP="$(find "$DERIVED" -maxdepth 6 -name '*.app' -type d -print 2>/dev/null | head -n 1)"
if [ -z "${APP:-}" ]; then
  echo "::error::没找到 .app，编译可能失败了" >&2
  exit 1
fi
echo "APP=$APP"
rm -rf "$OUT/Payload" "$OUT/SkyApp.ipa"
mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
(cd "$OUT" && zip -qry SkyApp.ipa Payload)
rm -rf "$OUT/Payload"
ls -lh "$OUT/SkyApp.ipa"

if [ "$MODE" = "simulator" ]; then
  echo "== 4/4 模拟器看一眼 =="
  # Release-iphoneos 是 arm64 真机产物，模拟器跑不了，必须再编一次模拟器版
  xcodebuild \
    -project SkyApp.xcodeproj \
    -scheme SkyApp \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$OUT/sim" \
    build
  SIM_APP="$(find "$OUT/sim" -path '*/Debug-iphonesimulator/*.app' -type d -print 2>/dev/null | head -n 1)"
  UDID="$(xcrun simctl list devices available -j \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print([i["udid"] for k,v in d["devices"].items() if "iOS" in k for i in v if "iPhone" in i["name"] and i.get("isAvailable",True)][0])')"
  xcrun simctl boot "$UDID" || true
  xcrun simctl install "$UDID" "$SIM_APP"
  xcrun simctl launch "$UDID" top.skyzyf.skyapp
  echo "模拟器已启动，UDID=$UDID"
fi

echo "完成：$OUT/SkyApp.ipa"
