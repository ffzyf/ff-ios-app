# FF大王 · iOS 原生 App（V2）

SwiftUI 原生客户端：博客文章 + 光遇版本情报 + 每日简报。**零 WKWebView、零第三方依赖**。

- 展示名：FF大王
- Bundle ID：`top.skyzyf.skyapp`
- 版本：3.7.0 (13)
- 最低系统：iOS 18.0 / iPadOS 18.0（**Universal：同一个 App，iPhone 与 iPad 自动识别**；iPhone 锁竖屏，iPad 四向）
- 设备适配：iPhone / iPad 同一份代码，靠 `horizontalSizeClass` + 容器宽度分三档（`compact` / `regularNarrow` / `regularWide`），**不用 `UIDevice.idiom`** —— 否则 Split View、Slide Over、Stage Manager 下必错。设计：`docs/design/2026-10-31-ipad-ios27-adaptation.md`。版式档 single / grid2(≥760) / grid3(≥1020) / rail(≥1040) 见 `docs/design/2026-10-31-ipad-layout-redo.md`
- 构建：Codemagic `ios-unsigned`（Xcode 26 / iOS 26 SDK，免费 M2 额度）+ xcodegen，产出未签名 `SkyApp.ipa`

> V1（四个 Tab 全 WebView 套壳）已被整体废弃，本仓库上一版文档与代码全部作废。

---

## 一、目录约定

```
Sources/
  App/            只做装配：入口、根视图、Tab、外观三态、占位页（后续由 Feature 目录替换）
  DesignSystem/   只做长相：玻璃、卡片、徽标、骨架、程序化封面、状态视图（不含颜色值）
  Shared/         主 App 与（批次 4 起的）Widget 共同编译：Theme token、数值 token、扩展、格式化、API 门面
  Models/         只做形状：Codable 结构，不 import SwiftUI
  Services/       只做取数：域名（Endpoint）、APIClient、快照缓存、离线降级、AppModel
Resources/
  Info.plist
  Assets.xcassets/（AppIcon / AccentColor / BgBase / LaunchBackground）
```

依赖方向单一：`App → DesignSystem → Shared`、`App → Services → Shared`。

主题只有一条规矩：**颜色值只能出现在 `Sources/Shared/Theme/Theme.swift`**，
其余位置一律引用 `Theme.xxx`；`scripts/lint-theme.sh` 在 CI 里卡这条（`xcodegen` 之前跑）。

## 二、本地生成工程

```bash
brew install xcodegen
cd ios-app          # project.yml 所在目录
xcodegen generate
open SkyApp.xcodeproj
```

## 三、CI 打包

推到 `main` 后自动跑 `.github/workflows/build-ipa.yml`：

1. `build` job：生成工程 → 无签名 Release 构建 → 打包 `SkyApp.ipa` → 上传 artifact；
2. `screenshots` job：模拟器 Debug 构建 → 动态挑一台可用 iPhone → 装包启动 → 截首页图（`continue-on-error`，失败不影响 IPA）。

## 四、玻璃方案（重要）

所有玻璃都必须走 `DesignSystem/GlassCompat.swift` 的 `glassSurface(_:in:tint:interactive:)`：

- iOS 26：内部 `#available` 走系统 `glassEffect`；
- iOS 18–25：同一入口走手工玻璃（材质 + 白叠层 + 顶缘渐变描边 + 内侧高光 + 投影）。

`glassEffect` / `GlassEffectContainer` / `Glass` / `.glassProminent` 这四个符号**只允许**出现在
`GlassCompat.swift` / `GlassGroup.swift` / `GlassButtonStyles.swift` 三个文件里。

## 五、V3.1 轨迹卡与 Tab 栏（本轮改动）

- `Sources/Shared/UI/TrackArc.swift` 是 App 与桌面小组件**共用**的弧线几何：
  弧线只画在卡片下沿的窄带里（`bandTop…bandBottom`），文字区永远在弧线之上。
- `Sources/DesignSystem/TrackCard.swift` 是卡片自己的深靛渐变底盘
  （`Theme.trackTop/trackBottom/trackArc/trackTextDim/trackDivider`），不再靠采样背景立住。
- Tab 栏：56pt 窄胶囊 → 74pt 整幅玻璃，选中态为 46pt 青柠渐变圆 + 徽标位。

# V3.1 轨迹卡重构：弧线几何下沉 Shared，App/Widget 同源

- 弧线带参数：红石卡 `bandTop 0.52 / bandBottom 0.98 / peak 0.70`，简报卡 `0.46 / 0.98 / 0.64`。

---

## 六、出包方式（2026-10-31 改：GitHub 额度省着用）

macOS runner 按 **10 倍** 计费，旧配置下「推一次 ≈ 250 计费分钟」，额度很容易烧穿。
现在有两条路，按需选：

| 方式 | 花什么 | 适合 |
|---|---|---|
| `bash scripts/build-local.sh` | 本地 CPU，**零额度** | 日常出包；需要 Xcode + `brew install xcodegen` |
| GitHub Actions | macOS 计费分钟 | 手上没有 Mac 时 |

CI 侧也做了三处省钱改造，改动落在 `.github/workflows/build-ipa.yml`：
① 不再 `on: push`，只在网页端手动 Run workflow；
② 先跑 `ubuntu-latest` 的 gate（主题闸门 + 静态预检），**失败了 macOS 机器根本不起**；
③ DerivedData 缓存 + 截图默认关闭，日常出包只编译一次。

### 版本号

每次改动后跑一下，构建号自动 +1（`project.yml` 里**两处**都要改，脚本不会漏）：

```bash
bash scripts/bump.sh          # 构建号 +1
bash scripts/bump.sh minor    # 顺带版本号小数位 +1
```

### 推送前自查

```bash
python3 scripts/preflight.py   # 括号配对 + 跨文件符号引用，毫秒级
bash scripts/lint-theme.sh     # 主题规范闸门
```

这两个脚本在 CI 里也跑，但**本地先跑一遍省的是真金白银** —— 静态检查在 macOS 上
失败的成本是 Linux 的 10 倍。
