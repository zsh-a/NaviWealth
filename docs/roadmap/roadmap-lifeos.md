# NaviWealth LifeOS Roadmap

Status: active cross-domain roadmap.

This document owns product and engineering sequencing that cuts across
FinanceOS, HealthOS, KnowledgeOS, and ExecutionOS. Domain-specific behavior remains in
the domain SSOTs:

- FinanceOS: `roadmap-finance.md`
- HealthOS: `../domains/healthos-domain.md`
- KnowledgeOS: `../domains/knowledgeos-domain.md`
- ExecutionOS: `../domains/executionos-domain.md`
- Shell and registration seams: `../architecture/lifeos-shell.md`
- Hard boundaries and non-goals: `../architecture/lifeos-architecture-northstar.md`

## Current Product Shape

NaviWealth is now a local-first Personal LifeOS:

| Domain | Activation | Primary value |
|---|---|---|
| FinanceOS | Always on | Wealth, cashflow, FIRE, investment, options income |
| HealthOS | User opt-in | Recovery signals, health trends, morning briefing |
| KnowledgeOS | User opt-in | Decision memory, assumptions, routines, review work |
| ExecutionOS | User opt-in | Personal actions, projects, commitments, progress review |

FinanceOS remains the seed domain, but the active roadmap is no longer
Finance-only. New work should improve the shared LifeOS substrate or close
one domain's real user workflow; do not add untriggered domains.

## Priority Order

### 1. Cross-Domain User Loop Depth

The first production cross-domain loop is now complete:

- Life Hub turns local Finance, Health, Knowledge, and agent state into
  actionable signals.
- Opening a signal shows the local evidence before offering an action.
- The user explicitly confirms an existing `execution_action` proposal; the
  resulting Execution Action keeps a domain-neutral source reference and the
  evidence snapshot in its note/reason.
- Execution Today owns completion, and Execution Review closes the visible
  loop. If ExecutionOS is disabled, the flow routes through domain settings
  instead of writing into an inactive domain.
- `life_execution_loop_flow_test.dart` proves the Health recovery vertical
  slice from signal through completed Review history.
- `life_finance_knowledge_execution_flow_test.dart` now proves the same
  source-preserving loop for Finance day evidence and the Knowledge inbox.
- Execution Review compares a completed action's source reference with the
  complete current Life signal candidate set and labels the outcome as
  cleared or still active. The comparison is deliberately observational; it
  does not claim that completing the action caused the source signal to move.

Keep this as the canonical pattern: originating domains contribute evidence
and suggested intent, `proposalApplierProvider` owns confirmed application,
and ExecutionOS owns action lifecycle. Do not add a second cross-domain task
store. Proposal appliers are resolved lazily after routing by kind, so an
Execution confirmation does not wait for unrelated domain repository graphs.
Next, deepen domain-specific outcome interpretation only where a domain has a
real, deterministic before/after signal.

### 2. High-Quality Data Ingestion

FinanceOS value is still limited by manual data entry. The ingest substrate
and provider detection exist; the next step is expanding the real, redacted
fixture corpus beyond Alipay and hardening provider-specific parsing:

- Add representative WeChat Pay and bank debit/credit export fixtures only
  from redacted real files or confirmed user demand.
- Keep review and dedup explicit.
- Do not call the LLM synchronously on capture/import save paths.
- Treat imported data as draft until the user confirms it.

### 3. Task-Spine Maintenance

The stable task spine now covers 17 journeys: the original 12 Finance/global
jobs plus optional-domain enablement, Knowledge capture, and Health, Finance,
and Knowledge Life-signal-to-Execution-Review loops. Maintain task-level tests
and product polish around durable user jobs, not pages:

- Add account.
- Import CSV or statement.
- Ask AI with local evidence.
- Generate FIRE report.
- Plan options income.
- Backup, restore, and export.

New journeys should earn a flow test only when they represent a durable job,
plus a primary-surface golden where useful and a targeted integration or
contract test for the data path.

### 4. AI Evidence, Proposal, And Memory Quality

Device AI should be auditable by construction:

- Tool outputs should return `EvidenceAnchor` where they cite local state.
- Write tools should return proposals or use explicit confirmation.
- Batch proposals need UI, undo, and progress treatment before they become
  normal agent output.
- Standard agent-result follow-up intents should be contributed by every
  agent-capable domain and de-duplicated at domain composition, so shared
  result actions do not depend on one seed domain's registry.
- Memory retrieval should be evaluated for answer quality, not only for
  successful vector lookup.

Current hardening baseline:

- Batch proposal UI includes progress, recovery, durable undo, and focused
  contract/widget tests.
- Standard agent-result intents are contributed by every agent-capable pack
  and de-duplicated in app composition.
- Fixed Memory answer-quality cases score required facts, forbidden claims,
  and expected/forbidden evidence ids.
- High-value Finance account/holding reads, all Health summary/trend reads,
  Knowledge search/review reads, and Execution list/summary reads emit
  navigable `EvidenceAnchor`s. Continue migrating lower-value legacy reads as
  they are changed; do not infer anchors from arbitrary JSON ids.

### 5. Observability And Diagnostics

Default-off observability should become useful for development and opt-in
production diagnostics:

- Sentry initialization is wired in `app/bootstrap.dart` behind
  `OptInCrashReporter` and the user's diagnostics preference.
- Surface sync and performance diagnostics in developer-facing views.
- Keep payload capture disabled unless the user explicitly enables verbose
  local diagnostics.

### 6. Sync Hardening

Sync v3 remains row-state LWW. Near-term work should harden the protocol,
not redesign it:

- Add Dart-to-Rust wire contract tests.
- Make conflicts and skipped rows diagnosable.
- Start E2EE only after the v3 stability window is met.
- Keep the backend schema-agnostic.

### 7. Bootstrap And Startup Composition

`bootstrap.dart` is the current composition root, but startup concerns should
stay modular:

- Move domain startup jobs into small startup modules.
- Keep provider overrides grouped by concern.
- Make eager background jobs opt-in aware and cheap at first paint.

### 8. Native Embedding Distribution

The Rust EmbeddingGemma path is a narrow native surface. It should be made
installable and diagnosable before more native runtime is added:

- Verify iOS and Android bundling paths.
- Keep Web on stub behavior.
- Model download, verification, deletion, and recovery diagnostics are
  available in the AI Models settings surface.
- Test embedder fingerprint changes and vector invalidation.

### 9. Dependency Maintenance

Maintenance pass completed on 2026-07-17:

- Replaced discontinued `golden_toolkit` with Flutter's native
  `matchesGoldenFile` matcher plus the repository's deterministic font,
  platform, bounded-pump, and real-shadow harness.
- Upgraded compatible runtime patches for Dio, Drift, Sentry, SQLite,
  image/image picker, local auth, sharing, package info, logging, UUID, and
  cross-file support.
- Keep `flutter_riverpod` at 3.2.1 until the recorded resumed-provider
  regression is fixed; keep `receive_sharing_intent` at 1.8.1 while the native
  Rust plugin requires CocoaPods; keep `drift_dev` at 2.34.0 until its analyzer
  requirement converges with Freezed. FRB beta and Forui upgrades require
  targeted native/UI validation rather than blind version bumps.

### 10. Engineering Debt Burn-Down

Keep the ratchets moving down:

- Keep the non-golden test suite at zero failures; do not introduce failure
  allowlists.
- Keep boundary lint gates green.
- Prefer contract tests for cross-language or cross-domain seams.

### 11. Completion Audit Discipline

Before claiming a roadmap item done, prove it from current state:

- Identify the authoritative file, test, command, or runtime behavior.
- Verify the full stated scope, not a narrow proxy.
- Update the owning SSOT when the implementation changes the roadmap.

## Anti-Goals

- Do not add TimeOS, LivingOS, or any future domain without a new ADR.
- Do not turn sync v3 into CRDT, event sourcing, or schema negotiation.
- Do not add a backend AI relay.
- Do not put domain entities into `core/` contracts.
- Do not introduce social, collaboration, publishing, or entertainment
  surfaces.
