# NaviWealth

个人财务管理软件 — 全资产类别支持、投资跟踪、组合分析、FIRE 追踪、再平衡提醒、AI 财务助手。

跨端：iOS / Android / Web。本地优先 + 云同步（Cloudflare Workers + Rust + D1）。

---

## 仓库结构

```
naviwealth/
├── apps/
│   ├── mobile/      # Flutter 三端 App（FIR-2 / FIR-14 ...）
│   └── backend/     # Cloudflare Workers + Rust（FIR-28 / FIR-32 / FIR-36 ...）
└── .github/
    ├── workflows/
    │   ├── mobile.yml     # analyze / test / 覆盖率 / build (web/android/ios)
    │   ├── backend.yml    # cargo fmt / clippy / check / cargo audit
    │   ├── security.yml   # 每周扫描：dart pub outdated / cargo audit / trivy fs
    │   └── release.yml    # 标签触发：mobile-vX.Y.Z / backend-vX.Y.Z
    ├── dependabot.yml     # Actions / pub / cargo 依赖自动更新
    └── CODEOWNERS         # 默认评审人
└── .github/workflows/
    ├── mobile.yml   # Flutter analyze + test + web build
    └── backend.yml  # cargo fmt / clippy / check + wrangler deploy（PR preview / main prod）
```

任务编号 `FIR-N` 对应 Multica 看板上的 issue。

---

## 本地开发

### Flutter

```bash
cd apps/mobile
flutter pub get
flutter test
flutter run                   # 默认设备
tool/setup-drift-web.sh       # Web 端运行前一次：拉取 sqlite3.wasm + 编译 drift worker
flutter run -d chrome         # Web
```

`tool/setup-drift-web.sh` 把 `sqlite3.wasm`（与 pubspec.lock 中 `sqlite3` 版本对齐）和编译好的 `drift_worker.dart.js` 落到 `apps/mobile/web/`。两个产物都被 `.gitignore`，CI 在 `build-web` 任务里会自动重新生成。

### 后端（Cloudflare Workers + Rust）

需要 `rustup target add wasm32-unknown-unknown` 和 `npm i -g wrangler`。

```bash
cd apps/backend
cargo check --target wasm32-unknown-unknown
wrangler dev                  # 本地 + D1 模拟
wrangler deploy               # 推到 *.workers.dev
```

健康检查：

- `GET /health`     — 服务存活
- `GET /health/db`  — D1 绑定可达

Worker 端的运行时 secret：

```bash
cd apps/backend
wrangler secret put JWT_SECRET   # HS256 签名 key（FIR-37 鉴权用）
```

CI / 部署所需的 GitHub 仓库 Secrets（在 `Settings → Secrets and variables → Actions` 配置；未配置时 CI 仍通过，deploy job 自动跳过）：

- `CLOUDFLARE_API_TOKEN` — 具备 Workers Deploy 权限的 API token
- `CLOUDFLARE_ACCOUNT_ID` — Cloudflare 账户 ID

PR 推送会跑 `wrangler versions upload`（生成 preview URL，不接管流量）；合并到 `main` 会跑 `wrangler deploy`（生产）。

---

## 技术决策（来自 FIR-1 讨论）

- 三端：iOS / Android / Web
- 同步：最终一致性（前台立即拉取 + 30s 轮询，无 WebSocket）
- 后端：Cloudflare Workers + Rust（workers-rs），D1 存储
- 加密：暂不做端到端加密（仅个人使用）
- 认证：单用户 JWT，无注册端点
- 不上架：Web 走 Cloudflare Pages，移动端 sideload / TestFlight 内部组

---

## Git Hooks

```bash
./tool/install-hooks.sh
```

安装一次后，提交时会对暂存的 `apps/mobile/**.dart` 跑 `dart format --set-exit-if-changed` 与 `flutter analyze --fatal-infos`。

## 贡献流程

1. 在 Multica 看板上认领任务（FIR-N）。
2. 从 `main` 拉分支：`feature/fir-<N>-<short>`。
3. 提交并推送，CI 通过后开 PR。

`main` 分支的保护规则与必需检查见 [`docs/branch-protection.md`](docs/branch-protection.md)。

---

## CI / 质量门禁

| 流水线 | 触发条件 | 关键步骤 |
| --- | --- | --- |
| `mobile` | 修改 `apps/mobile/**` 或 workflow | format / analyze / build_runner 一致性 / **test --coverage** / Codecov / web+android+ios 构建 |
| `backend` | 修改 `apps/backend/**` 或 workflow | cargo fmt / clippy / check (wasm32) / **cargo audit** |
| `security` | 每周一 03:17 UTC + 手动 + lockfile 变更 | `dart pub outdated` / `cargo audit` / Trivy 文件系统扫描 |
| `release` | tag 推送 `mobile-vX.Y.Z` / `backend-vX.Y.Z` | 版本号写入源文件 → 构建 → 创建 GitHub Release |

覆盖率阈值在 [`codecov.yml`](codecov.yml) 中配置：项目目标 60%（mobile flag），diff（patch）目标 70%。`*.g.dart` / `*.freezed.dart` 不计入。

依赖更新由 Dependabot 周一自动开 PR，见 [`.github/dependabot.yml`](.github/dependabot.yml)。

### 版本号约定

- **语义化版本** + **构建号**：`SEMVER+BUILD`
- 构建号 = 该 tag 在 git 历史上的提交计数（`git rev-list --count <tag>`），保证单调递增、可从历史复现
- 发版示例：

  ```bash
  ./tool/bump-version.sh mobile 0.2.0
  git push origin HEAD --follow-tags
  ```

  会修改 `pubspec.yaml`、提交、打 tag，并由 `release.yml` 在构建时把 `version: 0.2.0+1` 重写成 `0.2.0+<commit-count>`。
