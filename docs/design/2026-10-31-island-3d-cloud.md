# 增量需求实现方案：天光灵动岛 / 简报雨滴 / iPad 立体卡 / 云控更新

> 版本基线：3.7.0 (build 13)　目标：3.8.0 (build 14)
> 工程：`/workspace/ios-app`（172 个 .swift，xcodegen 双 target，Codemagic 免签名）
> 网站：`/workspace/appsite`（Cloudflare Pages Functions + KV `EARNINGS_KV`，`app.skyzyf335.top`）
> 本文只出方案，不改任何源码。

---

## 0. 结论速览

| 需求 | 结论 | 新增文件 | 改动文件 | 触碰热点 |
|---|---|---|---|---|
| A 天光实时活动 | 新增第二个实时活动，与红石**互斥**（红石优先），白天开、8 小时到点自灭、回前台续 | 4 | 5 | `SettingsView.swift`、`SkyWidgetBundle.swift`、`FFWangApp.swift` |
| B 简报雨滴 | 降水带拆成"天空段 + 地面段"两段，20 条按高度比例分配（10/10 或 8/12） | 0 | 1 | `BriefFace.swift` |
| C iPad 立体卡 | 视差倾斜 + 三层视差 + 随动高光；**不挂 modifier** 保证 iPhone 零回归 | 1 | 3 | 无 |
| D 云控更新 | 网站 3 个接口 + 1 个管理页；App 侧 `UpdateStore` + sheet；**只用 URL Scheme 唤起全能签** | 6 | 2 | `MonitorView.swift` |

**`Sources/Shared/Theme/Theme.swift` 一行都不用改。** 天光用的天色（`Theme.sky(_:)`）、立体卡用的玻璃 token（`glassSheen` / `glassShadowNear` / `glassHighlight` / `glassHighlightFade`）全都已经存在，且 `Theme.sky` 本来就是"物理天色、不随外观变"，正好是灵动岛要的性质（灵动岛永远是黑底，不能用随浅色模式变深的 `textPrimary`）。

**两条对原设想的修正（理由见各节）**：
1. 太阳点**不烘焙进 state**，改为视图渲染时按 `Date()` 现算 + App 每 10 分钟一次心跳。纯烘焙要每分钟 update 才不显得跳，那是滥用 update 配额（8 小时 = 480 次）。
2. 唤起全能签**不用 `canOpenURL`**，用 `UIApplication.open(_:options:completionHandler:)`。`canOpenURL` 对未在 `LSApplicationQueriesSchemes` 里声明的 scheme 恒返回 `false`，用它会逼我们改 `Resources/Info.plist`；而 `open` 的 completion 就能拿到"有没有 App 接"的真实结果，零 plist 改动。

---

## 1. 天光实时活动（需求 A）

### 1.1 ActivityAttributes 字段设计

新文件 `Sources/Shared/Models/DaylightActivityAttributes.swift`（**App 与 Widget 各编译一次**，与 `SunEventActivityAttributes.swift` 同一套路，含 `DaylightSettings` 偏好键）。

```swift
struct DaylightActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// 日出（当天，北京时间）。端点必须稳定：ProgressView(timerInterval:) 的区间从这里来
        var sunrise: Date
        /// 日落（当天）。同时是"这次活动最晚该结束的时刻"的上界
        var sunset: Date
        /// 本次活动窗口的上界 = min(sunset, 创建时刻 + 8h)。staleDate 用它
        var windowEnd: Date
        /// WMO 4677 天气代码原语。nil = 没拿到天气（不渲染任何天气元素）
        var weatherCode: Int?
        /// 服务端给的中文描述（"小雨"）。有就上屏，没有就不渲染这一格
        var weatherText: String?
        /// 气温（℃）。nil = 不渲染
        var tempC: Double?
    }

    /// 当天日期文案（"10月31日 周六"）。创建后不变
    var dayText: String
}

enum DaylightSettings {
    /// 设置里「天光实时活动」的开关键。**默认关闭**（新增的常驻型活动，不替用户做主）
    static let storageKey = "skyLightLiveActivity"
}
```

字段逐条理由：

| 字段 | 为什么必须在 state 里 | 谁算 |
|---|---|---|
| `sunrise` / `sunset` | `ProgressView(timerInterval:)` 与 `Text(timerInterval:)` 要一个**稳定的**区间；每次重绘重算虽然值相同，但区间对象变了会让系统进度条重置到起点（视觉上是"进度突然回零又追上"） | App 侧 `SunClock.times(on:)` |
| `windowEnd` | 8 小时上限必须在**创建时**就定死，不能每次重绘按 `now+8h` 算（那永远不会到点，成了常驻） | App 侧 `min(sunset, now + 8h)` |
| `weatherCode` | **Widget/实时活动进程拿不到 `WeatherStore`**（`Sources/Services` 不进 Widget target），天气只能由 App 写进来 | App 侧 `WeatherStore.current?.code` |
| `weatherText` / `tempC` | 同上，纯展示 | App 侧 `WeatherNow.text` / `.temp` |
| `dayText`（attributes） | 创建后不变的东西放 attributes，不参与 update 的 diff | App 侧 |

**为什么 `weatherCode: Int?` 而不是 `WeatherKind`**（这是本条需求的硬要求，说清两点）：
1. `WeatherKind` 虽然也在 `Sources/Shared`（Widget 能编译到），但它是 **`String` 原始值的 `enum`**：`JSONDecoder` 解到枚举里会走 `RawRepresentable` 合成实现，**遇到未知 case 直接抛错**。而 `ContentState` 解码失败 = 这次 `update` 整个失败 = 卡片停在旧内容上不动，且没有任何报错（ActivityKit 不抛给调用方）。将来服务端多给一个 WMO 代码、或者 App 与 Widget 的安装版本错位一天，就会出现"卡片冻住"。
2. `Int` 是原语，任何版本都能解；`WeatherKind.from(code:)` 本来就把未知码返回 `nil`（那个函数的设计意图就是"认不出就不画天气"）。所以中转用 `Int?`，视图里再翻译 —— 数据层用原语，画法层用枚举，这条分界在这个工程里已经用过一次（`Monitor.swift` 的原始字符串时间戳）。

**不放 `sunX` / `sunY` / `phase`**，理由见 §1.4。

### 1.2 与红石实时活动的让位规则

**规则（确定性，无歧义）**：

```
红石占用中  =  Activity<SunEventActivityAttributes>.activities 里存在
              activityState == .active 或 .stale 的那一个
天光可运行  =  开关开 ∧ areActivitiesEnabled ∧ 红石不占用 ∧ now < sunset
              ∧ (sunset − now) ≥ 10 分钟 ∧ 自己的活动列表为空
```

- **红石优先**。红石是"20 分钟后有个限时场次"，天光是"现在天色如何"——后者等得起，前者等不起。
- 红石一开始跑，天光**立刻收**（`end(content, dismissalPolicy: .immediate)`），不留 60 秒的重叠窗口（灵动岛同时塞两个活动会被系统折叠成一组，用户点开看到的是一团乱）。
- 红石结束（列表回到空）后，天光在**下一个前台 tick（≤60 秒）**重开，`sunrise/sunset` 按当前时刻重算 —— 视觉上就是"接上了"。

**为什么用 `activityState` 过滤而不是"列表非空"**：`end(_:dismissalPolicy:)` 传 `.after(date)` 时活动**仍然留在 `Activity.activities` 里**，直到系统真的把它从锁屏撤下。红石 coordinator 退后台时正是这么干的（`scheduleDismissalForRunningActivities`）。只判 `isEmpty` 会让天光的恢复被一个"已经 ended 但还没被撤下"的活动**永久阻塞**。`ActivityState` 的四个 case（`.active` / `.stale` / `.ended` / `.dismissed`）是公开 API，`.stale` 算占用（它还在屏幕上显示）。

**实现位置**（两处，各 3 行）：

1. `Sources/Services/DaylightActivityCoordinator.swift` 的 `evaluate(now:)` —— 天光自己的守卫，**唯一**的启动入口。它自己去查 `Activity<SunEventActivityAttributes>.activities`，**不通过任何共享状态与红石协调器通信**。理由：跨类型查活动是 ActivityKit 的公开能力，一个静态查询就够；引入"共享的 busy 标志"就有了两份真相（标志会不会在 App 被杀后残留？）。
2. `Sources/Services/LiveActivityCoordinator.swift` 的 `start(_:)` 成功后加一句：
   ```swift
   Task { @MainActor in DaylightActivityCoordinator.shared.suspendForRock() }
   ```
   让收尾是**立即**的，而不是等下一个 tick。

`DaylightActivityCoordinator.suspendForRock()` 做的事：把当前所有天光活动 `end(.immediate)` + `WidgetCenter.shared.reloadAllTimelines()`。

### 1.3 生命周期（诚实版：它不能常驻）

| 事件 | 动作 | 用户看到什么 |
|---|---|---|
| 启动条件成立 | `Activity.request(attributes:content:pushType: nil)`，`staleDate = windowEnd` | 锁屏多一张天际线卡，灵动岛挂上太阳 |
| 前台每 60 秒 tick | 只在满足下面任一条件时 `update`：① `now − lastUpdateAt ≥ 600s` ② 天气值变了 ③ `now ≥ windowEnd − 300s`（准备收尾） | 太阳每 10 分钟挪一小步（中号锁屏卡上约 3pt），天色档位跟着跳变 |
| 到 `windowEnd`（= min(日落, 创建+8h)） | `end(content, dismissalPolicy: .immediate)` | 卡片直接消失，不留"已结束"残影 |
| 用户退到后台 | 不动它。既不 end 也不 update（后台不允许 request/update） | 卡片继续显示**最后一次 update 的快照**；系统驱动部分（倒计时、进度条）照常走 |
| 再次回到前台且 `now < sunset` 且剩余 ≥10 分钟 | 重新 `request` 一个新活动（新的 8 小时预算） | 卡片"回来"了，太阳在正确的位置上 |
| 系统超时 | 活跃 8 小时后系统把它标记 stale，锁屏最多存在 12 小时，之后系统移除 | 见下方"必须承认的三件事" |

**8 小时从哪儿来**：北京 6 月的日出≈04:46、日落≈19:46，全天 15 小时，任何"日出到日落"的活动都必然超过系统允许的活跃 8 小时。所以 `windowEnd = min(sunset, createdAt + 8h)`，**不是** `sunset`。写死 8h 而不是"日落"，是为了让卡片消失的时刻是可预测的（创建时刻 + 8 小时），而不是"有时候 8 小时有时候 15 小时"。

**用户会看到的三种情况，必须写进 PRD/验收**（不假装能常驻）：
1. 早上 9 点打开 App → 卡片出现，18:00（9+8h 进整）它会消失，虽然太阳还没落。→ 这是**设计**，不是 bug。
2. 一整天不打开 App → 卡片停在最后一次 update 的内容上；倒计时/进度条（系统驱动）仍然正确走完当天；到 12 小时系统移除。**不会**变成"永远显示早晨的天色"。
3. 卡片消失后再打开 App → 立刻回来（`now < sunset` 且剩余 ≥10 分钟）。

**为什么要求"剩余 ≥10 分钟"**：日落前 8 分钟开一张卡片，用户关掉屏幕它就没了 —— 开了等于没开，还多耗一次 request。10 分钟是"至少能看到一次有效内容"的下界。

### 1.4 视觉：四区分工与"哪部分系统驱动"

**这一节有一处与你的预设不同，先说结论**：

> **不把太阳点烘焙进 state。** 视图在每次 `body` 求值时用 `SunClock.sunMark(at: Date(), on: Date())` 现算位置。

理由三条：
1. **现算比重绘更准**：系统在"锁屏点亮 / 灵动岛展开收起 / 外观切换 / 收到 update"时才重绘。每次重绘按 `Date()` 现算，得到的就是那一刻的真实位置 —— 这比"上一次 App 写进来的位置"永远更接近真值。
2. **纯烘焙的刷新频率是不可接受**：日出到日落 x 行程 0.80，全天 840 分钟。要在 344pt 宽的卡上做到"看不出在跳"（Δt ≤ 2pt），需要 `0.80 × Δt/840 × 344 ≤ 2` → Δt ≤ 6.1 分钟，也就是**每 6 分钟一次 update**，8 小时 80 次。ActivityKit 的 update 是带唤醒成本的推送帧，为一个装饰性圆点这么干是错的。
3. **App 被杀后烘焙值会永久冻结**：用户早上 8 点打开过一次 App，之后锁屏上的卡片会一直把太阳画在"8 点"的位置直到活动结束。现算至少能在任意一次重绘时自愈。

**烘焙的只有四样**：`sunrise` / `sunset` / `windowEnd` / 天气三件套。它们要么必须稳定（时间区间），要么本进程拿不到（网络）。

**分工表**：

| 元素 | 驱动方式 | 细节 |
|---|---|---|
| 长条进度（`ProgressView(timerInterval:sunset)`） | **系统** | 系统自己推进，不触发 SwiftUI 重绘、零 update 成本 |
| 紧凑区倒计时 `3:12` | **系统**（`Text(timerInterval: now...sunset, countsDown: true)`） | 构造前必须判 `sunset > now`：`now...sunset` 在 `sunset < now` 时是非法闭区间，`Text(timerInterval:)` 拿到会崩。`sunset <= now` 时改画静态 `Text("已日落")` |
| 太阳点位置、天色档位（背景渐变）、天气符号 | **现算 / 烘焙** | 位置与档位按 `Date()` 现算；天气符号由 `weatherCode` 翻译 |
| 更新心跳 | **App** | 10 分钟一次（`update`），仅前台 |

具体四区（字号与符号都给死）：

| 区域 | 内容 | 规格 |
|---|---|---|
| `compactLeading` | `Image(systemName: "sun.horizon.fill")` | `.system(size: 12, weight: .semibold)`，色 `Theme.sky(phase).edge`（固定亮色，不随外观；**不要**用 `Theme.textPrimary`，浅色模式下它是 `#0F1A26`，压在灵动岛黑底上等于没有） |
| `compactTrailing` | `Text(timerInterval: now...sunset, countsDown: true)` | `.system(size: 12, weight: .semibold, design: .monospaced)` + `.monospacedDigit()`，色 `Theme.sky(phase).ink`（`#F5F8FF`） |
| `minimal` | `Image(systemName: "sun.max.fill")` | `.system(size: 12, weight: .semibold)`，色 `Theme.sky(phase).edge` |
| `expanded .leading` | 天气符号（13pt）+ `SkyPhase.label`（13pt semibold） | 符号映射见下；`label` 直接用现成的七档文案（"距离日落"/"日落剩余"/"黄金时刻"…）。`weatherCode == nil` 时只画 `label` |
| `expanded .trailing` | `Text("18°")` 15pt `monospacedDigit` + `Text("小雨")` 11pt `Theme.sky(phase).inkDim` | `tempC` / `weatherText` 各自 nil 就整格不画（不写"未知"） |
| `expanded .bottom` | ① 28pt 高的天际线（`HorizonGround` + `HorizonEdge` + 4pt 太阳点）② `ProgressView(timerInterval:)` 3pt ③ `SkyPhase.countdownText(to:sunset, now:)` 12pt | 见下 |

**锁屏卡（`DaylightLockScreenView`）**——沿用「天际线」语言，几何**全部复用现成类型**，一个新 Shape 都不写：

```
LinearGradient(stops: [sky.top @0, sky.horizon @0.62, sky.ground @0.62])
  └ HorizonGround(crestY: 0.62, edgeY: 0.74).fill(sky.ground)      ← Sources/Shared/UI/HorizonShape.swift
  └ HorizonEdge(crestY: 0.62, edgeY: 0.74).stroke(sky.edge, lineWidth: 1)
  └ Circle().fill(sky.edge).frame(4×4).position(sunMark.point × size) ← SunClock.sunMark 现算
  └ 左上：dayText（13pt semibold）+ 天气符号与文案（11pt）
  └ 右下：距日落倒计时（17pt bold monospaced）
  └ 底部：ProgressView(timerInterval:) 高 2
```

`0.62` 不是随手取的：它就是 `SunClock.SunTrack.crestY`，与桌面「天光」组件、App 内天际线卡共用同一个弧顶比例（`Theme.SkyColors` 的注释里写着这条不变量）。**常量引用 `SunClock.SunTrack.crestY`，不要写 `0.62` 字面量**。

`activityBackgroundTint(Theme.sky(phase).top)` —— 锁屏卡的底色跟着天色走，与红石活动那套 `TrackGradient` 是两套配方，互不复用（红石的配色是"事件状态"，天光的是"物理天色"）。

`activitySystemActionForegroundColor(Theme.sky(phase).ink)`。

天气符号映射（`DaylightSymbol.of(_ kind: WeatherKind?) -> String`）：

| kind | SF Symbol |
|---|---|
| `.clear` | `sun.max.fill` |
| `.partly` | `cloud.sun.fill` |
| `.overcast` | `cloud.fill` |
| `.fog` | `cloud.fog.fill` |
| `.drizzle` | `cloud.drizzle.fill` |
| `.rain` | `cloud.rain.fill` |
| `.snow` | `cloud.snow.fill` |
| `.thunder` | `cloud.bolt.rain.fill` |
| `nil` | 不画 |

### 1.5 设置开关

| 项 | 值 |
|---|---|
| 键名 | `skyLightLiveActivity`（`DaylightSettings.storageKey`） |
| 默认值 | **关闭**。`defaults.bool(forKey:)` 天然返回 false，不需要写 `object(forKey:) == nil` 分支；但要在注释里写明"默认关闭是刻意的" |
| 位置 | 新增 `group("天光")`，插在 `group("红石")` 之后、`group("问卷管理")` 之前。**不合并进「红石」组**：那个组的三段说明全是红石语义，改名/混排会让"红石实时活动"这句话出现在一个叫"实时活动"的组里，反而更绕 |
| 实现 | 新文件 `Sources/Features/Settings/DaylightActivitySection.swift`，结构与 `LiveActivitySection` **逐行对齐**（同 `Spacing.cardPadding` / 同 `Spacing.listItemMinHeight` / 同 `glassSurface(.card, in: RoundedRectangle(cornerRadius: Radius.smallCard, style: .continuous))`） |
| 行内副标题 | 可用："锁屏与灵动岛显示此刻的天光"；降级："此设备不支持锁屏实时活动" |
| 说明段（可用） | "白天会在锁屏与灵动岛显示此刻的太阳位置、天色与天气。日落或 8 小时后自动消失，回到 App 会重新出现。" |
| 说明段（降级） | "此设备没有锁屏实时活动，桌面添加「天光」小组件是一样的效果。"（指向**已存在**的 `SkyLightWidget`，落点真实） |
| 说明段（第二段，两种态共用） | "与红石实时活动同时只会显示红石那一个；红石结束后天光会自动回来。" |
| iPad 降级 | 沿用 `LiveActivitySection` 的做法：`@State private var activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled`（在声明处读，不在 `onAppear` 补），`Toggle.disabled(!activitiesEnabled)`，副标题换文案，`.lineLimit(2)`，**行高不变**（`minHeight: Spacing.listItemMinHeight`） |
| 关掉时 | `onChange(of: isEnabled)` → `DaylightActivityCoordinator.shared.endAll()`，不等下一次 tick（与红石同一纪律） |
| 显式 init | `init() {}` 必须写：`@AppStorage` 是 private 存储属性，不写会让 memberwise init 被降级成 private（`scripts/check-signatures.py` 会报） |

`SettingsView.swift` 的改动**只有一行**：在 `group("红石") { LiveActivitySection() }` 之后插入 `group("天光") { DaylightActivitySection() }`。

### 1.6 Widget target 编译边界

| 文件 | 归属 target | 说明 |
|---|---|---|
| `Sources/Shared/Models/DaylightActivityAttributes.swift` | 两个 target | 与 `SunEventActivityAttributes.swift` 同目录同风格。只 `import Foundation` + `#if canImport(ActivityKit) import ActivityKit #endif`（Shared 下不许裸 `import UIKit`，`check-signatures.py` 规则 6 会报） |
| `Sources/Widget/DaylightLiveActivity.swift` | Widget only | 整个 `Widget` + 三个子视图 + `DaylightSymbol` |
| `Sources/Services/DaylightActivityCoordinator.swift` | App only | 生命周期 |
| `Sources/Features/Settings/DaylightActivitySection.swift` | App only | 开关行 |
| `Sources/Widget/SkyWidgetBundle.swift` | Widget | `body` 里加一行 `DaylightLiveActivity()`（现在是 4 个 Widget，变 5 个；文件头注释里的"四个组件"要一起改成"五个"） |

**能直接用的 Shared 件**（都在 Widget target 的编译范围里）：
- `SunClock`（`times(on:)` / `phase(at:)` / `sunMark(at:on:)`）、`SunTrack`（`crestY 0.62` / `peakY 0.10` / `glowFadeMinutes 45`）
- `SkyPhase`（`label` / `deadline(at:)` / `countdownText(to:now:)`）
- `WeatherKind.from(code:)`
- `HorizonGround` / `HorizonEdge`（`Sources/Shared/UI/HorizonShape.swift`）
- `Theme.sky(_:) → SkyColors`

**要用的天空 token（就这 6 个，全在 `Theme.SkyColors` 里）**：
`sky.top`（卡顶/背景 tint）、`sky.horizon`（地平线天色）、`sky.ground`（地面）、`sky.edge`（太阳点 / 亮边 / 进度条 tint）、`sky.ink`（主文字）、`sky.inkDim`（次要文字）。
**不用**：`Theme.lime*`（那是品牌面，天光不是品牌色也能不参与换肤）、`Theme.Palette`（换肤只管界面情绪）、`TrackGradient`（红石私有配方）。

**主题闸门四条要注意**：不出现 `Color(hex:)`；不出现 `colorScheme == .dark/.light`（天空色是固定 hex，天然不需要判深浅 —— 这是复用 `Theme.sky` 的第二个好处）；不出现 `Color.white.opacity(...)`；不出现 `foregroundStyle(Theme.lime)`。

---

## 2. 简报雨滴位置（需求 B）

### 2.1 现在的几何，与它为什么让雨"太往下"

`Sources/Widget/BriefFace.swift` 现状：

```
bodyTop(medium/small)    = 12 + 14 + 6 + 24 + 4            = 60
bodyBottom(medium)       = 60 + 16×2 + 2                   = 94
bodyBottom(small)        = 60 + 16                         = 76
precipitationBand.top    = bodyBottom + 20      → 114 / 96
precipitationBand.bottom = height − 6           → 152
band.height              = 38 (中号) / 56 (小号)
```

中号卡 158 高，降水带只占 **y∈[114,152]，也就是卡高 72%–96% 那一窄条**；正文上方 0–60 一整片天空里一颗粒子都没有。用户说"雨滴太往下了"，说的就是这个：雨只从卡片最下面那条缝里落。

### 2.2 新几何：两段

把一条带拆成两条，**净空带规则一个字不改**：

```
天空段 (sky)     top    = verticalPadding(family) × 0.2      → 2.4      ← 复用 cloudBand 的上沿
                 bottom = bodyTop(family) − particleClearBand → 40
                 height = 37.6
地面段 (ground)  top    = bodyBottom(family) + particleClearBand → 114 / 96   ← 与今天完全一致
                 bottom = size.height − particleBottomInset     → 152           ← 与今天完全一致
                 height = 38 (中号) / 56 (小号)
```

`particleClearBand = 20`、`particleBottomInset = 6`、`verticalPadding`、`bodyTop`、`bodyBottom` **一个都不动**。天空段的上沿刻意取 `verticalPadding × 0.2` 而不是 0：与 `cloudBand` 的上沿取同一个式子，于是"云带"和"天空段的雨"是**同一个框**——将来云要挪，雨跟着挪，不会出现"云在 2.4 起步、雨在 0 起步"的两套边距。

新增常量（都放 `BriefMetrics`，只在 Widget 里）：

```swift
/// 雨丝倾斜后的包围盒相对"未倾斜半长"的最大外溢（pt）。12° / 长度 8…12 的实测上界 0.016，
/// 取 1 是为了留 60 倍余量 —— 净空带是硬约束，不能靠"算出来刚好不超"
static let particleTiltGuard: CGFloat = 1
/// 一段太矮就整段放弃（把粒子全给另一段）：低于 16pt 画不出雨丝，只能画一条线
static let minFilledBand: CGFloat = 16
```

### 2.3 条数分配（证明②：不会挤在一条线上）

```swift
/// 20 条雨丝按两段高度比例分配，两段各保底 1 条
static func split(count: Int, skyHeight: CGFloat, groundHeight: CGFloat) -> (sky: Int, ground: Int)
```

算法：
1. 任一段高度 < `minFilledBand`（16）→ 该段 0 条，另一段全收；
2. 否则 `raw = count × skyH / (skyH + groundH)`，`sky = clamp(round(raw), 1, count−1)`，`ground = count − sky`。

算出来的实数（这是本节最该被 review 的一张表）：

| 场景 | 天空段高 | 地面段高 | rain(20) | thunder(18) | drizzle(10) | 天空段条间距 | 地面段条间距 |
|---|---|---|---|---|---|---|---|
| 中号 338×158（iPhone） | 37.6 | 38 | **10 / 10** | 9 / 9 | 5 / 5 | 338/10 = **33.8pt** | 338/10 = **33.8pt** |
| 小号 158×158（iPhone） | 37.6 | 56 | **8 / 12** | 7 / 11 | 4 / 6 | 158/8 = **19.75pt** | 158/12 = **13.17pt** |
| 中号 364×170（iPad） | 37.6 | 50 | **9 / 11** | 8 / 10 | 4 / 6 | 364/9 = **40.4pt** | 364/11 = **33.1pt** |

**"不会挤在一条线上"的三重保证**：

1. **横向**：每段内每条的列位置 `column = (i + 0.5) / n`，最密的一格是**小号地面段 13.17pt**。12° 倾斜后一条雨丝的横向包围盒 = `1×cos12° + 12×sin12° ≈ 3.5pt`；抖动最大偏移 `0.22 × 0.5 × 13.17 ≈ 1.45pt`，相邻两条最坏中心距 `13.17 − 2×1.45 = 10.3pt`，净空 `10.3 − 3.5 = 6.8pt > 0` —— 两条雨丝在任何情况下都不重叠、更不会合成一条粗线。今天 20 条全塞在 38pt 高的带里也一样不重叠，所以"挤成一条线"的风险本来就不在横向；真正的病是**纵向**。
2. **纵向**：一条雨丝的 y 只落在 `[minY + L/2 + guard, maxY − L/2 − guard]`。中号天空段：`37.6 − 12 − 2 = 23.6pt` 的自由行程；小号地面段：`56 − 12 − 2 = 42pt`。行程远大于 0，所以同一段的雨丝在纵向上是散布在一条**带**里，而不是压在一个 y 上。
3. **段数**：一段只有 4 条（drizzle 小号）时，横向间距 158/4 = 39.5pt，也不需要担心。

### 2.4 净空带证明（证明①：一颗粒子都不许进）

正文块的矩形是 `y ∈ [bodyTop, bodyBottom] = [60, 94]`（中号）/ `[60, 76]`（小号）。

**天空段**：`maxY = bodyTop − 20 = 40`。任何一条的绘制包围盒上/下沿 = `y ± (L/2·cos12° + 0.5·sin12°)`，其中 `y ≤ maxY − L/2 − 1`，所以包围盒下沿 `≤ 40 − L/2 − 1 + L/2 × 0.978 + 0.104 = 40 − 0.011L − 0.896 ≤ 39.1 < 60`。**离正文上边界还有 20.9pt。**

**地面段**：`minY = bodyBottom + 20 = 114`。`y ≥ minY + L/2 + 1`，包围盒上沿 `≥ 114 + L/2 + 1 − (0.489L + 0.104) = 114 + 0.011L + 0.896 ≥ 114.98 ≫ 94`。**离正文下边界还有 20.98pt。**

那个 `0.011L − 0.104` 的来由：旋转 12° 后包围盒半高 `= (L/2)cos12° + (w/2)sin12° = 0.489L + 0.104`，与未旋转的 `L/2` 相比，在 `L = 8` 时多出 **0.016pt**、在 `L = 12` 时反而少 0.028pt。也就是说"倾斜"最多让雨丝越界 0.016pt —— `particleTiltGuard = 1` 把它盖住，且余量是它的 60 倍。**没有这一步，"净空带里一颗粒子都没有"就只是"算出来差不多"。**

### 2.5 证明③：雨丝不能穿过正文块

不需要额外论证"斜雨会不会从上方横穿下来"：`streaks` 把每条雨丝**整体**限制在一个 `CGRect` 里（`y` 由 `band.minY` / `band.maxY` 与 `slack` 算出，`x` 由 `band.minX + band.width × column` 算出），段与正文之间隔着 `particleClearBand` 的真空。天空段 `maxY = 40 < 60 = bodyTop`，地面段 `minY = 114 > 94 = bodyBottom`，**两个矩形在 y 上与正文块完全不相交**。倾斜只改变一条雨丝的包围盒（≤0.016pt），不改变它属于哪一段。

另外提醒一条**不是**本次改动、但改这个文件时必然看到的事实：天气层是 `content` 的 `.background`，所以粒子永远在**所有文字之下**。即使将来有人把净空带改小，字也不会被盖住 —— 但"斜线切碎字形"的视觉问题依然存在，那才是净空带存在的理由。

### 2.6 落点改动清单（只改 `Sources/Widget/BriefFace.swift`）

| 位置 | 改什么 |
|---|---|
| `BriefMetrics`（新增 2 个常量 + 1 个函数） | `particleTiltGuard` / `minFilledBand` / `split(count:skyHeight:groundHeight:)` |
| `precipitationBand(in:)` | 删掉，换成 `precipitationBands(in:) -> (sky: CGRect, ground: CGRect)`，注释重写（今天那段"为什么雨落满下半卡"的论证要改成"为什么是两段"） |
| `streaks(in:count:...)` | 入参从 `CGRect` 换成两段，内部按 `split` 分配条数，两段各跑一遍 `ForEach`；y 计算加 `particleTiltGuard` |
| `fogBand(in:band:)` | 用地面段（雾是"能见度"，贴着地面才有意义） |
| `snowDots(in:)` | 上 1/3 落天空段、其余落地面段（今天是"上 1/3 落 cloudBand"，两段几何相同，行为不变） |
| `lightning(in:band:)` | 用地面段（起点仍在正文下方，不划过字） |
| `particleBottomInset` 注释 | 保留原意，但要把"雨落满整卡下半部"改成"雨落满整卡（正文净空带除外）" |

**零回归边界**：`clear` / `partly` / `overcast` 三档不产生降水粒子，几何怎么改都不影响；`clouds` / `overcastVeil` / `BriefTrack` / `footer` / `BriefCanvas` 一行不动。

---

## 3. iPad 立体卡（需求 C）

### 3.1 三个候选与取舍

| 候选 | 成本 | 判断 |
|---|---|---|
| A 纯视差倾斜（只有 `rotation3DEffect`） | 30 行 | **否**。整块卡（连同卡里的字）以同一速度歪一下，大脑读作"页面在转"，不是"这张卡是实物"。没有深度分层就没有立体感，只是变形 |
| **B 视差倾斜 + 分层深度 + 随动高光** | 90 行 | **选它**。三层以不同幅度位移（卡面 4pt / 高光 −10pt / 阴影 10pt），产生"玻璃下面有东西在滑"的视差；高光随倾斜方向移动，模拟固定光源。零资源、零依赖、可被现有闸门静态检查 |
| C SceneKit 真 3D | 一个模型 + 一次构建 = 一轮 | **否**。四条实打实的成本见下 |

**为什么不是 SceneKit（四条，都是这个工程的具体事实，不是泛泛而谈）**：

1. **资源**：本工程 `Resources/` 下只有 `Info.plist` / `Widget-Info.plist` / `Assets.xcassets`（AppIcon + AccentColor），**一个 `.usdz` 都没有**。要做 4 张卡的 3D，就是 4 个模型文件、每个几 MB；现在的 ipa 只有 2.1MB，这一下把包体积翻几倍，而这些卡片的**信息量是 0 增长**的（倾斜不增加任何数据）。
2. **本机没有 Xcode**：`usdz` 的材质、光照、相机视角只能在 Simulator 或真机里看。一轮"改参数 → 看效果"= 推一次 → Codemagic 出包（8 分钟起）→ 全能签签名 → 装机。90 行的 `rotation3DEffect` 改参数只要改一个数字，而且**改错了不会崩**（最多难看）；SceneKit 的坐标系写反了是"模型飞到镜头后面"，一样要跑一轮才看得出来。
3. **CI 无法验证**：`.github` / `codemagic.yaml` 只做 `xcodebuild build`（`ENABLE_PREVIEWS = NO`，连 Preview 都不编）。SceneKit 视图渲不渲染、模型能不能加载、光照对不对，**编译期零信号**。我们唯一的质量闸门是 `lint-theme.sh` + `preflight.py` + `check-signatures.py`，这三个对 3D 内容一无所知。
4. **与现有玻璃冲突**：卡片走 `glassSurface(.card, in:)`，iOS 26 上是 `glassEffect`（**要采样背后内容**）。`SCNView` 塞进 SwiftUI 得包 `UIViewRepresentable`，它默认不透明背景，真玻璃采样到的是黑色 —— 等于为了 3D 放弃整个 3.7 的玻璃质感。而 `rotation3DEffect` 作用在玻璃**外层**，玻璃自己完全不知道自己在转。

**而且**用户的原话是"跟模型一样"，说的是**观感**（有厚度、会随视角变），不是"一个能转的模型"。B 达成同一个观感，成本是 C 的 1/50。

### 3.2 API 与参数表

新文件 `Sources/DesignSystem/CardTilt.swift`：

```swift
extension View {
    /// 只在宽档（iPad）挂载；iPhone 上返回原视图（**不加任何 modifier**）
    func cardTilt(cornerRadius: CGFloat = Radius.card) -> some View
}

private struct CardTiltModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutMetrics) private var metrics
    @State private var tilt: CGSize = .zero       // 每轴 −1…1
    @State private var isDragging = false
}

/// 参数集中在一处，全部 private（**不进 `Motion` / `Spacing`**，避免动热点文件）
private enum Tilt { … }
```

| 参数 | 常量名 | 值 | 依据 |
|---|---|---|---|
| 最大倾角 | `Tilt.maxAngle` | `5.5`（度） | 344pt 宽的卡在 6° 以上时，远端边缘的透视缩短开始把标题字形拉斜（观感从"卡在转"变成"字变形"）。5.5° 是"明显但不夸张"的上界 |
| 透视强度 | `Tilt.perspective` | `0.45` | 0.3 太平（几乎无纵深），0.6 以上近端角明显放大、玻璃描边会露出破绽。0.45 时近/远边的长度差约 8% |
| 手势行程 | `Tilt.travel` | `260`（pt） | 手指拖 260pt 才到角度上限。这就是"阻尼"：位移→角度是**软映射**（`angle = maxAngle × translation / travel`），不是 1:1 跟手。130pt 时约 2.75° |
| 跟手死区 | `DragGesture.minimumDistance` | `8`（pt） | 见 §3.5。8pt 是 iOS 判定"这是拖拽而不是点击"的经验阈值（`UIPanGestureRecognizer` 默认 10pt，`ScrollView` 用 8pt 左右） |
| 回弹动画 | `Tilt.settle` | `.spring(response: 0.42, dampingFraction: 0.72)` | `response 0.42` 与 `Motion.push` 同量级（一次呼吸），`damping 0.72` 比 `Motion.press`（0.7）略高 → 只过冲一丁点就停，不晃 |
| 卡面视差 | `Tilt.parallaxCard` | `4`（pt） | 整卡随倾斜平移 4pt（×tilt）。太大就是"卡片在飘"，不是"卡片有厚度" |
| 高光视差 | `Tilt.parallaxHighlight` | `−10`（pt，反向） | 高光反向移动 = 光源固定、玻璃在转。这是"分层深度"里唯一能明显读出深度的量 |
| 高光不透明度上限 | `Tilt.highlightAlpha` | `0.6` | 再乘 `Theme.glassSheen`（深 3.5% / 浅 30%）的自身 α。**静止时乘 0 → 完全不可见**，浅色卡不会糊 |
| 阴影偏移 | `Tilt.shadowShift` | `10`（pt） | 阴影朝"远离光源"的方向偏，最大 10pt |
| 阴影半径 | `Tilt.shadowRadius` | `22 + 8×|tilt|` | 抬起来时影更大更散 |

具体 modifier 链（顺序不能调）：

```swift
content
    // 1 高光层（不占布局、不吃触摸、静止时 α=0）
    .overlay { highlight(cornerRadius: cornerRadius) }
    // 2 两次 3D 旋转（叠加 = 复合旋转；绕着两个轴分别转比构造斜轴好读）
    .rotation3DEffect(.degrees(-tilt.height * Tilt.maxAngle),
                      axis: (x: 1, y: 0, z: 0),
                      anchor: .center, perspective: Tilt.perspective)
    .rotation3DEffect(.degrees( tilt.width  * Tilt.maxAngle),
                      axis: (x: 0, y: 1, z: 0),
                      anchor: .center, perspective: Tilt.perspective)
    // 3 卡面视差
    .offset(x: tilt.width * Tilt.parallaxCard, y: tilt.height * Tilt.parallaxCard)
    // 4 接触影（深色下 glassShadowNear 全透明 → 深色模式零变化）
    .shadow(color: Theme.glassShadowNear,
            radius: Tilt.shadowRadius(tilt),
            x: tilt.width * Tilt.shadowShift,
            y: tilt.height * Tilt.shadowShift + 8)
    // 5 手势
    .highPriorityGesture(drag)
    // 6 回弹动画（跟手时给 nil，松手才给 spring）
    .animation(isDragging ? nil : Tilt.settle, value: tilt)
    // 7 倾斜中的卡压住邻居
    .zIndex(tilt == .zero ? 0 : 1)
```

高光层实现（**不用 `Color.white.opacity`**，主题闸门规则 3）：

```swift
LinearGradient(colors: [Theme.glassSheen, Theme.glassHighlightFade],
               startPoint: UnitPoint(x: 0.5 - tilt.width * 0.6, y: 0.5 - tilt.height * 0.6),
               endPoint:   UnitPoint(x: 1.0 - tilt.width * 0.6, y: 1.0 - tilt.height * 0.6))
    .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .opacity(Tilt.highlightAlpha * magnitude)
    .allowsHitTesting(false)
```

`glassSheen`（深 3.5% / 浅 30%）而不是 `glassHighlight`（浅 95%）的原因：后者压在浅色卡上是一块白斑。`glassHighlightFade` 是"两端都是 token 的 0"（Theme 里那条注释就是为这件事写的）。

### 3.3 作用范围

**开在哪**（`metrics.usesWideCards == true`，即 `widthClass != .compact` —— 覆盖 iPad 全屏、1/2 分屏、Stage Manager 宽窗；不含 Slide Over 与 1/3 分屏，那些宽度下卡片本来就和 iPhone 一样窄）：

| 卡片 | 文件 | 圆角实参 | 为什么选它 |
|---|---|---|---|
| 红石倒计时 hero 卡 | `Sources/Features/Overview/RedstoneCountdownCard.swift` | `Radius.card` | 一屏唯一锚点，344pt 宽、卡里只有数字和一条轨道 —— 倾斜时没有任何文字被拉斜到读不清 |
| 今日简报卡 | `Sources/Features/Overview/TodayBriefTrackCard.swift` | `Radius.card` | 有地平线弧，倾斜时弧的透视变化最像"一块有厚度的玻璃" |
| 收益平台卡 | `Sources/Features/Earnings/PlatformCard.swift` | `Radius.smallCard` | 2×2 网格里 4 张，一次只歪一张（拖谁歪谁），静止全平 —— 不会变成"一堆歪纸" |

**不开在列表卡上**（`ArticleRowCard` / `SurveyRowCard` / 各种 rail 卡）：iPad 三列网格一屏可能有 20 张，20 个 `DragGesture` + 20 个 `@State` 是实打实的开销，而列表里的卡本来就该"安静"。

**iPhone 上怎么办：不挂 modifier，而不是"角度恒 0"。** 理由（这是本节最该被记住的一条）：

> 挂上去即使角度永远是 0，`@State tilt` + `DragGesture` + `@State isDragging` 依然存在。`DragGesture` 会与 `ScrollView` 的滚动竞争：在卡片上竖直拖 30pt，如果卡片的手势赢了，**页面就滚不动**。这是这个 App 里最严重的一类回归（用户会以为卡死了），而它在模拟器/肉眼 review 里都极难发现（要恰好在卡上竖直拖）。
> 不挂 = 这个手势在这个平台上**根本不存在**，回归在物理上不可能发生。

条件写在 `body` 里（不是在调用点）：

```swift
func body(content: Content) -> some View {
    if metrics.usesWideCards && !reduceMotion {
        decorated(content)
    } else {
        content          // 逐像素与 3.7.0 相同：连一个 modifier 都不多
    }
}
```

`accessibilityReduceMotion` 为真 → 走 `else` 分支（不挂）。**不是**"角度归零"：同样是因为手势。前庭功能敏感的用户拖一下卡片晃一下，比"卡片完全不动"糟得多。

### 3.4 与既有系统的相互影响

| 系统 | 影响 | 处理 |
|---|---|---|
| `ScrollLight`（滚动光影） | 光影在**背景层**（`PageBackground`），卡片在**页面层**，两者是 `RootView` 里 `ZStack` 的兄弟节点。倾斜不产生滚动事件，也不读 `ScrollLightStore` | 无影响。**不要**让倾斜去影响光斑：那是"页面在动"，倾斜是"卡在动"，混起来就是"地在晃" |
| `PageBackground` | 同上 | 无影响 |
| `RootView` 的 `.transaction { $0.animation = nil }` | 这个 modifier 挂在 `page(for: tab)` 上，会把它下发事务里的动画摘掉。`withAnimation` 一定被吃掉 | 回弹**不用** `withAnimation`，用 `.animation(isDragging ? nil : Tilt.settle, value: tilt)` 挂在**倾斜视图自己**这一层。跟手阶段（`isDragging == true`）本来就没有动画，每帧直接写 `@State` —— 这一段是确定的，不受任何祖先事务影响 |
| `Tab 切换 / 换主题` | 换主题会 `.id(appearance.themeId)` 重建整棵子树 → `@State tilt` 归零（正确） | 无需额外处理 |
| 玻璃（`glassEffect` / `HandGlass`） | 旋转在玻璃**外层**，玻璃仍采样它背后（页面背景） | 正常。**唯一注意**：不要让 `rotation3DEffect` 挂在 `.glassSurface` **里面**（某些实现会在内部 `drawingGroup`，那样玻璃会被离屏渲染，采样到透明） |
| `hoverEffect`（`GlassListRow` 用的） | 本次卡片没用 | 不涉及 |

### 3.5 手势冲突：拖拽会不会吃掉点击

卡片本身是 `PressableGlassCard`（`Button` + `PressableStyle`）。三种接法：

| 接法 | 结果 | 判断 |
|---|---|---|
| `.simultaneousGesture(DragGesture(minimumDistance: 8))` | 拖拽与 Button 同时识别 → 松手时 Button **仍然触发 action** → "拖一下就打开了详情" | **错** |
| `.gesture(DragGesture(minimumDistance: 0))` | 死区 0 → 任何触摸都被判成拖拽 → **点不开了** | **错** |
| **`.highPriorityGesture(DragGesture(minimumDistance: 8))`** | 位移 < 8pt：高优先级手势不识别，Button 正常触发；位移 ≥ 8pt：高优先级手势胜出，Button 的 tap 被取消 | **选它** |

实现细节：
- `DragGesture(minimumDistance: 8)` 的 `minimumDistance` 就是"何时判定为拖"：8pt 之内不认，超过就认。
- `onChanged` 里写 `isDragging = true` 并算 `tilt`；`onEnded` 里 `isDragging = false` + `withAnimation(nil)` 不需要 —— 靠 `.animation(value:)` 在那个 `isDragging` 翻转的那一帧开始 spring（因为此时 `isDragging == false`，动画参数为 `Tilt.settle`）。
- `onEnded` **绝不调用** action / 导航。回弹就是唯一的收尾动作。
- `coordinateSpace` 用默认 `.local`，位移量取 `value.translation`（不是 `value.location`）—— 用 `translation` 就不需要 `GeometryReader` 量卡宽，**一个 GeometryReader 都不引入**（`LayoutMetricsScope` 里那条"全工程只有一个 GeometryReader 参与尺寸判定"的纪律继续成立）。

**结论**：8pt 以下 = 点击（打开详情），8pt 以上 = 倾斜（松手不打开），两者互斥且判定阈值明确、不需要长按、不需要第二次交互。

**验收时必做的一条**：在 iPad 上，① 轻点卡片 → 打开详情；② 在卡片上按住斜拖 50pt → 卡片歪、松手回弹、**不**打开详情；③ 在 iPhone 上，在卡片上竖直快拖 → 页面正常滚动（因为根本没挂手势）。

---

## 4. 云控更新系统（需求 D）

### 4.1 前提与边界（先把"不能做什么"钉死）

**全能签没有 HTTP 签名接口。** 官方只给了三个 URL Scheme：`nsk-sign://addsource?url=`、`nsk-sign://web?url=`、`nsk-sign://bookmark?url=`。其中 `nsk-sign://web?url=<.ipa 直链>` 是**唯一**能触发"下载 + 进签名流程"的入口。所以整个 D 的正确形态是：

```
我们托管 ipa  →  App/网页用 nsk-sign://web?url=<我们域名的 ipa 直链> 唤起全能签  →  全能签用用户自己的证书签
```

- **不做** `itms-services://` 企业分发：我们没有企业证书，`itms-services` 链接在没有有效企业签名的 plist/ipa 上点了只会弹"无法安装"。
- **不做**"提交任务拿签名链接"：API 不存在。
- **ipa 直链必须公网匿名可读**：全能签是另一个 App，它去下载时不会带我们的任何凭证。未签名 ipa 被任何人下走也没价值（装了也起不来，要自己的证书签）。

### 4.2 HTTP 契约

全部挂在 `app.skyzyf335.top`（App 侧 `Endpoint.briefBase`）。响应统一 `{ok, ...}` / `{ok:false, error:{code,message}}`，与 `functions/api/app/brief.js` 的信封一致。

| # | 方法 · 路径 | 鉴权 | 请求 | 成功响应 | 失败 |
|---|---|---|---|---|---|
| 1 | `GET /api/app/version` | 匿名 | 无 | `200 {"ok":true,"apiVersion":1,"serverTime":"…","latest":{"build":14,"version":"3.8.0","notes":"…","size":2104321,"sha256":"…","publishedAt":"…","ipaPath":"/api/app/download/3.8.0-14.ipa"}}`；未发布过任何版本时 `latest:null` | `500 kv_unavailable` |
| 2 | `POST /api/app/version` | `x-release-token` | `{"build":14,"version":"3.8.0","notes":"多行文本","ipaKey":"3.8.0-14.ipa"}` | `200 {"ok":true,"latest":{…}}` | `401 unauthorized` / `400 bad_request` / `400 build_regression` / `400 ipa_key_missing`（该 key 在 KV 里不存在）/ `503 release_token_missing` |
| 3 | `POST /api/app/version/upload` | `x-release-token` | `Content-Type: application/octet-stream`，头 `x-file-name: 3.8.0-14.ipa`，body = 原始 ipa 字节 | `200 {"ok":true,"key":"3.8.0-14.ipa","size":2104321,"sha256":"…"}` | `401` / `413 too_large`（> 20MB）/ `400 missing_file_name` |
| 4 | `GET /api/app/download/<file>` | 匿名 | 无 | `200`，`Content-Type: application/octet-stream`，`Content-Disposition: attachment; filename="<file>"`，`Content-Length` | `404 not_found` |
| 5 | `DELETE /api/app/version?build=13` | `x-release-token` | 无 body | `200 {"ok":true}` | `401` / `400 bad_request` / `404 not_found` |
| 6 | `GET /admin/release` | 站点登录（`ce_auth`）+ 页面内发布口令 | — | 静态 HTML | 站点锁屏页 401（`_middleware.js` 的行为，不改） |

**为什么 #3 用 raw body 而不是 multipart**：Pages Functions 运行在 Workers runtime 上，没有 `busboy` 这类 multipart 解析器，手写解析要处理 boundary、chunk、文件名转义 ≈ 80 行易错代码；而我们只传**一个文件**、文件名可以放头里。`const buf = await request.arrayBuffer()` 一行拿到全部字节，直接 `env.EARNINGS_KV.put(key, buf)`。这是"接口形态服从部署现实"的取舍。

**为什么 #1 允许 60s 缓存**：App 一天最多查 4 次（6 小时闸门），60s 的缓存只影响"刚发布完就有用户查"的那一分钟。`Cache-Control: public, max-age=60, s-maxage=60`。发布接口**不带**任何缓存（`no-store`）。

**为什么管理页是 #6 而不是接口**：见 §4.8 的"不做"清单——它是人操作的页面，不是自动化入口。

### 4.3 KV 键设计

| 键 | 内容 | 大小 | TTL |
|---|---|---|---|
| `release:ios:latest` | 最新版的元数据 JSON（就是 #1 的 `latest`） | ≤ 2KB | **不设**（长期保留） |
| `release:ios:history` | 数组，保留最近 **5** 版（build / version / publishedAt / ipaKey / size / sha256） | ≤ 8KB | 不设 |
| `release:ios:file:<key>` | ipa 二进制（`put(key, arrayBuffer)`） | 实测 **2.1MB**，上限 25MB | 不设 |

约束与取舍：
- **ipa 放 KV，不上 R2**：KV 单值上限 25MiB，我们的包 2.1MB；R2 需要先开通（多一个计费项、多一套绑定），而这里一个月最多 2 次写入、几十次读取。**只有包体超过 20MB 才需要迁 R2**，那时把 `release-store.js` 的 3 个函数换掉即可（接口形态不变）。
- **ipa 二进制保留最近 3 个 build**，发布新版本时自动删掉更老的（`DELETE` 也能手动删）。理由：一个 2MB 的文件留着没成本，但留 50 个就是 100MB 的 KV 垃圾；而"回退到上上版"是真实需求（新版崩了要能给用户一个能装的旧包）。
- **元数据不设 TTL**：KV 的 `expiration` 最小 60 秒，最长无上限，但设了就会在某个时刻**静默消失** —— 一个"某天突然所有用户都不提示更新"的故障，排查成本远高于省下的几 KB。
- **写后读一致性**：KV 是最终一致的（同 PoP 通常立刻可读，跨 PoP 最长 60s）。发布页要显示一句"已保存，边缘缓存与全球同步最长 60 秒"。

### 4.4 鉴权

| 项 | 设计 |
|---|---|
| 环境变量 | `RELEASE_TOKEN`（Cloudflare Pages → 设置 → 环境变量，**类型选 Secret**，Production + Preview 都加） |
| 请求头 | `x-release-token: <token>` |
| 比较 | **常量时间比较**：先对两个字符串做 `crypto.subtle.digest('SHA-256', …)`，再逐字节 XOR 累加比较（`timingSafeEqual(a,b)`，≈10 行）。直接 `===` 会在字节级泄露"前几位对了"，虽然现实威胁很低，但这一段代码成本是 10 行 |
| 失败 | **一律** `401 {"ok":false,"error":{"code":"unauthorized","message":"发布口令不正确。"}}`。**不区分**"头缺失"与"口令错"（区分等于给爆破者一个进度条） |
| 未配置 | **fail-closed**：`if (!env.RELEASE_TOKEN) return 503 {"code":"release_token_missing"}`。绝不能"没配就放行"——那就成了一个公开可写的文件托管 |
| 不复用 | **不用** `ACCESS_PASSWORD` / `ce_auth` / `creator_auth_config`。那一套是给终端用户（你自己在浏览器里）用的会话 Cookie；发布口令是**机器凭据**，混用会让"改一下站点访问密码"意外地打开写权限 |
| 与站点门禁的关系 | `functions/_middleware.js` 已经有一行 `if (url.pathname.startsWith('/api/app/')) return ctx.next();` —— 所以 `/api/app/version` 的 POST/DELETE **绕过了站点登录**。这不是漏洞，是设计（App 要匿名读）；但它把"写接口的唯一防线"完全压到了端点内部的 `RELEASE_TOKEN` 上，这就是上面那条 fail-closed 必须存在的原因。**`_middleware.js` 一个字都不用改** |

**部署时要在 Cloudflare 面板加什么（就一条）**：

```
Pages 项目 → 设置 → 环境变量 → 添加
  名称：RELEASE_TOKEN
  值：  一个 32 位以上的随机串（openssl rand -hex 24 生成）
  类型：Secret（加密）
  环境：Production + Preview 都勾
```

不需要：新 KV 命名空间（复用 `EARNINGS_KV`）、R2、新域名、新 DNS 记录、cron。

### 4.5 版本比较规则

- **主键 = `CFBundleVersion`（build 号，整数，单调递增）**。`MARKETING_VERSION`（"3.8.0"）**只做展示**。
- 比较函数语义（一句话）：
  ```swift
  enum UpdateCompare {
      /// 远端严格大于本地才算"有更新"。相等 = 已是最新（即使用户装的 MARKETING_VERSION 不同）
      static func isNewer(remote: Int, local: Int) -> Bool { remote > local }
  }
  ```
- **不用字符串比较**，两个理由：① `"3.10.0" < "3.9.0"`（字典序），3.9 之后的版本永远提示不了更新；② 本地拿到的可能是 `"3.7.0 (13)"` 这种拼串，完全不可比。
- 本地 build 读取：`Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0`。读不到按 0 处理 → `remote > 0` 恒真 → 弹更新。**这个方向是安全的**（宁可多提示一次，不可漏提示）。
- 服务端**拒收回退**：`build < 当前 latest.build` 返回 `400 build_regression`。所以远端 build 单调不减，App 侧只需 `>`。
- 允许 `build == 当前` 重发（改更新说明的错别字），此时 `latest` 被覆盖、`history` 里同 build 的那条被替换而不是追加。

### 4.6 App 侧

新文件 `Sources/Services/UpdateStore.swift` + `Sources/Services/UpdateInstaller.swift` + `Sources/Models/AppRelease.swift`。

```swift
struct AppRelease: Decodable, Equatable, Sendable {
    let build: Int
    let version: String
    let notes: String
    let size: Int?            // 字节
    let sha256: String?
    let publishedAt: Date?    // 用 APIJSON.decoder（带毫秒的 ISO 串）
    let ipaPath: String       // "/api/app/download/3.8.0-14.ipa"
}

struct AppVersionEnvelope: Decodable, Equatable, Sendable {
    let ok: Bool
    let latest: AppRelease?   // 未发布过 = nil
}
```

**状态机**：

```swift
@MainActor
final class UpdateStore: ObservableObject {
    static let shared = UpdateStore()

    enum Phase: Equatable {
        case idle                 // 还没查过
        case checking             // 请求在飞
        case upToDate             // remote <= local（或 latest == nil）
        case available            // remote > local
        case failed(APIError)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var release: AppRelease?
    @Published var showsSheet: Bool = false

    static let checkInterval: TimeInterval = 6 * 3600   // 前台闸门
    static let launchDelay: TimeInterval = 3            // 启动后延迟，避开首屏请求

    private let keyLastCheck     = "appUpdate.lastCheckAt"
    private let keyDismissedBuild = "appUpdate.dismissedBuild"

    var localBuild: Int { … }                            // 见 §4.5
    func checkIfDue() async                              // 距上次 ≥ 6h 才真查
    func check(force: Bool = false) async                // 真查（监控页按钮用 force）
    func install()                                       // → UpdateInstaller
    func snooze()                                        // 关掉 sheet + 记 dismissedBuild
}
```

转移表：

| 当前 | 事件 | 下一状态 | 副作用 |
|---|---|---|---|
| `idle` | `check` | `checking` | 发 `GET /api/app/version` |
| `checking` | `ok && latest == nil` | `upToDate` | 写 `lastCheckAt` |
| `checking` | `ok && latest.build > local` | `available` | 写 `lastCheckAt`；若 `build != dismissedBuild` → `showsSheet = true` |
| `checking` | `ok && latest.build <= local` | `upToDate` | 写 `lastCheckAt` |
| `checking` | 网络 / 解码 / 5xx | `failed(error)` | **不写** `lastCheckAt`（失败不该把 6 小时闸门重新计满）；**不清空** `release`（下次进来还能看到上次的说明） |
| `available` | `snooze()` | `available`（不变） | `showsSheet = false`；`dismissedBuild = build` → 同一 build 不再自动弹 |
| `available` | `check`（用户手动重查） | `checking` | — |

**检查时机**（三处，明确不做第四处）：

| 时机 | 位置 | 说明 |
|---|---|---|
| 启动后 3 秒 | `FFWangApp` 的 `.task`：`try? await Task.sleep(for: .seconds(3)); await UpdateStore.shared.checkIfDue()` | 延迟是为了不和首屏那批并发请求抢连接（概览首屏同时要拉简报 / 天气 / 红石排期） |
| 进监控页 | `MonitorView` 的 `.task` 里加 `await UpdateStore.shared.checkIfDue()` | 用户主动来看版本的地方，该给最新结果；6 小时闸门保证连点不刷接口 |
| 回前台 | `scenePhase == .active` → `checkIfDue()` | **6 小时闸门**：`now − lastCheckAt ≥ 6h` 才查 |

**不做的第四次**：不"每次前台都查"。用户切一次 App 就打一次接口，一天几十次；更糟的是它会让"有新版本"弹窗**反复出现**（每次前台都可能弹），而 `dismissedBuild` 只能压住自动弹、压不住"用户每切一次 App 就被打扰一次"这个体验问题。

**弹窗形态：`sheet`，不是 `alert`**。理由：更新说明是多行文本（真实更新说明 5–10 行，含换行），`alert` 的 message 区在 iOS 上会被截断到约 4 行且不可滚动 —— 用户看不到"改了什么"就点安装，那是我们在骗他点。`sheet` 里 `ScrollView` 想多长都行。

`UpdateSheet` 内容（新文件 `Sources/Features/Monitor/UpdateSheet.swift`）：

```
标题：发现新版本 3.8.0
副标题：build 14 · 2.0 MB · 2026-10-31      ← 用 Formatters 与 ByteCountFormatter
───
更新说明（ScrollView，Typography.footnote，保留换行）
───
[ 用全能签安装 ]   ← PrimaryCTAStyle()，唯一主按钮
[ 稍后 ]           ← 必须能关：SecondaryCTAStyle()，点它 → snooze()
（若 `open` 的 completion 回 `false`，展开一行灰字："没检测到全能签，点这里看安装步骤"）
```

**按钮行为**（`UpdateInstaller`）：

```swift
enum UpdateInstaller {
    static func installURL(ipaPath: String) -> URL? {
        var c = URLComponents()
        c.scheme = "nsk-sign"
        c.host   = "web"
        // IPA 直链：Endpoint.briefBase + ipaPath（URLComponents 会自动做百分号编码）
        c.queryItems = [URLQueryItem(name: "url", value: Endpoint.briefBase + ipaPath)]
        return c.url
    }

    @MainActor
    static func install(ipaPath: String, onFallback: @escaping () -> Void) {
        guard let url = installURL(ipaPath: ipaPath) else { onFallback(); return }
        UIApplication.shared.open(url, options: [:]) { ok in
            // completion 在 main queue 回调（Apple 文档），但仍显式切一次主线程，避免将来被挪走
            if !ok { DispatchQueue.main.async { onFallback() } }
        }
    }
}
```

- **为什么不用 `canOpenURL`**：`canOpenURL` 对未在 `Info.plist` 的 `LSApplicationQueriesSchemes` 里声明的 scheme **恒返回 `false`**（iOS 9 起）。用它就必须改 `Resources/Info.plist` 加一个键，而 `open(_:completionHandler:)` 的 `Bool` 参数本来就告诉我们"有没有 App 接住了这个 URL"，**不需要白名单**。零 plist 改动，语义还更准（`canOpenURL` 只是"能不能问"，`open` 的返回值才是"真的打开了"）。
- **回退**：`ok == false` → 打开站点的安装引导页 `Endpoint.briefBase + Endpoint.installGuidePath`（`/install/`，静态页，T6 一并出）。那页讲三件事：① 没有全能签怎么装；② 复制 ipa 直链；③ 全能签里"网页打开"粘贴直链。
- 提醒用户：**我们只负责把 ipa 递到全能签手里**。证书、重签、信任描述文件都是全能签那边的事，页面上要写清（否则"装了打不开"会被当成我们的 bug）。

### 4.7 与 `MonitorView` / `VersionStatusCard` 的关系

**结论：不新建卡，复用监控页的位置，新增一行入口。**

- `VersionStatusCard` **一个字段都不加**。它讲的是"光遇国服/国际服的版本"（`MonitorAppVersion`），跟"这个 App 自己有没有新版本"是两件事。混进同一张卡会出现"卡片右上角写着有新版本，其实是光遇的"这种致命歧义（这个工程里 `StatusPillKind.newVersion` 的绿胶囊已经承载了"光遇有新版本"的语义）。
- `MonitorView` 里，在 `cards` 之后、`windowNote` 之前插一个 `AppUpdateSection()`：
  ```
  ┌───────────────────────────────────────────────┐
  │  ⇩  这个 App            v3.8.0 可用  [检查更新] │
  │      当前 3.7.0 (13) · 5 分钟前检查过            │
  └───────────────────────────────────────────────┘
  ```
  一行玻璃行（`GlassListRow` 的视觉规格，但右侧是按钮不是 chevron），状态字读 `UpdateStore.phase`：
  | phase | 右侧 |
  |---|---|
  | `idle` | 灰字"尚未检查" |
  | `checking` | 小 `ProgressView` |
  | `upToDate` | 灰字"已是最新" |
  | `available` | 青柠胶囊"v3.8.0 可用" + 可点 → 打开 `UpdateSheet` |
  | `failed` | 红字"检查失败" + 按钮变"重试" |
- **绝不动「立即检查」那个按钮**：它打的是 `POST /api/app/monitor/check`，**会触发服务端巡检并向所有 Bark 订阅者群发版本通知**。把它复用成"检查 App 更新"，等于用户点一下"看看有没有新版"就给全站订阅者推一条通知。两个按钮在同一个页面上、都叫"检查"，必须在副文案上区分开：
  - 「立即检查」→ "服务端巡检，60 秒内只能一次"
  - 「检查更新」→ "检查这个 App 有没有新版本"

### 4.8 明确"不做"（这段话**要贴在管理页上**）

管理页 `admin/release/index.html` 顶部固定一条说明（不可折叠）：

> **v1 只支持手动上传。**
> 不会自动从 Codemagic 拉产物 —— 那需要 `CM_API_TOKEN`（团队级凭据，泄露等于别人能烧你的构建分钟），而且 Codemagic 的 Artifact 下载链接有有效期，写进 KV 几天后就是 404，"看起来有更新但点不动"比"没有更新"糟得多。
> 每次发版的完整流程见本页底部四步。

其余"不做"：
- 不做强制更新（不拦启动、不当启动门）。理由：自己的 App，用户点"稍后"就该能继续用。
- 不做静默下载 / 后台安装（iOS 上非 App Store 渠道根本做不到）。
- 不做 beta / 多渠道（`channel` 参数留在契约里但 v1 只认 `ios`，不实现灰度）。
- 不做"从 GitHub Release 拉 ipa"（同 Codemagic 的理由：链接会过期）。

---

## 5. 任务分解

排序即实现顺序。**并行度**：T1 → (T2 → T3)、T4、T5、T6 可同时开工；T7 等 T1 + T6。

> 通用闸门（每个任务提交前必须全绿，否则不要推 CI —— 一次编译 = 8 分钟配额）：
> `bash scripts/lint-theme.sh` → 0；`python3 scripts/preflight.py` → 0；`python3 scripts/check-signatures.py --quiet` → 0。
> 注意 `check-signatures.py` 规则 4：**新 View 只要有 private 存储属性（`@State` / `@AppStorage` / `@ObservedObject`），就必须显式写 `init() {}`**，否则跨文件构造会失败。

---

### T1 · 共享类型与端点

| 项 | 内容 |
|---|---|
| 文件 | 新增 `Sources/Shared/Models/DaylightActivityAttributes.swift`、`Sources/Models/AppRelease.swift`；改 `Sources/Shared/Config/Endpoint.swift`、`Sources/Shared/Config/API.swift` |
| 改什么 | ① attributes + `DaylightSettings.storageKey`（照 `SunEventActivityAttributes.swift` 的写法：只 import Foundation，ActivityKit 用 `#if canImport`）；② `AppRelease` / `AppVersionEnvelope`（`Decodable`，字段全可选除 `ok`/`build`）；③ `Endpoint` 加三个常量：`appVersionPath = "/api/app/version"`、`appVersionUploadPath = "/api/app/version/upload"`、`installGuidePath = "/install/"`；④ `API` 加三个方法：`appVersion()`、`appDownload(_ path: String)`、`installGuide()`（base 一律 `briefBase`） |
| 依赖 | 无 |
| 验收 | 三个闸门全绿；`preflight.py` 能识别 `Endpoint.appVersionPath` / `API.appVersion()`（它在 `NAMESPACES` 表里查这两个命名空间的成员，拼错会当场报）；Codemagic 编译通过 |
| iPhone 回归 | **0**。纯新增文件 + 两处只追加常量/方法。`Sources/Models/` 只进 App target，不影响 Widget 体积 |

---

### T2 · 天光 · Widget 侧视图

| 项 | 内容 |
|---|---|
| 文件 | 新增 `Sources/Widget/DaylightLiveActivity.swift`；改 `Sources/Widget/SkyWidgetBundle.swift`（+1 行，顺带把文件头"四个组件"改成"五个"） |
| 改什么 | `ActivityConfiguration(for: DaylightActivityAttributes.self)` + 四个区（§1.4 的规格）+ `DaylightLockScreenView`（`HorizonGround`/`HorizonEdge`/`sunMark`）+ `DaylightSymbol.of(_:)` + `DaylightCompactCountdown`（`Text(timerInterval:)` 前必须判 `sunset > now`） |
| 依赖 | **T1**（attributes 类型） |
| 验收 | 编译通过；装机后（配合 T3 的开关）在锁屏与灵动岛看到四种形态；**用一个临时的假 state 走一遍**：把 `sunset` 设成 `now + 60s`，确认 60 秒后倒计时归零不崩（这是唯一会在真机上崩的点） |
| iPhone 回归 | **0**。新 Widget 只在有活动时出现；`SkyWidgetBundle` 加一个 Widget 不改变已有四个的 Timeline 与外观 |

---

### T3 · 天光 · App 侧协调器 + 设置开关

| 项 | 内容 |
|---|---|
| 文件 | 新增 `Sources/Services/DaylightActivityCoordinator.swift`、`Sources/Features/Settings/DaylightActivitySection.swift`；改 `Sources/Features/Settings/SettingsView.swift`（+1 行 ← **热点**）、`Sources/App/FFWangApp.swift`（+1 个 `.task`）、`Sources/Services/LiveActivityCoordinator.swift`（`start(_:)` 成功后 +3 行） |
| 改什么 | ① `evaluate(now:)` 的守卫链（§1.2）；② `suspendForRock()` / `endAll()`；③ `monitorForeground` 60s 循环（**照抄** `LiveActivityCoordinator.monitorForeground` 的 `while !Task.isCancelled` + `Task.sleep` 写法，不要用 `Timer`）；④ 设置页 `group("天光")`；⑤ `FFWangApp` 里**再加一个** `.task(id: scenePhase)`（两个同名 id 的 `.task` 是允许的，各自独立取消） |
| 依赖 | T1、T2 |
| 验收 | 白天打开 App → 锁屏出现天际线卡；打开红石开关等一场 → 红石活动出现时天光消失、红石结束后 ≤60s 天光回来；关掉天光开关 → 卡片立刻消失；iPad 上该行置灰但**行高与其他行相同** |
| iPhone 回归 | **中**。三个风险点：① `SettingsView` 多一个 group → 设置页高度增加（**允许**，需求就是加开关行）；② `FFWangApp` 多一个 `.task` → 若 `monitorForeground` 内部抛错未捕获会静默退出（要求 `try? await Task.sleep`，与既有实现一致）；③ `LiveActivityCoordinator` 那 3 行若写成 `await` 会阻塞红石启动 → **必须是 `Task { }` 不 await** |

---

### T4 · 简报雨滴

| 项 | 内容 |
|---|---|
| 文件 | 只改 `Sources/Widget/BriefFace.swift`（1112 行，**单文件但内部 6 处联动**：`BriefMetrics` / `precipitationBands` / `streaks` / `fogBand` / `snowDots` / `lightning`） |
| 改什么 | 见 §2.6 清单 |
| 依赖 | 无（纯几何，与 T1–T3 零交集） |
| 验收 | 编译通过；真机看 `rain` / `drizzle` / `thunder` / `snow` / `fog` 五档；**中号与小号各看一次**（雨要落满整卡且正文上下各有一条干净的空带）；把系统切到浅色再看一次（粒子走 `paperAlpha`，浅色纸不该变成一片糊） |
| iPhone 回归 | **低但有**：改的是用户每天看的那张卡。风险点：① 小号正方形只有 158pt 宽，天空段 37.6pt 高 → 8 条雨丝挤在顶部，可能显得"雨从标题上落下来"（这是**设计**：标题不在保护区内，但要在真机上确认不难看）；② `fog` 从"降水带"改到"地面段"→ 小号雾带位置下移，要确认它没落到轨迹后面看不见；③ **中号/小号都必须验，不能只看中号** |

---

### T5 · iPad 立体卡

| 项 | 内容 |
|---|---|
| 文件 | 新增 `Sources/DesignSystem/CardTilt.swift`；改 `Sources/Features/Overview/RedstoneCountdownCard.swift`、`Sources/Features/Overview/TodayBriefTrackCard.swift`、`Sources/Features/Earnings/PlatformCard.swift`（各 +1 个 `.cardTilt(cornerRadius:)`） |
| 改什么 | §3.2 / §3.3 的规格 |
| 依赖 | 无（纯 DesignSystem，与 T1–T4 零交集）。**不碰** `Spacing.swift`（`Tilt.settle` 定义在 `CardTilt.swift` 内部，避免 `Motion` 命名空间变动） |
| 验收 | iPad：轻点开详情 / 斜拖歪卡松手回弹不导航 / `设置→辅助功能→动态效果→减弱动态效果` 打开后完全不动；iPhone：**在 hero 卡上竖直快拖，页面必须正常滚动**（挂了手势就会滚不动） |
| iPhone 回归 | **0（设计上）**，但这是**唯一一个"如果条件写错就糟透了"**的任务。要验的就是上面 iPhone 那一条。风险：把 `if metrics.usesWideCards` 写成 `if !reduceMotion`（漏了宽度判断）→ iPhone 上所有 hero 卡挂手势 → 滚动卡死在卡片区域 |

---

### T6 · 云控 · 网站侧

| 项 | 内容 |
|---|---|
| 文件 | 新增 `functions/api/app/version/index.js`（GET/POST/DELETE）、`functions/api/app/version/upload.js`（POST）、`functions/api/app/download/[file].js`（GET）、`functions/_lib/release-store.js`（KV 读写 + 校验 + `timingSafeEqual` + `sha256` + 版本比较）、`admin/release/index.html`（管理页）、`install/index.html`（安装引导页） |
| 改什么 | 照 §4.2 的契约实现；`_lib/release-store.js` 是**纯函数 + KV 封装**，三个端点都 import 它（与 `functions/_lib/app-brief-core.js` 同一个分工：端点只管 HTTP，逻辑在 `_lib`） |
| 依赖 | 无（与 iOS 侧只靠 §4.2 的契约耦合） |
| 验收 | ① `curl` 五个接口全通（含 401 / 400 / 404 / 413 四条失败路径）；② 上传 2.1MB 的 `/workspace/FFDaWang-v3.0.0-unsigned.ipa` 成功，`GET /api/app/download/<key>` 拿回来的字节数与 `sha256` 与本地 `shasum -a 256` 一致；③ 管理页能上传 + 发布 + 看到列表；④ **不带 token 的 POST 必须 401 且 body 完全一样**（不泄露"缺头"还是"错口令"） |
| iPhone 回归 | **0**（不碰 App） |
| 备注 | **不要动 `functions/_middleware.js`**。`/api/app/*` 已经在白名单里；改动它等于动全站门禁，风险与收益完全不成比例 |

---

### T7 · App 侧更新检查 + 监控页入口

| 项 | 内容 |
|---|---|
| 文件 | 新增 `Sources/Services/UpdateStore.swift`、`Sources/Services/UpdateInstaller.swift`、`Sources/Features/Monitor/AppUpdateSection.swift`、`Sources/Features/Monitor/UpdateSheet.swift`；改 `Sources/Features/Monitor/MonitorView.swift`（+1 行 `AppUpdateSection()` + 1 行 `.task`）、`Sources/App/FFWangApp.swift`（+1 个 `@StateObject` + `.sheet` + 启动检查 `.task`） |
| 改什么 | §4.6 的状态机与三处检查时机；`UpdateSheet`；`AppUpdateSection` 的行 + `snooze()` |
| 依赖 | T1（`AppRelease` / `Endpoint` / `API`）、T6（接口要能跑） |
| 验收 | ① 发布一个 build 15 → App（build 13）启动 3 秒后弹 sheet；② 点「稍后」能关，且再启动不弹；③ 点「用全能签安装」→ 装有机器的全能签被唤起（未装 → 打开 `/install/`）；④ 断网 → `failed`，卡片仍显示上次的说明；⑤ 连点「检查更新」→ 只有第一次真发请求（6h 闸门）|
| iPhone 回归 | **低但有**：① `MonitorView` 加一块 → 监控页高度变化（**允许**，需求就是加入口）；② `FFWangApp` 加 `.sheet` → sheet 挂在 `LayoutMetricsScope` **内部**、`RootView()` **外面**（`LayoutMetricsScope { RootView().sheet(...) }`），**不改 `RootView` 的 `.transaction` 与条件渲染**；③ 若把 `showsSheet` 写成在 `body` 里直接赋值会触发 "Modifying state during view update" 崩溃 → 只能在 `check` 的 async 尾部和按钮 action 里写 |

---

### 5.1 文件冲突矩阵

| 文件 | T1 | T2 | T3 | T4 | T5 | T6 | T7 |
|---|---|---|---|---|---|---|---|
| `Shared/Models/DaylightActivityAttributes.swift` | 建 | 读 | 读 | | | | |
| `Shared/Config/Endpoint.swift` / `API.swift` | 改 | | | | | | 读 |
| `Widget/SkyWidgetBundle.swift` | | 改 | | | | | |
| `Widget/BriefFace.swift` | | | | 改 | | | |
| `Features/Settings/SettingsView.swift` | | | **改（独占）** | | | | |
| `DesignSystem/CardTilt.swift` | | | | | 建 | | |
| `Overview/RedstoneCountdownCard.swift` 等 3 张卡 | | | | | **改（独占）** | | |
| `Services/LiveActivityCoordinator.swift` | | | 改 | | | | |
| `Features/Monitor/MonitorView.swift` | | | | | | | **改（独占）** |
| `App/FFWangApp.swift` | | | **改** | | | | **改（须在 T3 合并后）** |
| `Shared/Theme/Theme.swift` | — | — | — | — | — | — | — （**无人碰**） |
| `DesignSystem/Spacing.swift` | — | — | — | — | — | — | — （**无人碰**） |
| `functions/_middleware.js` | — | — | — | — | — | — | — （**不动**） |

**唯一需要串行的文件是 `FFWangApp.swift`（T3 → T7）。** 三个人并行时的分工建议：工程师甲 = T1 → T2 → T3；工程师乙 = T4 → T5；工程师丙 = T6 → T7。

### 5.2 发版流程（D 落地后必须走的四步，也要贴在管理页）

```
1. bash scripts/bump.sh patch          # MARKETING_VERSION 末位 +1，CURRENT_PROJECT_VERSION +1（两处都改，脚本保证）
2. 推到 GitHub → Codemagic 手动跑 ios-unsigned → 下 SkyApp.ipa
3. 打开 app.skyzyf335.top/admin/release/  → 过站点登录 → 输发布口令
   上传 ipa → 填版本号 3.8.1 / 更新说明 → 点发布
4. 用户下次启动或 6 小时内回前台 → 弹 sheet → 点「用全能签安装」
```

第 1 步不能跳过：`UpdateStore` 的 `localBuild` 直接读 `CFBundleVersion`，忘了 bump 就会"发了新版但用户永远不提示"。

---

## 6. 待明确事项（3 条，都给了推荐项）

**① 天光的夜间时段要不要开？**
推荐：**不开**（`phase == .night` 不启动）。夜里没有太阳可画，卡片只剩一片近黑的夜空 + 一个"距离日出 7 小时"的倒计时 —— 这个信息桌面「天光」小组件已经给了，而实时活动是"占着灵动岛"的资源，值得占用的只有白天。若你希望夜里也挂着（比如当"现在是深夜"的标记），改 `DaylightActivityCoordinator.evaluate` 里一个 `guard` 即可，不影响其他设计。

**② 未签名 ipa 直链公开是否接受？**
推荐：**接受，不加 token**。全能签是第三方 App，它去下载 ipa 时带不了我们的任何凭证，所以直链必须匿名可读；而未签名 ipa 被别人下走**没有实际价值**（没有对应证书装了也起不来，且里面没有任何密钥/用户数据）。若将来 ipa 里出现敏感资源，再改成"短时效签名 URL"（KV 存 `expires` + HMAC，`download/[file].js` 校验）—— 那时再加，v1 不预留复杂度。

**③ 管理页要不要第二道门？**
推荐：**保持现状（站点登录 + 发布口令），不额外放行 `/admin/*`**。`_middleware.js` 已经把非 `/api/*` 的页面请求全部压在 `ce_auth` 后面，管理页因此天然要求"先登录站点、再输口令"两道门。这看起来麻烦，但它意味着**即使 `RELEASE_TOKEN` 泄露，攻击者还得先过站点密码**。为了"方便"把 `/admin/release` 加进中间件白名单，等于主动砍掉一层防线 —— 不建议。

---

## 附录 A：本次新增/引用的常量一览（防拼错）

| 名称 | 值 | 位置 |
|---|---|---|
| `DaylightSettings.storageKey` | `"skyLightLiveActivity"` | 新 `Shared/Models/DaylightActivityAttributes.swift` |
| `Endpoint.appVersionPath` | `"/api/app/version"` | `Shared/Config/Endpoint.swift` |
| `Endpoint.appVersionUploadPath` | `"/api/app/version/upload"` | 同上 |
| `Endpoint.installGuidePath` | `"/install/"` | 同上 |
| `SunClock.SunTrack.crestY` | `0.62`（**引用常量，不写字面量**） | 已有 |
| `BriefMetrics.particleClearBand` | `20`（不动） | 已有 |
| `BriefMetrics.particleBottomInset` | `6`（不动） | 已有 |
| `BriefMetrics.particleTiltGuard` | `1`（新） | `Widget/BriefFace.swift` |
| `BriefMetrics.minFilledBand` | `16`（新） | 同上 |
| `Tilt.maxAngle` | `5.5` | 新 `DesignSystem/CardTilt.swift`（private） |
| `Tilt.travel` | `260` | 同上 |
| `Tilt.perspective` | `0.45` | 同上 |
| `UpdateStore.checkInterval` | `6 * 3600` | 新 `Services/UpdateStore.swift` |
| `UpdateStore.launchDelay` | `3` | 同上 |
| `nsk-sign://web?url=` | 全能签唤起 Scheme | `Services/UpdateInstaller.swift` |

## 附录 B：本方案的硬边界（做完要逐条核）

1. 不改 `entitlements` / App Group / `codemagic.yaml` / `project.yml`（除版本号由 `bump.sh` 改）。
2. 不改 `Resources/Info.plist`（`NSSupportsLiveActivities` 已有；不加 `LSApplicationQueriesSchemes`，因为不用 `canOpenURL`）。
3. 不改 `RootView` 的 `.transaction` 与条件渲染；新 `.sheet` 挂在 `LayoutMetricsScope { RootView().sheet(...) }`。
4. 不改 `functions/_middleware.js`。
5. 不改 `Theme.swift`、`Spacing.swift`。
6. 不用 `itms-services://`，不设计 HTTP 签名接口（全能签没有）。
7. 所有新 View 有 private 存储属性时必须显式 `init() {}`。
8. `Sources/Shared` 下不裸 `import UIKit`。
