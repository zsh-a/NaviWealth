# NaviWealth 个人部署手册

NaviWealth 不上架公开商店；本文档记录从零把当前 main 分支部署到一台个人设备 + 一个个人域名所需的全部步骤。一次跑通后保存账号 / API token，迁移机器或重置环境时只需重读 [快速回放](#快速回放) 一节。

部署目标：

| 组件 | 落点 | 出口 |
| --- | --- | --- |
| Web (Flutter) | Cloudflare Pages | `https://<project>.pages.dev` 或 `finance.zsh.dev` |
| Backend (Workers + Rust) | Cloudflare Workers | `https://naviwealth-backend.<account>.workers.dev` 或 `api.zsh.dev` |
| D1 数据库 | Cloudflare D1 (prod) | wrangler 远程绑定 |
| iOS | Xcode sideload 到自己 iPhone | 365 天证书 |
| Android | GitHub Release 下载 APK | 二维码扫码安装 |

## 一次性准备

### 账号与工具

- Cloudflare 账号 + Workers/Pages/D1 都已开通免费额度。
- `npm i -g wrangler` (≥ 3.x)，本机执行 `wrangler login`。
- `rustup target add wasm32-unknown-unknown`（仅在本机部署 backend 才需要）。
- Flutter stable（与 CI 的 `subosito/flutter-action@v2` channel: stable 对齐）。
- (iOS) Apple Developer 账号 + 一台 Mac + Xcode。免费 Personal Team 也可以但每 7 天重签；Apple Developer Program (USD 99/年) 可签 365 天。

### Cloudflare API token

在 Cloudflare dashboard → My Profile → API Tokens → Create Token，使用 "Edit Cloudflare Workers" 模板，并加上以下权限：

- Account → Workers Scripts → Edit
- Account → Workers Routes → Edit
- Account → D1 → Edit
- Account → Cloudflare Pages → Edit
- Account → Account Settings → Read
- Zone → Workers Routes → Edit（如要用自定义域名）
- Zone → DNS → Edit（同上）

记录两个值：

- `CLOUDFLARE_API_TOKEN`：刚创建的 token。
- `CLOUDFLARE_ACCOUNT_ID`：dashboard 右下角，或 `wrangler whoami`。

把两者写入仓库 GitHub Secrets（Settings → Secrets and variables → Actions）。在写入之前 `pages.yml` / `backend.yml` 的 deploy job 都会自动跳过，CI 仍然绿色（见 `deploy-config` gate）。

可选 GitHub Variables：

- `CLOUDFLARE_PAGES_PROJECT`：Pages 项目名。默认 `naviwealth-web`。

## Web — Cloudflare Pages

### 1. 创建 Pages 项目（一次）

```bash
cd apps/mobile
wrangler pages project create naviwealth-web --production-branch main
```

或者在 dashboard → Workers & Pages → Create → Pages → Direct Upload 创建同名项目。

> 不要选 "Connect to Git" 让 Cloudflare 自己拉源码构建：本仓库的 web 构建依赖 `tool/setup-drift-web.sh`（拉 `sqlite3.wasm`、编译 drift worker）和 `tool/build-cn-fonts.sh`（pyftsubset 中文字体），这些工具链在 Pages 默认构建容器里没有。我们在 GitHub Actions 里跑构建，再用 `wrangler pages deploy` 上传产物。

### 2. 自定义域名 + SSL

1. dashboard → Workers & Pages → naviwealth-web → Custom domains → Set up a custom domain。
2. 输入 `finance.zsh.dev`（或你自己的子域名），Cloudflare 会自动添加 CNAME 并签免费 SSL。Cloudflare 控的域名无需额外操作；外部 DNS 需要手动加 CNAME 指向 `<project>.pages.dev`。
3. 等待证书签发（一般 1–5 分钟）。

### 3. 自动部署

`.github/workflows/pages.yml` 已经接好。配置好 secrets 后：

- 推到 `main` → 生产部署。
- PR → preview 部署（Cloudflare 生成 `<branch>.<project>.pages.dev` 预览 URL）。

PR 上不会自动评论 preview 链接（需要的话见 [跟进](#跟进) 一节）。在 Pages dashboard → Deployments 查看。

### 4. 验证 PWA / SPA

部署后人工验证一遍：

- `https://<domain>/` 加载首屏。
- 直接访问 `https://<domain>/analytics` 不 404（`_redirects` 把未命中的路径回退到 `/index.html`）。
- DevTools → Application → Manifest 显示 NaviWealth、图标齐全。
- DevTools → Application → Service workers 看到 `service_worker.js` 已 `activated`。
- 离线模式刷新仍能进入 shell（service worker shell-cache 命中）。
- 推一个空 commit 后等几分钟再刷页面，应弹出 "有新版本" 提示（`naviwealthPwa` 桥接，见 `apps/mobile/web/index.html` 与 `lib/core/pwa/`）。

### 5. 体积监控

`pages.yml` 在每次构建后跑 `apps/mobile/tool/check-web-bundle-size.sh`：

- 正常：打印 `main.dart.js` / `flutter.js` / `flutter_bootstrap.js` 的 raw 与 gzip-9 体积。
- 失败：`main.dart.js` gzip-9 超过 900 KB（`WEB_BUNDLE_BUDGET_BYTES`，默认值给当前 ~821 KB 留 ~10% headroom）。

回归时优先把新引入的重依赖 `deferred as` 推回路由懒加载，而不是抬高上限。基线与策略写在 `apps/mobile/docs/web-bundle.md`。

`mobile.yml` 的 `build-web` job 也跑同一个脚本，所以 PR 阶段就会拦住溢出。

## Backend — Cloudflare Workers + D1

### 1. 创建 D1 数据库（一次）

```bash
cd apps/backend
wrangler d1 create naviwealth
# 输出里会有一行：database_id = "<uuid>"
```

把 `database_id` 替换到 `wrangler.toml` 的 `[[d1_databases]]` 块里（仓库里目前已经填了一个 ID — 如果不是你的账号，必须替换）。

### 2. 应用迁移

```bash
wrangler d1 migrations apply naviwealth --remote
```

`--remote` 是 prod；省略则在本地 `wrangler dev` 的 SQLite 模拟器里跑。新增迁移落在 `apps/backend/migrations/` 即可，命名沿用 `NNNN_xxx.sql`，迁移引擎按字母序应用一次。

### 3. 配置 secrets

```bash
# HS256 JWT 签名 key（FIR-29）
openssl rand -hex 32 | wrangler secret put JWT_SECRET

# 行情 / AI Key（按需启用）
wrangler secret put ANTHROPIC_API_KEY
wrangler secret put MARKET_API_KEY
```

`wrangler secret list` 验证。secret 不会出现在 `wrangler.toml` 或 git 里。

> 单用户没有注册端点，第一个用户记录直接 SQL 写入：
>
> ```bash
> wrangler d1 execute naviwealth --remote --command "INSERT INTO users(id, email, password_hash) VALUES ('<uuid>', '<email>', '<argon2-hash>');"
> ```
>
> argon2 hash 可以用 `cargo run --bin hash` (TODO，现没有) 或本地任何 argon2 CLI（`argon2 'pw' -e -id -t 2 -m 16 -p 1`）。

### 4. 部署

```bash
wrangler deploy
```

或者就让 `.github/workflows/backend.yml` 的 `deploy` job 跑：推到 `main` 自动 `wrangler deploy`，PR 自动 `wrangler versions upload`（生成 preview 但不接管流量）。

### 5. 自定义子域名（可选）

如果想把 worker 挂在 `api.zsh.dev`：

1. 把 `zsh.dev` 加到 Cloudflare 同一个账号下，DNS 由 Cloudflare 托管。
2. 在 `wrangler.toml` 末尾追加：

   ```toml
   [[routes]]
   pattern = "api.zsh.dev/*"
   zone_name = "zsh.dev"
   custom_domain = true
   ```

3. `wrangler deploy`。Cloudflare 会自动签 SSL 并把 `api.zsh.dev` 解到这个 worker。
4. 客户端的 `apiBaseUrl` 改到新域名（`apps/mobile/lib/core/network/...` 的 endpoint 配置；用对应的 dart-define 或 `--dart-define-from-file`）。

无需 ICP（不公开发布）。

### 6. 健康检查

```bash
curl https://naviwealth-backend.<account>.workers.dev/health
curl https://naviwealth-backend.<account>.workers.dev/health/db
```

两者都应 `200 OK`，后者返回 D1 ping 时间。

### 7. 监控

- **Cloudflare Analytics**（默认开启，免费）：dashboard → Workers → naviwealth-backend → Analytics。看 invocations / error rate / CPU time 即可。
- **Real-time logs**：`wrangler tail naviwealth-backend --format pretty`。
- **Sentry（可选）**：`apps/backend/src/error.rs` 里把 panic / 5xx 转成事件发到 Sentry HTTP ingest。免费个人额度足够单用户使用；token 通过 `wrangler secret put SENTRY_DSN` 注入。当前代码里还没接，暂列为 follow-up（见 [跟进](#跟进)）。

## 移动端

### iOS 个人 sideload

```bash
cd apps/mobile
flutter build ios --release
open ios/Runner.xcworkspace
```

Xcode 内：

1. Runner → Signing & Capabilities → Team 选个人 Apple ID 或 Apple Developer Program team。
2. Bundle Identifier 改唯一字串（如 `dev.zsh.naviwealth`）。
3. 选实体 iPhone 为目标设备，cmd+R 安装。
4. 第一次启动：iPhone → 设置 → 通用 → VPN 与设备管理 → 信任开发者证书。

证书有效期：

- 免费 Personal Team：7 天，到期需重新跑 `cmd+R`。
- Apple Developer Program (USD 99/年)：365 天。

### Android release APK

打 tag 触发 `release.yml`，自动构建并把 `app-release.apk` + `app-release.aab` 上传到 GitHub Release：

```bash
./tool/bump-version.sh mobile 0.1.0
git push origin HEAD --follow-tags
```

`release.yml` 里 `flutter build apk --release` 用项目默认签名（debug keystore）；要换成正式 keystore 见 Flutter 官方文档（`apps/mobile/android/key.properties` + `app/build.gradle.kts`）。仅自用，调试签名也能装。

下载 / 二维码安装：

```bash
gh release view mobile-v0.1.0 --json assets | jq -r '.assets[] | select(.name | endswith(".apk")) | .url'
```

把这个 URL 用 `qrencode -o /tmp/apk.png "<url>"` 生成二维码，手机相机扫一下直装。Android 7+ 需在系统设置里给浏览器开 "允许安装未知来源" 一次性权限。

## 快速回放

迁移机器或重置环境后的最短路径：

```bash
# 0. 拉仓库 + 工具
git clone <repo>
npm i -g wrangler
rustup target add wasm32-unknown-unknown

# 1. 登录 Cloudflare
wrangler login

# 2. Backend
cd apps/backend
# 如果是新账号，先 wrangler d1 create + 改 database_id
wrangler d1 migrations apply naviwealth --remote
openssl rand -hex 32 | wrangler secret put JWT_SECRET
wrangler deploy

# 3. Web (Pages)
cd ../mobile
flutter pub get
tool/setup-drift-web.sh
tool/build-cn-fonts.sh
flutter build web --release --no-source-maps --tree-shake-icons
tool/check-web-bundle-size.sh
wrangler pages deploy build/web --project-name=naviwealth-web --branch=main
```

之后推到 GitHub `main` 即可让 GitHub Actions 接管。

## 跟进

下面这些不是上线 v0.1 的阻塞项，但都是迁到自己域名后值得做的小事：

- **PR preview 评论**：Cloudflare wrangler-action 输出 deployment URL，把它评论回 PR（`gh pr comment` 或 `marocchino/sticky-pull-request-comment`）。
- **Sentry**：在 `apps/backend/src/error.rs` 接 Sentry HTTP DSN，移动端走 `sentry_flutter`。一次性接好，后面崩溃不再靠口口相传。
- **首签用户落库脚本**：把上面的 D1 INSERT 包成 `tool/seed-user.sh`，省去手算 argon2。
- **CSP**：当前 `_headers` 只设了基础安全头。Flutter 在 `index.html` 内联了 PWA 桥脚本，做严格 CSP 需要把那段脚本搬到外置文件并 hash。延后到首次安全 review 时再做。
