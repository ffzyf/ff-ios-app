#!/usr/bin/env bash
# 保活 dylib 注入 —— 构建期把 libGShoutaiDylib.dylib 塞进 .app，用户下载即自带，
# 签名时不再需要手动录入（用户 2026-11-22 明确的诉求）。
#
# 为什么这么做：
#   - 源 dylib 是用户的保活插件，之前每次签名都要手动注入，容易漏、容易注错路径。
#   - 它依赖越狱框架 CydiaSubstrate（/Library/Frameworks/CydiaSubstrate.framework/
#     CydiaSubstrate），原 install name 是异常嵌套路径
#     @executable_path/Frameworks/libGShoutaiDylib.dylib/libGShoutaiDylib.dylib，
#     必须先用 -id 改成正常路径，否则 dyld 找不到。
#   - **必须 --weak**（LC_LOAD_WEAK_DYLIB）：非越狱设备没有 CydiaSubstrate，
#     强注入会让 dyld 直接崩、App 打不开；weak 注入时 dyld 跳过它，
#     App 正常启动（退回 Bark 兜底）。这是整个方案能上自签通道的前提。
#   - 必须先 mkdir Frameworks：目录不存在时 codesign/打包阶段会报"缺少 Framework(s) 目录"。
#
# 用法：bash scripts/inject_dylib.sh build/Build/Products/Release-iphoneos/SkyApp.app
#
# vendor/dylibs/libGShoutaiDylib.dylib 的 SHA256（换 dylib 时务必同步更新这里与 preflight）：
#   4637c38d752398c593ebdfc0579b26e56afc0dffb0426b6c7611d933e9b80e36
set -euo pipefail

# 所有路径相对项目根：从任意目录调用都能正常工作。
cd "$(dirname "$0")/.."

APP="${1:-}"                                        # 形如 build/.../SkyApp.app
SRC="vendor/dylibs/libGShoutaiDylib.dylib"
BIN="$APP/SkyApp"                                   # PRODUCT_NAME=SkyApp（见 project.yml）
LOAD="@executable_path/Frameworks/libGShoutaiDylib.dylib"
DST="$APP/Frameworks/libGShoutaiDylib.dylib"

# --- 入参 / 环境校验：给明确错误，而不是让后面的工具报一堆看不懂的错 ---
[ -n "$APP" ] || { echo "用法: bash scripts/inject_dylib.sh <SkyApp.app 路径>"; exit 1; }
[ -d "$APP" ] || { echo "找不到 .app 目录: $APP（编译是否成功？路径是否正确？）"; exit 1; }
[ -f "$BIN" ] || { echo "找不到主二进制: $BIN（PRODUCT_NAME 是否从 SkyApp 改过？）"; exit 1; }
[ -f "$SRC" ] || { echo "找不到源 dylib: $SRC（vendor 目录没同步到 CI？）"; exit 1; }
for tool in install_name_tool codesign otool insert_dylib; do
  command -v "$tool" >/dev/null 2>&1 \
    || { echo "缺少工具 $tool —— 本脚本只能在 macOS + Xcode 命令行工具下运行"; exit 1; }
done

# 1. 先建 Frameworks，否则 codesign / 打包阶段会报"缺少 Framework(s) 目录"。
mkdir -p "$APP/Frameworks"
# 2. 覆盖式复制：每次都从 vendor 原件取，避免上一次注入的残留。
cp "$SRC" "$DST"
# 3. 改 id 为正常路径（原嵌套路径会让 dyld 找错地方）。
install_name_tool -id "$LOAD" "$DST"
# 4. 先给 dylib 做 ad-hoc 签名，避免后续整包重签时报"框架未签名"。
codesign -f -s - "$DST" 2>/dev/null || true
# 5. weak 注入主二进制：--weak 是关键，缺 CydiaSubstrate 时 dyld 跳过而非崩溃。
insert_dylib --inplace --strip-codesign --weak --all-yes "$LOAD" "$BIN"
# 6. 断言注入结果：用 bash 内建的 glob 匹配而不是 `grep -q`，因为 grep -q 命中即退、
#    会让管道写端收到 SIGPIPE，在 set -o pipefail 下被误判成失败（发出没注入的包）。
LOADS="$(otool -L "$BIN")"
if [[ "$LOADS" != *libGShoutaiDylib.dylib* ]]; then
  echo "注入失败：otool -L 里找不到 libGShoutaiDylib.dylib"
  exit 1
fi

echo "已 weak 注入: $DST -> $BIN"
