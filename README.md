# NaviWealth

**Personal LifeOS** — 本地优先、多域生活操作系统。FinanceOS（种子域）始终开启；HealthOS、KnowledgeOS、ExecutionOS 用户按需启用。

跨端：iOS / Android / Web。设备端 AI（用户自带 LLM key）+ 云同步（Cloudflare Workers + Rust + D1）。

---

## 域架构

| 域 | 状态 | 核心能力 | 同步前缀 |
|---|---|---|---|
| FinanceOS | 始终开启 | 资产、现金流、FIRE、投资、期权收入 | `fin:` |
| HealthOS | 用户启用 | 睡眠、HRV、恢复信号、晨间简报 | `health:` |
| KnowledgeOS | 用户启用 | 决策记忆、原则、假设、例程、知识回顾 | `know:` |
| ExecutionOS | 用户启用 | 行动、项目、承诺、进展复盘 | `exec:` |

每个域通过 `DomainPack` 注册，贡献：AI 工具、系统提示、Shell 路由、Agent、命令面板条目和标签页路径。新增域只需一个 `DomainPack` 条目。

---

## 仓库结构

```
naviwealth/
├── apps/
│   ├── mobile/              Flutter 三端 App（iOS / Android / Web）
│   │   ├── lib/
│   │   │   ├── app/         启动、路由、域注册、组合根
│   │   │   ├── core/        跨域基础设施（AI / auth / sync / persistence / shell / memory）
│   │   │   ├── features/    域业务代码
│   │   │   │   ├── finance/    FinanceOS 组合与数据
│   │   │   │   ├── health/     HealthOS 数据、UI、AI 工具、Agent
│   │   │   │   ├── knowledge/  KnowledgeOS 数据、UI、AI 工具、Agent
│   │   │   │   ├── execution/  ExecutionOS 数据、UI、AI 工具、Agent
│   │   │   │   └── <slices>/   accounts / assets / cashflow / investment 等
│   │   │   ├── design_system/  设计令牌、主题、图表、可复用组件
│   │   │   └── l10n/           中英文 ARB
│   │   └── native/
│   │       └── lifeos_native/  Rust 嵌入运行时（EmbeddingGemma via flutter_rust_bridge）
│   └── backend/             Cloudflare Workers + Rust + D1
├── tool/                    版本工具、git hooks、证券目录构建、CI lint gates
├── docs/                    MkDocs 文档源：架构、域 SSOT、AI、同步、开发、归档
├── mkdocs.yml               文档站导航与构建配置
├── llms.txt                 LLM 友好的文档入口
└── .github/
    ├── workflows/
    │   ├── mobile.yml          analyze + test / golden / build web / Pages 部署
    │   ├── backend.yml         fmt + clippy + check (wasm32) / deploy / preview
    │   └── release.yml         tag 触发：版本写入 + APK + Pages + 后端部署
    ├── dependabot.yml
    └── CODEOWNERS
```

---

## 技术栈

| 层 | 技术 |
|---|---|
| 前端 | Flutter + Riverpod + go_router + Forui |
| 数据 | Drift (SQLite) + freezed + json_serializable |
| 同步 | Sync v2 行状态 LWW + Hybrid Logical Clock |
| 后端 | Cloudflare Workers (Rust, workers-rs) + D1 |
| AI | 设备端 agent loop（Anthropic / OpenAI 兼容），用户自带 key |
| 嵌入 | Rust EmbeddingGemma-300M ONNX INT8 via flutter_rust_bridge |
| 认证 | 单用户 JWT (HS256)，无注册端点 |
| 部署 | Cloudflare Pages (Web) / sideload + TestFlight (移动端) |

---

## 本地开发

完整步骤见 [`docs/index.md`](docs/index.md) 和 [`docs/development/local-development.md`](docs/development/local-development.md)。

### Flutter

```bash
cd apps/mobile
flutter pub get
flutter test
flutter run                            # 默认设备
flutter run -d chrome                  # Web
```

Web 一次性资源准备：

```bash
apps/mobile/tool/setup-drift-web.sh    # sqlite3.wasm + drift_worker.dart.js
apps/mobile/tool/build-cn-fonts.sh     # CN 字体子集
```

### 后端

```bash
cd apps/backend
cargo check --target wasm32-unknown-unknown
wrangler dev                           # 本地 + D1 模拟
wrangler deploy                        # 生产
```

健康检查：`GET /health`、`GET /health/db`。

### Secrets

Worker 运行时（`wrangler secret put`）：

- `JWT_SECRET` — HS256 签名 key

GitHub Actions（`Settings → Secrets and variables → Actions`）：

- `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` — Workers + Pages 部署
- `CODECOV_TOKEN` — 覆盖率上传（私有仓库必填）
- `KEYSTORE_BASE64` + 签名 key — Android 签名

> LLM API key 是用户自有的，存储在设备端 `LlmProfile` 中，不作为后端 secret。

---

## 架构边界

详细架构见 [`docs/index.md`](docs/index.md)、[`CLAUDE.md`](CLAUDE.md) 和 [`llms.txt`](llms.txt)。关键约束：

- `core/` 保持域中立，不导入 `features/<domain>/`
- 域业务代码在 `features/<domain>/` 下，域之间不互相导入
- `app/` 是组合根，可导入多域来组装路由、工具、Agent
- AI 仅设备端运行，无后端 AI 中继，无云端回落
- Web 构建排除 AI 运行时和 Health 平台集成
- Sync v2 行状态 LWW，后端保持 schema-agnostic

架构文档索引：

| 文档 | 用途 |
|---|---|
| [`docs/architecture/lifeos-architecture-northstar.md`](docs/architecture/lifeos-architecture-northstar.md) | 架构边界与非目标 |
| [`docs/architecture/lifeos-shell.md`](docs/architecture/lifeos-shell.md) | 跨域 Shell SSOT |
| [`docs/decisions/lifeos-decision-2026-05-24.md`](docs/decisions/lifeos-decision-2026-05-24.md) | Phase D ADR |
| [`docs/domains/healthos-domain.md`](docs/domains/healthos-domain.md) | HealthOS 域行为 |
| [`docs/domains/knowledgeos-domain.md`](docs/domains/knowledgeos-domain.md) | KnowledgeOS 域行为 |
| [`docs/domains/executionos-domain.md`](docs/domains/executionos-domain.md) | ExecutionOS 域行为 |
| [`docs/ai/ai-architecture.md`](docs/ai/ai-architecture.md) | 设备端 AI 运行时设计 |
| [`docs/sync/sync-v2.md`](docs/sync/sync-v2.md) | 同步协议 v2 |
| [`docs/roadmap/roadmap-lifeos.md`](docs/roadmap/roadmap-lifeos.md) | 跨域路线图 |

---

## CI / 质量门禁

| 流水线 | 触发 | 关键步骤 |
|--------|------|----------|
| `mobile` | `apps/mobile/**` | format / analyze / build_runner 一致性 / test --coverage / Codecov / golden / web 构建 / Pages 部署 |
| `backend` | `apps/backend/**` | fmt / clippy / check (wasm32) / deploy 或 PR preview |
| `release` | `vX.Y.Z` tag + 手动 dispatch | 版本写入 → APK GitHub Release → Pages 部署 → 后端部署 |

覆盖率阈值（[`codecov.yml`](codecov.yml)）：项目 60%、patch 70%。`*.g.dart` / `*.freezed.dart` 不计入。

架构 lint gates：

```bash
./tool/lint-no-finance-in-core.sh
./tool/lint-cross-feature-imports.sh
./tool/lint-row-family-prefix.sh
./tool/lint-domain-neutral-contracts.sh
./tool/check-tool-descriptors.sh
```

---

## 版本号

- **语义化版本** + **构建号**：`SEMVER+BUILD`
- 构建号 = tag 在 git 历史上的提交计数（`git rev-list --count <tag>`），单调递增
- 发版：

  ```bash
  ./tool/bump-version.sh 0.6.1
  git push origin HEAD --follow-tags     # 触发 release.yml
  ```

---

## Git Hooks

```bash
./tool/install-hooks.sh
```

提交时对暂存的 `apps/mobile/**.dart` 跑 `dart format --set-exit-if-changed` 与 `flutter analyze --fatal-infos`。

## 贡献流程

1. 从 `main` 拉分支：`feature/<short-description>`。
2. 提交并推送，CI 通过后开 PR。

`main` 的保护规则与必需检查见 [`docs/operations/branch-protection.md`](docs/operations/branch-protection.md)。
