# HIG 叠加式迭代 · QA 验证清单（HIG-ITER-1）

> 基线：5.6.6（65） · 部署目标 iOS 18 / Xcode 26 + iOS 26 SDK
> 性质：纯叠加。业务 Store / 网络 / 数据模型 / 表单校验 / 按钮 action / 导航绑定 /
> `.task(id: scenePhase)` / `glassSurface` 签名 / 既有 token 值 —— 全部零改动。
> 工程侧闸门：`bash scripts/lint-theme.sh`（5 条）、`bash scripts/lint-hig.sh`（3 条）、
> `python3 scripts/preflight.py`（括号配对 + 跨文件符号）。

## 一、HIG 逐条验收

### A. 安全区与 Home Indicator

- [ ] **基础避让**：iPhone 有 Home Indicator 机型，底部 Tab 栏与内容不压指示器
      （既有 `safeAreaInset(edge:)` 行为未变）。
- [ ] **沉浸页 defer**：天光页（`skyapp://sky` 深链入口 / 概览入口）、全屏看图，
      首次从底部上滑只唤出指示器、不退出页面；二次上滑才返回主屏。
- [ ] **自动隐藏可恢复**：轻触屏幕后浮层/指示器恢复；这是偏好而非强制，
      页面功能绝不依赖"指示器真的消失"。
- [ ] **退出复位**：关闭沉浸页 → 普通页面不 defer、不隐藏；不会把隐藏态带到下一页。
- [ ] **回前台复位**：App 切后台再回来，沉浸页的 defer 自动失效；再退出重进才重新启用。
- [ ] **iPad 不受影响**：iPad 横屏沉浸页，底部上滑仍触发系统多任务手势
      （`ImmersiveGestureModifier` 用 `usesTopTabStrip == false` 判定，仅 compact 生效）。
- [ ] **Stage Manager**：拖窗到窄档（尺寸类变 compact）再打开沉浸页，defer 按设备档正确切换。

### B. Dynamic Type

- [ ] **默认零回归**：系统字号 standard（large）下，12 个文本 token 与基线截图逐点一致
      （34/28/22/20/17/17/16/15/13/13/12/11）。
- [ ] **五档跟随**：xSmall → accessibilityXXXLarge，正文、卡片标题、Tab 标签随字号放大，
      无截断、无重叠。
- [ ] **护栏有效**：Tab 栏标签、徽标、固定高度读数在 accessibility 大档不溢出槽位
      （上限 `accessibilityLarge`）；数字读数/机器码/水印保持固定 pt。
- [ ] **中文回退**：苹方回退正常，无豆腐块；SF Symbols 图标不随字号错位。

### C. 触控目标

- [ ] `IconGlassButton`：视觉仍 36pt，命中区 ≥44×44；相邻图标按钮的命中区不重叠。
- [ ] `CapsuleGlassButton`：短文案下命中区 ≥44×44，胶囊视觉尺寸未变。
- [ ] Tab 栏项：底部 ≥69.8×66、顶部 78×44，叠加后相邻项不抢点击。
- [ ] 命中区叠加不改变布局：按钮间距、Tab 栏高度与基线一致。

### D. 玻璃 / 语义色 / 深浅色

- [ ] iOS 26 真机：玻璃融合与形变正常；相邻玻璃经 `GlassGroup` 融合。
- [ ] iOS 18–25：`GlassCompat` 手工配方无崩溃，深浅色正确。
- [ ] `Theme.Semantic.*`：浅色/深色下对比度达标，与既有品牌 token 并排无脏色；
      既有 token 数值一个都没变。
- [ ] 8 套主题 × 深/浅外观：新增语义色元素随外观正确解析。
- [ ] 闸门：`lint-theme.sh` + `lint-hig.sh` 全绿。

## 二、无回归验收（关键）

- [ ] 7 个 Tab 切换正常，选中圆 `Motion.tab` 动画与 `Haptics.light()` 保留。
- [ ] 深链 4 条（brief / rock / earnings / ai）+ `skyapp://sky`、含 `?focus=alerts` 全部可用。
- [ ] 键盘避让：AI 聊天页输入时底栏让位逻辑不变。
- [ ] 3 个 `fullScreenCover`（文章 / 天光 / Debug 预览）present / dismiss 时序不变，
      无 350ms 竞态回归；天光页两个入口（RootView 深链 / OverviewView 卡片）都正常。
- [ ] `FFWangApp` 全部 `.task(id: scenePhase)`（实时活动 / 天光实时活动 / 天气 / 预警 /
      分钟降水 / 远程通知 / 云控 / 远程配置）逐条 diff 无增减。
- [ ] 换肤 `.id(themeId)` 重建行为不变，滚动位置保活。
- [ ] Stage Manager 拖窗 / 旋转：四档 PageTier 切换正常，无首帧闪。
- [ ] 252 个 Swift 文件 Xcode 26 编译通过，无 signing / duplicate main 问题。

## 三、本次改动文件与 diff 自查点

| 任务 | 文件 | 性质 | diff 自查要点 |
|---|---|---|---|
| T01 | `HIG/HIGEnvironment.swift` | 新建 | 只定义枚举 / 环境键 / Scope；不持有任何 Store |
| T01 | `HIG/ImmersiveGestureModifier.swift` | 新建 | 恒定 modifier 链；仅 compact + `.immersive` 生效 |
| T01 | `HIG/TapTargetModifier.swift` | 新建 | overlay 透明命中区，不改变布局尺寸 |
| T01 | `FFWangApp.swift` | 修改 | **只新增两行**（Scope 开合）；task / 绑定 / sheet 逐字未动 |
| T01 | `Spacing.swift` | 修改 | 只 `+tapMinSide` / `+homeIndicatorReserve` / `+Motion.immersiveChrome` |
| T02 | `Typography.swift` | 修改 | 仅 12 个 token 定义体；metric / code / version / eyebrow 原样 |
| T02 | `HIG/DynamicTypeGuard.swift` | 新建 | 无业务调用，只对指定视图加范围 |
| T02 | `FloatingTabBar.swift` | 修改 | 标签字号 + 护栏 + tapTarget；action / 快捷键 / 徽标形状未动 |
| T02 | `WideTabStrip.swift` | 修改 | 标签字号 + 护栏；78×44 槽与快捷键未动 |
| T02 | `GlassButtonStyles.swift` | 修改 | 两个按钮各加一行 tapTarget；action / Haptics / 签名未动 |
| T03 | `Theme/SemanticColors.swift` | 新建 | 只新增命名空间，无 hex |
| T03 | `Theme.swift` | 修改 | **仅末尾注释**，既有 token 数值零改动 |
| T03 | `GlassCompat.swift` | 修改 | **仅文档注释**，函数体 / 签名 / `GlassLevel.switch` 零改动 |
| T03 | `HIG/HIGLintSupport.swift` | 新建 | 纯契约常量（文档 §2.1 已列，任务卡 T03 漏列，按 §2.1 补齐） |
| T03 | `scripts/lint-hig.sh` | 新建 | 3 条静态闸门 |
| T04 | `RootView.swift` | 修改 | **仅注释**；present / 绑定 / onDismiss / deepLink 零改动 |
| T04 | `SkyRoomView.swift` | 修改 | 仅 body 链尾 +`.immersiveChrome()`；@State / action 零改动 |
| T04 | `ImageViewer.swift` | 修改 | 仅 body 链尾 +`.immersiveChrome()`；点按关闭零改动 |
| T05 | `scripts/lint-theme.sh` | 修改 | 只加第 5 条护栏检查 |
| T05 | `README.md` | 修改 | 新增"HIG 叠加约定"一节 |
| T05 | `docs/HIG-ITERATION-QA.md` | 新建 | 本文件 |

## 四、核验结论（无需改动处）

- **PageToast**：字号已是 `Typography.captionXS`（语义 token，随 Dynamic Type），
  且 `allowsHitTesting(false)` 不吃点击 —— 触控目标检查不适用。核验通过，**未改动**。
- **GlassGroup**：iOS 26 `GlassEffectContainer`、18–25 透传，已是合规唯一容器，未改动。
- **RootView 的 `safeAreaInset` / `.transaction` / `tabSelection` setter / `page(for:)` /
  `open(deepLink:)` / `onOpenURL` / 键盘避让**：全部保持逐字不变。
- **iOS 18 降级**：两处沉浸 API（iOS 16+）与语义 Font 全版本可用，玻璃继续走 `GlassCompat`
  既有 `#available(iOS 26)` 分流，本迭代没有新增任何 `#available` 分支。

## 五、交付环境未能验证的部分

交付沙箱为 Linux，**无 swift / xcodebuild / xcodegen**，因此：

- 未做 Xcode 26 真编译与 252 文件全量构建验证；
- 未做 iOS 18 / 26 真机与模拟器运行验证（手势 defer、浮层显隐、Dynamic Type 五档、
  玻璃材质、深浅色、iPad Stage Manager）；
- 已完成的静态核对：全部新增 / 修改 Swift 文件的 API 可用性与 `#available` 分支人工复核、
  `lint-theme.sh` / `lint-hig.sh` / `preflight.py` 的结果见交付说明。
  上线前必须在 macOS + Xcode 26 环境补做本节全部验证项。
