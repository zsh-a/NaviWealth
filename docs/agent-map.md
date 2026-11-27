# Agent Task Map

Status: active documentation router.

Use this page to load the smallest authoritative context for a task. It is a
router, not a second source of product or architecture truth.

## Client Direction

[Product Scope](product/product-scope.md),
[Personal Local Scope](architecture/personal-local-scope.md) and the
[roadmap](roadmap/roadmap-nsh.md) govern new work. The NSH client is
personal and local-only: `navi-storage` supplies shared SQLite infrastructure,
`navi-finance` owns the ledger and catalog repositories, and `navi-health`
owns meals, nutrition and Garmin parsing. Android is the only release target;
desktop builds exist for development. Web and iOS are out of scope, and the
Flutter client and Sync backend are retired (2026-11-15).

## Task Routing

| Task | Read first | Code authority | Minimum verification |
|---|---|---|---|
| Plan or scope product work | [Product Scope](product/product-scope.md), [roadmap](roadmap/roadmap-nsh.md), ADRs | `docs/product/`, `docs/roadmap/` | Phase exit evidence; archived plans do not authorize work |
| Change NSH UI or pages | [`apps/nsh-client/README.md`](../apps/nsh-client/README.md), `apps/nsh-client/DESIGN.md` | `apps/nsh-client/src/`, `App.tsx`, `tsx/` | Headless `nsh-testing` flows; device evidence where the roadmap requires it |
| Change ledger, holdings or catalog behavior | `crates/navi-finance/` tests | `crates/navi-finance/src/` | Focused `cargo test` fixtures; exact money/rounding invariants |
| Change meals, nutrition or Garmin behavior | `crates/navi-health/` tests | `crates/navi-health/src/` | Focused `cargo test` fixtures |
| Change AFU-WL scale or Android hardware | [`apps/nsh-client/android/README.md`](../apps/nsh-client/android/README.md), [roadmap](roadmap/roadmap-nsh.md) | `crates/navi-health/src/scale.rs`, app `src/data/scale.rs`, `tsx/`, `android/` | Protocol/storage fixtures, mixed flows, Android lint/unit tests; physical scale gate separately |
| Change persistence, migrations or backup | `apps/nsh-client/src/data/db.rs`, owning crate tests | Domain repositories in `crates/navi-health/` and `crates/navi-finance/`; neutral `crates/navi-storage/`; app backup and cross-domain composition | Migration, backup roundtrip and restore atomicity tests |
| Change AI recognition or provider calls | [Agent Runtime Current Architecture](architecture/agent-runtime-current.md) | `third_party/agent-runtime/`, `crates/navi-health/`; unified capture in app `src/domain/capture.rs` and `src/data/vision.rs` | Adapter tests with fixed wire fixtures; capture headless flows |
| Change the general assistant, memory or research tools | [Product Scope](product/product-scope.md), [Agent Runtime Current Architecture](architecture/agent-runtime-current.md) | `crates/navi-assistant/`, app `src/data/assistant*.rs`, `src/pages/assistant.rs` | Deterministic tool-loop and cancellation tests; session/backup/proposal contracts and assistant headless flows |
| Change the securities catalog | [`tool/asset_catalog/README.md`](../tool/asset_catalog/README.md) | `tool/asset_catalog/` | `python3 -m pytest tool/asset_catalog/tests`, catalog validator |
| Change CI or release flow | [Branch Protection](operations/branch-protection.md) | `.github/workflows/` | The affected workflow's own gate |
| Rust toolchain or workspace setup | [Local Development](development/local-development.md) | `rust-toolchain.toml`, `.cargo/config.toml` | `rtk cargo test` in the touched workspace |

## Source-Of-Truth Rules

- Code inventory comes from registries and tests, not copied Markdown lists.
- ADRs own direction decisions; Product Scope owns what is built; the roadmap
  owns unfinished sequencing only; crates own business behavior through their
  tests.
- When two documents overlap, follow the document whose contract explicitly
  says it owns the topic. If neither does, resolve ownership before adding a
  third description.
- `Last reviewed` is maintenance metadata, not proof of authority. Prefer the
  declared code authority and executable contracts.

## Verification

Run the focused `cargo test` suite of the touched workspace plus clippy with
`-D warnings`. For CI-equivalent commands, see
[Local Development](development/local-development.md). Do not run every suite
by default when a focused executable contract covers the change.
