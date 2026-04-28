# NaviWealth Mobile (Flutter)

跨端三平台 App（iOS / Android / Web）。本 README 记录工程基线决策（FIR-14）。

## 运行

```bash
flutter pub get
flutter run                   # 默认设备
tool/setup-drift-web.sh       # Web 才需要：sqlite3.wasm + drift_worker.dart.js
tool/build-cn-fonts.sh        # Web 才需要：app-cn-base.woff2 + app-cn-ext.woff2
flutter run -d chrome         # Web (dev server)
flutter test
flutter analyze --fatal-infos
flutter build web --release   # 产物在 build/web
flutter build apk --debug     # Android
flutter build ios --debug --no-codesign  # iOS（需 macOS）
```

> Web 字体子集化（FIR-38）的细节见 [`docs/design/13-web-fonts.md`](docs/design/13-web-fonts.md)。`build-cn-fonts.sh` 自动扫描 `lib/` 中的中文字符并产出 ≤ 250 KB 首屏 woff2，CI 在 `flutter build web` 之前会重新构建。

## 目录结构

```
lib/
├── app/        # MaterialApp、router、bootstrap
├── core/       # 配置、日志、错误处理等横切关注点
├── features/   # 业务模块（feature-first）：home / assets / analytics / settings
└── shared/     # 跨 feature 复用的 UI / 工具
```

新增功能默认进入 `lib/features/<feature>/`，避免按层级（presentation/data/domain）拆分跨 feature 的目录。

## 关键依赖

| 用途 | 包 |
|----|----|
| 状态管理 | `flutter_riverpod` + `riverpod_annotation` |
| 路由 | `go_router`（Web URL 同步、深链路） |
| 数据模型 | `freezed` + `json_serializable` |
| 本地存储 | `drift` + `drift_flutter`（跨平台连接，Web 走 sqlite3 wasm） |
| HTTP | `dio` |
| i18n / 数字货币 | `intl` |
| 日志 | `logger` |

## Web 路由策略

使用 **Path URL strategy**（`/assets` 而非 `/#/assets`）。在 `bootstrap()` 中调用 `usePathUrlStrategy()`，部署时（Cloudflare Pages）需要把未匹配路径 fallback 到 `index.html`，否则刷新子路由会 404。

`web/index.html` 的 `<base href="$FLUTTER_BASE_HREF">` 占位符由 `flutter build web --base-href=...` 在构建时替换；默认 `/` 即可。

## Web PWA / 离线 Shell（FIR-37）

`web/service_worker.js` 是手写的 Service Worker，替换 Flutter 默认的 `flutter_service_worker.js`。Build Web 时 **必须** 关闭 Flutter 自带 SW，否则两者会互相覆盖：

```bash
flutter build web --release --pwa-strategy=none
```

策略一览：

| 流量 | 策略 | 缓存桶 |
|------|------|--------|
| 导航请求 (`mode: navigate`) | Network-First → 离线回退 `index.html` | `nw-shell` |
| Shell (`index.html` / `flutter_bootstrap.js` / `manifest.json`) | Cache-First + 后台刷新 | `nw-shell` |
| WASM (`sqlite3.wasm` / `drift_worker.dart.js`) | Cache-First, 长期 | `nw-wasm` |
| `GET /api/*` | Network-First → 离线 fallback (`X-NaviWealth-Offline: 1`) | `nw-api` |
| 其它同源 GET（hash chunks / 字体 / 图标） | Stale-While-Revalidate | `nw-runtime` |

`SW_VERSION` 常量是缓存版本号 — **在影响 shell 的发布上手动 bump**（chunk hash 变化由 hash-busting URL 自动隔离，不必 bump）。`activate` 阶段会清掉所有非当前版本的 `nw-*` 缓存。

更新提醒：`window.naviwealthPwa` JS 桥接到 Dart 端 `PwaUpdateController`（`lib/core/pwa/`）；新版本就绪时 `MaterialApp.router` 的 `builder` 中的 `PwaUpdateBanner` 会出现底部横幅。点击「立即刷新」会发送 `SKIP_WAITING` 并在 `controllerchange` 后整页 reload。

`manifest.json` 已包含：`scope` / `id` / `lang` / `categories` / `screenshots` / `shortcuts` / maskable icons —— Lighthouse PWA installability 应当全绿。

## 渲染策略

默认走 Flutter 默认 Web 渲染器（CanvasKit on desktop，HTML/auto on mobile）。Wasm 模式在 `flutter build web` dry-run 中已通过；后续如需可加 `--wasm` 切换。

## 状态：单包（非 melos）

`apps/mobile` 是单一 Flutter package；当前没有需要拆分成多个 Dart package 的需求，暂不引入 melos。后续若出现共享的 pure-Dart 工具包再评估。

## 代码规范

- `analysis_options.yaml` 启用 strict-casts / strict-inference / strict-raw-types，并打开 `prefer_const_*`、`avoid_dynamic_calls`、`avoid_print`、`require_trailing_commas` 等。
- 生成代码（`*.g.dart` / `*.freezed.dart`）已从 lint 中排除。
- 提交前钩子见仓库根目录 `tool/install-hooks.sh`：会对暂存的 `.dart` 文件跑 `dart format` 与 `flutter analyze`。

## CI

`.github/workflows/mobile.yml` 在 `apps/mobile/**` 变更时触发：

1. `analyze-and-test` — `dart format --set-exit-if-changed` + `flutter analyze --fatal-infos` + `flutter test`
2. `build-web` — `flutter build web --release`
3. `build-android` — `flutter build apk --debug`
4. `build-ios` — `flutter build ios --debug --no-codesign`（macOS runner）
