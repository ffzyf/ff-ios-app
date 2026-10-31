# 小组件设计语言手册（参考图 4 张 · 可复用）

| 项 | 值 |
|---|---|
| 版本 | v1（2026-10-31） |
| 适用 | `Sources/Widget` 全部组件；App 内 **hero 级**卡片（`SkyCard` / `TrackCard`） |
| 不适用 | 列表卡、正文卡、表单、可滚动内容 |
| 参考来源 | 用户提供的 4 张 iOS 小组件合集截图（每张约 10 个真实组件）。**不含**上一轮误用的 6 张天光图 |
| 颜色纪律 | `Color(hex:)` 只允许出现在 `Sources/Shared/Theme/Theme.swift`（`scripts/lint-theme.sh` 规则 1） |
| 数据纪律 | 涨 = 红（`Theme.riseRed`）、跌 = 绿（`Theme.fallGreen`）、货币 ¥ |

---

## 1. 一句话定义

> **一张卡 = 一个饱和色场 + 一条时间轴 + 一个当下。**

它的推论（三条，后面所有规则都从这三条长出来）：

1. **色场先于内容**：先铺一块有颜色的底，再往上排字；不是"白卡 + 彩色点缀"。
2. **时间轴是唯一的图形**：卡上所有的几何都为"时间走到哪儿"服务，不为装饰服务。
3. **当下只有一个**：每张卡只回答"现在这一刻"，第二个当下就要拆成第二张卡。

---

## 2. 七条硬规则

### R1 色场：3 档渐变、180°、纱压在 `ground` 上

| 项 | 158×158（`.systemSmall`） | 338×158（`.systemMedium`） | 338×354（`.systemLarge`） |
|---|---|---|---|
| 停靠点数量 | 3 | 3 | 3 |
| 位置 | `0 / 0.60 / 1` | 同 | 同 |
| 角度 | `.top → .bottom`（180°，**唯一角度**） | 同 | 同 |
| 停靠点 token | `Theme.sky(band).top` / `.horizon` / `.ground` | 同 | 同 |
| 压纱层 | `sky.ground`，alpha `0 … 0.28` | `0 … 0.32` | `0 … 0.35` |
| 色场最大层数 | 3（渐变 + 纱 + 1 团径向气） | 3 | 3 |
| 纯白/纯灰底 | 0 处 | 0 处 | 0 处 |

落地要点（SwiftUI）：

```swift
// 唯一合法写法：3 停靠点、180°、tokens 全来自 Theme.sky
LinearGradient(
    gradient: Gradient(stops: [
        .init(color: sky.top,     location: 0),
        .init(color: sky.horizon, location: 0.60),
        .init(color: sky.ground,  location: 1)
    ]),
    startPoint: .top, endPoint: .bottom
)
```

- **禁止** `topLeading → bottomTrailing`：斜向渐变在 158 方卡上会把左上角提亮，与"顶部一行小字"抢注意力，且同一套组件里出现两种角度就读不成一套系统。
- **压纱禁止压向 `Theme.bgBase`**：`bgBase` 在浅色外观是 `#EDF1EC`（近白米），0.66–0.76 的纱会把饱和色场洗成灰白卡 —— 直接违反"没有一张是纯白或纯灰"。要压深就压向该档自己的 `ground`。
- **浅色外观下色场不变浅**：这与 App 内卡片相反（App 内卡片必须跟随深浅色）。理由：小组件贴在桌面上，桌面是一张照片/一张壁纸，卡必须自己立得住；文字对比度由固定的 `sky.ink` 保证，不靠换底色。
- **`Theme.lime` 的用法边界**：只允许作 **≤1 处面**（`fill` / 徽标底 / 进度条填充），面积 ≤ 卡面 **8%**（158 → ≤2000pt²），且该面上的字必须是 `Theme.onLime`。**饱和色场上禁用 lime 面**（青柠压在夜蓝上会被读成第二个强调色）。需要青柠色的文字用 `Theme.limeInk`；`foregroundStyle(Theme.lime)` 会被 lint 规则 4 直接卡住。
- 认不出地图 / 无数据时的兜底：`Theme.trackTop → Theme.trackBottom`（2 停靠点、同样 180°），不允许出现第 3 套渐变。

---

### R2 层级：158 宽度全卡只有 11 / 34 两档字号（空态才用 13）

参考图的信息层级是固定的三层，字号是**断崖式**的，不是渐变式的。

```
┌─────────────────────────────────┐
│ ● 左主（eyebrow）        右值   │  11pt semibold
│                                 │
│   34pt rounded bold             │  主值（唯一大数）
│                                 │
│   ╭───●───○───╮                 │  轨迹（22pt 高）
│   11:08        23:08            │  11pt mono
│   ↘ 还有 39:27     今日 4 场    │  11pt
└─────────────────────────────────┘
```

| 层 | 158 宽度 | 338 宽度 | 字体构造 | 颜色 token |
|---|---|---|---|---|
| eyebrow 左（"这是什么"） | **11** semibold，`tracking +0.5` | **12** semibold，`+0.5` | `.system(size:weight:)` | `sky.ink` |
| eyebrow 右（"多少"） | **11** semibold，`monospacedDigit` | **12** | `.system` | `sky.inkDim` |
| 主值 | **34** bold rounded（下限 28 / 上限 36） | **44** bold rounded（40–48） | `.system(size:weight:design:.rounded)` | `sky.ink` |
| 主值旁标（"进行中/次日"） | **11** semibold | **12** | `.system` | `sky.inkDim` |
| 轨迹两端极值 | **11** medium `monospaced` | **12** | `.system(design:.monospaced)` | `sky.inkDim` |
| 第三层（场次计数等） | **11** medium | **12** | `.system` | `sky.inkDim` |
| 空态/收官态标题 | **13** semibold | 15 | `.system` | `sky.ink` |
| 空态/收官态说明 | **11** regular | 12 | `.system` | `sky.inkDim` |

硬数字：

- 158 宽度下**可用的字号只有 11 / 13 / 34 三档**（空态用 13），**没有任何 10pt、9pt**。参考图里最小字号 ≈ 11pt 等效，这是可读性底线，不是审美偏好。
- 主值宽度 ≤ 内容宽的 **78%**（158 → 132 × 0.78 = **103pt**）。超出就降字号，不许让主值挤掉轨迹。
- 主值行高 = 字号 × 1.2（34 → 40.8，44 → 52.8）。
- 主值与 eyebrow 的层级差 ≥ **23pt**（34 − 11）；小于这个值两层会读成同一层。
- eyebrow 与极值**同字号**，靠颜色（`ink` vs `inkDim`）和位置分主次，不靠字号 —— 这是"紧排 + 大反差"的关键：中间那一个数必须是全卡唯一的大字。

---

### R3 轨迹：圆头、1.2pt 本体、5pt 光点、亮段对准光点

| 项 | 158 | 338 | 说明 |
|---|---|---|---|
| 弧带高度 | **22** | 28 | 含弧的全部起伏，框外不放字 |
| `crestY / edgeY` | **0.32 / 1.0** | 0.32 / 1.0 | 0.32 才有半圆弯度 |
| 本体线宽 | **1.2** | 1.6 | |
| 本体 alpha：峰值 / 谷值 | **0.62 / 0.18** | 0.70 / 0.20 | 峰谷比 ≈ 3.4:1 |
| 雾化层线宽 / alpha | **3.2 / 0.16** | 3.4 / 0.16 | 代替 `.blur()` 的那一层 |
| 线端 / 拐角 | **`.round` / `.round`** | 同 | 默认 `butt` 会在两端切出直角 |
| 节点直径 | **3** | 4 | |
| 已过节点 alpha | **0.30** | 0.30 | |
| 光点本体 | **5** | 7 | 取 `sky.edge`（该档最亮） |
| 光点环线宽 / 间隙 | **1 / 1.5** | 1.25 / 2 | 浅色外观下白色本体靠这圈留住 |
| 光点径向光直径 / 中心 alpha | **20 / 0.32** | 28 / 0.32 | 中心到边缘 2 停靠点衰减到 0 |
| 首末节点内缩 | **0.06** | 0.06 | 圆有直径，贴端点会被卡边裁一半 |
| 渐变描边方向 | **横向 `leading → trailing`**，亮段顶点对齐光点 x，`spread 0.34` | 同 | 与 `SkyLightSky.strokeStyle` 同一实现 |

```swift
// 线端必须显式给 .round —— 不写就是 butt，弧两端是两个方角
.stroke(Theme.trackArc.opacity(0.62),
        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
```

几何只能有一份实现：`Sources/Shared/UI/HorizonShape.swift` 的 `HorizonEdge` / `HorizonGround`。**禁止在新组件里重画贝塞尔**（节点位置用的是同一条曲线的参数方程反算，重画必然与弧漂开）。

---

### R4 光效：两种，径向 + 提亮；`.blur()` 零容忍

| 光效 | 半径（158） | 中心 alpha | 衰减 | 混合模式 |
|---|---|---|---|---|
| 轨迹光点光 | 10（直径 20） | **0.32** | 2 停靠点，边缘 0 | `normal` |
| 主值柔光（可选） | ≤ **66**（0.42 × 短边） | ≤ **0.16** | 3 停靠点（0 / 0.35 / 1） | `normal` |
| 背景"那口气" | ≤ **79**（0.50 × 短边） | ≤ **0.18** | 2 停靠点 | `normal` |
| 天光太阳光 | ≤ 0.45 × 宽度 | **0.45 × intensity** | 3 停靠点 | `.plusLighter` |

- `.plusLighter` **只允许**用在"底色已经很亮、要把光提亮而不是盖住"的一处（天光太阳）。新组件不用它。
- 一张卡最多 **2 处**光效（1 处轨迹光 + 1 处主值/背景光）。第 3 处开始读成"发光的卡"，不是"有光的卡"。

**为什么禁止 `.blur()`（三条，都不是口味问题）**

1. **每帧成本**：Widget 的帧是系统快照，一次刷新要重算整棵子树。`blur` 走离屏渲染：先渲一张层、再采样、再合成。158² 上 `radius 8` 的一次模糊，等效于多铺 3–4 层 `LinearGradient`，而这段代码在锁屏/待机/AOD 场景会被反复触发。
2. **项目已经糊过一次**：旧红石背景用 12pt 模糊铺三层云海，用户原话"背景糊"（见 `RedstoneBackdrop` 文档注释）。模糊半径与 11pt 文字的字怀（约 5pt）同量级时，文字笔画会被底色吃进去。
3. **跨设备不可控**：`blur(radius:)` 是点单位，2x/3x 屏幕上实际采样核不同，同一份代码在 SE 与 Pro Max 上的柔度不一致；`RadialGradient` 的停靠点是归一化的，任何尺寸都同形。

**允许的替代**（三个，按优先级）：

1. `RadialGradient`（柔边）；
2. "更粗 + 更淡"的双层描边（雾化层 3.2/0.16 + 本体 1.2/0.62）；
3. `LinearGradient` 停靠点做亮段（`strokeStyle(peak:base:spread:)`）。

---

### R5 留白：四边 13、纵向占用 ≤96%

| 项 | 158 | 338 |
|---|---|---|
| 四边内边距 | **13**（内容区 132×132） | **16**（内容区 306×126） |
| 圆点 ↔ 文字 | **5** | 6 |
| 行内元素间距 | **3** | 4 |
| eyebrow → 主值 | **8** | 10 |
| 主值 → 轨迹 | **≥10（硬下限）** | ≥12 |
| 轨迹 → 两端极值 | **2** | 3 |
| 极值行 → 底行 | **6** | 8 |
| 纵向占用上限 | **96%（127 / 132）** | 96% |
| 底部必须留白（有 Spacer 时） | ≥4 | ≥6 |

- 13pt 是**刻意偏离** HIG 的 16pt 默认边距：`contentMarginsDisabled()` 已关闭系统边距，158 方卡四边各让 16 只剩 126，主值 34pt 就撑不住"eyebrow + 主值 + 轨迹 + 极值 + 底行"五层。**这个偏离只对 158 成立，338 必须回到 16。**
- 留的这 5pt 不是审美：中文行高在不同系统版本有 ±1pt 浮动，5 层叠下来正好吃掉这点余量，超了就是倒计时那行被裁。
- 主值与轨迹之间 10pt 是硬要求：光点光晕半径 10pt，贴住就蹭到字。

---

### R6 圆角：交给系统裁切，一个数值都不要写

| 项 | 规则 |
|---|---|
| 外层圆角 | **不写数值**。背景交给 `.containerBackground(for: .widget)`，系统按 family 裁切（`systemSmall` 实测 ≈22pt，随设备、外观、待机模式插值） |
| 自绘圆角 | 卡面层 **0 处** `RoundedRectangle` / `.clipShape` / `.cornerRadius` |
| 描边 / 投影 | **0 处**（小组件内） |
| 内部 widget 形（如徽标底） | 圆角 **4**，且遵守同心规则：子圆角 = 外层圆角 − 内边距 |
| 需要"系统形状"时 | 用 `ContainerRelativeShape()`，**不要**再叠 `.clipShape` |

```swift
// 唯一合法的组件装配
.contentMarginsDisabled()   // 否则渐变外围留一圈系统底色，看着像"卡里嵌了一张小卡"
// 视图侧
RedstoneFace(entry: entry)
    .widgetURL(WidgetDeepLink.rock)
    .containerBackground(for: .widget) { RedstoneBackdrop(mapName: …) }
```

硬编码圆角（`cornerRadius: 16`）在桌面上会与系统裁切打架，露出 1–2pt 的直角边；也不要在 `containerBackground` 里再包一层 `clipShape`。

---

### R7 禁止项（命中即打回）

| # | 禁止 | 原因 / 替代 |
|---|---|---|
| 1 | 插画、写实照片、渐变网格 | 参考图 40 张里 0 张有插画。要"氛围"只用色场 + 1 团径向气 |
| 2 | 卡内嵌套卡（底 + 描边 + 投影） | 一张卡就是一个色块；层级靠字号与透明度，不靠边框 |
| 3 | 强调色 > 2 种 | 上限 = 1 支天色强调（`sky.edge`）+ 1 支状态色（`riseRed`/`fallGreen`）。`lime` 算第 3 支，只能作 ≤1 处面 |
| 4 | `foregroundStyle(Theme.lime)` | lint 规则 4；青柠字用 `limeInk` |
| 5 | 纯白 / 纯灰底 | 违反第 1 条定义；兜底也必须是 `trackTop → trackBottom` 的夜 |
| 6 | 依赖 Dynamic Type 的布局 | 小组件字号写死（`Font.system(size:)`），不用 `.title` 等语义字号 |
| 7 | 可滚动内容、输入框、多点击区 | WidgetKit 不提供；整卡只能一个 `widgetURL` |
| 8 | 装饰性几何（第二个"意象"） | 图形位只留给轨迹。剪影/角标/水印：0 处（历史红石卡最多 2 个剪影，本次评审建议删除） |
| 9 | 小于 11pt 的字 | 底线，见 R2 |
| 10 | `.blur()` | 见 R4 |

---

## 3. 三套配色档位对照表（深蓝 / 紫橙·黑金 / 橙红 → 七档）

七档来自 `Theme.sky(_:)`（`Sources/Shared/Theme/Theme.swift:447`）。参考图里的"深蓝 / 紫橙 / 黑金 / 青绿 / 橙红"五种气质，对应如下。**七档里没有青绿**：绿色只能由品牌 `limeDeep` 补，且只做雾与剪影，不承载文字（`sky.edge` 七档全是暖白/冷白/粉紫，没有绿）。

### 3.1 气质 → 档位映射

| 参考图气质 | 本项目档位 | `top / horizon / ground` | 与参考图的差 |
|---|---|---|---|
| 深蓝（最接近的一组，占参考图约一半） | **`night`** | `#05070E / #101A2C / #02040A` | 更黑，`edge` 冷蓝灰 `#2E4068` 是唯一亮部 |
| 紫橙 | **`sunrise`** | `#E8894A / #FFD9A0 / #2A1608` | 参考图偏"紫在上橙在下"，本档是橙上暖黄下 |
| 紫橙（冷版） | **`blueDusk`** | `#C9486F / #7A4E86 / #0E0713` | 绯红压紫，属于"日落之后"而非"日落" |
| 黑金 | **`golden`** | `#5FB6EA / #FFC46B / #1C1106` | 上部仍是蓝（物理天空），只有地平线是琥珀 |
| 青绿 | **无对应档** | — | 用 `blueDusk` + `Theme.limeDeep` 雾（参考图那种青绿底本工程造不出来，也不该造） |
| 橙红 | **`sunset`** | `#DD5530 / #FFB067 / #180A05` | 最接近 |
| 近白 / 灰白 | **`day`** | `#3E8FD6 / #BFE4FF / #0B1620` | 参考图里最亮的那几张；本档只能配 `ground` 压纱到 0.28 以下才不刺眼 |

### 3.2 七档 → 该承载什么信息

| 档 | 气质 | 适合承载 | 不要承载 | 文字 |
|---|---|---|---|---|
| `night` | 深蓝近黑 | **大字数字**（主时刻、总额、天数）；冷调倒计时；"没有事发生"的静默态 | 3 行以上正文（底色近黑，行长一多就闷） | `ink` / `inkDim` |
| `blueDawn` | 靛蓝 → 紫 | **"再过一会儿会变"**：晨间蓝调、次日预告、即将开始的场次 | 强调"现在正在发生"（蓝调是过渡，不是事件） | `ink` / `inkDim` |
| `sunrise` | 橙红 → 暖黄 | **"刚刚开始 / 正在进行"**：进行中、日出、开播 | 长文案（`horizon` 太亮，正文压不住） | `ink`（`horizon` 区不要放字） |
| `golden` | 蓝 → 琥珀 | **"还有一段缓冲"**：倒计时 > 1 小时、黄金时刻、可安排的时间 | 紧急提醒（暖黄读作"还早"） | `ink` / `inkDim` |
| `day` | 蓝 → 近白 | **承载最多小字**：唯一能放 3 行以上文字、多处 11pt 的档；摘要卡、云野 | 大数字做主视觉（亮底上 34pt 会"糊"成一团） | `ink` 必须配 `ground` 压纱 ≥0.20 |
| `sunset` | 深橙红 → 暖橙 | **暖调提醒**：重要但不紧急、末场、收官前 1 小时 | 长时间停留的阅读（红底读久了累） | `ink` |
| `blueDusk` | 绯红 → 紫 | **"过去 / 收束"**：已结束、收官态、上月、暮土 | "即将开始"（绯红读作"已经晚了"） | `ink` / `inkDim` |

选择顺序固定为一条判断链，避免每张卡各挑各的：

```
有"正在发生"的场次？ → 是 → sunrise
                      → 否 → 30 分钟内开始？ → 是 → blueDawn
                                              → 否 → 今天还有场次？ → 是 → golden（>1h）/ sunset（末场）
                                                                    → 否 → 本月还有？ → 是 → blueDusk（今日收官）
                                                                                     → 否 → night（本月收官）
需要放 3 行以上正文？ → day（覆盖上面全部判断）
```

---

## 4. 现状评审：红石小组件

对象：`Sources/Widget/RedstoneFace.swift`（卡面 + 轨迹 + 背景）、`Sources/Widget/RedstoneWidget.swift`（装配）。
前提：V3.7 已只留 `.systemSmall`，中号的场次表整段删除。

### 4.1 打分（7 条 → 达标 1 / 偏离 6）

| 规则 | 现状 | 判定 | 改法 |
|---|---|---|---|
| **R1 色场** | 3 停靠点 `0/0.60/1` ✓；但 `unknown` 分支用 `topLeading→bottomTrailing`（`RedstoneFace.swift:653`）；压纱压向 `Theme.bgBase`（`:679`），`暮土 0.76` 在浅色外观会把卡洗成米白；层数 = 渐变 + 纱 + 气 + 剪影 = **4 层**（上限 3） | **偏离** | ①`:653` 角度改 `.top → .bottom`，保留 `trackTop/trackBottom`；②`:679` 纱改 `Theme.sky(phase).ground`，上限 0.76 → **0.28**；③删剪影（见 R7 行） |
| **R2 层级** | eyebrow 11 semibold ✓ 但**无 `tracking(0.5)`**（`:215`）；右上值是 `Theme.lime` 填充胶囊（`:230`），是全卡第 2 支强调色 + 唯一嵌套面；三处 10pt（`endpoint:23`、`tag:27`、`sessionCount:34`）低于 11pt 底线；文字用 `Theme.textPrimary`（会随外观翻转，饱和色场上浅色模式变深字） | **偏离** | ①胶囊 → 11pt semibold 纯文字，色用 `Theme.trackArc`；②三处 10pt → 11pt；③`:217/:250/:310/:315` 改 `sky.ink`，`:331` 与两端极值改 `sky.inkDim`；④`:215` 补 `.tracking(0.5)` |
| **R3 轨迹** | 线宽 1.2 / 雾化 3.2 / 0.16 / 光点 5+20 全达标 ✓；但 `.stroke` 未给 `StrokeStyle`（`:483`、`:488`）→ **默认 butt 端**；弧是**单一不透明度**，没有"一段亮一段暗"的渐变描边；`occurrences.count >= 2` 才画（`:295`），**单场日整块消失** | **偏离** | ①两处 stroke 加 `style: StrokeStyle(lineWidth:, lineCap: .round, lineJoin: .round)`；②弧改横向 `LinearGradient` 描边，峰值 0.62 对齐光点 x、谷值 0.18（照 `SkyLightFace.swift:302` 的 `strokeStyle`）；③单场日画"22pt 短线 + 光点" |
| **R4 光效** | `.blur()` 0 次 ✓；光点 20pt/0.32 ✓；但背景那口气半径 **0.80–0.90 × 卡宽**、alpha **0.22–0.26**（`:916-939`）—— 接近"整卡泛光"，把色场的渐变吃掉了，比上限大一倍 | **偏离** | `:696` 半径系数 → **0.50**、alpha → **0.16**；中心从贴边（`0.66, 0.92`）移到主值附近（`0.38, 0.32`） |
| **R5 留白** | 内容区 132×132、内边距 13 ✓；但纵向预算 **131 / 132 = 99.2%**（`RedstoneFace.swift:183` 自己算的），余量只剩 1pt；`gapHeaderTime 8`、`gapArcEndpoint 2`、`arcHeight 24` 已无腾挪空间 | **偏离（临界）** | `gapHeaderTime 8→6`、`gapArcEndpoint 2→1`、`arcHeight 24→22` → **126 / 132 = 95.5%**，正好抵掉 R2 里 11pt 带来的 +1.2pt |
| **R6 圆角** | 卡面 0 处自绘圆角/描边/投影 ✓；`contentMarginsDisabled()` ✓（`RedstoneWidget.swift:39`）；唯一自绘形是倍率胶囊 4pt（允许的同心例外） | **达标** | 胶囊按 R2 去掉后，自绘形归 0 |
| **R7 禁止项** | 倍率胶囊 = 第 3 支强调色（命中 #3）；剪影 = 装饰几何（命中 #8）；无插画 ✓、无 embed 卡 ✓、无 lime 字 ✓、无 <11pt… ✗（命中 #9） | **偏离** | 胶囊去面、剪影删除、三处 10pt → 11pt |

### 4.2 两个指定问题

**Q1：中号删掉后"今日几场"够用吗？**

结论：**信息位够，呈现不合规。**

- 位置没问题：`countdownRow` 右端是全卡唯一还剩的横向余量。实测宽度：箭头 10 + 3 + "还有"22 + 3 + `39:27` 33 = 71，右端 "今日 4 场" 44，合计 119 < 132 ✓。改成 11pt 后约 124，仍 < 132 ✓。
- 问题在两处：①字号 10pt（`RedstoneMetric.sessionCount`，`:34`）；②`Theme.textPrimary.opacity(0.45)`（`:331`）压在 `day` 档（纱 0.58）上，实际对比度约 2.4:1，11pt 以下文字读不清。
- 改法：字号 11 medium、颜色 `sky.inkDim`、`needsCheck` 时显示"待核对"（现有逻辑保留，`:339`）。**不要**把"今日 4 场"挪去 eyebrow 右端与倍率并列 —— 两者相加 44 + 4 + 28 + 地名 77 = 153 > 132，会把地图名压到 `minimumScaleFactor` 0.68 以下。

**Q2：34pt 主时刻在 158 宽度里还留得住轨迹吗？**

- **横向留得住**：`23:08` 在 34pt rounded + `monospacedDigit` 下实测约 85–90pt，占内容宽 65–68%，在 78% 上限内；加上"进行中"（11pt ≈ 33 + 6 间距）总宽 124–129 < 132 ✓。
- **纵向才是瓶颈**：五层合计 131/132（99.2%），轨迹只剩 24pt 且没有余量。**升到 40pt 会直接顶掉倒计时**（+7pt 行高）。所以 34 是 158 宽度的正确值，不要为了"更冲击"加到 40；40 留给 338。
- 腾挪只能从 R5 那三处挤（8→6、2→1、24→22），不许压缩主值到 28 —— 28pt 与 11pt 的层级差只有 17pt，低于 R2 要求的 23pt。

### 4.3 可立刻执行的修改（按优先级）

| P | 文件:行 | 改动 | 验收 |
|---|---|---|---|
| P0 | `RedstoneFace.swift:230-240` | 删 `rateBadge` 的 `Theme.lime` 底与 4pt 圆角，改 `Text("2.5×").font(11 semibold).foregroundStyle(Theme.trackArc)` | 卡面自绘形 0 处；强调色只剩 `sky.edge` 一支 |
| P0 | `RedstoneFace.swift:483`、`:488` | `.stroke(…, style: StrokeStyle(lineWidth: …, lineCap: .round, lineJoin: .round))` | 弧两端是圆头，不再有方角 |
| P0 | `RedstoneFace.swift:34 / :23 / :27` | `sessionCount`／`endpoint`／`tag` 全部 10pt → **11pt** | 全卡 grep 不到 `size: 10` |
| P0 | `RedstoneFace.swift:331` | `Theme.textPrimary.opacity(0.45)` → `band.sky.inkDim`（**不用** `textSecondary`：它在浅色外观翻成深灰，压不住饱和色场） | 11pt 下对比度 ≥ 4.5:1 |
| P0 | `RedstoneFace.swift:45 / :51 / :61` | `gapHeaderTime 8→6`、`gapArcEndpoint 2→1`、`arcHeight 24→22` | 纵向 126/132（95.5%），倒计时行不被裁 |
| P0 | `RedstoneFace.swift:679-690` | 纱从 `Theme.bgBase` 改 `band.sky.ground`，`Band.veil` 六档 0.18–0.76 → **0.10–0.28** | 浅色外观下卡片仍是饱和色场，不是米白 |
| P1 | `RedstoneFace.swift:483-496` | 弧改横向渐变描边：`peak 0.62` 锚在光点 x、`base 0.18`、`spread 0.34` | 轨迹"一段亮一段暗"，亮段随场次移动 |
| P1 | `RedstoneFace.swift:696-708` + `:916-939` | 那口气半径系数 →0.50、alpha →0.16、中心 →`(0.38, 0.32)` | 主值附近有柔光，卡边不再泛光 |
| P1 | `RedstoneFace.swift:717-831` | 删 `silhouettes` 整块（6 个形状函数一并删，不留死代码） | 背景层数 = 3 |
| P2 | `RedstoneFace.swift:295-303` | 单场日不再整块不画：保留 22pt 弧带，画一条 24pt 短线 + 1 个光点 | 单场日卡面不塌陷，纵向仍是 126 |

> 说明：以上全部是"改数值 / 删代码"，不涉及新架构。P0 六条合起来约 40 行改动。

---

## 5. 现状评审：天光小组件

对象：`Sources/Widget/SkyLightFace.swift`、`SkyLightWidget.swift`、`WidgetTheme.swift`（`SkyLight` 段）。
**本节不改代码**（用户明确"保持不动"），只标注将来若调整的方向。

### 5.1 打分（7 条 → 达标 4 / 偏离 3）

| 规则 | 现状 | 判定 | 若将来调整，往哪调 |
|---|---|---|---|
| **R1 色场** | 色场层 = 渐变（`top → horizon`）+ 1 团径向太阳光 + 地面填充 = **3 层**（地平线三层与太阳归属轨迹组，不计入色场层）；饱和色场 ✓；不随外观变浅 ✓（`sky.*` 固定 hex）；文字固定 `sky.ink/inkDim` ✓ | **达标** | 保持。若要说一处：`glowLayer` 的 `.plusLighter`（`:251`）在 `day` 档（近白底）会把地平线提亮到与 `ink` 抢层级，可加 `alpha × 0.8` 上限 |
| **R2 层级** | **中间那层缺主值**：全卡最大字号是倒计时 12pt（中号）/10pt（小号），"三层"实际只有两层半，靠太阳的图形替代主值；小号字号 9pt（`phaseLabelSmall`）/10pt（`countdownSmall`）/9pt（`sunTimeSmall`）三处低于 11pt 底线 | **偏离** | 倒计时提为主值：158 → **34** rounded bold、338 → **44**（与 R2 表一致）。前提是主值只放**数字**：`12小时32分钟` 一律改写成 `12:32`，中文量词移到 eyebrow（"距日出 12:32"）。宽度核算：5 字符 34pt ≈ 90pt < 103pt（78% 上限）✓；阶段名降为 11/12pt eyebrow，标点与"剩余"字样一并移出主值行；`sunTime` 统一 11pt |
| **R3 轨迹** | 地平线本体 1.6 / 雾化 3.4 / 夜间 1.0 / `crestY 0.62 / edgeY 0.74` 与 App 同源 ✓；亮段由 `strokeStyle` 锚在太阳 x（`peak 0.95 / base 0.36 / spread 0.34`）—— **这是全工程唯一一处真正实现"渐变描边"的地方，红石应照抄**；`.stroke` 同样未给 `StrokeStyle`（`:270`、`:275`、`:287`）→ butt 端（地平线贯穿全宽，两端在卡外，影响为 0） | **达标（细节待补）** | 若要统一：三处 stroke 补 `lineCap: .round`，与红石一致，供 `HorizonEdge` 未来被裁短时复用 |
| **R4 光效** | 0 次 `.blur()` ✓；太阳光半径 0.45×宽 / alpha 0.45 / 3 停靠点 ✓；余晖 0.18 ✓ | **达标** | 保持 |
| **R5 留白** | 小号 11pt / 中号 14pt（`WidgetTheme.swift:194-196`）—— 与红石 13 不一致：两张卡并排在桌面上，字与卡边的距离差 2pt，肉眼能看出来 | **偏离（统一性）** | 小号 11 → **13**（与红石同一值），中号 14 → **16**（与 R5 表一致）。小号改 13 后内容区 132×132，34pt 主值 + 两行 11pt 仍在 96% 以内 |
| **R6 圆角** | 0 处自绘 ✓；`contentMarginsDisabled()` ✓（`SkyLightWidget.swift:47`） | **达标** | 保持 |
| **R7 禁止项** | 无插画 ✓、无嵌套卡 ✓、无 lime ✓、字号有 <11pt（命中 #9）、不支持大号（正确，4×2 会把天空拉空） | **偏离** | 只改 #9，见 R2 行 |

### 5.2 一句话结论

天光是这套语言的**样板实现**（饱和色场 + 一条轨迹 + 一个当下，三样齐全，且刻度全在 `Theme.sky` 上），唯一的结构性缺口是"中间没有那个大数"。将来若动手，顺序是：R2（提主值到 34/44、清掉 9pt 与 10pt）→ R5（内边距统一到 13/16）；R1 / R4 / R6 保持不动，R3 只在下次因别的原因动这三处 stroke 时顺手补 `lineCap: .round`。

---

## 6. 给 App 内页面的迁移建议

对象：`Sources/DesignSystem/SkyCard.swift`、`TrackCard.swift`、`SectionHeader.swift`。

### 6.1 可以迁（3 条）

| # | 迁什么 | 落点 | 理由 |
|---|---|---|---|
| 1 | **三层信息骨架**：eyebrow（11 semibold +0.5）→ 主值（40 rounded）→ 两端极值（11 mono `inkDim`） | `TrackCard` 的内容区（红石页 hero、首页红石卡）；`SectionHeader` 右侧动作沿用 17pt 但标题保持 22pt（App 内需要 22pt 分区标题，不套用小组件的 11pt） | 收益页/红石页现在都是"标题 + 一段正文 + 一堆小字"，主值不突出。骨架搬过来即可得到"一个大数 + 一行小字"的读法，且不需要新 token（`Typography.metricL` 40 rounded 已存在） |
| 2 | **径向柔光替代 shadow** | `TrackCard.swift:121`（`shadow(radius:16, y:8)`）、`SkyCard.swift:82`（`shadow(radius:18, y:10)`） | 列表里十几张卡各带一层 shadow，滚动时每帧都要重新合成阴影。改成 1 层 `RadialGradient`（半径 ≤0.5×短边、alpha ≤0.16）观感更"发光"、成本更低；深浅色跟随问题也不存在（阴影本来就是黑的） |
| 3 | **固定色场 + 固定 `sky.ink`** | `SkyCard` 已经是这个做法；把它推广到 hero 级卡（红石页月度卡、收益页总额卡） | 物理天空色不随深浅外观翻转，卡在浅色模式下仍是一块"天色"，这正是参考图的气质来源。收益页用 `night` + `riseRed/fallGreen` 做涨跌，货币用 ¥（`+¥1,280` / `−¥320`，符号与数字同 40pt rounded，不用箭头图标 —— 图形位留给轨迹） |

### 6.2 不要迁（3 条）

| # | 不要迁什么 | 为什么 | 该保留什么 |
|---|---|---|---|
| 1 | **"整卡一个色块、只有一个点击目标"** | 小组件只能 `widgetURL` 整卡跳转；App 内卡片要按钮（展开、翻月、跳详情）、要可选中、要长按菜单。压成一个不可分的色块等于砍掉交互 | 保留 `GlassButtonStyles` 的按压反馈 + 多个可点区域（≥44pt） |
| 2 | **"无描边、无投影、不跟深浅色"** | App 内卡片浮在页面渐变上；浅色模式下如果既无描边也无投影，`trackTop`（白）与页面底（`#EDF1EC`）会粘成一片。而且 App 内必须跟随 `Theme.active` 五套主题与深浅外观，不能像小组件那样固定色 | 保留 `TrackCard.swift:111-120` 的 `glassStrokeTop → glassStrokeBottom` 渐变描边、`SkyCard.swift:79-81` 的 1pt 描边；`SkyCard.swift:105` 的 `.blur(radius: 0.5)` 可保留（单张、非每帧），但**新组件不要引** |
| 3 | **"每张卡都是饱和色场"** | 一屏 10+ 张饱和卡会互相打架；正文（17pt）在饱和底上对比度不够（`sunrise` 的 `horizon #FFD9A0` 配 `ink` 只有 1.6:1），长文不能用 | 饱和色场只给 **hero 级**（每屏 ≤2 张）；列表卡继续走 `glassStaticFill` + `textPrimary` |

补充一条边界：小组件字号写死，App 内**必须**吃 Dynamic Type。所以 R2 的字号表只在 `Sources/Widget` 生效，App 内用 `Typography` 的语义档位，不要照搬 11/34 这两个数字。

---

## 7. 检查清单（新组件自查，10 条）

- [ ] **1** 底色是 `Theme.sky(band)` 的 3 停靠点渐变（`0 / 0.60 / 1`）、角度 `.top → .bottom`，全卡没有纯白/纯灰。
- [ ] **2** 卡面自绘形 0 处：没有 `RoundedRectangle` / `clipShape` / 描边 / `shadow`；背景在 `containerBackground`，系统 `contentMarginsDisabled()`。
- [ ] **3** 字号只有三档：158 → 11 / 13 / 34；338 → 12 / 15 / 44。`grep "size: 1[0-9]"` 里**没有 9 或 10**。
- [ ] **4** 主值宽度 ≤ 内容宽 78%；主值与 eyebrow 层级差 ≥ 23pt。
- [ ] **5** 轨迹有且只有一条；`.stroke` 带 `StrokeStyle(lineCap: .round)`；亮段用横向 `LinearGradient` 描边、顶点对齐光点 x。
- [ ] **6** 光效 ≤2 处；径向光半径 ≤0.5×短边、中心 alpha ≤0.32；`grep -c "blur(" == 0`。
- [ ] **7** 纵向占用 ≤96%；主值到轨迹 ≥10pt。
- [ ] **8** 颜色全部来自 token：无 `Color(hex:)`、无 `Color.white.opacity`、无 `foregroundStyle(Theme.lime)`、饱和色场上没有 `Theme.textPrimary`。
- [ ] **9** 强调色 ≤2 支；`Theme.lime` 最多 1 处面、面积 ≤8%、面上字是 `onLime`。
- [ ] **10** 空态/无数据不画假轨迹、不写 `00:00`；`bash scripts/lint-theme.sh` 全绿。

---

## 附录 A · 视觉角色 → token 对照总表

| 视觉角色 | token | 备注 |
|---|---|---|
| 色场 3 停靠点 | `Theme.sky(band).top / .horizon / .ground` | `Sources/Shared/Theme/Theme.swift:447` |
| 压纱 | `Theme.sky(band).ground` | **不用** `Theme.bgBase`（R1） |
| 卡上主文字 | `Theme.sky(band).ink` | 固定 `#F5F8FF`，不随外观翻转 |
| 卡上次文字 | `Theme.sky(band).inkDim` | `ink` 的 0.72 |
| 卡上第三层字 | `Theme.sky(band).ink.opacity(0.55)` | 见附录 B |
| 轨迹 / 光点环 | `Theme.trackArc` | 动态；浅色 `#5C74A8` |
| 轨迹雾化 | `Theme.trackArc.opacity(0.16)` | |
| 光点本体（地图主色） | `Theme.sky(band).edge` | 该档最亮、最有色相的一支 |
| 唯一允许的强调面 | `Theme.lime` + `Theme.onLime` | ≤1 处、≤8% |
| 青柠色文字 / 可点图标 | `Theme.limeInk` | 禁 `lime` |
| 绿色（雨林雾、剪影） | `Theme.limeDeep` | 只做雾/形，不做字 |
| 状态：涨 / 跌（App 内） | `Theme.riseRed` / `Theme.fallGreen` | 中国习惯 |
| 平台身份（App 内） | `Theme.Platform.of(name)` | 只做圆点与 ≤2pt 细条 |
| 兜底夜（认不出地图） | `Theme.trackTop → Theme.trackBottom` | 2 停靠点 |
| 层级文字（App 内玻璃卡） | `Theme.textPrimary / textSecondary / textTertiary` | 只在**非饱和底**上用 |
| 禁止 | `Color(hex:)`、`Color.white.opacity`、`foregroundStyle(Theme.lime)`、饱和场上的 `textPrimary` | lint 规则 1 / 3 / 4 |

## 附录 B · token 增量

**必须新增：0 项。** 上面所有角色都能落到现有 token 上，`Theme.sky` 六元组 + `trackArc` + `lime/onLime/limeInk/limeDeep` + `trackTop/trackBottom` 已经够覆盖"色场 / 轨迹 / 光点 / 三层字"。

**建议新增（1 项，非阻塞）：**

| token | 值 | 为什么现有不够 |
|---|---|---|
| `Theme.SkyColors.inkFaint` | `ink.opacity(0.55)`（188/255） | 现有只有 `ink`（1.0）与 `inkDim`（0.72）两档，而 R2 要求三层字（eyebrow 主 / 次 / 极值）。现在第三层只能在 5 个 View 里各写一次 `.opacity(0.45)` / `.opacity(0.55)` / `.opacity(0.62)` —— 三张卡已经出现三个不同值（`RedstoneFace.swift:331` 0.45、`:310` 0.55、`:387` 0.62），无人审过的浅色值就是这么长出来的。加一档后这三个数收成一个 token |

新增位置：`Sources/Shared/Theme/Theme.swift` 的 `SkyColors` 结构（`sky(_:)` 七档各加一行 `inkFaint: ink.opacity(0.55)`），不动任何 hex。`SkyColors` 是固定色结构（不走 `dyn`），所以这一项不影响 lint 与深浅外观。

## 附录 C · 变更记录

| 日期 | 变更 | 触发 |
|---|---|---|
| 2026-10-31 | v1 建档：一句话定义 + 7 条硬规则 + 七档对照 + 红石/天光评审 + 迁移建议 + 检查清单 | 用户第 4 次提供小组件参考图并要求"以后都按这样设计"；上一轮误把 6 张天光图当参考，本轮把语言显式写下来，避免再次跑偏 |
