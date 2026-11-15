# NaviWealth Agent Guide

NaviWealth is a local-first personal finance and health app for one Android
phone. The client is NSH (Rust) in `apps/nsh-client/`; business truth lives in
`crates/finance-core/` and `crates/health-core/`. The Flutter client and the
Sync v3 backend were retired on 2026-11-15 (ADR 0003); their source is
archived at the `flutter-final` git tag. Read
`docs/architecture/adr/0003-flutter-retirement.md`,
`docs/product/product-scope.md` and `docs/roadmap/roadmap-lifeos.md` before
planning work. Start with `docs/agent-map.md`, which routes each task to the
smallest authoritative context.

## Repository Map

| Area | Path | Language |
|---|---|---|
| NSH client | `apps/nsh-client/` | Rust, NSH |
| Finance core (double-entry ledger, holdings, catalog) | `crates/finance-core/` | Rust |
| Health core (meal recognition, nutrition, Garmin) | `crates/health-core/` | Rust |
| Neutral SQLite/backup infrastructure | `crates/lifeos-core/` | Rust |
| Agent Runtime | `third_party/agent-runtime/` | Rust submodule |
| Market data SDK | `third_party/market-data-rs/` | Rust |
| Securities catalog bundle | `assets/catalog/` | NDJSON |
| Catalog build/publish pipeline | `tool/asset_catalog/` | Python |
| Project docs | `docs/` | Markdown |
| CI/CD | `.github/workflows/` | GitHub Actions |

NSH client layout:

```text
apps/nsh-client/src/
  domain/   host-owned meals/account and shared health-core domain exports
  data/     device storage, photos, local time, thin NSH fetch Transport
  ui/       styled components over nsh-base and its tokens
  pages/    home (Today, Records, Assets, Review tabs, capture sheet), meal
            editing, Settings
  i18n/     English and Chinese copy
tests/      headless meal, weight, Garmin, review and backup flows
```

## Architecture Rules

- Domain truth lives in Rust crates. `finance-core` owns the ledger, holdings
  and catalog repositories; `health-core` owns meals, nutrition and Garmin
  parsing; `lifeos-core` owns SQLite storage, migrations and backup/restore.
  `apps/nsh-client/` is UI, composition and device storage only.
- The client is local-only: no Sync, no login, no backend calls. Business
  data lives in SQLite (`rusqlite`, bundled) in the app's private directory;
  NSH KV is a 5 MB preferences store. Only exported backups are
  passphrase-encrypted (ADR 0002).
- Features follow `docs/product/product-scope.md`: personal use, four tabs,
  AI for recognition drafts only. Do not port removed features or re-add the
  retired Flutter features (Knowledge, Execution, AI chat/agents, FIRE,
  options, rebalance, Runway, allocation display, broker statement import).
- AI is device-only against user-owned LLM profiles. There is no backend AI
  relay or cloud fallback. Provider protocols live in
  `third_party/agent-runtime/crates/llm-protocol`; request policy in
  `llm-client`.
- Domain crates depend on neutral infrastructure, never on sibling domain
  business models. Keep deterministic calculations out of any model.
- Recognition and imports produce drafts; every confirmed write goes through
  explicit user confirmation and is atomic.
- Dated observations (prices, FX, valuations) keep provenance and never
  overwrite manual entries on the same or newer day.
- NSH is Android-only for releases; desktop builds exist for development and
  headless tests. Web and iOS are out of scope.

## Build And Test

Each crate is an independent Cargo workspace; there is no root `Cargo.toml`.
Keep each workspace's `Cargo.lock` committed and use `--locked`.

```bash
rtk cargo fmt --manifest-path <crate>/Cargo.toml --all -- --check
rtk cargo clippy --manifest-path <crate>/Cargo.toml --all-targets --locked -- -D warnings
rtk cargo test --manifest-path <crate>/Cargo.toml --locked
```

Run the three commands for `apps/nsh-client`, `crates/finance-core` and
`crates/health-core`; CI runs fmt, clippy (`-D warnings`) and `--locked`
tests.

Securities catalog and docs:

```bash
./tool/build-asset-catalog.sh                  # stub bake from committed CSVs
python3 -m pytest tool/asset_catalog/tests
python3 -m tool.asset_catalog.validate_release
node tool/check-docs.mjs                       # documentation link/nav check
```

Release: `nsh-vX.Y.Z` tags, APK built and signed by the manual `nsh client`
workflow; see `docs/operations/branch-protection.md`.

## Search Workflow

Use CodeGraph for structural questions and `rg` for text/prose.

CodeGraph:

- Find symbol: `codegraph_search`
- Focused task context: `codegraph_context`
- Callers/callees/impact: `codegraph_callers`, `codegraph_callees`, `codegraph_impact`
- Directory inventory: `codegraph_files`

Use `rg` for exact strings, comments, config literals, and generated-file checks.

## Conventions

- Rust: nightly toolchain per workspace; `rustfmt` and strict clippy with
  `-D warnings`; errors are `Result`, UI-facing errors are strings mapped at
  the seam.
- Money is exact: integer minor units and string decimals; floating point
  never touches accounting truth; postings sum to zero separately within
  each currency.
- Documentation: update the owning SSOT (see `docs/agent-map.md`); run
  `node tool/check-docs.mjs` after doc changes; keep `README.md`, `llms.txt`
  and the mkdocs nav consistent with the docs tree.

## Testing Rules

- Crates express contracts as tests: property tests for ledger invariants,
  corpus fixtures for statement parsers, fixtures for catalog and Garmin
  parsing.
- NSH client has headless flows (`nsh-testing`) for capture, review, backup
  and restore; restore must be atomic and reject malformed backups without
  touching current data.
- Android device evidence (TLS, Keystore, upgrade/migration) is recorded
  separately from headless tests; emulator evidence does not close a
  physical-device roadmap item.

## Environment

- No secrets in the repository. The Android release keystore arrives in CI
  through `KEYSTORE_BASE64`/password secrets; `tool/sign-nsh-apk.sh` keeps
  passwords out of argv.
- Local development defaults: nightly toolchain per workspace; the WSL2 +
  Windows emulator topology is documented in
  `docs/development/local-development.md`.
- `.nsh/` and `apps/client/` are local-only development data and are
  gitignored; never commit them.

## Documentation Index

| Doc | Use |
|---|---|
| `docs/agent-map.md` | Task → SSOT router |
| `docs/product/product-scope.md` | Product scope SSOT |
| `docs/roadmap/roadmap-lifeos.md` | Active phases and exit gates |
| `docs/architecture/adr/0001-nsh-client-migration.md` | NSH direction |
| `docs/architecture/adr/0002-personal-local-scope.md` | Personal, local-only scope |
| `docs/architecture/adr/0003-flutter-retirement.md` | Flutter/backend retirement, catalog move, D1 ids |
| `docs/architecture/agent-runtime-current.md` | Rust runtime code map and invariants |
| `docs/development/local-development.md` | Local setup and Android debugging |
| `docs/operations/branch-protection.md` | CI checks and release policy |
| `tool/asset_catalog/README.md` | Securities catalog pipeline |
| `docs/roadmap/roadmap-finance.md` | Archived FinanceOS roadmap (historical) |
| `docs/roadmap/product-direction-and-demand-validation.md` | Archived product-direction study (historical) |

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
