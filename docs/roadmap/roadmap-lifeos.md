# NaviWealth LifeOS Roadmap

Status: active cross-domain sequencing SSOT.

Last reviewed: 2026-07-19.

This roadmap contains only work that changes cross-domain product outcomes or
shared delivery risk. Current architecture belongs in the architecture SSOTs,
domain behavior belongs in domain SSOTs, and test-layer policy belongs in the
testing strategy:

- FinanceOS sequencing: `roadmap-finance.md`
- HealthOS: `../domains/healthos-domain.md`
- KnowledgeOS: `../domains/knowledgeos-domain.md`
- ExecutionOS: `../domains/executionos-domain.md`
- Shell and registration seams: `../architecture/lifeos-shell.md`
- Hard boundaries and non-goals: `../architecture/lifeos-architecture-northstar.md`
- Test task inventory and coverage layers: `../development/testing-strategy.md`

## Product Snapshot

NaviWealth is a local-first Personal LifeOS. FinanceOS is always on; HealthOS,
KnowledgeOS, and ExecutionOS are user opt-in. Device AI remains native-only,
Web has neither an AI runtime nor Health platform integration, and the backend
remains a schema-agnostic Sync v3 row store.

The first production cross-domain loop is complete: Life signals expose local
evidence, confirmed proposals create source-preserving Execution actions, and
Execution Review shows whether the current source signal is cleared or still
active without claiming causality.

## Now

Keep at most three initiatives in this section. An initiative leaves `Now`
only when its exit evidence is present in the repository.

### N1. Real-World Statement Ingestion Quality

Outcome: reduce manual Finance entry without allowing imported rows to bypass
review, deduplication, or explicit confirmation.

Current evidence:

- Provider detection exists for Alipay, WeChat Pay, bank, broker, and generic
  statements.
- The checked-in representative corpus contains privacy-safe Alipay, measured
  WeChat Pay XLSX, and measured CMB credit-card PDF-layout fixtures. Their
  auto-discovered manifests pin every accepted and rejected row without
  retaining user data.
- WeChat XLSX capture stays on the local deterministic path. CMB statement
  text has a dedicated parser; binary PDF capture retains the existing
  provider-Vision boundary.
- Confirmation requires a selected statement account and batch confirmation
  excludes duplicate and likely-duplicate drafts. Unsupported trade principal
  and transfer/refund rows remain closed before draft creation.

Exit evidence:

- Add a redacted representative bank debit fixture only after a real sample or
  confirmed user demand is available.
- Each representative fixture pins provider detection, accepted/rejected row
  counts, direction, amount, status filtering, and privacy-safe diagnostics.
- Dedup behavior is covered for account, expense, trade, and transfer import
  paths.
- Capture remains offline-first: no synchronous LLM call, and every imported
  row remains a draft until confirmation.

Owner: FinanceOS. Cross-domain roadmap ownership reflects its current product
priority; parser and workflow details remain in `roadmap-finance.md`.

### N2. Data Portability Recovery Correctness

Outcome: make encrypted recovery trustworthy under destructive failure modes,
not merely navigable from Settings.

Current evidence:

- Restore validates authenticated payload structure and row counts before
  pausing Sync or opening the destructive transaction.
- Wrong passphrases, truncated/corrupt archives, incomplete current-schema
  archives, and failed row inserts preserve the existing database.
- Wipe, row insertion, and Sync outbox enqueue use one real Drift transaction.
- Older known-table archives preserve Sync metadata, and a 1,000-row recovery
  fixture is bounded to ten seconds in the deterministic test environment.
- The native file-backed integration suite now forces an in-transaction
  restore failure and proves the previous rows and outbox pointer survive a
  full database close/reopen. Android emulator CI owns the device evidence.
- A two-process Android harness now waits until a large valid restore has
  completed its transactional wipe, force-stops the app, then launches a fresh
  verifier against the same application data. It binds to the explicit
  emulator serial, proves the target PID existed and then stopped, rejects a
  skipped verifier through a dedicated evidence marker, and preserves a
  privacy-safe JSON summary with the raw log. A green emulator run containing
  that summary remains the required external device evidence.
- Successful backup export and restore now emit machine-readable diagnostics
  containing only schema version, full/domain scope, table count, aggregate
  row count, byte count, duration, and outcome. The tested restore summary
  excludes table names, row ids, and payload values.
- The generic encrypted export now has a cross-currency money contract test:
  ISO currency and high-precision decimal principal, rate, and payment fields
  survive decrypt/restore exactly, without symbols, grouping, or locale text.

Exit evidence:

- On-device Android recovery keeps the same atomicity guarantees under a
  process interruption or documents the platform-specific recovery path.

### N3. Android Database-At-Rest Encryption

Outcome: protect native local data at rest without silently losing existing
plaintext installs or replacing a missing device key.

Current evidence:

- Native builds select the SQLCipher community library through the supported
  `sqlite3` 3.x build hook and refuse to open unless `cipher_version` is
  available.
- A random 256-bit database key is stored through Android Keystore-backed
  secure storage. An existing encrypted file with a missing or malformed key
  fails closed; the client never generates a destructive replacement key.
- Existing plaintext SQLite files are exported into a validated encrypted
  temporary database. The original is retained through the swap, and the next
  launch can finish a process interruption or fall back from corrupt staged
  bytes without dropping rows.
- Native file tests prove a non-plaintext header, correct-key reopen,
  wrong-key rejection without byte changes, plaintext migration, interrupted
  migration recovery, and narrowly scoped reset. The root unlock gate exposes
  retry and a double-confirmed local reset only for unrecoverable key failures;
  migration and unknown failures remain non-destructive.
- Android cloud backup and device-to-device transfer are disabled because the
  OS cannot port the non-exportable Keystore key with SQLCipher bytes. Sync and
  app-owned encrypted exports remain the supported portability paths.
- The Android suite now exercises the production secure-storage resolver in
  addition to fixed-key cipher behavior: it requires key persistence across a
  new `FlutterSecureKeyStore` instance, fail-closed handling after key removal,
  and successful reopen after the original key is restored. Its CI wrapper
  rejects a nominally green Flutter run when any encryption, migration,
  Keystore, or backup/restore evidence marker is missing, and emits a separate
  privacy-safe JSON summary. A green emulator artifact is still required
  before this initiative can leave `Now`.

Exit evidence:

- A green Android emulator integration run proves SQLCipher availability,
  encrypted file bytes, correct-key reopen, wrong-key rejection, legacy
  plaintext migration, and existing backup/restore journeys on the packaged
  application.

## Next

These are accepted follow-ups but are not allowed to displace `Now` work
without an explicit reorder.

### Sync V3 Stability Gate

The client now sorts terminal samples by timestamp and persists a privacy-safe
rolling window of the latest 50 cycles in local-only `sync_meta`. The gate
requires at least 10 cycles spanning 14 days, at least 95 percent success, zero
fatal protocol errors, and zero generation-reset failures. Settings explains
whether evidence is still collecting, failing, or passing, identifies exact
blockers, and can copy aggregate JSON without row ids or payloads. The remaining
exit evidence is a real release window that reaches the gate before any Sync
E2EE decision.

## Triggered Bets

Triggered work stays out of `Now` and `Next` until its evidence is recorded.

| Area | Trigger | Required decision |
|---|---|---|
| Sync E2EE | Sync v3 meets the documented production stability gate | Threat model, key recovery, Rust/Dart boundary |
| New statement provider | Redacted real sample or repeated measured manual-entry pain | Format support and fixture ownership |
| Wider native engine | Demonstrated performance or security delta with a current caller | ADR and narrow FRB surface |
| iOS native distribution | iOS returns to the active platform scope | CocoaPods/cargokit CI and simulator/device smoke |
| Future LifeOS domain | Explicit user need that cannot fit an existing domain | New ADR and real domain package |
| Collaboration/social/publishing | No current trigger; outside product boundaries | Northstar change required |

## Completed Baseline

The following are current-state guarantees and must not be reintroduced as
future roadmap phases:

- Registry-driven multi-domain shell, opt-in, routes, tools, prompts, agents,
  proposal appliers, settings, data management, and background hooks.
- Source-preserving Health, Finance, and Knowledge Life-signal-to-Execution
  loops with task-level flow coverage.
- Deterministic Finance budget-pressure before/after interpretation through
  the same observational Life-to-Execution contract.
- Unified agent artifacts, result UI, preferences, scheduling, follow-up
  intents, trace links, visibility state, and FinanceOS agents. Every
  production Agent has executable ready and no-finding corpus coverage.
- A privacy-safe 30-day local Agent quality report exposes completed/ready,
  no-finding, failed, dismissed/snoozed, evidence-anchor, and actual navigation
  success rates with visible sample counts. It retains no result content,
  evidence ids, or routes; navigation history stores only timestamp and router
  acceptance.
- The fixed answer-quality gate emits aggregate forbidden-claim/evidence and
  missing-fact/evidence failures. Its JSON field allowlist, production route
  navigation, and cross-domain outcome corpus are deterministic regression
  contracts.
- Completed Life-to-Execution outcomes require a concrete source and a later,
  successful source-family evaluation. Loading, failed, or disabled sources
  remain unknown, and UI copy is observational rather than causal.
- Batch proposal progress, recovery, durable undo, and focused contracts.
- Memory answer-quality fixtures and navigable anchors for high-value reads;
  lower-value legacy tools gain anchors only when touched by a real workflow.
- Opt-in Sentry wiring plus Sync and performance diagnostic surfaces.
- Dart/Rust Sync v3 serializer fixtures, accepted-ack behavior, conflict and
  skipped-row diagnostics, and domain reset generations.
- Deferred startup composition: auth restore, sync, maintenance, Memory,
  agents, credentials, domain background work, and debug health checks do not
  block first paint.
- Native model lifecycle diagnostics and embedding fingerprint invalidation.
- The 2026-07-17 dependency maintenance pass and native Flutter golden harness.

## Roadmap Operating Rules

- `Now` contains outcomes, not completed implementation history or permanent
  engineering policy.
- Every initiative states current evidence and exit evidence. A broad verb such
  as “improve”, “harden”, or “deepen” is insufficient without observable scope.
- Triggered bets do not enter scheduled work until their trigger is recorded.
- Architecture boundaries and anti-goals are referenced from the Northstar;
  they are not duplicated here.
- When implementation satisfies an exit criterion, update this roadmap in the
  same change and move the item to `Completed Baseline` or a release changelog.
- Mutable roadmap section numbers must not be used as source-code contract
  references; code should cite a stable architecture/domain SSOT or the owning
  test instead.
