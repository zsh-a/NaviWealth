# NaviWealth — Agent Guide

Personal finance management app: all asset classes, investment tracking, portfolio analysis, FIRE dashboard, rebalancing, AI assistant. Cross-platform: iOS / Android / Web. Local-first + cloud sync.

## Quick Reference

| Area | Path | Language |
|------|------|----------|
| Mobile app | `apps/mobile/` | Dart (Flutter) |
| Backend | `apps/backend/` | Rust (Cloudflare Workers) |
| Docs | `docs/` | Markdown |
| Build tools | `tool/` | Shell |
| CI/CD | `.github/workflows/` | GitHub Actions |

---

## Build & Run

### Flutter Mobile

```bash
cd apps/mobile
flutter pub get                              # install deps
flutter test                                 # unit + widget tests
flutter analyze --fatal-infos                # static analysis
flutter run                                  # default device
flutter run -d chrome                        # web dev
flutter build web --release --pwa-strategy=none  # web production
flutter build apk --debug                    # android
flutter build ios --debug --no-codesign      # iOS (macOS only)
```

One-time web setup:
```bash
tool/setup-drift-web.sh    # sqlite3.wasm + drift_worker.dart.js
tool/build-cn-fonts.sh     # CN font subsets (app-cn-base.woff2, app-cn-ext.woff2)
```

### Rust Backend

```bash
# prerequisites: rustup target add wasm32-unknown-unknown && npm i -g wrangler
cd apps/backend
cargo check --target wasm32-unknown-unknown  # type check
cargo fmt --all -- --check                   # format check
cargo clippy --target wasm32-unknown-unknown --all-targets -- -D warnings
wrangler dev                                 # local dev
wrangler deploy                              # deploy to production
```

### Web Smoke Tests

```bash
cd apps/mobile && flutter build web --release
cd web_smoke && npm install && npm test
```

### Versioning & Release

```bash
./tool/bump-version.sh 0.2.0           # stamps both mobile + backend, commit, tag v0.2.0
git push origin HEAD --follow-tags      # triggers release.yml (mobile + backend)
```

Build number = `git rev-list --count <tag>` (monotonic, reproducible).

### Git Hooks

```bash
./tool/install-hooks.sh   # pre-commit: dart format + flutter analyze on staged .dart
```

---

## Architecture

### Monorepo Structure

```
apps/
  mobile/         Flutter app (iOS / Android / Web)
  backend/        Cloudflare Workers + Rust + D1
docs/             Protocol specs, compat matrix, monitoring
tool/             Hooks, scripts, versioning
```

No workspace-level build tool. Each app is self-contained. CI uses path filters to run only relevant workflows.

### Mobile Architecture (Feature-First Clean Architecture)

```
lib/
  app/            MaterialApp, router, bootstrap, route guards
  core/           Cross-cutting: auth, config, sync, logging, security, PWA, shortcuts, backup
  data/
    db/           Drift ORM (app_database, tables, converters, connection variants)
    domain/       Domain model classes (freezed): Account, Asset, JournalEntry, Posting, Liability, Expense...
    market/       Market data providers (Yahoo Finance, CoinGecko, Sina), cache, rate limiter
    repositories/ Data repositories
  domain/         Pure domain services: net worth, currency converter, market data, quotes
  features/       Feature modules (feature-first):
    accounts/     Account management
    ai_chat/      AI chat (SSE streaming, proposal/confirm cards, tool visualization)
    analytics/    Analytics, benchmark comparison, concentration risk
    assets/       Asset pages (cash, deposit, wealth product, physical)
    auth/         Login, devices, auth controller
    expense/      Expense tracking, categories, monthly reports
    fire/         FIRE dashboard (goal, projection, scenarios)
    home/         Dashboard, allocation, trend cards
    investment/   Trade entry, cost basis (FIFO/LIFO/avg), holdings, FX PnL, tax
    liabilities/  Liabilities, amortization
    rebalance/    Rebalancing engine, allocation schemes
    settings/     Settings page
    shared/       Shared form widgets
  design_system/  W3C Design Tokens, themes, charts, reusable widgets
  l10n/           Localization (en + zh, ARB files)
```

Each feature module internal structure: `ui/` (or `presentation/`), `data/`, `domain/`.

### Backend Architecture

```
src/
  lib.rs          Worker Router (main entry)
  error.rs        AppError enum with coded JSON responses
  hlc.rs          Hybrid Logical Clock implementation
  ai/             Anthropic Claude proxy, SSE streaming, guardrails, tools
  auth/           JWT (HS256, hmac+sha2), Argon2 password hashing, middleware
  routes/         HTTP handlers: health, auth, me, sync, ai
  sync/           OpLog, materialise, state management
migrations/       D1 SQL migrations
```

### Key Architectural Decisions

- **Local-first**: client is source of truth; server is durable storage + fan-out
- **Sync**: eventual consistency via polling (30s), HLC-ordered OpLog, row-level LWW conflict resolution, tombstones for deletes
- **Sync protocol**: Frozen v1.0 — see `docs/sync-protocol.md`
- **Monetary types**: `Decimal` (not `double`) everywhere, enforced by `Money` value object
- **Database**: Drift ORM + SQLCipher encryption (native), sqlite3 WASM (web)
- **Auth**: single-user JWT (HS256), no registration endpoint, `BYPASS_AUTH` flag for dev
- **Routing**: go_router with Path URL strategy, deferred imports for web code-splitting
- **AI**: Anthropic Claude API via backend proxy, SSE streaming

---

## Code Conventions

### Dart / Flutter

- **Linting**: strict-casts, strict-inference, strict-raw-types. See `apps/mobile/analysis_options.yaml`
- **File naming**: `snake_case.dart`
- **Classes**: `PascalCase`; private widgets: `_PrefixName`
- **Providers**: `camelCase` + `Provider` suffix (e.g., `appRouterProvider`, `dashboardSnapshotProvider`)
- **Constants**: `k` prefix (e.g., `kPrimaryTabPaths`, `kPushBatchMaxOps`)
- **Quotes**: single quotes enforced
- **Trailing commas**: required
- **Generated files**: `*.g.dart`, `*.freezed.dart` — excluded from lint, do not edit manually

### State Management (Riverpod)

- `Provider<T>` — singletons, sync derivations
- `FutureProvider<T>` — async one-shot reads
- `StreamProvider<T>` — live database streams
- `StateProvider<T>` — simple mutable UI state
- `AsyncNotifierProvider` — complex async state, uses `ConventionalAsyncNotifier<T>` base with `fetch()`, `refresh()`, `mutate()` (see `core/async/async_notifier_convention.dart`)
- Provider files per layer: `data/db/providers.dart`, `data/repositories/providers.dart`, `core/sync/providers.dart`, etc.

### Rust

- Standard Rust 2021 conventions: `snake_case` functions, `PascalCase` types, `SCREAMING_SNAKE_CASE` constants
- Centralized `AppError` enum with `thiserror::Error` derive and factory methods
- Handler pattern: `pub async fn push(...)` with inner `_inner` function for error/metrics handling
- Formatting enforced by `cargo fmt` in CI

### Money / Currency

- Use `Decimal` type, never `double` for monetary values
- `Money` value object rejects cross-currency operations at the type boundary
- FX conversion goes through explicit currency converter service

---

## Testing

### Test Structure

```
test/
  app/            Router, route guards, deferred routes
  core/           Sync engine, auth, format, security, shortcuts, backup
  data/           Database, repositories, HLC
  domain/         Money, currency converter, net worth, FX rate
  design_system/  Theme, tokens, widgets
  features/       Per-feature: home, expense, auth, fire, ai_chat
  e2e/            Sync end-to-end with virtual device clusters
```

### Key Testing Patterns

- **In-memory databases**: `makeTestDatabase()` — Drift in-memory, bypasses SQLCipher
- **Deterministic fakes**: `makeStubStamper()`, `InMemoryOutboxStore`, `InMemoryCursorStore`, `FakeSyncApiClient`
- **E2E sync**: `SyncCluster` / `VirtualDevice` harness simulates multi-device with explicit clock control
- **Widget tests**: `testWidgets` with `MaterialApp` wrappers for theme resolution
- **Convention**: override data layer, not providers with static `AsyncValue`

### Coverage

- Project target: 60%, patch target: 70% (see `codecov.yml`)
- Generated files excluded

---

## CI/CD

| Workflow | Trigger | Steps |
|----------|---------|-------|
| `mobile.yml` | `apps/mobile/**` changes | format, analyze, build_runner check, test+coverage, web+android+ios build |
| `backend.yml` | `apps/backend/**` changes | fmt, clippy, check (wasm32), cargo audit, deploy/preview |
| `security.yml` | Weekly Monday + lockfile changes | dart pub outdated, cargo audit, Trivy scan |
| `release.yml` | Tag `vX.Y.Z` + manual dispatch | Version stamp, build mobile + backend (optional), GitHub Release, deploy backend |
| `web-smoke.yml` | Nightly + manual | Playwright smoke tests (Chromium, Firefox, WebKit) |

---

## Environment & Config

- **No `.env` files committed.** Compile-time config via `--dart-define`:
  - `API_BASE_URL` (default: `http://127.0.0.1:8787`)
  - `BYPASS_AUTH` (default: `true` in dev)
  - Defined in `apps/mobile/lib/core/config/app_config.dart`
- **Wrangler secrets**: `JWT_SECRET`, `ANTHROPIC_API_KEY` (set via `wrangler secret put`)
- **GitHub secrets**: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `CODECOV_TOKEN`, `KEYSTORE_BASE64` + signing keys

---

## Detailed Documentation

| Doc | Description |
|-----|-------------|
| `docs/sync-protocol.md` | Sync protocol spec (Frozen v1.0): HLC, OpLog, push/pull API, conflict resolution |
| `docs/sync-protocol-tests.md` | 50+ protocol test cases |
| `docs/sync-e2e-manual.md` | Manual E2E checklist for multi-device sync |
| `docs/sync-monitoring.md` | Monitoring baseline: latency targets, alert tiers, D1 sampling |
| `docs/web-compat-matrix.md` | Cross-browser compatibility matrix and known issues |
| `docs/web-routing.md` | Web routing verification checklist |
| `docs/visual-baseline/README.md` | FIR-113 visual baseline: golden suite, Figma sync contract, FIR-103 §10 walkthrough |
| `docs/branch-protection.md` | Branch protection rules for main |
| `apps/mobile/README.md` | Mobile engineering baseline |
| `apps/mobile/design_tokens/README.md` | W3C Design Token system |
| `apps/mobile/web_smoke/README.md` | Playwright smoke test docs |
| `apps/mobile/docs/web-bundle.md` | Web bundle size baseline and regression policy |
