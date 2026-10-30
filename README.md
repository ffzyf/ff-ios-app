# FF大王 · 四站合一 iOS 壳 App

这是一个 **纯壳工程**：把四个已上线的 Cloudflare Pages 站点包成一个 iOS App（底部四个 Tab，每个 Tab 一个站点）。
网站本身的代码不在本仓库，本仓库只负责「壳」和「自动打包未签名 IPA」。

App 展示名 **FF大王**，Bundle ID `top.skyzyf.skyapp`，最低 iOS 15.0，仅支持 iPhone。

---

## 一、四个 Tab 对应站点

| Tab | 名称 | 地址 | 图标（SF Symbol） |
|---|---|---|---|
| 1 | 博客 | https://skyzyf335.top | doc.text |
| 2 | 简报 | https://app.skyzyf335.top | bell.badge |
| 3 | 收益 | https://gzz.skyzyf335.top | chart.line.uptrend.xyaxis |
| 4 | 问卷 | https://wj.skyzyf335.top | list.bullet.clipboard |

---

## 二、如何拿到 IPA 文件

1. 本仓库每次 `push` 到 `main` 分支，GitHub 会自动编译一次（也可以在 Actions 页面点 **Run workflow** 手动触发）。
2. 打开仓库页面的 **Actions** 标签页，点开最新一次绿色的 run。
3. 拉到页面最底部，找到 **Artifacts** 区域。
4. 下载 `SkyApp-unsigned-ipa`（一个 zip）。
5. 解压后得到 `SkyApp.ipa`。

> 这个 IPA 是 **未签名** 的。未签名的 IPA 不能直接双击安装，必须先用下面的任意一条路径在本地签名。

---

## 三、如何装到 iPhone（三种路径，选一条）

### 路径 A：Sideloadly（Windows / Mac 电脑，最稳，推荐先试这条）

适用人群：有一台电脑 + 一根数据线，愿意每 7 天重装一次。

1. 电脑浏览器打开 `https://sideloadly.io`，下载并安装 Sideloadly。
2. 电脑装好 iTunes（Windows 需要，用来提供驱动），Mac 自带无需安装。
3. 数据线连接 iPhone，手机上点「信任此电脑」。
4. 把 `SkyApp.ipa` 拖进 Sideloadly 的 IPA 框。
5. 在 `Apple ID` 一栏填写你的 Apple ID（免费账号即可，不需要开发者账号）。
6. 点 **Start**，输入 Apple ID 密码（如果开了双重验证，需要在弹出的窗口里填一次验证码）。
7. 装完后，手机打开「设置 → 通用 → VPN 与设备管理 → 开发者 App」，点你的 Apple ID，选「信任」。
8. **（iOS 16 及以上必做）** 打开手机「设置 → 隐私与安全性 → **开发者模式**」，打开开关，按提示**重启手机**，重启后解锁再确认一次「打开」。
   > 不做这一步，App 图标点下去会立刻闪退，且没有任何报错——这是自签 App 最常见的「装好了却打不开」的原因。
9. 回到桌面，图标出现，可以打开。

**注意**：免费 Apple ID 签名的 App **有效期 7 天**，7 天后打不开，需要重新用 Sideloadly 装一次。签名期间最多同时存在 3 个自签 App。

### 路径 B：AltStore（可以在手机上自动续签）

适用人群：家里有常开的电脑（同一 WiFi），不想每 7 天插线。

1. 电脑浏览器打开 `https://altstore.io`，安装 **AltServer**（Windows 要额外装 iTunes 和 iCloud，务必从苹果官网下载，不要用 Microsoft Store 版本）。
2. 数据线连 iPhone，在 AltServer 托盘/菜单栏图标里选 **Install AltStore → 你的设备**，输入 Apple ID。
3. 手机上会出现 **AltStore**，打开它，在「Settings」里登录同一个 Apple ID。
4. 把 `SkyApp.ipa` 传到手机（AirDrop / 文件 App / iCloud 云盘都行），在文件 App 里点它 → 分享 → 用 AltStore 打开。
5. 也可以在 AltStore 的 **My Apps** → 左上角 `+` → 选择 IPA 文件安装。
6. 保持 iPhone 和装有 AltServer 的电脑在同一个 WiFi，AltStore 会在后台自动续签（7 天 → 自动刷新）。

**注意**：电脑关机/不在同一 WiFi 时无法续签，超过 7 天仍会失效。

### 路径 C：爱思助手（Windows，图形化，傻瓜式）

适用人群：完全不想碰命令行，能接受"可能过几天就失效"。

1. 电脑安装爱思助手（`i4.cn`）。
2. 数据线连 iPhone，进「应用游戏」→ 左上角「导入」→ 选择 `SkyApp.ipa`。
3. 在弹窗里使用「一键签名安装」（需要登录爱思账号），或直接用它的 IPA 签名功能。
4. 安装完成后，按路径 A 第 7 步去「设置 → 通用 → VPN 与设备管理」信任。

**注意**：爱思走的是共享企业证书，**证书随时可能被苹果吊销**，一旦吊销所有装了的 App 全部打不开，要重新装。**不建议作为长期方案**。

### 关于 TrollStore（永久签名，但限制很死）

TrollStore 仅适用于 **iOS 14.0–16.6.1**（另有 16.7 RC 与 17.0 的特定安装路径）；iOS 15.2 及以上通常需要借助 TrollStore Helper 或电脑辅助安装。不确定自己的系统版本能否用时，先走路径 A（Sideloadly）。
装好 TrollStore 后可以永久签名、不会掉签；如果你的系统不在上述范围，**不建议折腾**。

---

## 四、修改站点

打开 `Sources/AppConfig.swift`，改 `tabs` 数组即可：

```swift
static let tabs: [AppTab] = [
    AppTab(title: "博客",
           urlString: "https://skyzyf335.top",
           systemImage: "doc.text"),
    // ... 增删改都只动这里
]
```

- `title`：底部 Tab 文字，同时也是页面标题。
- `urlString`：站点完整地址，必须带 `https://`。
- `systemImage`：SF Symbol 图标名，可以在苹果官方 SF Symbols App 里查名字；名字写错不会崩溃，只是没图标。

改完 push 到 `main`，等 Actions 重新出包即可。

---

## 五、修改 App 名称 / 图标

| 想改什么 | 改哪里 |
|---|---|
| 桌面显示名 | `Resources/Info.plist` 里的 `CFBundleDisplayName` |
| 图标 | 覆盖 `Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`（必须是 **1024×1024 的 PNG，不能带透明通道**） |
| Bundle ID | `project.yml` 里的 `PRODUCT_BUNDLE_IDENTIFIER` |
| 版本号 | `project.yml` 里的 `MARKETING_VERSION`（对外版本）/ `CURRENT_PROJECT_VERSION`（构建号） |
| 主题色（Tab 高亮色、按钮色） | `Sources/AppConfig.swift` 里的 `primaryColor` |

---

## 六、常见问题（FAQ）

**1. 装了 7 天后图标变灰 / 打不开怎么办？**
免费 Apple ID 的签名证书只有 7 天有效期，这是苹果的限制，不是 App 的问题。用 Sideloadly 重新装一次即可（不需要删除旧 App，直接覆盖安装，数据保留）。想彻底解决只有两条路：买 99 美元/年的开发者账号（1 年有效期），或者用 AltStore 自动续签。

**2. 签名失败，提示 "Provisioning profile" / "Unable to install"？**
- 检查 Apple ID 是否已经在手机上登录过 App Store（全新账号有时要先在手机上登录一次）。
- 免费账号同时最多只能有 3 个自签 App，超了要先删掉一个。
- 换一根数据线 / 换一个 USB 口，Windows 上确认 iTunes 能正常识别设备。
- 手机系统太新（比如 iOS 18+）时，Sideloadly 要更新到最新版。

**3. 打开是白屏？**
- 首屏白屏通常是站点侧的「访问锁」还没解锁，或者站点正在部署。先在 Safari 里打开对应地址确认能访问。
- 如果 Safari 能打开但 App 白屏，下拉页面触发刷新；仍然不行就杀掉 App 重开。
- 网络断开时会自动弹出「加载失败 + 重试」页，点重试即可。

**4. 视频不能播放 / 一点就全屏？**
- 壳里已经开启 `allowsInlineMediaPlayback`（内联播放）和自动播放许可。
- iOS 对**移动网络下的自动播放**有限制，且单个视频文件建议 **小于 20MB**，否则容易加载失败。把视频压缩或改成分段 HLS 更稳。

**5. 点了链接跳到别的 App / 没反应？**
`tel:`、`mailto:`、`weixin:`、`itms-apps:` 这类非网页协议，壳里会交给系统处理（打电话、发邮件、跳微信）。这是预期行为。

**6. 深色模式？**
跟随系统。系统切深色，App 自动深色，不需要手动设置。

**7. 想要「返回上一页」按钮？**
当前导航栏是隐藏的，返回上一页有两种方式：网页内部的返回链接，或者用 WebView 自带的左缘右滑返回**网页上一页**（`allowsBackForwardNavigationGestures`）。注意这里返回的是网页历史，不是 App 页面栈。

---

## 已知限制

- 文章里的视频**在 App 内可正常内联播放**；但「导出 / 下载附件」类按钮（例如站点的 CSV、PDF 导出）**在 App 内点击无响应**——这是首版没有接入 `WKDownloadDelegate` 的已知限制，请改用 Safari 打开站点操作。
- 本项目产出的是**未签名 IPA**，必须自行重签才能安装；免费 Apple ID 签名的 App **7 天过期**，过期后重装即可（数据都在服务端，不会丢）。
- App 只是四个站点的壳，站点内容更新**无需重新打包** App。
- 非 `http/https` 的白名单外协议（例如某些第三方 App 的私有 scheme）在 App 内点击不会有反应，属预期行为。

---

## 七、目录结构

```
.
├── README.md
├── .gitignore                      # 忽略 xcodeproj / build / Payload / ipa
├── project.yml                     # xcodegen 工程描述（生成 SkyApp.xcodeproj）
├── Sources/
│   ├── AppDelegate.swift           # 应用入口
│   ├── SceneDelegate.swift         # 窗口装配
│   ├── AppConfig.swift             # 四站配置（唯一配置源）
│   ├── RootTabBarController.swift  # 四个 Tab 容器
│   ├── WebViewController.swift     # WKWebView 封装（核心）
│   └── ErrorViewController.swift   # 加载失败重试页
├── Resources/
│   ├── Info.plist
│   └── Assets.xcassets/            # AppIcon + AccentColor
└── .github/workflows/build-ipa.yml # 自动编译未签名 IPA
```

本地要有 Mac + Xcode 才能自己编译；没有 Mac 就用 GitHub Actions 出的包。
