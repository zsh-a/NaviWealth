# NaviWealth Mobile (Flutter)

跨端三平台 App（iOS / Android / Web）。本 README 覆盖工程基线；功能架构详见仓库根目录的 [`CLAUDE.md`](../../CLAUDE.md)。

## 运行

```bash
flutter pub get
flutter run                              # 默认设备
flutter test
flutter analyze --fatal-infos
flutter build web --release --pwa-strategy=none
flutter build apk --debug
flutter build ios --debug --no-codesign  # macOS only
```

仅 Web 端需要的一次性资源准备：

```bash
tool/setup-drift-web.sh    # sqlite3.wasm + drift_worker.dart.js
tool/build-cn-fonts.sh     # app-cn-base.woff2 + app-cn-ext.woff2（CN 字体子集）
```

> Web 字体子集化的细节见 [`docs/design/13-web-fonts.md`](docs/design/13-web-fonts.md)。`build-cn-fonts.sh` 自动扫描 `lib/` 中文字符并产出 ≤250 KB 首屏 woff2，CI 在 `flutter build web` 之前会重新构建。

## 目录结构

```
lib/
├── app/             MaterialApp、go_router、bootstrap、route guards、master-detail layout
├── core/            横切关注点：async / auth / backup / command_palette / config /
│                    format / haptics / logging / perf / pwa / security / shortcuts / sync
├── data/            audit / db (Drift) / domain (freezed models) / market /
│                    repositories / securities_catalog
├── domain/          纯领域服务：entities / services / values
├── features/        功能模块（feature-first，14 个）：accounts / activity / ai_chat /
│                    analytics / assets / auth / expense / fire / home / investment /
│                    liabilities / rebalance / settings / shared
├── design_system/   W3C tokens / 主题 / 图表 / 通用 widgets（基于 Forui）
└── l10n/            en + zh ARB
```

每个 feature 内部按 `ui/`（或 `presentation/`）/ `data/` / `domain/` 组织。新增功能默认进入 `lib/features/<feature>/`。

## 关键依赖

| 用途 | 包 |
|----|----|
| 状态管理 | `flutter_riverpod` + `riverpod_annotation` |
| 路由 | `go_router`（PathUrlStrategy、深链路、Web code-splitting） |
| UI 组件 | `forui`（FCard / FButton / FTheme(zinc)） |
| 数据模型 | `freezed` + `json_serializable` |
| 本地存储 | `drift` + `drift_flutter`（Web 走 sqlite3 wasm） |
| HTTP | `dio` |
| i18n / 数字货币 | `intl` |
| 日志 | `logger` |

## Web 路由

使用 **Path URL strategy**（`/accounts` 而非 `/#/accounts`）。`bootstrap()` 调用 `usePathUrlStrategy()`；部署到 Cloudflare Pages 时需把未匹配路径 fallback 到 `index.html`，否则刷新子路由会 404。

`web/index.html` 的 `<base href="$FLUTTER_BASE_HREF">` 由 `flutter build web --base-href=...` 在构建时替换，默认 `/`。手动验证清单见 [`../../docs/web-routing.md`](../../docs/web-routing.md)。

## Web PWA / 离线 Shell

`web/service_worker.js` 是手写 SW，替换 Flutter 默认的 `flutter_service_worker.js`。Build Web 时 **必须** 关闭 Flutter 自带 SW：

```bash
flutter build web --release --pwa-strategy=none
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

1. `analyze + test (coverage)` — `dart format --set-exit-if-changed`、`flutter analyze --fatal-infos`、`flutter test --coverage --exclude-tags=golden`、Codecov 上传
2. `golden regression (mobile)` — `flutter test test/golden --tags=golden`，PR 上 byte-diff 失败
3. `build web` — `flutter build web --release --pwa-strategy=none`

Android / iOS 构建在 `release.yml` 里跟着 tag 跑，不属于 PR 必需 check。
