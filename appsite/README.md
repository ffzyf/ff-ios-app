# appsite/ · 云控更新 · 网站侧源码

本目录是 **Cloudflare Pages 工程 `app.skyzyf335.top`** 的源码快照，用于在 iOS App 仓库里保留一份可追溯的服务端代码。
**实际部署在 Cloudflare Pages 上完成**，不通过本仓库的 CI 发布。

## 目录结构

```
appsite/
├── README.md                              # 本文件
├── install/
│   └── index.html                         # 安装引导页（/install/）
├── admin/
│   └── release/
│       └── index.html                     # 发布管理台（/admin/release/）
└── functions/
    ├── _lib/
    │   └── release-store.js               # KV 读写封装 + 业务逻辑（纯函数）
    └── api/app/
        ├── version/
        │   ├── index.js                   # GET / POST / DELETE 版本
        │   └── upload.js                  # POST 上传 ipa
        └── download/
            └── [file]/                    # 动态路由：文件名占位
                └── index.js               # GET 下载 ipa（匿名直链）
```

## 部署步骤

1. **拷贝文件**：把本目录下的内容合并到 Cloudflare Pages 工程的对应路径。
   Pages 工程根目录即 `functions/`、`admin/`、`install/` 的父级。

2. **配置环境变量**：在 Cloudflare Pages 后台 → 设置 → 环境变量 → 添加：

   | 名称 | 值 | 类型 | 环境 |
   |------|----|------|------|
   | `RELEASE_TOKEN` | 一个 **32 位以上**的随机串（推荐 `openssl rand -hex 24` 生成） | **Secret**（加密） | Production + Preview 都勾 |

   ⚠️ **fail-closed**：未配置 `RELEASE_TOKEN` 时，所有写接口（POST/DELETE）一律返回 `503 release_token_missing`，**绝不能没配就放行**。

3. **KV 绑定**：复用现有的 `EARNINGS_KV` 命名空间，变量名保持 `EARNINGS_KV` 不变。
   本模块写入的键都带 `release:ios:` 前缀，与现有业务数据隔离。

   KV 键一览：
   - `release:ios:latest` — 最新版元数据（≤2KB，不设 TTL）
   - `release:ios:history` — 最近 5 版历史数组（不设 TTL）
   - `release:ios:file:<key>` — ipa 二进制（不设 TTL，自动清理到最近 3 个 build）

4. **无需改动 `functions/_middleware.js`**：
   现有的 `_middleware.js` 已有一行 `if (url.pathname.startsWith('/api/app/')) return ctx.next();`，
   `/api/app/*` 在站点登录白名单里（App 要匿名读），写接口的鉴权完全由端点内部的 `RELEASE_TOKEN` 负责。
   **不要改 `_middleware.js`**，改动它等于改全站的访问控制，范围太大。

## 接口契约

| # | 方法 · 路径 | 鉴权 | 成功 | 主要错误码 |
|---|---|---|---|---|
| 1 | `GET /api/app/version` | 匿名 | `200 {ok, apiVersion, serverTime, latest}` | `500 kv_unavailable` |
| 2 | `POST /api/app/version` | `x-release-token` | `200 {ok, latest}` | `401 unauthorized` / `400 build_regression` / `400 ipa_key_missing` / `503 release_token_missing` |
| 3 | `POST /api/app/version/upload` | `x-release-token` | `200 {ok, key, size, sha256}` | `401` / `413 too_large` / `400 missing_file_name` |
| 4 | `GET /api/app/download/<file>` | 匿名 | `200` 二进制 | `404 not_found` |
| 5 | `DELETE /api/app/version?build=N` | `x-release-token` | `200 {ok}` | `401` / `404 not_found` / `400 bad_request` |

响应统一信封：`{ok, ...}` / `{ok:false, error:{code, message}}`。

## 不做的事（v1 边界）

- 不做强制更新
- 不做静默下载 / 后台安装
- 不做 beta / 多渠道 / 灰度
- 不做从 Codemagic / GitHub Release 自动拉 ipa（链接会过期）
- 管理页顶部固定展示以上说明，文案见 `admin/release/index.html`

## 本地验证

JS 语法检查（沙箱/本地有 node 即可）：

```bash
node --check functions/_lib/release-store.js
node --check functions/api/app/version/index.js
node --check functions/api/app/version/upload.js
node --check "functions/api/app/download/[file]/index.js"
```

本目录只做源码存档，真实运行环境是 Cloudflare Pages 的 Workers runtime（`fetch` / `KV` / `crypto.subtle` / `URL` 等 API 由平台提供）。
