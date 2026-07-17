# NaviWealth LifeOS Roadmap

Status: active cross-domain sequencing SSOT.

Last reviewed: 2026-07-17.

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
- The checked-in representative corpus contains an Alipay export with an
  auto-discovered, privacy-safe row-level expectation manifest. WeChat Pay and
  bank coverage is still synthetic and must not be described as verified
  production-format support.
- Confirmation requires a selected statement account and batch confirmation
  excludes duplicate and likely-duplicate drafts. Unsupported trade principal
  and transfer/refund rows remain closed before draft creation.

Exit evidence:

- Add redacted representative WeChat Pay and bank debit/credit fixtures only
  after real samples or confirmed user demand are available.
- Each representative fixture pins provider detection, accepted/rejected row
  counts, direction, amount, status filtering, and privacy-safe diagnostics.
- Dedup behavior is covered for account, expense, trade, and transfer import
  paths.
- Capture remains offline-first: no synchronous LLM call, and every imported
  row remains a draft until confirmation.

Owner: FinanceOS. Cross-domain roadmap ownership reflects its current product
priority; parser and workflow details remain in `roadmap-finance.md`.

### N2. Cross-Domain Outcome And Agent Quality

Outcome: make proactive results useful, evidence-backed, and low-noise rather
than increasing the number of agents or creating another AI destination.

Current evidence:

- The Health, Finance, and Knowledge signal-to-Execution flows preserve source
  references through completion and Review.
- Agent results share one artifact, presentation, intent, proposal, trace, and
  visibility model across active `DomainPack`s.
- Fixed answer-quality cases already score required facts, forbidden claims,
  and expected/forbidden evidence ids.

Exit evidence:

- Every production agent has executable ready, no-finding or skip/failure
  cases appropriate to its behavior, with evidence and action-intent checks.
- New cross-domain outcome interpretation is added only for deterministic
  before/after signals and keeps observational wording where causality cannot
  be established.
- The evaluation report exposes high-signal result rate, no-finding rate,
  dismissed/snoozed result rate, evidence-navigation success, and forbidden
  claim failures without capturing private payloads.
- Lower-value legacy read tools gain `EvidenceAnchor`s only when touched by a
  real workflow; ids are not guessed from arbitrary JSON.

### N3. iOS Native Runtime Distribution Confidence

Outcome: make the narrow Rust EmbeddingGemma and agent-runtime surface
installable and diagnosable on iOS before expanding native capability.

Current evidence:

- Android arm64 release builds and Android emulator integration tests run in
  CI.
- Model download, verification, deletion, recovery diagnostics, fingerprint
  changes, and stale-vector deletion are implemented and tested.
- Web remains on stub behavior.

Exit evidence:

- A macOS CI job builds iOS with `--no-codesign` through the production
  CocoaPods/cargokit path.
- An iOS simulator or device smoke proves the bundled native library loads,
  missing model files fall back safely, and installed model files resolve.
- Packaging failures identify whether the native library, ONNX Runtime, or
  model bundle is missing without exposing user content.
- The current CocoaPods dependency is recorded explicitly while Swift Package
  Manager support remains unavailable.

## Next

These are accepted follow-ups but are not allowed to displace `Now` work
without an explicit reorder.

### Sync V3 Stability Gate

Define the production stability window before deciding on Sync E2EE. The gate
must specify release duration, successful-cycle rate, fatal protocol errors,
conflict/skipped-row diagnostics, reset-generation failures, and recovery
evidence. Existing Dart/Rust serializer fixtures and conflict diagnostics are
baseline, not future work.

### On-Device Database Encryption Decision

The on-device integration layer proves the real file-backed Drift connection,
migrations, repository writes, and backup/restore, but the SQLCipher
PRAGMA/key-recovery path is not implemented. Either promote database-at-rest
encryption into a scoped initiative with key-loss/recovery acceptance tests or
record an explicit non-goal and threat-model rationale.

### Data Portability Recovery Matrix

Extend the existing backup/restore/export task coverage only around real
failure modes: wrong passphrase, corrupt/truncated archive, interrupted
restore, cross-version migration, and large datasets. Do not add more
page-bound navigation tests as a proxy for recovery correctness.

## Triggered Bets

Triggered work stays out of `Now` and `Next` until its evidence is recorded.

| Area | Trigger | Required decision |
|---|---|---|
| Sync E2EE | Sync v3 meets the documented production stability gate | Threat model, key recovery, Rust/Dart boundary |
| New statement provider | Redacted real sample or repeated measured manual-entry pain | Format support and fixture ownership |
| Wider native engine | Demonstrated performance or security delta with a current caller | ADR and narrow FRB surface |
| Future LifeOS domain | Explicit user need that cannot fit an existing domain | New ADR and real domain package |
| Collaboration/social/publishing | No current trigger; outside product boundaries | Northstar change required |

## Completed Baseline

The following are current-state guarantees and must not be reintroduced as
future roadmap phases:

- Registry-driven multi-domain shell, opt-in, routes, tools, prompts, agents,
  proposal appliers, settings, data management, and background hooks.
- Source-preserving Health, Finance, and Knowledge Life-signal-to-Execution
  loops with task-level flow coverage.
- Unified agent artifacts, result UI, preferences, scheduling, follow-up
  intents, trace links, visibility state, and FinanceOS agents.
- Batch proposal progress, recovery, durable undo, and focused contracts.
- Memory answer-quality fixtures and navigable anchors for high-value reads.
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
