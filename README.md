# FF大王 · iOS 原生 App（V2）

SwiftUI 原生客户端：博客文章 + 光遇版本情报 + 每日简报。**零 WKWebView、零第三方依赖**。

- 展示名：FF大王
- Bundle ID：`top.skyzyf.skyapp`
- 版本：2.0.0 (2)
- 最低系统：iOS 18.0（iPhone 竖屏，双主题：跟随系统 / 始终浅色 / 始终深色）
- 构建：GitHub Actions `macos-26`（Xcode 26 / iOS 26 SDK）+ xcodegen，产出未签名 `SkyApp.ipa`

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
