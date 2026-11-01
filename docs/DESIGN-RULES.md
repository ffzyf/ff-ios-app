# 设计与开发铁律（长期有效）

> 本文件是用户明确提出的长期约定，每次开发前先读一遍。新增条目只追加，不删除历史条目。

## 1. iPad 与 iPhone 同步开发（2026-11-01）

**所有设计默认「iPad + iPhone 一起做」**，不允许出现"先做 iPhone、iPad 以后适配"的交付。
- 版式分档统一走 `LayoutMetrics` 的 `PageTier`（single / grid2 / grid3 / rail），不写 `UIDevice` / `userInterfaceIdiom` / `UIScreen.main`；
- 每个新页面/新卡面交付时必须说明四档（或适用的档位）各自的布局差异；
- 新功能验收清单里必须有「iPad 宽屏」一项。

## 2. 动态效果：有，但克制（2026-11-01）

- 背景/光影必须有缓慢的动态（滚动光影 + 极慢氛围层），但**幅度小、周期长**（≥8s，背景层 40s+）；
- 只允许走 `offset` / `scaleEffect` / `opacity` 做动画，禁止逐帧改颜色、禁止 `Timer` 驱动；
- 必须尊重 `reduceMotion`；
- 判据：静止看 10 秒不应注意到"在动"，但截图对比能看出层次。

## 3. 小组件必须覆盖多尺寸（2026-11-01）

- 每个小组件至少覆盖 `.systemSmall / .systemMedium`，能撑起 Large 的加 Large；
- 锁屏档（accessoryCircular / Rectangular / Inline）按内容适配；
- 每个 face 用 `@Environment(\.widgetFamily)` 分档渲染，禁止一套布局硬缩放；
- 不加的档位必须在 `supportedFamilies` 旁注释写明理由。

## 4. 交互入口单一（2026-11-01）

- 一个页面只从约定好的入口进入，不要在多个地方挂同一目标（避免入口泛滥）；
- 沉浸式页面（`SkyRoomView`）的入口只有两个：天光相关小组件深链 `skyapp://sky`、概览第二张卡片的「今日」。

## 5. 简报要"少而准"（2026-11-01）

- App 内简报默认只露 3–4 条高信息量内容（农历 / 宜忌 / 天气相关），其余进「展开全文」；
- 不挂"原文"外链占位，需要时放在页头小字入口。
