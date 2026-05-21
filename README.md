# NaviWealth

个人财务管理软件 — 全资产类别支持、投资跟踪、组合分析、FIRE 追踪、再平衡提醒、AI 财务助手。

跨端：iOS / Android / Web。本地优先 + 云同步（Cloudflare Workers + Rust + D1）。

---

## 仓库结构

```
naviwealth/
├── apps/
│   ├── mobile/              Flutter 三端 App
│   └── backend/             Cloudflare Workers + Rust
├── tool/                    版本工具、git hooks、证券目录构建
├── docs/                    协议、监控、路线图、兼容矩阵
└── .github/
    ├── workflows/
    │   ├── mobile.yml          analyze + test (coverage) / golden regression / build web / Pages deploy
    │   ├── backend.yml         fmt + clippy + check (wasm32) / deploy / preview
    │   └── release.yml         tag vX.Y.Z 触发：版本写入 + APK Release + Pages / 后端部署
    ├── dependabot.yml          Actions / pub / cargo 依赖自动更新
    └── CODEOWNERS              默认评审人
```

任务编号 `FIR-N` 对应 Multica 看板。详细架构见 [`CLAUDE.md`](CLAUDE.md)。

---

## 本地开发

完整步骤见 [`docs/local-development.md`](docs/local-development.md)；以下是速通版本。

### Flutter

```bash
cd apps/mobile
flutter pub get
flutter test
flutter run                            # 默认设备
flutter run -d chrome                  # Web
```

仅 Web 端需要的一次性资源准备（产物在 `.gitignore`，CI 在 `build web` 任务里会自动重建）：

```bash
apps/mobile/tool/setup-drift-web.sh    # sqlite3.wasm + drift_worker.dart.js
apps/mobile/tool/build-cn-fonts.sh     # CN font 子集
```

### 后端（Cloudflare Workers + Rust）

需要 `rustup target add wasm32-unknown-unknown` 和 `npm i -g wrangler`。

```bash
cd apps/backend
cargo check --target wasm32-unknown-unknown
wrangler dev                           # 本地 + D1 模拟
wrangler deploy                        # 生产
```

健康检查：`GET /health`、`GET /health/db`。

#### Secrets

Worker 运行时（`wrangler secret put`）：

- `JWT_SECRET` — HS256 签名 key
- `ANTHROPIC_API_KEY` — AI 代理

GitHub Actions（`Settings → Secrets and variables → Actions`）：

- `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` — Workers + Pages 部署（未配置时 deploy job 自动跳过）
- `CODECOV_TOKEN` — 覆盖率上传（私有仓库必填）
- `KEYSTORE_BASE64` + 签名 key — Android 签名

PR 推送 → `wrangler versions upload`（生成 preview URL，不接管流量）；合并 `main` → `wrangler deploy`（生产）。

---

## 技术决策

- 三端：iOS / Android / Web
- 同步：最终一致性（前台立即拉取 + 30s 轮询，无 WebSocket）
- 后端：Cloudflare Workers + Rust（workers-rs），D1 存储
- 加密：暂不做端到端加密（仅个人使用）
- 认证：单用户 JWT（HS256），无注册端点
- 不上架：Web 走 Cloudflare Pages，移动端 sideload / TestFlight

---

## Git Hooks

```bash
./tool/install-hooks.sh
```

提交时对暂存的 `apps/mobile/**.dart` 跑 `dart format --set-exit-if-changed` 与 `flutter analyze --fatal-infos`。

## 贡献流程

1. 在 Multica 看板上认领任务（FIR-N）。
2. 从 `main` 拉分支：`feature/fir-<N>-<short>`。
3. 提交并推送，CI 通过后开 PR。

`main` 的保护规则与必需检查见 [`docs/branch-protection.md`](docs/branch-protection.md)。

---

## CI / 质量门禁

| 流水线 | 触发 | 关键步骤 |
|--------|------|----------|
| `mobile` | `apps/mobile/**` | format / analyze / build_runner 一致性 / **test --coverage** / Codecov / golden regression / web 构建 / Pages 部署 |
| `backend` | `apps/backend/**` | fmt / clippy / check (wasm32) / deploy 或 PR preview |
| `release` | `vX.Y.Z` tag + 手动 dispatch | 版本写入 → APK GitHub Release → Pages 部署 → 后端部署 |

覆盖率阈值（[`codecov.yml`](codecov.yml)）：项目 60%、patch 70%。`*.g.dart` / `*.freezed.dart` 不计入。

依赖更新由 Dependabot 周一自动开 PR（[`.github/dependabot.yml`](.github/dependabot.yml)）。

### 版本号

- **语义化版本** + **构建号**：`SEMVER+BUILD`
- 构建号 = 该 tag 在 git 历史上的提交计数（`git rev-list --count <tag>`），单调递增、可从历史复现
- 发版：

  ```bash
  ./tool/bump-version.sh 0.4.1           # 同时改 pubspec.yaml + Cargo.toml，提交并打 tag v0.4.1
  git push origin HEAD --follow-tags     # 触发 release.yml
  ```

  `release.yml` 在构建时把版本号重写成 `0.4.1+<commit-count>`。
