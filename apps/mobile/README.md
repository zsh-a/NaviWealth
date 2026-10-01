# NaviWealth Mobile (Flutter)

Personal LifeOS 的 Flutter 客户端，产品目标平台为 iOS / Android / Web。当前自动发布 Android，Web 由 CI 构建并部署；macOS 支持本地开发及部分原生能力验证，iOS 原生分发仍是路线图中的触发项目。本 README 覆盖工程基线；功能架构详见仓库根目录的 [`docs/index.md`](../../docs/index.md) 和 [`CLAUDE.md`](../../CLAUDE.md)。

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
tool/build-latin-fonts.sh  # Latin 字体资源
```

macOS 上可运行固定模型和普通话 WAV 的原生 ASR 回归。脚本会将文件缓存到
指定目录、逐个校验 SHA-256，并断言生产流式识别配置的完整转录结果：

```bash
tool/run-asr-native-smoke.sh .cache/asr-native-smoke
```

> Web 字体准备与验证见[本地开发](../../docs/development/local-development.md)和[浏览器兼容矩阵](../../docs/development/web-compat-matrix.md)。`build-cn-fonts.sh` 自动扫描 `lib/` 中文字符并产出首屏 woff2，CI 在 `flutter build web` 之前会重新构建。

## 目录结构

```
lib/
├── app/                   启动、路由、域注册（DomainPack）、组合根、Shell chrome
│   ├── bootstrap.dart     首帧前初始化（binding、偏好、formatter、日志）
│   ├── bootstrap/        Provider overrides、首帧后启动与原生模型发现
│   ├── domain_composition.dart 跨域 Provider、Action 与 proposal 组合
│   ├── domain_packs.dart  生产域清单（Finance / Health / Knowledge / Execution）
│   ├── routing/            外层 dock Shell + 域路由
│   └── shell/              多域导航 chrome
├── core/                  跨域基础设施（域中立）
│   ├── ai/                运行时契约、Host 接缝、本地记忆、嵌入、组合接缝
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
│   ├── finance/           FinanceOS 组合根、全部业务切片、数据与域模型
│   ├── health/            HealthOS 数据、UI、AI 工具、Agent（用户启用）
│   ├── knowledge/         KnowledgeOS 笔记、决策、UI、AI 工具（用户启用）
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

| 域 | 启用方式 | Shell 标签页 | Agent |
|---|---|---|---|
| FinanceOS | 始终开启 | Today / Activity / Wealth / Plan | Weekly Wealth / Cashflow Anomaly / FIRE Drift / Options Risk |
| HealthOS | 用户启用 | Today / Trends | Recovery Alert / Weekly Summary |
| KnowledgeOS | 用户启用 | Inbox / Library | — |
| ExecutionOS | 用户启用 | Today / Plans / Review | Due Action / Review |

生产域及工具清单以 [`domain_packs.dart`](lib/app/domain_packs.dart) 和各域 pack 为准。
FinanceOS 规划页包含现金安全、目标与定投，以及按需展开的高级投资工具；
定投创建独立于可选的历史预览。具体行为见
[FinanceOS Domain](../../docs/domains/financeos-domain.md#investment-interaction)。

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

这里的设备端指执行、上下文和凭证所在边界；使用远程 `LlmProfile` 时，推理请求与选定上下文仍会从设备发送给该 provider，并非离线推理。

- 用户自带 LLM key（Anthropic 或 OpenAI 兼容端点），存储为 `LlmProfile`
- Rust Agent Runtime 管理模型调用、ChatTurn 状态、续轮与工具轮次预算；Dart host 组装设备上下文、执行本地工具并处理用户确认
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

默认 `flutter build web --release` 使用 CanvasKit。启用 `--wasm` 时，可用浏览器使用 skwasm，不支持时回退到 CanvasKit；当前常规 Web 构建不启用该选项。

## 单包（非 melos）

`apps/mobile` 是单一 Flutter package。当前没有共享 pure-Dart 工具包的需求，暂不引入 melos。

## 代码规范

- `analysis_options.yaml` 启用 strict-casts / strict-inference / strict-raw-types，并打开 `prefer_const_*`、`avoid_dynamic_calls`、`avoid_print`、`require_trailing_commas`。
- 生成代码（`*.g.dart` / `*.freezed.dart`）已从 lint 排除。
- 提交前钩子见仓库根 `tool/install-hooks.sh`。

## CI

`.github/workflows/mobile.yml` 在 `apps/mobile/**` 变更时触发：

1. `static checks` — `flutter analyze --fatal-infos`、生成代码 freshness、l10n 与架构边界检查
2. `test shard 0..3 / 4` — 按文件分片执行完整普通 unit/widget/flow/integration 测试，每个文件只加载一次
3. `golden regression (mobile)` — PR 执行响应式任务流；`main` 和发布执行完整 Linux golden 回归
4. `build web` — `main` 上并行执行 release 构建；Pages 部署等待静态检查、全部分片及 golden 回归通过

静态检查与普通测试使用字体占位文件，真实截图和 Web 构建通过共享 action
按字体脚本与所需字符集缓存字体。各分片直接写入耗时摘要，仅失败时上传
JSON 事件；Markdown、浏览器测试、设备 harness 和 README 图片维护不再
触发整套移动端检查。README 图片使用本地脚本按需更新。
Android 签名 APK/AAB、native payload 与 16 KiB ELF 检查由 `release.yml`
负责；设备集成测试仍在相关 PR、每周及发布流程运行。

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

`release.yml` 在 tag 发布时运行质量门槛并构建 Android arm64 APK/AAB；其中设备质量门槛复用 `integration-device.yml`。当前没有 iOS tag 构建或分发 job；其验证与分发条件见 [LifeOS 路线图](../../docs/roadmap/roadmap-lifeos.md#triggered-bets)。
