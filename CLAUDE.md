# NaviWealth Agent Guide

NaviWealth is a local-first personal finance and health app for one Android
phone. The client is NSH (Rust) in `apps/nsh-client/`; business truth lives in
`crates/navi-finance/` and `crates/navi-health/`. The Flutter client and the
Sync v3 backend were retired on 2026-11-15; their source is
archived at the `flutter-final` git tag. Read
`docs/product/product-scope.md` and `docs/roadmap/roadmap-nsh.md` before
planning work. Start with `docs/agent-map.md`, which routes each task to the
smallest authoritative context.

## Repository Map

| Area | Path | Language |
|---|---|---|
| NSH client | `apps/nsh-client/` | Rust, NSH |
| Finance (ledger, holdings, catalog) | `crates/navi-finance/` | Rust |
| Health (meals, nutrition, Garmin) | `crates/navi-health/` | Rust |
| Neutral SQLite infrastructure | `crates/navi-storage/` | Rust |
| Assistant and recognition runtime | `crates/navi-assistant/` | Rust, pi-rust |
| Market data SDK | `third_party/market-data-rs/` | Rust |
| Catalog source CSVs | `tool/asset_catalog/sources/` | CSV |
| Catalog build/publish pipeline | `tool/asset_catalog/` | Python |
| Project docs | `docs/` | Markdown |
| CI/CD | `.github/workflows/` | GitHub Actions |

NSH client layout:

```text
apps/nsh-client/src/
  domain/   host account/capture composition and shared health re-exports
  data/     device storage, photos, local time, thin NSH fetch Transport
  ui/       styled components over nsh-base and its tokens
  pages/    home (Today, Records, Assets, Review tabs, capture sheet), meal
            editing, Assistant, Settings
  i18n/     English and Chinese copy
tests/      headless meal, weight, Garmin, review and backup flows
```

## Architecture Rules

- Domain truth lives in Rust crates. `navi-finance` owns the ledger, holdings
  and catalog repositories; `navi-health` owns meal/favorite models and
  repositories, nutrition, weight/review calculations and Garmin parsing.
  `navi-storage` supplies neutral SQLite migrations, snapshots and atomic
  table replacement. The client owns UI, device adapters, the clock, encrypted
  backup orchestration and cross-domain capture/scale transactions.
- The client is local-only: no Sync, no login, no backend calls. Business
  data lives in SQLite (`rusqlite`, bundled) in the app's private directory;
  NSH KV is a 5 MB preferences store. Only exported backups are
  passphrase-encrypted (Personal Local Scope).
- Features follow `docs/product/product-scope.md`: personal use, four tabs,
  recognition drafts and the owner-authorized general assistant (2026-11-27).
  Do not port removed features or re-add the retired Flutter features
  (Knowledge, Execution, the seven named agents and legacy Memory Runtime, FIRE,
  options, rebalance, Runway, allocation display, broker statement import).
- AI is device-only against user-owned LLM profiles. There is no backend AI
  relay or cloud fallback. Provider protocols live in
  pinned pi-rust `rpi-ai` through `navi-assistant`; recognition makes a single
  bounded call and the general assistant uses `rpi-agent`. App adapters own tool permissions,
  SQLite sessions, explicit memory confirmation and business proposals.
- Domain crates depend on neutral infrastructure, never on sibling domain
  business models. Keep deterministic calculations out of any model.
- Recognition and imports produce drafts; every confirmed write goes through
  explicit user confirmation and is atomic.
- Assistant model runs are bounded and cancellable. Restart or restore never
  replays tools automatically. A record proposal opens unsent capture after
  confirmation; the normal review owns the final business write. Saved memories
  require confirmation and are included with conversations in encrypted backups.
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

Run the three commands for `apps/nsh-client`, `crates/navi-finance`,
`crates/navi-health`, `crates/navi-storage` and `crates/navi-assistant`; automatic CI runs fmt, clippy
(`-D warnings`) and `--locked` tests on relevant pushes and PRs. Signed
Android packaging remains a separate manual workflow.

Securities catalog and docs:

```bash
./tool/build-asset-catalog.sh                  # stub bake from committed CSVs
python3 -m pytest tool/asset_catalog/tests
python3 -m tool.asset_catalog.validate_release
node tool/check-docs.mjs                       # first-party documentation link/path check
node --test tool/tests/check-docs.test.mjs      # document checker regressions
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
  `node tool/check-docs.mjs` after doc changes; keep `README.md` and
  `llms.txt` consistent with the docs tree.

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
- NSH generates its dev workspace at `.nsh/` inside the app dir and caches
  builds under `target/`; both are gitignored. UI acceptance tests live in
  `apps/nsh-client/tests/` (`*.test.ts`, run with `nsh test tests`); never
  commit generated `.nsh/` state.

## Documentation Index

| Doc | Use |
|---|---|
| `docs/agent-map.md` | Task → SSOT router |
| `docs/product/product-scope.md` | Product scope SSOT |
| `docs/roadmap/roadmap-nsh.md` | Active phases and exit gates |
| `docs/architecture/personal-local-scope.md` | Personal, local-only scope policy |
| `docs/architecture/agent-runtime-current.md` | Rust runtime code map and invariants |
| `docs/development/local-development.md` | Local setup and Android debugging |
| `docs/operations/branch-protection.md` | CI checks and release policy |
| `tool/asset_catalog/README.md` | Securities catalog pipeline |

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
