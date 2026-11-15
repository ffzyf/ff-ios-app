# FF大王 / SkyApp · 5.1.2 交付总结

| 项 | 值 |
|---|---|
| 版本 | `MARKETING_VERSION 5.1.2` / `CURRENT_PROJECT_VERSION 47`（`project.yml` 4 处同步） |
| 团队 | `software-512`：许清楚(PRD) → 高见远(架构) → 寇豆码(实现) → 严过关(QA)，齐活林(主理人) 编排 |
| 交付状态 | **代码冻结，可交付发版** |
| 测试 | 主口径 **107/107**，定点回归 31/31，补测 33/33，12→49 个后端 JS `node --check` 全过，`IS_PASS: YES`，智能路由 `NoOne` |
| 已知问题 | 0 个源码缺陷（DEF-001 + 端点归一化链路漏推 2 项均已修复闭环） |
| 环境遗留 | 5 类（见 §6），均为无 macOS/Xcode/外部平台导致，不构成发版阻断 |

---

## 1. TL;DR

把用户 5 条抱怨收敛成一次可验收的版本补齐：**预警首屏从「读不到」变成四态确定态 + 跨启动缓存 + 可诊断数据源；新增 Bark 定时差异推送；红石补结束时间；AI 加联网开关/引用/朗读；「更多→工具」新增小组件调试后台**。跨 iOS 双 target + Cloudflare 后端，共约 55 个文件，全程 SOP 顺序流转、成员产出为据。

## 2. 五条需求 → 落地对照

| # | 用户原话 | 根因 / 判读 | 落地 |
|---|---|---|---|
| R1 | 天光页预警每次打开读不到、不知道专门链接有没有用 | 实测上游 `GET /api/app/alerts` 正常（`ok:true`/`hit`/当前 `warnings:[]`），是 **App 首帧 `.unknown` + 四种失败语义被压平 + 无跨启动缓存** | 新增 `AlertPresentation` 四态状态机（有预警/确认无预警/读取中/读取失败）+ `AlertRefreshPolicy`（300s 窗口，10 分钟进出≤2 次请求）+ `AlertCache`（原文 JSON 跨启动，`ok==true` 才写）+ 诊断区可长按复制「接口/最近结果/时刻/X-Alerts-Cache」。「读取失败」绝不冒充「无预警」 |
| R2 | 有预警根本没通知，用 ark 推送 | 「ark」= **Bark**（项目已有 `push_bark_key`/`api.day.app`）；侧载无 APNs，本地通知进程挂起即失效 | 新增第三个 cron 端点 `/api/push/weather-alert`（cron-job.org `*/5`）+ `alert-push-core.js` 差异判定（新增/级别升级才推、解除不推、按 id 24h 去重）+ 配置 KV `alert_push_config`（开关/最低级别/免打扰，设置页可读）+ 失败进推送监控。**前台本地通知保留**，双通道各自去重 |
| R3 | 红石只显示降落时间 | `Occurrence.endAt`（落地+52 分钟）是现成真值，只是没展示 | `RedstoneTimeText`（Shared，App/Widget 共用）统一输出：紧凑 `11:08–12:00`、详情「降落 11:08 · 结束 12:00」、跨日「次日 00:22」、`notGenerated` 不显示假时间。覆盖顶部条/列表/详情/Widget 小中大/实时活动，**不重算时长** |
| R4 | DeepSeek 全家桶：搜索朗读、联网搜索搬到 App | 文章《全家桶应用 API》(2026-11-13) 的 `deepseek-flash`/`deepseek_web_search` **未验证**，后端实测仅 `deepseek-chat`；本地无密钥、离线测不了 | 按 **官方 Demo 交互骨架 + 本项目液态玻璃**（不换肤）：联网搜索 chip（默认关、按会话记忆）+ 引用区 + 状态行 + 每条回复朗读/暂停/停止/复制（复用 `/api/app/tts`）。后端走「总闸默认 off + 能力探测 + 发上游前降级 + 单独记账」，**关闭时 payload 与旧版逐字一致、零工具调用费**；真实联网待云端验证后开闸 |
| R5 | 设置里加小组件调试页面（放更多里） | 需求措辞「设置中加、放更多里面」歧义；Widget 与 App 无 App Group | 「更多→工具」**唯一入口**（设置页仅一行静态指引）。5 区面板：8 组件 × 全 family × 8 显示状态 × 预设/自定义数据/时间旅行 × 刷新 Timeline/重置/复制诊断。复用既有 `*Face` 渲染层（为此把 6 个 Entry 值类型与 3 个 Face 下沉/平移到 Shared），**调试态仅内存、退出即恢复、不污染桌面组件** |

## 3. 关键工程决策（团队产出）

- **版本号**：用户明说 5.1.2 按之，构建号在历史 46 后取 47；`project.yml` 4 字段同步，未跑 `bump.sh`（它会自增到 3.32.0）。
- **R4a 降级**：文章不当接口契约。总闸 `AI_SEARCH_ENABLED` 默认 off、探测候选集中在一张常量表、不支持时发上游前降级，关闭时零差异、零费用。
- **R5 无 App Group**：主 App target 原先编不到任何 `*Face`，通过 `project.yml` 逐个显式接线 + `SunArc/MoonPhase/Wind` 三个 Face 纯平移 + 6 个 Entry 下沉 `Sources/Shared` 解决，`excludes:["Widget"]` 保留、`SkyWidgetBundle.swift`(@main) 未进主 App。
- **R2 触发**：cron-job.org 外部 HTTP GET（仓库内无 wrangler/scheduled），严禁凭空造 cron 文件；双触发（cron + alerts 缓存 miss 惰性）共用去重 KV 幂等。
- **入口单一**：`WidgetDebugView` 只在 `MoreView` + 自身出现，设置页无 `.sheet` 复制实现。

## 4. 文件清单（按仓库）

**iOS `/workspace/ios-app` → `ffzyf/ff-ios-app`**（新增 18 个 + 修改约 24 个）
- 配置：`project.yml`（版本 4 处 + sources 接线）、`Endpoint.swift`、`API.swift`
- Shared 纯逻辑：`Domain/AlertPresentation.swift`、`AlertRefreshPolicy.swift`、`RedstoneTimeText.swift`；`WidgetDebug/WidgetDebugCatalog.swift`、`WidgetDebugPresets.swift`、`WidgetEntries.swift`；`Config/WidgetDeepLink.swift`
- 模型：`Models/AIChat.swift`、`Models/Monitor.swift`
- Services：`AlertCache.swift`、`AlertStore.swift`（四态重写）、`AIChatStore.swift`、`SpeechStore.swift`
- SkyRoom：`SkyRoomView.swift`、`SkyRoomWeatherCards.swift`、`SkyRoomAlertDiagnosticsView.swift`
- Rock：`NextEventBar.swift`、`RockTodayColumn.swift`、`RedstoneDaySheet.swift`、`SkyStatusCard.swift`
- AIChat：`AIChatView/Composer/MessageList/AIModelPickerSheet` + 新建 `AIChatCapabilityBar/CitationView/MessageActions`
- Settings/More：`SettingsView.swift`、`MoreView.swift`、`AlertPushSettingsSection.swift`、`PushStatusRow.swift`、`RootView.swift`（深链）
- WidgetDebug：`WidgetDebugView/Session/PreviewContainer.swift`
- Widget：`RedstoneFace.swift`、`RedstoneWidget.swift`、2 个 LiveActivity + 新建 `SunArcFace/MoonPhaseFace/WindFace.swift`（纯平移）
- 发版：`notes-5.1.2.txt`

**后端 `/workspace/gx-main` → `ffzyf/ios-appgx`**（新建 5 + 修改 9，另有 `kv-stats.js` 为清单外既存改动）
- 新建：`_lib/bark.js`、`_lib/alert-push-core.js`、`_lib/ai-search.js`、`api/app/alert-push-config.js`、`api/push/weather-alert.js`
- 修改：`api/settings.js`、`api/app/monitor/index.js`、`api/app/alerts.js`、`api/ai/chat.js`、`api/ai/models.js`、`_lib/ai-store.js`、`api/ai/conversation.js`、`README.md`（cron 表第三行）、`schema.sql`
- **红线不动**：`_lib/ai-models.js`（模型/人设）、`_lib/ai-context.js::buildPayload`、`chat.js::pump()` UTF-8 半包两行、`/api/app/alerts` 契约、`tts.js`、`_middleware.js`、`VERSION`；4 个历史镜像 `appsite/site/gx-work` 零改动。

**文档/QA**：`docs/PRD-5.1.2.md`、`docs/ARCH-5.1.2.md`、`qa/QA-5.1.2-report.md`（551 行，含 3 轮 TAP 与遗留项）、`qa/*.mjs`（独立测试，零 npm 依赖）。

## 5. 测试与质量关卡

| 关卡 | 结果 |
|---|---|
| 工程师全局一致性审查 | `IS_PASS: YES`（S1–S14 全过、12 个 JS 语法 OK、14 组 fixture 绿、App↔后端字段逐项对齐） |
| QA 第 1 轮 | 106/107，发现 **DEF-001**（非法免打扰时刻被洗成合法夜间窗口 → 极端预警夜间漏推），路由 `Engineer` |
| 修复 + 第 2 轮回归 | 107/107，`IS_PASS: YES`，DEF-001 关闭、合法免打扰零回归；QA 另报 **端点归一化链路 P2 观察项** |
| 主理人拍板发版前加固 | 「两端都堵」：写入口强制脏 dnd `enabled=false` + 端点/`diffAlerts` 透传原始 cfg |
| 最终定点回归 | 107/107 + 31/31 + 33/33，`diffAndPush` mock KV 真跑确认极端预警夜间不再整轮短路，`NoOne` |

## 6. 已知遗留项（环境能力边界，均非发版阻断）

1. **编译级验收**：本环境 Linux 无 macOS/Xcode，Swift 未编译。双 target 链接、`\.widgetFamily` 在 App 进程可写、`@MainActor WidgetDebugSession` 的 `@StateObject`、3 个 Face 平移与 Entry 下沉、iPad/浅深/动态字体四档 → 由 **Codemagic / Xcode 26** 补做。
2. **cron-job.org 第三任务**：`*/5 * * * * → /api/push/weather-alert` 需在外部平台手动创建（README 已登记）。
3. **R4a 真实联网顺延**：总闸默认 off、候选全 `verified:false`；云端用已配 `DEEPSEEK_API_KEY` 真实验证后，只改 `SEARCH_PROBE_CANDIDATES` 表并开闸即可，调用点不动。
4. **真机端到端**：Bark 到达、SSE 真实上游流、深链滚动时机、Widget 真实渲染、线上响应体实拍。
5. **`kv-stats.js`**：S14 清单外的既存登录自检改动，提交时勿误带；`notes-5.1.2.txt` 提交前复核。

## 7. 用户下一步建议

1. 走既有发版链路：`scripts_commit.py` 把改过的 iOS 文件推 `ffzyf/ff-ios-app`、`gx-main` 推 `main` 自动部署；**排除 `kv-stats.js`**。
2. 在 **Codemagic** 触发 5.1.2 构建（版本 5.1.2 / build 47），确认双 target 编译通过——这是本次唯一的编译级验收。
3. 在 **cron-job.org** 建第三个任务（每 5 分钟 GET `/api/push/weather-alert`），并用 `?dry=1` 预演一次。
4. 云端验证 DeepSeek 联网能力后再决定是否开 `AI_SEARCH_ENABLED` 总闸；不开则 App 联网 chip 保持置灰、零费用。
5. 真机侧载验证：天光预警四态与长按复制、红石结束时间（含跨日）、预警 Bark 通知、AI 朗读、「更多→工具」小组件调试面板。
