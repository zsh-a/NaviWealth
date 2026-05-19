# NaviWealth — Agent Guide

Personal finance app: all asset classes, investment tracking, portfolio analysis, FIRE dashboard, rebalancing, AI assistant. Cross-platform iOS / Android / Web. Local-first + cloud sync.

## Quick Reference

| Area | Path | Language |
|------|------|----------|
| Mobile app | `apps/mobile/` | Dart (Flutter) |
| Backend | `apps/backend/` | Rust (Cloudflare Workers + D1) |
| Securities catalog build | `tool/asset_catalog/` | Python |
| Docs | `docs/` | Markdown |
| CI/CD | `.github/workflows/` | GitHub Actions |

---

## Build & Run

### Flutter Mobile

```bash
cd apps/mobile
flutter pub get
flutter test                                 # unit + widget tests
flutter analyze --fatal-infos                # static analysis
flutter run                                  # default device
flutter run -d chrome                        # web dev
flutter build web --release --pwa-strategy=none
flutter build apk --debug
flutter build ios --debug --no-codesign      # macOS only
```

One-time web setup (scripts live under the mobile app):
```bash
apps/mobile/tool/setup-drift-web.sh    # sqlite3.wasm + drift_worker.dart.js
apps/mobile/tool/build-cn-fonts.sh     # CN font subsets (app-cn-base/ext.woff2)
```

### Rust Backend

```bash
# prerequisites: rustup target add wasm32-unknown-unknown && npm i -g wrangler
cd apps/backend
cargo check --target wasm32-unknown-unknown
cargo fmt --all -- --check
cargo clippy --target wasm32-unknown-unknown --all-targets -- -D warnings
wrangler dev                                 # local dev
wrangler deploy                              # production
```

### Securities Catalog

```bash
tool/build-asset-catalog.sh           # rebuilds bundled NDJSON consumed by mobile FTS5
                                       # see tool/asset_catalog/README.md (full ingest is manual)
```

### Web Smoke Tests

```bash
cd apps/mobile && flutter build web --release
cd web_smoke && npm install && npm test
```

### Versioning, Release & Hooks

```bash
./tool/bump-version.sh 0.2.0           # stamp mobile + backend, commit, tag v0.2.0
git push origin HEAD --follow-tags     # triggers release.yml
./tool/install-hooks.sh                # pre-commit: dart format + analyze on staged .dart
```

Build number = `git rev-list --count <tag>` (monotonic, reproducible).

---

## Architecture

### Monorepo Layout

```
apps/mobile/      Flutter app (iOS / Android / Web)
apps/backend/     Cloudflare Workers + Rust + D1
tool/             Versioning, hooks, securities catalog build, dev utilities
docs/             Protocol specs, roadmap, monitoring, compat matrix
```

No workspace-level build tool. Each app is self-contained. CI uses path filters.

### Mobile (Feature-First Clean Architecture)

```
lib/
  app/            MaterialApp, go_router, bootstrap, route guards, master/detail layout
  core/           Cross-cutting:
                    ai/               Device-only AI runtime, tools, contracts,
                                      trace (see docs/ai-architecture.md)
                    async/            ConventionalAsyncNotifier base, isolate runner
                    auth/             Auth controller, providers
                    backup/           Encrypted local backup
                    command_palette/  Cmd-K palette + default commands
                    config/           Compile-time config (AppConfig)
                    format/           Number/date/currency formatting
                    haptics/          Platform haptic feedback
                    logging/          Structured logging
                    perf/             Performance instrumentation
                    pwa/              Web PWA install/update
                    security/         SQLCipher key handling
                    shortcuts/        Keyboard shortcuts
                    sync/             OpLog, push/pull engine, providers
  data/
    audit/             Domain event log (writer/reader)
    db/                Drift ORM: app_database, tables, converters, connection variants
    domain/            Freezed models: Account, Asset, JournalEntry, Posting, Liability, Expense...
    market/            Market-data providers (Yahoo, CoinGecko, Sina), cache, rate limiter
    repositories/      Data repositories
    securities_catalog/ Bundled FTS5 catalog loader + search
  domain/         Pure domain layer:
                    entities/  fx_rate, quote, historical_bar, symbol_info
                    services/  net worth, currency converter, market data, price/balance sources
                    values/    Money, asset_market
  features/       Feature modules (each: ui/, data/, domain/):
                    accounts, activity, ai_chat, analytics, assets, auth,
                    cashflow, expense, fire, home, ingest, investment,
                    liabilities, rebalance, settings, shared
  design_system/  W3C Design Tokens (color / typography / motion / dimension),
                  themes, charts, reusable widgets. UI is built on Forui
                  (FCard / FButton / FTheme(zinc)); spacing & radius via
                  AppSpacing / AppRadius tokens (no magic numbers in chrome).
  l10n/           Localization (en + zh, ARB files)
```

### Backend

```
src/
  lib.rs          Worker Router (entry point)
  error.rs        AppError enum with coded JSON responses
  hlc.rs          Hybrid Logical Clock
  auth/           JWT (HS256), Argon2 password hashing, middleware
  routes/         HTTP handlers: health, auth, me, sync
  sync/           OpLog (op), materialise, state
migrations/       D1 SQL migrations (AI read-model tables kept as history; W-D7)
```

### Key Architectural Decisions

- **Local-first**: client is source of truth; server is durable storage + fan-out.
- **Sync**: eventual consistency via 30s polling, HLC-ordered OpLog, row-level LWW, tombstones for deletes. Protocol frozen at v1.0 — see `docs/sync-protocol.md`.
- **Money**: `Decimal` (not `double`) everywhere; `Money` value object rejects cross-currency ops at the type boundary; FX through explicit converter service.
- **Database**: Drift ORM; SQLCipher (native), sqlite3 WASM (web).
- **Auth**: single-user JWT (HS256), no registration endpoint; `BYPASS_AUTH` for dev.
- **Routing**: go_router with Path URL strategy; deferred imports for web code-splitting.
- **AI**: device-only — on-device agent runtime calls the user's chosen LLM provider (Anthropic- **or** OpenAI-compatible endpoint) directly with the user's own key; provider + key managed as switchable `LlmProfile`s in Settings, no opt-in toggle (W-D7 deleted the cloud AI backend; no `/ai/chat` relay, no cloud fallback; web has no AI). See `docs/ai-architecture.md` (design) + `docs/ai-protocol.md` (runtime event contract).

---

## Code Conventions

### Dart / Flutter
- **Linting**: strict-casts, strict-inference, strict-raw-types (`apps/mobile/analysis_options.yaml`).
- Files `snake_case.dart`; classes `PascalCase`; private widgets `_PrefixName`.
- Providers: `camelCase` + `Provider` suffix (e.g. `appRouterProvider`).
- Constants: `k` prefix (e.g. `kPrimaryTabPaths`, `kPushBatchMaxOps`).
- Single quotes; trailing commas required.
- `*.g.dart` / `*.freezed.dart` are generated — never edit.

### Riverpod
- Use `Provider`, `FutureProvider`, `StreamProvider`, `StateProvider` for the obvious cases.
- Complex async state extends `ConventionalAsyncNotifier<T>` (`fetch / refresh / mutate`) — see `core/async/async_notifier_convention.dart`.
- Group provider declarations per layer (`data/db/providers.dart`, `core/sync/providers.dart`, ...).

### Rust
- Standard Rust 2021. `cargo fmt` enforced in CI.
- Centralized `AppError` (`thiserror`) with factory methods.
- Handler pattern: public `pub async fn name(...)` wrapping an inner `_inner` for error/metrics handling.

---

## Testing

```
test/
  app/, core/, data/, domain/, design_system/, features/, l10n/, golden/
  e2e/            Multi-device sync via SyncCluster / VirtualDevice harness
```

- **In-memory DB**: `makeTestDatabase()` (Drift in-memory, bypasses SQLCipher).
- **Deterministic fakes**: `makeStubStamper()`, `InMemoryOutboxStore`, `InMemoryCursorStore`, `FakeSyncApiClient`.
- **Widget tests**: wrap in `MaterialApp` so theme resolves.
- **Convention**: override the data layer in tests, not providers with static `AsyncValue`.
- **Coverage targets** (`codecov.yml`): project 60%, patch 70%; generated files excluded.

---

## CI/CD

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `mobile.yml` | `apps/mobile/**` | format, analyze, build_runner check, test+coverage, web/android/iOS build |
| `backend.yml` | `apps/backend/**` | fmt, clippy, wasm32 check, cargo audit, deploy/preview |
| `asset-catalog.yml` | `tool/asset_catalog/**`, `tool/build-asset-catalog.sh` | offline pytest + stub bake (full ingest is manual / self-hosted) |
| `security.yml` | weekly + lockfile changes | dart pub outdated, cargo audit, Trivy |
| `release.yml` | tag `vX.Y.Z` + manual | version stamp, build mobile+backend, GitHub Release, deploy backend |
| `web-smoke.yml` | nightly + manual | Playwright (Chromium / Firefox / WebKit) |

---

## Environment & Config

- **No `.env` files committed.** Compile-time config via `--dart-define` (see `apps/mobile/lib/core/config/app_config.dart`):
  - `API_BASE_URL` (default `http://127.0.0.1:8787`)
  - `BYPASS_AUTH` (default `false`; opt in with `--dart-define=BYPASS_AUTH=true` for dev)
- **Wrangler secrets**: `JWT_SECRET` (`wrangler secret put`). `ANTHROPIC_API_KEY` is no longer a backend secret — W-D7 removed the cloud AI proxy; the model key is the user's, held on-device.
- **GitHub secrets**: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `CODECOV_TOKEN`, `KEYSTORE_BASE64` + signing keys.

---

## Detailed Documentation

| Doc | Description |
|-----|-------------|
| `docs/sync-protocol.md` | Sync protocol spec (Frozen v1.0): HLC, OpLog, push/pull, conflict resolution |
| `docs/sync-protocol-tests.md` | 50+ protocol test cases |
| `docs/sync-e2e-manual.md` | Manual E2E checklist for multi-device sync |
| `docs/sync-monitoring.md` | Latency targets, alert tiers, D1 sampling |
| `docs/ai-architecture.md` | AI design source of truth: device-only runtime, tools, contracts, UI grammar (read before touching `lib/core/ai/`) |
| `docs/ai-protocol.md` | Device AI runtime event contract (stream events, stop reasons, tool catalog) |
| `docs/local-development.md` | Local dev setup walkthrough |
| `docs/market-data-providers.md` | Market-data provider matrix and limits |
| `docs/web-compat-matrix.md` | Cross-browser compatibility and known issues |
| `docs/web-routing.md` | Web routing verification checklist |
| `docs/visual-baseline/README.md` | Golden suite + Figma sync contract |
| `docs/branch-protection.md` | Branch protection rules for `main` |
| `docs/roadmap.md` (+ `roadmap-phase1.md`, `roadmap-midterm-execution.md`, `roadmap-fire-os.md`) | Product roadmap |
| `apps/mobile/README.md` | Mobile engineering baseline |
| `apps/mobile/design_tokens/README.md` | W3C Design Token system |
| `apps/mobile/web_smoke/README.md` | Playwright smoke tests |
| `apps/mobile/docs/web-bundle.md` | Web bundle size baseline + regression policy |
| `tool/asset_catalog/README.md` | Securities catalog build pipeline |
