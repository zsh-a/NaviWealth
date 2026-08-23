# NaviWealth LifeOS Roadmap

Status: active cross-domain sequencing SSOT.

Last reviewed: 2026-08-23.

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

### N2. Six-Week Product Discovery Study

Outcome: validate whether the current activation, Inbox, Runway, and decision
loops produce a weekly return event before adding more features or domains.

Current evidence:

- The product-direction SSOT (`product-direction-and-demand-validation.md`)
  defines a target-user hypothesis, three validation tasks, six-week
  recruitment plan, and five explicit validation gates.
- Finance activation is a resumable first-task path with opt-in local
  product-funnel measurement.
- Financial Inbox, Monthly Close, Money Runway, and decision review actions
  are implemented and testable end-to-end.
- The six-week study instruments the existing activation, Inbox, and
  repeated-close paths; no new telemetry surface is required to begin.

Exit evidence:

- Recruit 15 to 20 participants matching the target-user hypothesis.
- Complete three tasks per participant: import and close one statement period,
  answer whether the next 90 days are safe, and compare alternatives for one
  real decision.
- Record time, corrections, abandoned steps, external tool switches, and
  whether each result caused a real follow-up action.
- Pass or fail each of the five validation gates with an explicit
  stop/continue/pivot decision recorded in this roadmap.

Owner: cross-domain. Domain teams provide task support; the study result
changes sequencing for all downstream roadmap work.

## Delivered

These cross-domain initiatives have repository exit evidence. Follow-up work
must enter `Now` or `Next` with a new measurable outcome instead of reopening
the removed legacy architecture.

### Personal Intelligence Loop

Outcome: turn the existing domain Agents, Memory Runtime, Life signals, and
proposal safety seams into one personal intelligence loop that correlates
active-domain evidence, stays silent when nothing material changed, and gives
the user one traceable next-step judgment on the Life surface.

Delivered evidence:

- The Life hub already composes bounded deterministic signals contributed by
  active `DomainPack`s, and source-preserving Life actions can be evaluated
  against later domain state.
- `AgentArtifact`, stable findings, trace links, evidence navigation,
  dismiss/snooze state, proposal confirmation, and outcome corpus evaluation
  already provide most of the trust and presentation substrate.
- `EventRecord` now requires typed domain/kind/time/source identity, confidence,
  facts, entities, and evidence anchors. Schema v73 rebuilt the derived event
  index directly; no legacy free-form event contract remains.
- `PersonalProfileSnapshot` materializes explicitly confirmed structured
  profile facts with authority, provenance, scope, and validity metadata.
  `LifeContextSnapshot` combines that stable profile with fingerprinted
  active-domain state, freshness, changes, goals, constraints, and relevant
  history.
- The app-owned Daily Navigator consumes domain-owned `LifeSignal`s, gates on
  material change and evidence freshness before any model call, and owns the
  Life-surface cross-domain judgment. The retired Health-owned briefing code,
  preferences, UI, schedules, notifications, and tests were removed.
- `AgentTrigger` supports schedule, event, threshold, state transition,
  freshness, and manual triggers. Knowledge write debounce uses the shared
  coordinator, while Daily Navigator combines signal triggers with a schedule
  fallback.
- `AttentionArbiter` is the only notification policy owner. It persists
  `silent`, `surface`, or `interrupt` decisions under a global interrupt
  budget; the background-safe callback reads only a precomputed primitive
  snapshot and never invokes an LLM or writes business data.
- Durable Memory has explicit retrieval role, evidence authority, provenance,
  and supersede lineage. Domain Agents no longer write periodic summaries into
  Memory or directly send notifications; Agent Artifacts remain temporary
  unless the user explicitly confirms a Memory proposal.
- Structured Agent feedback links accepted, dismissed, snoozed, completed, and
  undone outcomes to Life context, finding, and attention fingerprints. The
  policy corpus evaluates silence, duplication, stale data, evidence,
  actionability, severity, domain isolation, and interrupt budget behavior.
- Advanced Settings now exposes local-only Developer Issue capture. It retains
  the last domain route, build identity, latest trace id, at most five tool
  error codes, and optional screenshot identity; export is explicit, excludes
  user identity and local paths, and never creates a remote issue.

Delivered vertical slices:

1. **Typed event and evidence identity.** Added explicit domain, namespaced kind,
   occurred/observed times, source row family/id/fingerprint, confidence, and
   stable evidence identity to the cross-domain event contract. Migrated
   storage and all four current domain indexers directly. Unknown domains fail
   closed rather than defaulting to Finance; source routes resolve through
   registered domain contributions.
2. **Personal profile and Life context.** Materialized a structured
   `PersonalProfileSnapshot` for goals, preferences, constraints, and rules,
   with authority, provenance, confirmation, validity, and update metadata.
   Domain baselines and routines remain deterministic current-state inputs or
   explicitly confirmed profile rules rather than model-authored profile data.
   Composed it with deterministic active-domain state, freshness, recent
   changes, goals, and relevant history into a fingerprinted
   `LifeContextSnapshot`. Domain business calculations remain domain-owned;
   app composition assembles only domain-neutral slices.
3. **Daily Navigator vertical slice.** Added one app-owned Life synthesis Agent
   and a Life-surface presentation owner without creating a new opt-in domain.
   It starts with available Health and Finance findings, with Execution context
   included only when enabled and relevant. The Agent correlates, prioritizes,
   explains, and proposes a next step; it does not recalculate domain metrics
   or write business rows directly. It invokes the device LLM only after a
   deterministic material-change gate, retains a deterministic fallback, and
   replaces the removed duplicate domain-owned briefing implementation.
4. **Signal-driven triggers and attention arbitration.** Introduced event,
   threshold, state-transition, freshness, schedule, and manual trigger specs
   without conflating them with persisted run provenance. Migrated the existing
   Knowledge debounce path first, then connect real Finance import and Health
   refresh transitions. Routed every candidate through one global attention
   decision (`silent`, `surface`, or `interrupt`) that considers novelty,
   severity, confidence, actionability, recent notifications, and current
   dismiss/snooze state. A bounded background-safe path may inspect only a
   precomputed snapshot and record pending attention; it must not invoke an
   LLM or mutate business data.
5. **Memory hygiene, feedback, and policy evaluation.** Distinguished source
   facts, user-confirmed records, deterministic derived records, model-derived
   candidates, and temporary Agent artifacts through evidence authority,
   provenance, retrieval role, and access policy. Agent
   artifacts do not become durable Memory by default; periodic reviews remain
   artifacts, and only explicit confirmation can promote an Agent inference
   into durable Memory or the personal profile. Linked accepted,
   dismissed, snoozed, completed, and undone suggestions back to their
   snapshot/finding fingerprints. Extended the Agent corpus to test whether a
   result should appear at all, and added Developer Mode issue capture with
   explicit local export of route, build, trace, bounded tool errors, and an
   optional screenshot.

Repository verification:

- Every event written by Finance, Health, Knowledge, and Execution has an
  explicit domain and source identity. Regression fixtures prove that unknown,
  Knowledge, and Execution events cannot enter Finance synthesis by exclusion.
- Every evidence-bearing ready artifact in the vertical slice resolves to the
  correct active-domain source route. Missing or inactive-domain evidence
  fails closed instead of routing to a generic or wrong domain page.
- A deterministic fixture produces the same personal profile and Life context
  fingerprint from the same inputs. Stale inputs are marked explicitly, and
  unconfirmed profile candidates cannot act as hard constraints or authorize
  a proposal.
- A checked-in Health/Finance fixture produces one Daily Navigator artifact
  with conclusion-level evidence and at most one confirmed action path. A
  no-material-change fixture produces no visible artifact and records zero LLM
  calls; inactive-domain and stale-data fixtures make no cross-domain claim.
- Trigger tests prove debounce/idempotency, threshold and state-transition
  behavior, and schedule fallback. Background tests prove that the
  background-safe path performs no LLM call, tool effect, proposal apply, or
  business write.
- Every notification is backed by a persisted attention decision. Duplicate,
  unchanged, dismissed, and actively snoozed findings cannot consume the
  interrupt budget, while silent decisions remain available to local quality
  evaluation.
- Retrieval tests prove that temporary Agent artifacts are excluded from
  durable personal context unless explicitly promoted; periodic Agent reviews
  no longer write durable Memory rows.
- The Agent policy corpus covers `should_surface`, `should_stay_silent`,
  severity, evidence completeness, actionability, duplicate suppression,
  stale data, wrong-domain combination, and no-model-call gating. Architecture
  composition and lint tests continue to enforce active-domain isolation and
  the boundaries owned by the LifeOS Northstar and Agent Experience SSOT.
- The local dogfood surface records export state and Agent feedback records
  real outcome transitions without promoting either record into Memory.

Owner: cross-domain app composition. Domains own deterministic facts,
findings, routes, and proposal application; shared contracts and lifecycle
policy remain in their existing core seams.

### Agent Runtime Capability Contract

Outcome: keep NaviWealth's runtime integration documentation aligned with the
exact pinned standalone runtime instead of manually copying a fast-moving
capability inventory.

Delivered evidence:

- NaviWealth pins `third_party/agent-runtime` at
  `a89e11b0924107b637e741aeb8d75950b6430ac6`.
- That commit contains the dependency-light `bindings/ts` package and lists it
  in the runtime README.
- Exact runtime APIs are already owned by the submodule crates, schemas,
  fixtures, and contract tests; the host documentation should describe the
  integration boundary rather than duplicate their feature list.

Repository verification:

- `tool/generate_agent_runtime_capabilities.dart` derives a machine-readable
  manifest from the pinned submodule's Cargo metadata, package metadata,
  schemas, and README.
- `docs/architecture/agent-runtime-capabilities.json` records the pinned commit,
  bindings, transports, stores, providers, and protocol/snapshot versions.
- `tool/check-mobile-static.sh` runs the generator in `--check` mode, and CI
  checks out the submodule before that gate.
- `agent-runtime-current.md` references the generated manifest and retains only
  NaviWealth-owned integration boundaries and host limitations.

Owner: native Agent Runtime integration. This track may proceed independently
and does not block the Personal Intelligence Loop vertical slice.

## Next

These are accepted follow-ups but are not allowed to displace `Now` work
without an explicit reorder.

### Data Portability Recovery Correctness

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

### Android Database-At-Rest Encryption

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

### Sync V3 Stability Gate

The client now sorts terminal samples by timestamp and persists a privacy-safe
rolling window of the latest 50 cycles in local-only `sync_meta`. The gate
requires at least 10 cycles spanning 14 days, at least 95 percent success, zero
fatal protocol errors, and zero generation-reset failures. Settings explains
whether evidence is still collecting, failing, or passing, identifies exact
blockers, and can copy aggregate JSON without row ids or payloads. The remaining
exit evidence is a real release window that reaches the gate before any Sync
E2EE decision.

### Platform Quality Track

Outcome: make the existing cross-domain loops feel native at 120fps and reach
feature parity on Web without weakening device-only guarantees.

Current evidence:

- Scroll perf analysis identified repeated `List<_FeedItem>` and
  `List<_TimelineItem>` allocations in Activity Feed and AI Chat that were
  causing GC pressure on every scroll tick. Caching these lists removes the
  per-frame allocation spike.
- Web builds exclude AI runtime and Health platform integration by design; the
  remaining parity gap is UI completeness, not architecture.
- The project has lint gates for cross-feature imports, domain-neutral
  contracts, and FRB entrypoints.

Exit evidence:

- Activity Feed and AI Chat maintain 8ms frame budget on 120Hz test devices
  during sustained scroll, measured in Flutter DevTools performance traces.
- Web parity checklist covers every cross-domain shell route, settings panel,
  Finance view, and Knowledge view currently available on mobile.
- Platform quality regressions are caught by a targeted widget or integration
  test added for each identified hotspot.

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

## Current Capability Source

Completed behavior is intentionally not archived in this roadmap. Current
cross-domain guarantees belong in the architecture, AI, Sync, and domain SSOTs
routed by the [Agent Task Map](../agent-map.md); exact coverage belongs in
executable tests. Release history belongs in Git tags and release notes.

## Roadmap Operating Rules

- `Now` contains outcomes, not completed implementation history or permanent
  engineering policy.
- Every initiative states current evidence and exit evidence. A broad verb such
  as “improve”, “harden”, or “deepen” is insufficient without observable scope.
- Triggered bets do not enter scheduled work until their trigger is recorded.
- Architecture boundaries and anti-goals are referenced from the Northstar;
  they are not duplicated here.
- When implementation satisfies an exit criterion, remove it from this
  roadmap, update the owning SSOT when behavior changed, and record release
  history in the release notes.
- Mutable roadmap section numbers must not be used as source-code contract
  references; code should cite a stable architecture/domain SSOT or the owning
  test instead.
