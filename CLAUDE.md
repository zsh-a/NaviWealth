# NaviWealth Agent Guide

NaviWealth is a local-first Personal LifeOS. FinanceOS is the seed domain; HealthOS and KnowledgeOS are opt-in domains registered through the LifeOS shell. The app targets iOS, Android, and Web. Device AI is native-only; Web has no AI runtime and no Health integration.

Read these before changing architecture or cross-domain code:

- `docs/lifeos-architecture-northstar.md`: boundaries and non-goals.
- `docs/lifeos-shell.md`: cross-domain shell, domain registration, AI, sync, memory, persistence.
- `docs/lifeos-decision-2026-05-24.md`: ADR that started Phase D and selected HealthOS as the second domain.
- Roadmaps and domain SSOTs as needed: `docs/roadmap-lifeos.md`,
  `docs/roadmap-finance.md`, `docs/healthos-domain.md`,
  `docs/knowledgeos-domain.md`.

## Current Domains

| Domain | Status | Main paths | Sync prefix |
|---|---|---|---|
| FinanceOS | Always on | `features/finance/`, finance feature slices, `features/finance_ai_tools.dart` | `fin:` |
| HealthOS | User opt-in | `features/health/`, `features/health_ai_tools.dart` | `health:` |
| KnowledgeOS | User opt-in | `features/knowledge/`, `features/knowledge_ai_tools.dart` | `know:` |

The production domain inventory is `apps/mobile/lib/app/domain_packs.dart`. Each domain contributes a `DomainPack`: tools, prompt block, shell route, shell spec, agents, command palette entries, and tab paths. Add a new domain by adding a real domain package and one registry entry; do not scatter one-off branching through bootstrap.

## Repository Map

| Area | Path | Language |
|---|---|---|
| Mobile app | `apps/mobile/` | Dart, Flutter |
| Native embedding runtime | `apps/mobile/native/lifeos_native/` | Rust, flutter_rust_bridge |
| Backend | `apps/backend/` | Rust, Cloudflare Workers, D1 |
| Securities catalog build | `tool/asset_catalog/` | Python |
| Project docs | `docs/` | Markdown |
| CI/CD | `.github/workflows/` | GitHub Actions |

Mobile layout:

```text
apps/mobile/lib/
  app/                  bootstrap, router, domain packs, app-level composition
  core/                 cross-domain infrastructure only
    ai/                 contracts, runtime, local memory, agents, composition seams
    audit/              domain-neutral event log
    auth/               JWT/session/domain opt-in
    lifeos/             DomainPack registry seam
    persistence/        Drift adapter and shared tables
    shell/              multi-domain IA primitives
    sync/               sync v2 row-state client and sync envelope types
  design_system/        tokens, themes, charts, reusable widgets
  domain/               legacy pure finance-neutral values/services still shared by Finance
  features/
    finance/            Finance composition and data root
    health/             HealthOS data, UI, AI tools, agents
    knowledge/          KnowledgeOS data, UI, AI tools, agents
    <finance slices>/   accounts, assets, cashflow, investment, options, etc.
  l10n/                 ARB files and generated localizations
```

Backend layout:

```text
apps/backend/src/
  lib.rs                Worker router
  auth/                 JWT, password hashing, middleware
  routes/               health, auth, me, sync
  sync/                 generic row-state sync store
  error.rs              coded JSON errors
  hlc.rs                Hybrid Logical Clock
```

## Architecture Rules

- `core/` is domain-neutral. It must not import `features/<domain>/` or domain business entities.
- Domain business code lives under `features/<domain>/`. Finance slices may be legacy sibling features, but new cross-domain work should use `features/finance/` composition seams or app-level composition.
- `app/` is the composition root. It may import multiple domains to assemble routers, memory indexers, domain packs, AI tools, agents, and provider overrides.
- AI contracts and runtime stay in `core/ai/`; concrete domain tools live in `features/<domain>/ai_tools/` and are exported by `<domain>_ai_tools.dart`.
- `core/persistence/` is the shared Drift adapter. Domain repositories own domain table access. Cross-domain infrastructure may use only its own tables.
- Sync is v2 row-state: generic versioned blobs, last-writer-wins, one `POST /sync`. Do not rebuild sync as CRDT, event sourcing, or schema negotiation.
- AI is device-only. There is no backend AI relay, no cloud fallback, and no `/ai/chat` endpoint. Users provide their own Anthropic or OpenAI-compatible profile on device.
- Web builds exclude AI runtime and Health platform integration.

## Search Workflow

Use CodeGraph for structural questions and `rg` or `semble` for text/prose.

CodeGraph:

- Find symbol: `codegraph_search`
- Focused task context: `codegraph_context`
- Callers/callees/impact: `codegraph_callers`, `codegraph_callees`, `codegraph_impact`
- Directory inventory: `codegraph_files`

Semble examples:

```bash
rtk semble search "DomainPack registry" apps/mobile --content all
rtk semble search "MorningBriefingAgent" apps/mobile
rtk semble search "deployment guide" docs --content docs
```

If `semble` is unavailable, use:

```bash
rtk uvx --from "semble[mcp]" semble search "DomainPack registry" apps/mobile --content all
```

Use `rg` for exact strings, comments, config literals, and generated-file checks.

## Build And Test

Prefix shell commands with `rtk` when running from this repo.

Mobile:

```bash
cd apps/mobile
rtk flutter pub get
rtk dart format .
rtk flutter analyze --fatal-infos
rtk flutter test
rtk flutter run
rtk flutter run -d chrome
rtk flutter build web --release
rtk flutter build apk --debug
rtk flutter build ios --debug --no-codesign
```

Generated code:

```bash
cd apps/mobile
rtk dart run build_runner build --delete-conflicting-outputs
```

One-time or asset setup:

```bash
apps/mobile/tool/setup-drift-web.sh
apps/mobile/tool/build-cn-fonts.sh
apps/mobile/tool/build-latin-fonts.sh
```

Native embedding runtime:

```bash
cd apps/mobile
rtk bash tool/build-lifeos-native.sh macos
```

Backend:

```bash
cd apps/backend
rtk cargo check --target wasm32-unknown-unknown
rtk cargo fmt --all -- --check
rtk cargo clippy --target wasm32-unknown-unknown --all-targets -- -D warnings
rtk wrangler dev
rtk wrangler deploy
```

Web smoke:

```bash
cd apps/mobile
rtk flutter build web --release
cd web_smoke
rtk npm install
rtk npm test
```

Project lint gates:

```bash
./tool/lint-no-finance-in-core.sh
./tool/lint-cross-feature-imports.sh
./tool/lint-row-family-prefix.sh
./tool/lint-domain-neutral-contracts.sh
./tool/check-tool-descriptors.sh
```

## Dart And Flutter Conventions

- Strict analysis is enabled: strict casts, strict inference, strict raw types.
- Files use `snake_case.dart`; classes use `PascalCase`.
- Providers use `camelCaseProvider`.
- Constants use the existing local style; many cross-domain constants use `k` prefixes.
- Use single quotes and trailing commas.
- Never edit generated `*.g.dart`, `*.freezed.dart`, or FRB generated files by hand.
- Complex async state should extend `ConventionalAsyncNotifier<T>` when it matches the fetch/refresh/mutate convention.
- Override data/repository layers in tests instead of replacing feature providers with static `AsyncValue` unless the existing test pattern already does that.

## UI Conventions

- UI uses Forui plus the local design system. Prefer `FCard`, `FButton`, `FTheme`, `AppSpacing`, `AppRadius`, and chart components already in `design_system/`.
- Keep domain shells dense and task-oriented. Do not add marketing pages or explanatory hero screens inside the app.
- Use existing domain routes and `DomainTabsShell`; do not invent a second navigation model.
- Cards are for repeated items, modals, and framed tools. Do not nest cards or turn every section into a card.
- Use generated/localized strings where the surrounding UI does. Keep English and Chinese ARB files in sync.
- After frontend changes, run a targeted widget test or inspect in the browser when a local web target is relevant.

## Testing Rules

- In-memory DB helper: `makeTestDatabase()`.
- Common fakes: `makeStubStamper()`, `InMemoryOutboxStore`, `InMemoryCursorStore`, `FakeSyncApiClient`.
- Widget tests should wrap UI in `MaterialApp` or the existing app test harness so theme and localization resolve.
- Add focused tests for new repositories, sync behavior, AI tools, proposal appliers, and route shell changes.
- Generated files are excluded from coverage; patch coverage target is 70 percent.

## Data And Sync

- Drift lives in `core/persistence/`; domain repositories live under `features/<domain>/data/`.
- Shared sync envelope types live in `core/sync/`: `Hlc`, `SyncMeta`, `MutationStamper`, and outbox providers.
- Row families are domain-prefixed at the sync boundary:
  - Finance: `fin:<table>`
  - Health: `health:<table>`
  - Knowledge: `know:<table>`
- Local-only derived data, memory embeddings, and triage side tables do not sync unless explicitly designed to do so.

## AI Runtime

- Runtime contracts: `core/ai/contracts/`.
- Provider-neutral loop: `core/ai/runtime/`.
- Domain tools: `features/<domain>/ai_tools/`.
- Tool registry aggregation: `deviceToolsProvider` in `bootstrap.dart`, based on active `DomainPack`s.
- Prompt aggregation: `systemPromptBlocksProvider`, also based on active `DomainPack`s.
- Agents: `core/ai/agents/` framework; domain agents live under `features/<domain>/agents/` and are registered through `DomainPack.agentBuilder`.
- Proposal application is a cross-domain seam. Finance and Knowledge proposals are composed in `features/knowledge/composition/knowledge_bootstrap.dart`.

## Environment

- Do not commit `.env` files.
- Mobile compile-time config uses `--dart-define` in `apps/mobile/lib/core/config/app_config.dart`.
- Key defines include:
  - `API_BASE_URL`, default `http://127.0.0.1:8787`
  - `BYPASS_AUTH`, default `false`
  - `RUST_EMBEDDER_MODEL_DIR`
  - `RUST_EMBEDDER_ORT_DYLIB_PATH`
  - `RUST_EMBEDDER_LIBRARY_PATH`
- Wrangler secret: `JWT_SECRET`.
- The LLM API key is user-owned and stored on device as an `LlmProfile`, not as a backend secret.

## Documentation Index

| Doc | Use |
|---|---|
| `docs/lifeos-architecture-northstar.md` | Architecture boundaries and non-goals |
| `docs/lifeos-shell.md` | Cross-domain shell SSOT |
| `docs/lifeos-decision-2026-05-24.md` | Phase D ADR |
| `docs/healthos-domain.md` | HealthOS scope, data, AI tools, agents |
| `docs/knowledgeos-domain.md` | KnowledgeOS scope, data, AI tools, agents |
| `docs/ai-architecture.md` | Device AI runtime design |
| `docs/ai-protocol.md` | AI event/tool protocol |
| `docs/sync-v2.md` | Active sync protocol |
| `docs/sync-protocol.md` | Historical v1 protocol only |
| `docs/options-income.md` | Options income engine |
| `docs/market-data-providers.md` | Market data providers |
| `docs/local-development.md` | Local setup |
| `docs/testing-strategy.md` | Test strategy |
| `apps/mobile/README.md` | Mobile engineering baseline |
| `apps/mobile/design_tokens/README.md` | Design tokens |
| `apps/mobile/web_smoke/README.md` | Playwright smoke tests |


<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged — so it is always safe to use.

## Key Commands
```bash
# Git (59-80% savings)
rtk git status          rtk git diff            rtk git log

# Files & Search (60-75% savings)
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>      rtk diff <file>

# Test (90-99% savings) — shows failures only
rtk pytest tests/       rtk cargo test          rtk test <cmd>

# Build & Lint (80-90% savings) — shows errors only
rtk tsc                 rtk lint                rtk cargo build
rtk prettier --check    rtk mypy                rtk ruff check

# Analysis (70-90% savings)
rtk err <cmd>           rtk log <file>          rtk json <file>
rtk summary <cmd>       rtk deps                rtk env

# GitHub (26-87% savings)
rtk gh pr view <n>      rtk gh run list         rtk gh issue list

# Infrastructure (85% savings)
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->
