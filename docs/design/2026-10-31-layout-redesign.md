# 版面重构报告：把「空」改成 App Store Today 的节奏

- 日期：2026-10-31
- 角色：产品（Alice）
- 范围：`Sources/Features/**` 五个一级页 + `Sources/DesignSystem/**`
- 硬约束：不发明颜色 / 不发明字阶 / 不新增圆角；所有数值要么落在现有 token，要么进本文 §5「token 增量」
- 不改 Swift 代码（本文件即交付物，工程师照着写）

---

## 1. 结论先行

**根因一：卡片"底盘大、内容小"。** 首页两张主卡分别是 196pt（`SkyCard.swift:71` `minHeight: 196`）与约 223pt（`TrackCard.swift:28/33` arcBand 52 + arcGap 22 + 16 内距），但卡内真正承载信息的文字只占 4 行 12pt（`TodayBriefTrackCard.swift:58-78`）与右栏 3 行 12pt（`RedstoneCountdownCard.swift:67/176-194`）。剩下的是渐变与天空留白 —— 观感是"三块深色玻璃 + 一堆 11–13pt 小字"，不是"一屏内容"。

**根因二：块与块之间没有重量差。** 全宽 353pt、圆角 24（`Radius.card`）、阴影 16/18、间距要么 12 要么 24，而**首页没有任何一处 22pt 文本**（`Typography.titleL` 在首页 0 命中，仅出现在设置/文章/问卷等次级页）。于是字阶只剩 `34 → 17/20 → 13 → 11`，缺了 Title 2 这一级；眼睛扫下去找不到"这是新的一组"。

**改版主线（一句话）：把等距堆叠换成「1 大 + 2 中 + N 小 + 每组一条横滑 rail」的节奏 —— 一屏一个锚点，每两个块必有一个 22pt 分区标题，组间 32 / 组内 12。**

---

## 2. App Store Today 版式解剖（7 条规则）

依据：Apple HIG《Typography》《Layout》（大字阶表、视觉层级、用留白与容器分组）、WWDC 2017 Session 301（Today = 一系列每日更新的卡片，卡片即模块系统，保留最多 7 天内容并用日期标记分隔）、App Store Connect 创意素材规范（卡片媒介是 16:9 横构图，文字压在图上）。

> 说明：苹果从未公布 Today 卡片的像素稿。下表的数值是**由 HIG 字阶 + 8pt 网格 + 本工程现有 token 反推的可落值**，不是"官方像素"。凡能对上现有 token 的，一律标 token 名。

| # | 规则 | 数值（可落 SwiftUI） | 本 App 怎么用 |
|---|---|---|---|
| R1 | **一屏一锚点**：首屏只有一个视觉重量最高的块，其余必须明显更轻 | 锚点 ≥ 240pt 高，或含 ≥ 40pt 主数字；次重块 ≤ 168pt；两者高度差 ≥ 70pt | 首页锚点 = 红石倒计时（`CardTier.hero` 240，主数字用新 token `metricL` 40pt）；今日简报降为 `CardTier.medium` 168 |
| R2 | **每个分组必须有 Title 2 级标题 + 尾部动作**，标题比正文大 ≥ 5pt | `Typography.titleL` 22 semibold，下间距 `Spacing.sectionTitleGap` 12；尾部动作 17pt regular `Theme.limeInk` | 新增 `SectionHeader`；首页/收益/简报/更多/红石全部接入；删掉 `EarningsView.swift:478-487` 那个 12pt 的假 sectionTitle |
| R3 | **组距 ≥ 2.5 × 组内距**：间距差就是层级 | 组间 `Spacing.sectionGapLoose` 32；组内 `Spacing.cardGap` 12；标题下 12 | 现在 24 : 12 = 2.0，读不出换组；首页 `OverviewView.swift:76` 用 12 串所有块、`:109` 又用 24，一页两套"组距" |
| R4 | **每组给一条横滑 rail，且必须"露边"**（露出下一张 ≥ 1/3），这是"还有内容"的唯一低成本暗示 | 卡宽 140 × 高 188，间距 12，左侧与页面 20 对齐、右侧出血到屏幕边；393 屏上第三张露出 49pt（35%） | 新增 `Rail`（`ScrollView(.horizontal)` + `LazyHStack` + `.scrollTargetBehavior(.viewAligned)`）；首页「继续读」、红石「今日场次」、简报「版本记录」 |
| R5 | **卡片只有三档尺寸，禁止全宽同高** | `CardTier`：hero 240 / medium 168 / tile 96 / rail 140×188（8pt 网格） | 现有 3 张大卡全是"无名高度"，一张 196、一张 223；统一进 `Layout.swift` |
| R6 | **每张卡必须有一个"大东西"**：大数字、大图、或大标题；禁止"全 13pt 文字卡" | 卡内最大字号 ≥ 20pt（`titleM`），或图像/渐变区 ≥ 80pt 高 | 收益页 `platformCard`（`EarningsView.swift:279-309`）整卡最大字 12pt → 必须给平台名 15pt + 金额 17pt + 12pt 占比条 |
| R7 | **眉题（eyebrow）+ 日期标记**：小、宽、无声，负责说"这是什么栏目"；日期标记负责把"今天/昨天"切成段 | 眉题 11pt semibold + 字距 0.5（新 token），色 `Theme.textTertiary`，与标题间距 6；日期标记 13pt + 1pt `Theme.divider` | 新增 `Eyebrow`；每张 hero/medium 卡左上角一枚（「红石 · 今日」「简报 · 未推送」「收益 · 本月」）；首页日期行下加一条 divider + 3 个内联指标 |

补充两条 Today 的"感觉"来源，落到本 App 就是：

- **卡片即模块**（WWDC 301 原话：story 是"a series of modules"）：同一份数据在不同层级用不同模块承载 —— 首页的简报是"摘要卡"，简报页是"全文模块"，两者**不能是同一张玻璃卡**（现状 `TodayBriefCard.swift:21` 是普通 `GlassCard`，首页却是漂亮的 `SkyCard`，同一数据两个长相）。
- **一屏最多 3 种视觉材质**：Today 全页只有"图 + 文字 + 系统分组背景"。本 App 现有材质有：深靛轨迹渐变、天空渐变、玻璃卡、静态玻璃卡、胶囊 —— 一屏出现 4 种以上就会"花而不满"。

---

## 3. 逐页审计表

> 证据一律给 `文件:行号` 或组件名。行号对应本仓库当前版本。

### 3.1 首页 `OverviewView`（Tab 1）

| 现有区块 | 问题 | 证据 |
|---|---|---|
| 页面骨架 | 全页只有 3 个子块（header / bodyContent / 收尾），bodyContent 又用 12pt 串所有卡；**同一页并存两套组距**（12 与 24），差 12pt 读不出层级 | `OverviewView.swift:33`（sectionGap 24）、`:76`（cardGap 12）、`:109`（sectionGap 24） |
| 日期头 | 只有 `footnote 13 → display 34 → captionXS 11` 三级跳，中间空档；无日期标记 / 无内联指标，一屏最有"编列感"的位置被浪费 | `OverviewHeader.swift:19/22/28` |
| 红石倒计时卡 | 223pt 高，主数字 36pt 是 inline 硬写；右栏固定 126pt 只放 3 行 12pt；无进度感（"今天第 2/3 场"这件事没说） | `RedstoneCountdownCard.swift:130`（`.system(size: 36…)`）、`:67`（`frame(width: 126)`）、`:176`（`prefix(3)`） |
| 今日简报卡 | 196pt 高但正文只有 1 句 headline 17pt + 1 行 12pt；卡片顶部只用 12pt 的时段标签，缺"今天"这个大标题 | `SkyCard.swift:71`、`TodayBriefTrackCard.swift:60-77`、`SkyCardBody`（title 17pt / body 12pt，`SkyCard.swift:169/176`） |
| 光遇状态卡 | 与上两张卡同宽同圆角同阴影，视觉重量接近 → 三块"一样重"，没有主次 | `SkyStatusCard.swift:22`（`PressableGlassCard`）、`Cards.swift:9` |
| 快捷入口 | 3 枚胶囊，48pt 行高，压在页尾 —— 首屏最轻的块，却和卡片同色同宽 | `Badges.swift:94-108`（`HStack(spacing: 10)`） |
| 内容流 | **首页没有任何文章内容**（"最近写的"整块被删），读完 3 张卡即到底 → "空"的直接来源 | `OverviewView.swift:12-14` 注释 |
| 横向 | 全页 0 个横向滚动区；`CoverArt` 程序化封面在首页完全未使用 | `grep ScrollView(.horizontal)` 只在文章代码块/简报详情/记账表单命中 |
| 字阶层级 | 无 22pt 文本 → 字阶 34 / 20 / 17 / 13 / 11，缺 Title 2 | `grep Typography.titleL Sources/Features/Overview` 0 命中 |

**一屏纵向预算（iPhone 15 Pro 393×852，扣除状态栏 59 与底栏 90，可视 ≈ 703pt）**

| 元素 | 高度 |
|---|---|
| top padding | 8 |
| 日期头 | 76 |
| 组距 | 24 |
| 红石卡 | ~223 |
| 组内距 | 12 |
| 简报卡 | 196 |
| 组内距 | 12 |
| 状态卡 | ~150 |
| **合计** | **~701** |

结论：**一屏塞进了 4 个块，但 3 个是"深色/玻璃大底盘 + 小字"，1 个是"天空大底盘 + 小字"**。空不是块少，是每块的"内容占比"低、块间无差。任何"再加一张卡"的修法都会让页面更长更闷。

### 3.2 红石页 `RockCalendarView`（Tab 2）

| 现有区块 | 问题 | 证据 |
|---|---|---|
| 页面骨架 | 6 个块全部 `cardGap 12` 等距平铺：下一场条 / 翻月器 / 月历 / 分布 / 规律入口 | `RockCalendarView.swift:28-35` |
| 标题区 | `display 34` + `footnote 13`，无 22pt；攻略按钮是页头唯一动作 | `:71-102` |
| 翻月器 | 32pt 圆形箭头 + 20pt 月份，独立占一行 40pt，前后各 12pt → 白白吃掉一屏的 64pt | `:114-132`、`:140-157` |
| 月历 | `cellHeight 56 × 6 行 ≈ 336pt`，是全页唯一重量，但前后只有 12pt → 节奏断裂（重块被轻块夹住） | `RedstoneMonthGrid.swift:41` |
| 本月分布 | 折叠卡，标题 17pt，与月历同级 → 图和表打架 | `MonthDistributionCard.swift:41` |
| 规律入口 | 单行 `GlassListRow`，无分组标题 | `RockCalendarView.swift:205-213` |

### 3.3 简报页 `BriefView`（Tab 3）

| 现有区块 | 问题 | 证据 |
|---|---|---|
| 页头 | `display 34` + `captionXS 11` 两级，缺"今天"的锚点 | `BriefView.swift:57-69` |
| 版本面板 | 两列玻璃并排，是首屏第一眼；但"今日简报"这个主角被排在它下面 → 主角开场缺席 | `:93`、`SkyVersionPanel.swift:12-20` |
| 今日简报卡 | 普通 `GlassCard` + 17pt 标题 + 15pt 行，与首页那张天空卡完全两个长相；同一份数据两套视觉 | `TodayBriefCard.swift:21/50/124-141` |
| 版本记录 | 又一张玻璃卡，与版本面板内容同源 → 首屏三张卡说同一件事（版本） | `BriefView.swift:95` |
| 推送行 | 11pt 单行收尾，页面止于最轻元素 | `:97` |
| 组距 | 4 块统一 24，无分组标题 | `:92` |

### 3.4 收益页 `EarningsView`（Tab 4）—— "一个大数字 + 一堆小字"的典型

| 现有区块 | 问题 | 证据 |
|---|---|---|
| 页面骨架 | 6 个块 `sectionGap 24` 等距，全部同宽同圆角 | `EarningsView.swift:33-48` |
| heroCard | 一张卡里塞 40pt 总数字 + 3 个 17pt 格子 + 12pt 说明 + CTA，**一屏只有这一个锚点**，之后全是小字表 | `:126-171`、`:135`（`.system(size: 40…)`）、`:147-153`、`:206-222` |
| 分区标题 | **sectionTitle 用 12pt caption** —— 分区标题比卡内正文（17pt）还小，等于没有分区标题 | `:478-487` |
| 平台占比 | 6pt 高胶囊条 + 12pt 文字，撑不起"平台占比"这四个字 | `:233-268`（`:253-263`） |
| 平台明细 / 活动流水 | 12pt 名称 + 11pt 数字，两张大卡都是"一堆小字" | `:279-309`、`:313-349` |
| 三态拆分 | 三个 17pt 数字并排 + 竖线，无"构成关系"（三态之和 = 总额这件事没被画出来） | `:147-153`、`:224-229` |
| 页脚 | 11pt 双行说明收尾 | `:463-476` |

### 3.5 更多页 `MoreView`（Tab 5）

| 现有区块 | 问题 | 证据 |
|---|---|---|
| 页头 | 34pt 标题 + 13pt 副行，无状态摘要 | `MoreView.swift:123-133` |
| 列表 | 4 行全部 48pt 等高、8pt 等距、无分组（问卷/监控/设置/关于混在一起） | `:38-76`（`VStack(spacing: 8)`）、`MoreRow :212` |
| 页尾 | 11pt 一句说明 | `:78-82` |

### 3.6 文章列表 `ArticlesView`（非 Tab，可间接进入）

| 现有区块 | 问题 | 证据 |
|---|---|---|
| 分组标签 | "置顶"用 `captionXS` 11pt —— 与正文同量级，等于没有分组 | `ArticlesView.swift:104-109` |
| 密度 | 列表本身密度够（`ArticleRowCard` 116/124pt 行高），**是全 App 唯一"不空"的页**，可作为其他页的密度基准 | `ArticleRowCard.swift:43` |

### 3.7 跨页共性四点

1. **0 处 22pt 分区标题**（全工程 `Typography.titleL` 只出现在次级页与弹层）。
2. **0 处横向 rail**（`ScrollView(.horizontal)` 只在代码块、黄历 chips、记账表单里出现）。
3. **0 张图**：`CoverArt` 只在文章列表缩略图（56×56）与详情 Hero 用，信息流主界面从未出现图像/色块。
4. **材质过多**：一屏可能同时出现 深靛轨迹渐变 + 天空渐变 + 真玻璃 + 静态玻璃 + 胶囊，5 种材质 ≠ 5 种层级。

---

## 4. 重构方案（逐页）

统一约定（下文不再重复）：

- 页面左右边距 `Spacing.page` 20；底 `Spacing.pageBottomInset` 120。
- **组间 32（`Spacing.sectionGapLoose`）/ 组内 12（`Spacing.cardGap`）/ 标题下 12（`Spacing.sectionTitleGap`）**。
- 卡片圆角一律 `Radius.card` 24；rail 卡与缩略图 `Radius.smallCard` 14；卡内图 `Radius.insideCard` 8。
- 尺寸只取 `CardTier`：hero 240 / medium 168 / tile 96 / rail 140×188。
- 每张主卡左上角一枚 `Eyebrow`（11pt semibold，字距 0.5，`textTertiary`）。

### 4.1 首页

```
┌────────────────────────────────────────────┐
│ 今天 · 周六                          [⚙]   │ 13pt textSecondary
│ 10月31日                                   │ 34pt display
│ ─────────────────────────────────────────  │ 1pt Theme.divider
│ 农历九月十二 · 距下一场 39:27 · 今日 3 场   │ 11pt，三点内联指标
├────────────────────────────────────────────┤ 24
│ ╭──────────── HERO · 240pt ──────────────╮ │ CardTier.hero
│ │ 红石 · 今日                    [2.5×]   │ │ Eyebrow + RateBadge
│ │                                         │ │
│ │ 39:27                                   │ │ 40pt metricL（剩余时间做主数字）
│ │ 下一场 23:08 · 霞谷 · 圆梦村            │ │ 17pt titleS
│ │ ──────────────●──────────               │ │ 4pt 进度轨（今日第 2/3 场）
│ │ 11:08  圆梦村   17:08  霞谷   23:08 霞谷 │ │ 13pt 三场并列
│ ╰─────────────────────────────────────────╯ │
│                                             │ 12
│ ╭──────────── MEDIUM · 168pt ────────────╮ │ CardTier.medium（SkyCard compact）
│ │ ● 日出            2分4秒   已推送 07:03 │ │ 12pt sky.inkDim
│ │ 今天风速偏大，记得添件外套。             │ │ 20pt titleM ← 从 17pt 升
│ │ ╭──────── 地平线 ────────╮              │ │ crestY 0.62 保留
│ │ 06:05                        18:13      │ │ 12pt
│ ╰─────────────────────────────────────────╯ │
├────────────────────────────────────────────┤ 32
│ 今日一览                            全部 ›  │ 22pt titleL + 17pt limeInk
│ ┌───────────────┐ ┌───────────────┐         │ 12
│ │ 国服   1.2.3  │ │ 国际服  1.2.2 │         │ CardTier.tile 96
│ │ 已是最新       │ │ 有新版本  NEW │         │ 20pt + 13pt + StatusPill
│ └───────────────┘ └───────────────┘         │
├────────────────────────────────────────────┤ 32
│ 继续读                              更多 ›  │ 22pt
│ ┌──────┐┌──────┐┌──────┐                   │ rail 140×188，第三张露 49pt
│ │ cover││ cover││ cover│                   │ CoverArt 96pt 高
│ │ 标题  ││ 标题  ││ 标题  │                 │ 17pt titleS 2 行
│ │ 3天前 ││ 5天前 ││ 1周前 │                 │ 11pt
│ └──────┘└──────┘└──────┘                   │
├────────────────────────────────────────────┤ 32
│ 快捷                                        │ 22pt（无尾部动作）
│ [全部文章]  [光遇简报]  [关于]              │ 保留 QuickEntryRow
└────────────────────────────────────────────┘
```

| 顺序 | 组件 | 文件 | 尺寸 / 间距 |
|---|---|---|---|
| 1 | `OverviewHeader`（改） | `Sources/Features/Overview/OverviewHeader.swift` | 加 divider + 内联指标行，总高从 76 → 92 |
| 2 | `RedstoneCountdownCard`（改，新增 `tier: CardTier = .hero`） | `Sources/Features/Overview/RedstoneCountdownCard.swift` | 240pt；主数字 `Typography.metricL`；新增 `RedstoneProgressTrack`（同文件，4pt 高） |
| 3 | `TodayBriefTrackCard`（改，`SkyCard` 传 `minHeight: CardTier.medium)`） | `Sources/Features/Overview/TodayBriefTrackCard.swift` + `DesignSystem/SkyCard.swift`（加 `minHeight` 参数） | 168pt；标题 17 → 20（`SkyCardBody` 加 `titleFont` 参数） |
| 4 | **新** `SectionHeader` | `Sources/DesignSystem/SectionHeader.swift` | 22pt + 17pt 动作 + 12 下距 |
| 5 | **新** `VersionTileRow`（复用 `SkyCardPhase`） | `Sources/Features/Overview/VersionTileRow.swift` | 两张 `CardTier.tile` 96，间距 12 |
| 6 | **新** `SectionHeader` + **新** `Rail` + **新** `ArticleRailCard` | `DesignSystem/Rail.swift`、`Features/Overview/ArticleRailCard.swift` | rail 140×188，CardArt 96 高，`Radii` 14 |
| 7 | `QuickEntryRow`（保留） | `DesignSystem/Badges.swift` | 不变 |

**首屏纵向预算（改造后）**

| 元素 | 高度 |
|---|---|
| top padding | 8 |
| 日期头（含 divider + 指标行） | 92 |
| 组距 | 24 |
| hero | 240 |
| 组内距 | 12 |
| medium | 168 |
| 组距 | 32 |
| 分区标题 + 下距 | 28 + 12 |
| tile 行 | 96 |
| **首屏止于** | **712 ≈ 703 可视** |

→ 首屏 = **4 个信息块（hero / medium / 2 张 tile）+ 1 个 22pt 分区标题**，且 hero 高度是 medium 的 1.43 倍、是 tile 的 2.5 倍，主次一眼可分。

### 4.2 红石页

```
┌────────────────────────────────────────────┐
│ 红石                            [ 攻略 ]   │ 34pt + 胶囊
│ 已生成 2026-09 ~ 2026-11                   │ 13pt
│ ╭──────────── HERO · 132pt ──────────────╮ │
│ │ 下一场 · 今日 23:08                     │ │ Eyebrow
│ │ 39:27          霞谷 · 圆梦村      2.5×  │ │ 40pt metricL + 17pt
│ ╰─────────────────────────────────────────╯ │
├────────────────────────────────────────────┤ 32
│ 本月                          ‹ 10月 › ›   │ 22pt + 32pt 圆钮并入同一行
│ ╭──────────── 月历 · 336pt ──────────────╮ │
│ │ 一  二  三  四  五  六  日              │ │ cellHeight 56
│ │  …                                      │ │
│ ╰─────────────────────────────────────────╯ │
├────────────────────────────────────────────┤ 32
│ 今日场次                                    │ 22pt（新增，rail）
│ ┌──────┐┌──────┐┌──────┐                   │ 128×112
│ │11:08 ││17:08 ││23:08 │                   │ 20pt 时刻 + 13pt 地图
│ │圆梦村││ 霞谷 ││ 霞谷 │                   │ 已过场次 0.32 透明（沿用）
│ └──────┘└──────┘└──────┘                   │
├────────────────────────────────────────────┤ 32
│ 本月分布                                    │ 22pt
│ ╭──────────── 折叠卡 · 88pt ─────────────╮ │
│ ╰─────────────────────────────────────────╯ │
│ 为什么是这天？                        v1.4 › │ 22pt + 17pt（原 rulesRow 升格为分区）
└────────────────────────────────────────────┘
```

关键动作：

- `RockCalendarView.swift:28` 的 `spacing: cardGap` → `sectionGapLoose`；
- `monthSwitcher`（`:114-132`）从独立一行变成 `SectionHeader` 的右侧插槽，**省 52pt**；
- `MonthDistributionCard` 默认折叠、高度固定 88，进"本月分布"分组（原来和月历同级）；
- `rulesRow` 由单行 `GlassListRow` 升为分组（标题 22pt + 单行 48pt）。

### 4.3 简报页

```
┌────────────────────────────────────────────┐
│ 简报                                        │ 34pt
│ 更新于 今天 07:30                           │ 11pt
│ ╭──────────── HERO · 260pt ──────────────╮ │ SkyCard（hero 变体）
│ │ ● 日出            2分4秒                │ │
│ │ 今天风速偏大，记得添件外套。             │ │ 22pt titleL（正文首句升为标题）
│ │ 日出 06:05 · 日落 18:13 · 紫外线 弱      │ │ 13pt 单行三个数字
│ │ ╭──────── 地平线 ────────╮              │ │
│ │ 宜 晒被、散步        忌 远行             │ │ 12pt chips
│ ╰─────────────────────────────────────────╯ │
├────────────────────────────────────────────┤ 32
│ 今日详情                                    │ 22pt
│ ╭──────────── 卡 · 自适应 ───────────────╮ │ 保留 TodayBriefCard 主体
│ │ 农历 · 星座 · 彭祖百忌 · 黄历（可展开）  │ │ 15pt 行
│ ╰─────────────────────────────────────────╯ │
├────────────────────────────────────────────┤ 32
│ 两服版本                                    │ 22pt
│ ┌──────────────┐ ┌──────────────┐          │ SkyVersionColumn ×2（保留）
│ └──────────────┘ └──────────────┘          │
│ 两个服的版本不一样 ›                        │ 13pt limeInk（diffRow 保留）
├────────────────────────────────────────────┤ 32
│ 版本记录                              全部 › │ 22pt + rail
│ 推送                            已推送 07:03 │ 22pt + 单行 48pt
└────────────────────────────────────────────┘
```

关键动作：**同一份简报数据在两页分饰两角** —— 首页是 168pt 摘要卡（`CardTier.medium`），简报页是 260pt hero（`CardTier.hero`，复用同一个 `SkyCard`，只是 `minHeight` 与标题字号不同）。`TodayBriefCard` 只保留"详情/展开"部分，删掉它的 17pt 标题头（`TodayBriefCard.swift:49-60`）。

### 4.4 收益页

```
┌────────────────────────────────────────────┐
│ 收益                                  [↻]  │ 34pt
│ 刚刚更新 · 来自收益工作台                   │ 13pt
│ ╭──────────── HERO · 216pt ──────────────╮ │
│ │ 总计 · 本月 +¥1,280.00 ↑                │ │ Eyebrow；本月新增用 riseRed
│ │ ¥12,480.00                              │ │ 40pt metricL
│ │ ━━━━━━━━━━━━━━━━━━━━━━                  │ │ 10pt 三态堆叠条（新）
│ │ ● 待发 ¥3,200   ● 未结 ¥5,000   ● 已结 ¥4,280 │ 13pt 图例 + 17pt 值
│ │                              [ + 记一笔 ]│ │ PrimaryCTA 胶囊
│ ╰─────────────────────────────────────────╯ │
├────────────────────────────────────────────┤ 32
│ 本月                                        │ 22pt
│ ┌────────┐ ┌────────┐ ┌────────┐           │ 3 × CardTier.tile 96
│ │本月新增│ │待结算  │ │活动 / 平台│         │ 11pt Eyebrow
│ │¥1,280  │ │2 个    │ │12 / 3  │           │ 28pt metricM
│ └────────┘ └────────┘ └────────┘           │
├────────────────────────────────────────────┤ 32
│ 平台占比                              明细 › │ 22pt
│ ╭──────────── 卡 · 168pt ────────────────╮ │
│ │ B站     ████████████████  ¥6,200  50%  │ │ 15pt 名 + 17pt 值 + 12% 条
│ │ 抖音    █████████         ¥3,600  29%  │ │ 条高 12（从 6 升）
│ │ 小红书  ██████            ¥2,680  21%  │ │
│ ╰─────────────────────────────────────────╯ │
├────────────────────────────────────────────┤ 32
│ 最近活动                              全部 › │ 22pt
│ ╭ 行 · 72pt ─────────────────────────────╮ │ 15pt 名 + 17pt 金额
│ ╰─────────────────────────────────────────╯ │
│ （页脚 11pt 说明，降为 textTertiary 单行）   │
└────────────────────────────────────────────┘
```

关键动作：

- `sectionTitle`（`:478-487`）**删除**，换 `SectionHeader`；
- 三态从"3 个并排数字 + 竖线"改成 **1 条 10pt 堆叠条 + 图例**，把 `pending + receivedUnclosed + closed == total` 这个不变量画出来（模型里已有 `isConsistent`，`Earnings.swift:73`）；
- 平台占比条 6 → 12pt（`:253-263`），名称 12 → 15pt，金额 12 → 17pt；
- "本月新增"从页内 12pt 小字升级成一张 tile（28pt），并配 `Theme.riseRed`（涨=红）；
- 40pt / 28pt 一律走 `Typography.metricL / metricM`，不再 inline。

### 4.5 更多页

```
┌────────────────────────────────────────────┐
│ 更多                                        │ 34pt
│ 只有问卷要密码，监控与设置都不用登录         │ 13pt
│ ┌───────────────┐ ┌───────────────┐         │ 12
│ │ 问卷           │ │ 推送监控       │         │ CardTier.tile 96
│ │ 已连接         │ │ 07:30 已推送   │         │ 20pt + 13pt
│ └───────────────┘ └───────────────┘         │
├────────────────────────────────────────────┤ 32
│ 工具                                        │ 22pt
│ ╭ 问卷工作台                      已连接 › ╮ │ 行 48
│ ╭ 推送监控                    今日 07:30 › ╮ │ 行 48
├────────────────────────────────────────────┤ 32
│ 其他                                        │ 22pt
│ ╭ 设置                                   › ╮ │ 行 48
│ ╭ 关于                                3.2.0 › ╮ │ 行 48
│ （页脚说明保留）                             │
└────────────────────────────────────────────┘
```

关键动作：4 个等高行拆成 **2 组 + 每行升格进组**，顶部补两张 tile 把"连接状态"从行内 13pt 提成 20pt；行距维持 8（`MoreView.swift:38`），组间 32。

---

## 5. 设计 token 增量（只有这 6 项，其余全部复用）

| # | 增量 | 值 | 为什么不能复用现有 token |
|---|---|---|---|
| 1 | `Spacing.sectionGapLoose` | `32` | 现有 `sectionGap` 24 与 `cardGap` 12 只差 12pt（2.0×），HIG 的"用留白分组"读不出来；32 : 12 = 2.67× 才形成肉眼可辨的两级 |
| 2 | `Typography.metricL` | `40, .bold, design: .rounded` | 现在 40pt 是 inline 硬写在 `EarningsView.swift:135`，36pt 硬写在 `RedstoneCountdownCard.swift:130`；同一语义两个值且无 token，无法统一"锚点数字" |
| 3 | `Typography.metricM` | `28, .bold, design: .rounded` | tile（96pt 高）里的数字需要比 `titleL` 22 大、比 `metricL` 40 小的第三档，现有字阶在 22 与 34 之间是空的 |
| 4 | `Typography.eyebrow` + `Typography.trackingEyebrow` | `11, .semibold` + `0.5` | `captionXS` 是 11 medium、无字距，用于"时间戳"；眉题要"更小更宽"才不会和元信息混为一谈（R7）。中文不做大写变形，只加字距 |
| 5 | `Theme.riseRed` / `Theme.fallGreen` | rise `#FF6B5A / #C43B22`，fall `#6BDB5C / #1F6B22`（深/浅） | 中国习惯涨红跌绿。不能借用 `statusError`（红色=报错）或 `statusNew`（绿=有更新）—— 语义错位会让 "+12%" 看起来像错误。**像素值与现有 token 刻意相同，因此不引入任何视觉漂移**，只是给出正确语义名 |
| 6 | `enum CardTier` + `enum Layout`（新文件 `Sources/DesignSystem/Layout.swift`） | `CardTier.hero 240 / .medium 168 / .tile 96 / .rail CGSize(140, 188)`；`Layout.trackHeight 4`、`Layout.compositionBar 10`、`Layout.railGap 12`、`Layout.railPeek 20` | 高度/轨道高不是"间距"，塞进 `Spacing` 会污染 8pt 网格语义；但散在每个 View 里就等于"每个工程师自己拍一个高度"—— 现状 196 / 223 / 150 三个无名数字（`SkyCard.swift:71`、`TrackCard.swift:28`+`33`、`SkyStatusCard` 自适应）就是这么来的 |

明确**不新增**的（评审时请勿再提）：

- 圆角：24 / 14 / 6 / 8 四档已够（`Radius.card / smallCard / badge / insideCard`）。
- 颜色：除涨跌两枚外，全部走现有 `Theme.*`；天空七档 `Theme.sky(_:)` 原样保留。
- 字体：不引入自定义字体（中文下字重不全，会破坏层级，见 `Typography.swift:5`）。
- 间距：8 / 12 / 16 / 20 / 24 / 32 / 120 已覆盖所有场景。

**新增组件文件清单（7 个）**

| 文件 | 类型 | 说明 |
|---|---|---|
| `Sources/DesignSystem/SectionHeader.swift` | 新 | 22pt 标题 + 可选右侧动作/插槽（红石翻月器塞进插槽） |
| `Sources/DesignSystem/Rail.swift` | 新 | 横向出血滚动容器：`.safeAreaPadding(.horizontal, Spacing.page)` + `LazyHStack(spacing: Layout.railGap)` + `.scrollTargetBehavior(.viewAligned)` |
| `Sources/DesignSystem/Eyebrow.swift` | 新 | 11pt + 字距 0.5 + 可选前置圆点（复用 `Theme.limeInk`） |
| `Sources/DesignSystem/Layout.swift` | 新 | `CardTier` / `Layout` 常量 |
| `Sources/Features/Overview/ArticleRailCard.swift` | 新 | 140×188：`CoverArt`(96 高) + 17pt 2 行 + 11pt 元信息 |
| `Sources/Features/Overview/VersionTileRow.swift` | 新 | 两张 96pt tile，内部复用 `SkyCardPhase` 四态判定（不复制业务逻辑） |
| `Sources/Features/Earnings/StatCompositionBar.swift` | 新 | 三态 10pt 堆叠条 + 图例，入参三个 `Int` 分（不碰单位换算） |

**改造（不新建文件）**：`SkyCard` 加 `minHeight` 与 `SkyCardBody.titleFont`；`RedstoneCountdownCard` 加 `tier` 参数与 `RedstoneProgressTrack` 子视图；`EarningsView.sectionTitle` 删除。

---

## 6. 优先级

### P0（这一轮就做，做完立刻不空）

| # | 事项 | 具体到文件 / 组件 / 数值 |
|---|---|---|
| P0-1 | **落地 6 项 token 增量** | `Spacing.swift` +1 行；`Typography.swift` +3 个静态量；`Theme.swift` +2 组 `dyn`；新建 `DesignSystem/Layout.swift` |
| P0-2 | **新增 `SectionHeader` 并接入 5 页** | 新建 `DesignSystem/SectionHeader.swift`（22pt/`titleL` + 12 下距 + 17pt `limeInk` 动作）；替换 `EarningsView.swift:478-487` 那个 12pt `sectionTitle`；首页加「今日一览 / 继续读 / 快捷」；红石加「本月 / 今日场次 / 本月分布」；简报加「今日详情 / 两服版本 / 版本记录」；更多加「工具 / 其他」 |
| P0-3 | **组距改 32** | 5 个页面最外层 `VStack` 的 `spacing` 从 `Spacing.sectionGap`（或 `cardGap`）改为 `Spacing.sectionGapLoose`；页面内部"同一组"的块仍用 `cardGap` 12 |
| P0-4 | **首页红石卡升 Hero** | `RedstoneCountdownCard.swift`：加 `tier`（240）；`bigValue` 用 `Typography.metricL` 取代 `:130` 的 inline 36；新增 `RedstoneProgressTrack`（4pt，`Theme.trackArc` 轨 + `Theme.lime` 节点）；底部加"三场并列"行（13pt，数据取 `RedstoneTimeline.occurrences`） |
| P0-5 | **首页简报卡压到 168** | `SkyCard.swift` `minHeight` 变参数（`CardTier.medium`）；`SkyCardBody` 加 `titleFont`，首页传 `Typography.titleM` 20pt；正文仍 `lineLimit(1)` |
| P0-6 | **首页新增「继续读」rail** | 新建 `DesignSystem/Rail.swift` + `Features/Overview/ArticleRailCard.swift`；数据读 `model.articles.prefix(8)`（`AppModel+Derived.swift:15`），封面用现有 `CoverArt(seed:title:)` |
| P0-7 | **首页版本卡拆两张 tile** | 新建 `Features/Overview/VersionTileRow.swift`（96pt，两张并排，间距 12），内部复用 `SkyCardPhase.resolve`；原 `SkyStatusCard` 保留给简报页 |
| P0-8 | **收益页去掉"小字表"** | hero 数字改 `metricL`；三态改 `StatCompositionBar`（新建，条高 10）；`breakdownCard` 条 6→12、名称 12→15、金额 12→17；平台明细/活动流水的名称 12→15、金额 12→17；新增 3 张 tile（本月新增 28pt，涨用 `Theme.riseRed`） |
| P0-9 | **更多页分组 + 两张 tile** | `MoreView.swift:38` 拆成两个 `VStack(spacing: 8)`，中间 32；顶部加两张 `CardTier.tile`；行高 48 不变 |

P0 完成后应能一眼看到：首页 = 大卡 + 中卡 + 两组分区标题 + 一条横滑 + 两张小卡。

### P1（下一轮）

- 简报页 hero：`SkyCard` 用于简报页顶部（260pt），`TodayBriefCard` 降级为"今日详情"模块（删标题头）。
- 红石页：`monthSwitcher` 并入 `SectionHeader` 右侧插槽；新增「今日场次」rail（128×112）。
- 收益页：三态/平台若后端某天提供时间序列，再上 `Swift Charts`（现在**没有**时间序列字段，禁止编造趋势图）。
- 文章页：`sectionLabel`（`ArticlesView.swift:104-109`）11pt → `SectionHeader` 22pt。
- 骨架屏（`SkeletonBlock`，`OverviewView.swift:101-102`）与新高度档对齐，避免加载完成时跳高。

### P2（可选）

- 首页日期行滚动时收成 sticky 小标题（Today 的日期标记感）。
- 卡片轻微视差 / 按压缩放已有 `PressableStyle`，可加 0.98 的 scale。
- iPad 双列（Today 在 iPad 是两列高低错落）。
- Dynamic Type 全量审计（本项目刻意用固定 pt，需单独评估 AX 尺寸）。

---

## 7. 验收标准（"不空"的可检验判据）

以 iPhone 15 Pro（393×852，可视高 ≈ 703pt，已扣状态栏 59 与底栏 90）为基准，逐条可量：

| # | 判据 | 检验方法 |
|---|---|---|
| A1 | 首页首屏 ≥ **4 个信息块**，其中恰好 **1 个是锚点**（≥ 240pt，或含 ≥ 40pt 数字） | 截图量高度：hero 240 / medium 168 / tile 96×2 |
| A2 | 首屏出现 **≥ 1 个 22pt 分区标题** | 检查字阶表：`titleL` 在首屏命中 ≥ 1 |
| A3 | 纵向**不出现 > 120pt 的连续空白**（除 hero 上方 24pt 组距） | 用 Accessibility Inspector 量相邻元素间距；组间 = 32±0 |
| A4 | 每页 **≥ 1 处横向滚动**，且首屏露出第 3 张卡 **≥ 35%**（≥ 49pt） | rail 卡宽 140、间距 12：353 − 304 = 49 |
| A5 | 每页 **≥ 2 个 22pt 分区标题**；全页字阶同时存在 34 / 22 / 17 / 13 / 11 五级 | grep + 视觉走查 |
| A6 | **每张卡内最大字号 ≥ 20pt**，或含 ≥ 80pt 高的图像/渐变区 | 收益页 `platformCard` 是重点复查对象 |
| A7 | 同一页内**不同卡片高度档 ≥ 2 种**（禁止全页 196/223 两种无名高度） | 对照 `CardTier` 枚举 |
| A8 | `bash scripts/lint-theme.sh` 全绿：无 `Color(hex:)`、无 `colorScheme ==`、无 `Color.white.opacity`、`lime` 不当文字色 | CI 闸门（`scripts/lint-theme.sh:56-69`） |
| A9 | 金额一律 `¥` 前缀（`EarningsMoney.formatCents`，`Earnings.swift:410-438`）；上涨用 `Theme.riseRed`、下跌用 `Theme.fallGreen`，不得反用 | 代码 review |
| A10 | 新增颜色/字号/圆角 **0 处** 出现在 View 层字面量；§5 六项之外无新 token | `git diff` + 本报告 §5 对照 |

**回归红线**：改版不得改动数据层（`Services/**`）、不得改 `FloatingTabBar` 的 74pt 几何、不得删 `TrackCard` 的「文字永远在弧线之上」约束（`TrackCard.swift:9-15`）、不得让首页在 feed 失败时失去红石卡（`OverviewView.swift:72-81`）。
