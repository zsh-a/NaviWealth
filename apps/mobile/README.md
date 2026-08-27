# NaviWealth Mobile (Flutter)

跨端三平台 App（iOS / Android / Web），Personal LifeOS 的客户端。本 README 覆盖工程基线；功能架构详见仓库根目录的 [`docs/index.md`](../../docs/index.md) 和 [`CLAUDE.md`](../../CLAUDE.md)。

## 运行

```bash
flutter pub get
flutter run                              # 默认设备
flutter test
flutter analyze --fatal-infos
flutter build web --release
flutter build apk --debug
flutter build appbundle --release --target-platform android-arm64 \
  --android-project-arg=naviwealth-arm64-only=true
flutter build ios --debug --no-codesign  # macOS only
```

Android release 产物仅打包 `arm64-v8a`，并且必须通过 native payload、
非 arm64 ABI 排除与 16 KiB page-size 检查：

```bash
../../tool/check-android-native-libs.sh build/app/outputs/bundle/release/app-release.aab
../../tool/check-android-native-libs.sh build/app/outputs/flutter-apk/app-release.apk
```

仅 Web 端需要的一次性资源准备：

```bash
tool/setup-drift-web.sh    # sqlite3.wasm + drift_worker.dart.js
tool/build-cn-fonts.sh     # app-cn-base.woff2 + app-cn-ext.woff2（CN 字体子集）
```

macOS 上可运行固定模型和普通话 WAV 的原生 ASR 回归。脚本会将文件缓存到
指定目录、逐个校验 SHA-256，并断言生产流式识别配置的完整转录结果：

```bash
tool/run-asr-native-smoke.sh .cache/asr-native-smoke
```

> Web 字体子集化的细节见 [`docs/design/13-web-fonts.md`](docs/design/13-web-fonts.md)。`build-cn-fonts.sh` 自动扫描 `lib/` 中文字符并产出 ≤335,000 B（约 327 KiB）的首屏 woff2，CI 在 `flutter build web` 之前会重新构建。

## 目录结构

```
lib/
├── app/                   启动、路由、域注册（DomainPack）、组合根、Shell chrome
│   ├── bootstrap.dart     Provider overrides 和 Shell 组合
│   ├── domain_packs.dart  生产域清单（Finance / Health / Knowledge / Execution）
│   ├── routing/            外层 dock Shell + 域路由
│   └── shell/              多域导航 chrome
├── core/                  跨域基础设施（域中立）
│   ├── ai/                运行时契约、设备端 agent loop、本地记忆、嵌入、组合接缝
│   ├── auth/              JWT / session / 域启用（DomainScope）
│   ├── persistence/       Drift adapter 和共享表（含 health / knowledge / execution 表声明）
│   ├── shell/             多域 IA 原语（DomainShell spec）
│   ├── sync/              Sync v3 行状态客户端、accepted ack 与域 generation
│   ├── lifeos/            DomainPack 注册契约
│   ├── background/        后台任务调度
│   ├── notifications/     通知通道
│   ├── audit/             域中立事件日志
│   ├── backup/            备份与恢复
│   ├── command_palette/   跨域命令面板
│   └── ...                config / format / haptics / logging / perf / pwa / security
├── features/              域业务代码（feature-first）
│   ├── finance/           FinanceOS 组合根、数据、域模型
│   ├── health/            HealthOS 数据、UI、AI 工具、Agent（用户启用）
│   ├── knowledge/         KnowledgeOS 数据、UI、AI 工具、Agent（用户启用）
│   ├── execution/         ExecutionOS 数据、UI、AI 工具、Agent（用户启用）
│   ├── ai_chat/           跨域 AI 对话 UI
│   ├── settings/          设置（含域启用页）
│   └── life/              跨域 Life hub
├── design_system/         W3C 设计令牌 / 主题 / 图表 / 通用 widgets（Forui + 本地组件）
└── l10n/                  en + zh ARB
```

FinanceOS 及各可选域按 `ui/`、`data/`、`domain/` 组织；域级目录还可包含 `ai_tools/`、`agents/`、`composition/`。新增域功能默认进入 `lib/features/<domain>/`，跨域装配留在 `lib/app/`。

## 域架构

NaviWealth 是 Personal LifeOS，通过 `DomainPack` 注册多域：

| 域 | 启用方式 | Shell 标签页 | AI 工具 | Agent |
|---|---|---|---|---|
| FinanceOS | 始终开启 | Today / Activity / Wealth / Plan | 35 设备工具 | Weekly Wealth / Cashflow Anomaly / FIRE Drift / Options Risk |
| HealthOS | 用户启用 | Today / Trend / Plan | 7 设备工具 | Recovery Alert / Weekly Summary |
| KnowledgeOS | 用户启用 | Inbox / Library / Review | 16 设备工具 | Review / Assumption / Contradiction / Inbox Triage |
| ExecutionOS | 用户启用 | Today / Commitments / Review | 8 设备工具 | Due Action / Review |

跨域判断由 app-level `DailyNavigatorAgent` 完成；领域 Agent 只生成可验证的
事实和 finding，不进行 agent-to-agent 调用。

域启用状态通过 `domainOptInsProvider` 管理，所有工具、提示、Shell spec、Agent 和命令面板条目从 active packs 派生。

## 关键依赖

| 用途 | 包 |
|----|----|
| 状态管理 | `flutter_riverpod` |
| 路由 | `go_router`（PathUrlStrategy、深链路、Web code-splitting） |
| UI 组件 | `forui` + 本地设计系统（`SoftCard` / `AppSection` / `FButton` / `AppTheme`） |
| 数据模型 | `freezed` + 显式 JSON / Drift 适配器 |
| 本地存储 | `drift` + `drift_flutter`（Web 走 sqlite3 wasm） |
| 健康数据 | `package:health`（HealthKit / Health Connect，仅原生端） |
| 原生嵌入 | `flutter_rust_bridge`（EmbeddingGemma ONNX） |
| HTTP | `dio` |
| i18n / 数字货币 | `intl` |
| 日志 | `talker` + `talker_dio_logger` |

## 设备端 AI

AI 仅在设备端运行，无后端中继：

- 用户自带 LLM key（Anthropic 或 OpenAI 兼容端点），存储为 `LlmProfile`
- `DeviceAgentLoop` 在端侧完成 prompt 组装 / provider 调用 / tool dispatch / proposal
- 工具注册聚合：`deviceToolsProvider`，基于 active `DomainPack`s
- 提示聚合：`systemPromptBlocksProvider`，同样基于 active packs
- 写入工具返回 `ProposalEnvelope` 或要求显式确认
- Web 端无 AI 运行时

## Web 路由

使用 **Path URL strategy**（`/wealth` 而非 `/#/wealth`）。`bootstrap()` 调用 `usePathUrlStrategy()`；部署到 Cloudflare Pages 时需把未匹配路径 fallback 到 `index.html`，否则刷新子路由会 404。

`web/index.html` 的 `<base href="$FLUTTER_BASE_HREF">` 由 `flutter build web --base-href=...` 在构建时替换，默认 `/`。手动验证清单见 [`../../docs/development/web-routing.md`](../../docs/development/web-routing.md)。

## Web PWA / 离线 Shell

`web/service_worker.js` 是手写 SW，替换 Flutter 默认的 `flutter_service_worker.js`。Flutter 自带 SW 的关闭不再依赖已废弃的 `--pwa-strategy` flag（[flutter#156910](https://github.com/flutter/flutter/issues/156910)）——改由自定义模板 `web/flutter_bootstrap.js` 实现：它调用 `_flutter.loader.load()` 时不传 `serviceWorkerSettings`，Flutter 因此不会注册自带 SW。普通构建即可：

```bash
flutter build web --release
```

| 流量 | 策略 | 缓存桶 |
|------|------|--------|
| 导航请求 (`mode: navigate`) | Network-First → 离线回退 `index.html` | `nw-shell` |
| Shell（`index.html` / `flutter_bootstrap.js` / `manifest.json`） | Cache-First + 后台刷新 | `nw-shell` |
| WASM（`sqlite3.wasm` / `drift_worker.dart.js`） | Cache-First, 长期 | `nw-wasm` |
| `GET /api/*` | Network-First → 离线 fallback (`X-NaviWealth-Offline: 1`) | `nw-api` |
| 其它同源 GET（chunks / 字体 / 图标） | Stale-While-Revalidate | `nw-runtime` |

`SW_VERSION` 是缓存版本号 — **影响 shell 的发布手动 bump**（chunk hash 变化由 hash-busting URL 自动隔离）。`activate` 阶段会清掉所有非当前版本的 `nw-*` 缓存。

更新提醒：`window.naviwealthPwa` 桥接到 Dart 端 `PwaUpdateController`（`lib/core/pwa/`）；新版本就绪时底部出现 `PwaUpdateBanner`，点击「立即刷新」会发送 `SKIP_WAITING` 并整页 reload。

## Cloudflare Pages

`wrangler.toml` 声明 Pages 项目名和构建输出目录，`web/_redirects` 负责把刷新后的 SPA 子路由 fallback 到 `index.html`，`web/_headers` 给 service worker / shell 文件设置 no-cache，并给静态资源设置长缓存。

本地直传：

```bash
flutter build web --release
wrangler pages deploy --branch main
```

## 渲染策略

走 Flutter 默认 Web 渲染器（CanvasKit on desktop，HTML/auto on mobile）。Wasm 模式 dry-run 已通过；后续按需加 `--wasm`。

## 单包（非 melos）

`apps/mobile` 是单一 Flutter package。当前没有共享 pure-Dart 工具包的需求，暂不引入 melos。

## 代码规范

- `analysis_options.yaml` 启用 strict-casts / strict-inference / strict-raw-types，并打开 `prefer_const_*`、`avoid_dynamic_calls`、`avoid_print`、`require_trailing_commas`。
- 生成代码（`*.g.dart` / `*.freezed.dart`）已从 lint 排除。
- 提交前钩子见仓库根 `tool/install-hooks.sh`。

## CI

`.github/workflows/mobile.yml` 在 `apps/mobile/**` 变更时触发：

1. `static checks` — `flutter analyze --fatal-infos`、生成代码 freshness、l10n 与架构边界检查
2. `test shard 0..3 / 4` — 普通 unit/widget 测试
3. `responsive task-flow goldens` — PR 上执行响应式 byte-diff
4. `golden regression (mobile)` — `main` 上执行完整 Linux golden 回归
5. `build Android arm64 AAB` — `main` 上执行 release cross-compile、native payload 完整性与 16 KiB ELF 对齐检查
6. `build web` — `main` 上执行 `flutter build web --release`

`.github/workflows/asr-native-smoke.yml` 独立运行真实 `sherpa_onnx` 推理：
语音运行时相关变更会在 PR/main 上触发，同时每周一和手动调度也会执行。
模型与 WAV 均固定 SHA-256；诊断仅输出音频时长、推理时长和实时因子，不
记录转录文本。

架构 lint gates（CI 和本地均可运行）：

```bash
./tool/lint-no-feature-in-shared.sh      # core/design_system 不反向依赖 features
./tool/lint-cross-feature-imports.sh     # feature 间无跨域导入
./tool/lint-finance-domain-data-imports.sh # Finance domain 不依赖 data/repository 层
./tool/lint-domain-neutral-contracts.sh  # 域中立契约不含域类型
./tool/lint-frb-llm-entrypoints.sh       # 生产 LLM/agent 入口保持 FRB seam
./tool/check-ai-contract-wire-enums.sh   # AI wire enum fixture 一致
```

Android / iOS 构建在 `release.yml` 里跟着 tag 跑，不属于 PR 必需 check。
