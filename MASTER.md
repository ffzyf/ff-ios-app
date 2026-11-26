# SkyApp 设计系统 · MASTER.md

> 唯一真相来源。所有颜色、字号、间距、圆角、阴影、动效参数都从这里取，View 层不许出现 magic number。
> 基于 2026-11-26 确认的视觉与交互主张：`交付/iOS视觉动效主张-预览.html`。

---

## 0. 主张（Phase 3 已确认，本节不可随意改）

### 视觉主张 · 夜间天文观测台

产品本质是「此刻的天光与红石」。青柠 `#6BDB5C` 是通用 SaaS 色，不是产品自己的材料；**日晕金 `#F2C879` 来自太阳本身**，是产品自己的材料。背景从深灰转为**深靛夜空**，让金色有夜色可依。

### 交互主张 · 界面做产品做的事

核心动效是**太阳沿地平线下沉**——天光 App 让天空真的在走。其余动效都是这个动作的配角：微交互 120ms、转场 220–280ms、页面 350ms；禁止 scale-to-0、ease-in 入场、布局属性动画；减弱动态时全部降级为 crossfade。

### 边界（不可越）

- **功能链路零改动**：导航、弹窗、TabBar、模态的入口、事件、跳转一个不动。
- **旧主题全部保留**：暮金是新增默认色，不是替换。用户可在设置页切回青柠及 7 套旧主题。
- **token 名不变**：沿用 `Theme.lime` 等现有名，84 个调用点零改动。

---

## 1. Color palette

### 1.1 新增默认 · 暮金 `dusk`

色相取自太阳落到地平线那一刻：高亮暖金 + 深靛夜空。对比度按 WCAG 相对亮度自查，深浅两档都过 4.5:1。

| token | dark | light | 用途 |
|---|---|---|---|
| `bgBase` | `#0A0E1A` | `#F5F2EA` | 屏幕最底 |
| `bgRaise` | `#121829` | `#FAF8F2` | 卡片底 |
| `bgDeep` | `#080B15` | `#E9E3D6` | 页面渐变最底段 |
| `bgElevated` | `#1A2235` | `#FFFFFF` | 抬升层（弹层） |
| `scrim` | `#000000` @ 50% | `#1A1206` @ 28% | 遮罩 |
| `lime`（品牌面） | `#F2C879` | `#A8761C` | 主按钮、进度填充 |
| `limeInk`（品牌字） | `#F2C879` | `#8A5F14` | 强调字 |
| `onLime`（面上字） | `#1A1206` | `#FFFFFF` | 金色面上的字 |
| `limeBright` | `#FFE0A3` | `#D9A94F` | 高光、悬停 |
| `limeDeep` | `#C99B45` | `#7A5210` | 按压、深一档 |
| `limeGlow` | `#F2C879` @ 38% | `#A8761C` @ 16% | 光晕 |
| `glassTint` | `#F2C879` @ 10% | `#A8761C` @ 8% | 玻璃材质着色 |

**对比度自查**：深 `#F2C879` 面 + `#1A1206` 字 ≈ 9.6:1；浅 `#A8761C` 面 + `#FFFFFF` 字 ≈ 5.1:1。金面配深字，不配白字（白字在金面上会糊）。

### 1.2 物理天空色（不随外观切换）

沿用 `Theme.SkyColors` 的五段色，不动。天空底上永远压浅色字，地面底上压半透浅字。

### 1.3 保留的旧主题

`lime` / `violet` / `sand` / `ocean` / `sakura` / `aurora` / `ember` / `graphite` 共 8 套，hex 一个不改。`all` 数组顺序：暮金在最前，其余顺延。

---

## 2. Typography

沿用现有 `Typography.swift` 的 11 档语义字号，**不改字阶**——SF Pro 是 HIG 的一部分，字号改动会波及所有 30 屏。

| 档 | 用途 | 现有 size |
|---|---|---|
| largeTitle | 页面大标题 | 34 |
| title1/2/3 | 卡片标题 | 28 / 22 / 20 |
| headline | 强调正文 | 17 |
| body | 正文 | 16 |
| callout | 次要正文 | 15 |
| subhead | 说明 | 13 |
| footnote | 脚注 | 12 |
| caption1/2 | 标签 | 11 / 10 |

规则：数字用 `.monospacedDigit()` + `tabular-nums`，保证倒计时跳动时不抖。

---

## 3. Spacing

沿用现有 `Spacing` token：页边 20 / 卡内 16 / 卡间 12 / 组间 32。2.67 倍间距层级不改。

---

## 4. Radii

沿用现有：卡片 22 / 弹层 32 / 胶囊 999 / 小圆角 12–16。不改。

---

## 5. Shadows

沿用现有 `glassShadow` 系列。暮金主题下阴影不变（夜空底上阴影更明显，正好加深层次）。

---

## 6. Base components

| 组件 | 暮金态 | 状态 |
|---|---|---|
| 主按钮 | 金面 `#F2C879` + 深字 `#1A1206`，按下 `#C99B45` | 新增暮金皮肤 |
| 玻璃卡 | `glassFill` + `glassTint` 金色 @10% + 顶缘高光 | 新增暮金着色 |
| 进度轨 | 轨底深靛，填充金，端点光晕 `limeGlow` | 新增暮金皮肤 |
| Tab 胶囊 | 选中金点 + 金字，滑移用 `Motion.tab` | 沿用结构，换色 |
| 文字按钮 | `limeInk` 金色字 | 新增暮金皮肤 |

组件结构、事件、点击区域全部沿用现有实现，只换 token 解析结果。

---

## 7. Motion tokens

### 7.1 时长档（来自主张）

| 档 | 时长 | 用途 |
|---|---|---|
| micro | 120ms | 按压、开关、小反馈 |
| transition | 220–280ms | Tab、弹层、卡片入场 |
| page | 350ms | 页面推入/返回 |
| ambient | 1.2s | 太阳下沉（环境动作，慢） |

### 7.2 Spring 参数（新增到 `Motion`）

| token | 参数 | 主张里的角色 |
|---|---|---|
| `sunSink` | `easeInOut(duration: 1.2)` | 太阳沿地平线下沉（核心动效） |
| `stagger` | 每张卡延迟 60ms | 卡片依次入场 |
| `micro` | `spring(response: 0.12, dampingFraction: 0.78)` | 微交互 |
| `press` | `spring(response: 0.28, dampingFraction: 0.70)` | 按压回弹（有过冲，已有） |

沿用不改：`tab(0.35/0.82)` / `push(0.42/0.86)` / `pop(0.38/0.86)` / `expand(0.4/0.85)` / `glassIn(easeOut .3)` / `glassOut(easeIn .22)` / `notice(0.34/0.86)`。

### 7.3 禁止项

- `scale → 0`：入场只做位移 + 淡入，最小 scale 0.96。
- `ease-in` 入场：入场一律 easeOut 或 spring。
- 布局属性动画（width/height/offset 直接 animate）：用 `matchedGeometryEffect` 或 transform。
- 减弱动态：所有位移归零、stagger 归零、spring 降级为 `easeOut(0.18)` 的纯 opacity crossfade。

---

## 8. The one motion · 太阳下沉

| 项 | 定义 |
|---|---|
| **触发** | 天光页首帧出现；简报卡进入视口；Live Activity 时间推进 |
| **前** | 太阳圆盘在地平线上方，`y = -12pt`，opacity 0 |
| **动** | 1.2s easeInOut，太阳 `y: -12 → 0`，同时地平线亮边 `#FFD89A` 从 40% → 100% |
| **后** | 太阳贴地平线，光晕稳定，倒计时数字开始跳动 |
| **若不动** | 太阳已在位（静态），信息完整可读——动效只是锦上添花 |
| **减弱动态** | 太阳直接出现（无位移），仅 opacity 0 → 1 的 180ms crossfade |

---

## 9. 实现清单（Phase 4 逐项落地）

1. `Theme.Palette.dusk` 新增 + 设为默认 + 老用户一次性迁移（青柠 → 暮金，可切回）
2. `Motion` 新增 `sunSink` / `micro` / `stagger`，`Motion.reduced(_:)` 降级函数
3. 太阳下沉动效落到天光页 `SkyRoomView` 的太阳视图
4. Tab 胶囊滑移、卡片依次入场、按压回弹落到现有组件
5. 减弱动态守卫（`@Environment(\.accessibilityReduceMotion)`）
6. 版本号 5.7.0，走 Codemagic 发包

---

**生成日期**：2026-11-26
**状态**：Phase 3 完成，等待 Phase 4 实现
