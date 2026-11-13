# LifeOS Client Migration Roadmap

Status: active sequencing SSOT; replaces the previous Now/Next plans.

Last reviewed: 2026-11-13.

## Contract And Baseline

[ADR 0001](../architecture/adr/0001-nsh-client-migration.md) owns the NSH/Rust
direction and open platform decisions. The [Northstar](../architecture/lifeos-architecture-northstar.md)
owns boundaries; domain SSOTs own business behavior; [Sync v3](../sync/sync-v3.md)
owns the unchanged protocol. This roadmap owns unfinished migration sequencing.

Flutter (`apps/mobile`) is frozen: fix bugs only; put new features in NSH and
Rust crates. The NSH 0.5.0 meal client and shared `health-core` are the seed.
Meals still use KV; API credentials are currently plaintext in KV. Neither
SQLite migration nor cross-client Sync has been delivered by Phase 0.

The [Finance roadmap](roadmap-finance.md) and
[product-direction study](product-direction-and-demand-validation.md) are
archived historical inputs. Their Now/Next priorities do not authorize work.
Owner labels below identify accountable roles, not assigned people. Each
implementation PR must name its actual owner and attach the gate evidence.
Phases are dependency gates, not dates or claims of completion.

## Phase 0 — Freeze And Architecture Decision

- Owner: architecture maintainer, with product owner for open decisions.
- Scope: accept ADR 0001; freeze Flutter feature work; update the Northstar,
  documentation router, guide, navigation, and this roadmap; archive old plans.
  Inspect the Agent Runtime submodule branch without pushing its `main`.
- Exit evidence: consistent architecture and entry documents, no broken links,
  documentation checks, NSH tests, and the requested Flutter regression checks
  for the existing shared-meal/FRB change; reviewed PR with actual CI results.
- Stop condition: unresolved contradictory ownership or broken documentation
  blocks declaring the freeze complete. Record failed checks explicitly;
  Phase 0 does not assert any Phase 1 technical proof.

## Phase 1 — Technical Proofs

Owner: Rust/platform maintainer; product owner resolves platform choices.
Keep probes small and record build commands, pinned dependencies, device/ABI,
observed results, and limitations. All four probes need recorded outcomes:

1. **Android rusqlite + SQLCipher.** Package and run an encrypted database on
   Android arm64; create, read, update, close, and reopen rows. Demonstrate
   atomic migrations and wrong-key rejection, and inspect the packaged native
   dependencies. Exit evidence is device logs and a reproducible APK/database
   test. Stop if encryption, linking, or reopen durability cannot be proved;
   do not substitute plaintext persistence.
2. **Kotlin Keystore over NSH host channel.** Prove a minimal plugin can store,
   retrieve, and delete a secret across process restarts, handle missing or
   invalidated keys, and remove migrated plaintext KV credentials. Document
   lifecycle and error contracts. Exit evidence is a device exercise with no
   secret in logs, backup, or Sync. Stop if the host channel or key lifecycle
   cannot safely support the app; keep credential migration blocked.
3. **Pure Rust NSH Web.** Build and run the actual Rust UI on Web, exercising
   navigation and a viable persistence boundary. Exit evidence is a browser
   build/smoke result or a reproducible unsupported-target failure, not NSH
   marketing support alone. If pure Rust fails, the product owner must choose
   dropping Web or a TSX UI. Stop Web implementation until that choice;
   Web continues to exclude device AI and Health platform integration.
4. **`nsh-base` plot suitability.** Reproduce representative `fl_chart` needs:
   time series, bars, axes/labels, gaps, touch inspection, large histories,
   theme and accessible summaries. Exit evidence is a comparison on Android
   with performance and interaction results. Stop expansion if critical chart
   behavior is absent; agree a bounded adapter or narrowed scope before porting.

Phase exit: all outcomes are recorded, native blockers are resolved, and Web
scope is explicitly decided. iOS remains outside active delivery until a
product decision and native proof add it. A failing critical proof pauses the
migration path that depends on it; it does not reopen Flutter feature work.

## Phase 2 — Shared Storage And Meal Sync

- Owner: Rust persistence/sync maintainer and Health maintainer.
- Scope: implement `lifeos-core` (rusqlite + SQLCipher, HLC, outbox, accepted
  acks, domain generations, audit, backup) and `sync-wire` (envelopes and exact
  per-table JSON row formats shared with backend). Move NSH meal persistence
  to domain-owned SQLite repositories and sync `health:health_meals`.
  Migrate existing NSH KV meals transactionally before clearing legacy values.
- Exit evidence: create/edit/delete on Flutter and observe on NSH, then the
  reverse, using the same test account. Include concurrent/offline changes,
  retries, accepted acks, tombstones, reset-generation rejection, process
  restart, and backup/restore tests against existing Sync v3 fixtures. Pull an
  existing server account into a clean NSH database without Drift conversion.
- Dependencies: native storage/key proofs from Phase 1. Production coexistence
  requires the product owner's decision; test-account interoperability does not.
- Stop condition: any row-format divergence, data loss, reset resurrection,
  key exposure, or failed restore blocks rollout. Do not invent a new Sync
  version to bypass incompatibility or assume photos/local-only rows sync.

## Phase 3 — Health, Execution, Knowledge, And Shell

- Owner: respective domain maintainers and NSH shell maintainer.
- Scope: move remaining Health models/repositories and platform adapters,
  Execution plans/actions/progress, Knowledge notes/decisions/relations, and
  domain opt-in/navigation to Rust. Implement a `DomainPack`-style Rust trait
  registry. Use an Android Kotlin host plugin for Health Connect and background
  work where NSH needs it. Keep the UI focused on existing tasks.
- Exit evidence: each domain passes repository and wire fixtures, cross-client
  create/edit/delete checks, inactive-domain gating, source routing, and
  `nsh-testing` shell flows; Android platform permission/resume behavior is
  exercised on a device. Record parity gaps per domain before cutover.
- Dependencies: Phase 2 storage, Sync, audit, and restore contracts.
- Stop condition: cross-domain imports, UI-owned business truth, missing opt-in
  isolation, or unsupported native behavior blocks the affected domain cutover.

## Phase 4 — In-Process AI

- Owner: AI runtime and native capability maintainers.
- Scope: implement `lifeos-ai` as the in-process Agent Runtime host; register
  domain tools through traits; port confirmation, proposals, memory, transport,
  cancellation, and audit seams. Replace remaining FRB/native capabilities and
  remove FRB / `lifeos_native` once no supported client depends on them.
- Exit evidence: domain tool and proposal parity, provider/transport contract
  tests, cancellation/resume and secret-isolation tests, device runtime checks,
  and an inventory proving no live FRB caller remains. Stage deletion after
  Flutter callers are retired or given replacements; retain the adapter while
  they exist, even if final deletion must wait for Phase 6.
- Dependencies: domain ownership/registry from Phase 3; a reviewable upstream
  integration for the Agent Runtime transport branch.
- Stop condition: missing confirmation, a second Agent loop, cloud fallback,
  or any remaining dependent client blocks runtime/bridge removal.

## Phase 5 — Finance In Batches

- Owner: Finance maintainer with persistence and NSH maintainers.
- Scope: build `finance-core`; begin with accounts, expense, ingest, Monthly
  Close, Runway, and Inbox. Port remaining Finance capabilities in separate
  dependency-ordered batches, each with an explicit inventory and parity gate.
  Reuse statement corpus fixtures and expected accepted/rejected rows.
- Exit evidence: per-batch exact money/rounding and repository tests, existing
  JSON row compatibility, deduplication/reversal and audit tests, cross-client
  Sync, and `nsh-testing` task flows. Compare imports and consequential financial
  calculations against the frozen implementation; complete chart device checks.
- Dependencies: Phase 2 storage and Phase 3 shell; AI workflows require Phase 4.
- Stop condition: an unexplained calculation delta, duplicate financial effect,
  missing source provenance, or absent corpus coverage blocks that batch.
  Do not use Finance size as a reason for an unverified big-bang replacement.

## Phase 6 — Retire Flutter

- Owner: release maintainer and product owner, with all domain maintainers.
- Scope: cut over supported platforms, close any remaining native adapter
  removal, retire Flutter distribution and obsolete code/CI after user data
  continuity is established. Update implementation SSOTs to Rust code authority.
- Exit evidence: all supported domain workflows and platform choices signed
  off; packaged-device acceptance, NSH release CI, successful server-pull
  migration and encrypted restore/recovery exercises, and a rollback/retention
  plan covering unsynced and local-only data. No remaining FRB consumers.
- Dependencies: domain parity across Phases 3–5 and explicit decisions on Web,
  coexistence, and iOS. Keep unsupported platforms outside release claims.
- Stop condition: any account lacks a tested recovery path, an active platform
  has no accepted replacement, or a supported workflow still requires Flutter.
  Do not delete local data simply because the new client can sign in.

## Operating Rules

- Do not start broad domain ports before their technical and data gates pass.
- Record implementation, headless tests, packaged-device evidence, and user
  acceptance separately. Passing one is not proof of another.
- Lock the reviewed NSH baseline and keep framework calls behind local UI
  adapters. Upgrade deliberately with device and regression evidence.
- The backend stays a generic Sync v3 store; domain semantics stay client-side.
- Keep domain business truth in the owning Rust crate and cross-domain
  infrastructure neutral. New crates need current callers, not speculative APIs.
- Track open product decisions in ADR 0001. No phase silently decides platform
  support or authorizes production dual-client operation.
