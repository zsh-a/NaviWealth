# NaviWealth LifeOS Roadmap

Status: active cross-domain sequencing SSOT.

Last reviewed: 2026-10-24 against the owning code and executable contracts.

## Document Contract

This document owns unfinished cross-domain work, delivery order, and release
acceptance. Architecture and domain SSOTs own current behavior; the
[Product Direction And Demand Validation](product-direction-and-demand-validation.md)
document owns research sources, product hypotheses, and study design.
Completed implementation appears below only where it establishes the starting
point or explains a remaining gap. Release history belongs in Git.

| Concern | Authority |
|---|---|
| Finance implementation sequencing | [FinanceOS Roadmap](roadmap-finance.md) |
| Shell and composition | [LifeOS Shell](../architecture/lifeos-shell.md) |
| Boundaries and non-goals | [Architecture Northstar](../architecture/lifeos-architecture-northstar.md) |
| Domain behavior | [Finance](../domains/financeos-domain.md), [Health](../domains/healthos-domain.md), [Knowledge](../domains/knowledgeos-domain.md), [Execution](../domains/executionos-domain.md) |
| Verification layers and device evidence | [Testing Strategy](../development/testing-strategy.md) |
| Memory work deferred beyond V1 | [Personal Memory Implementation Plan](../ai/personal-memory-implementation-plan.md) |

## Planning Baseline

Finance remains the always-on acquisition domain; Health, Knowledge, and
Execution are opt-in. The product loop is reviewed personal data → an informed
decision → a confirmed Action → a later source review. AI remains native-only;
Web excludes AI runtime and Health platform integration. These boundaries are
owned by the Northstar, not changed by this plan.

The current code already provides:

| Implemented baseline | Evidence and remaining distinction |
|---|---|
| Activation, Financial Inbox, Monthly Close, Runway, and saved financial decisions | [FinanceOS Roadmap](roadmap-finance.md) and [Finance task flows](https://github.com/zsh-a/NaviWealth/tree/main/apps/mobile/test/flow/). These workflows are available for study; adoption and repeated-use evidence are still required. |
| Shared source-linked Action creation and navigation | [SourceActionControl](https://github.com/zsh-a/NaviWealth/blob/main/apps/mobile/lib/core/lifeos/ui/source_action_control.dart), [Execution source repository](https://github.com/zsh-a/NaviWealth/blob/main/apps/mobile/lib/features/execution/data/execution_repository_actions.dart), and [repository tests](https://github.com/zsh-a/NaviWealth/blob/main/apps/mobile/test/features/execution/data/execution_repository_test.dart). Direct user-confirmed creation works without an AI proposal; open/Done Actions are reused and Dropped replacement is confirmed. De-duplication is local, not cross-device uniqueness. |
| Source outcome presentation and recoverable details | [ExecutionOS](../domains/executionos-domain.md) and [LifeOS Shell](../architecture/lifeos-shell.md) own the shared source/detail/Review presentation, explicit evaluation states, source retry/review, nullable counts, retained content, and section retry. Source observations remain non-causal. |
| Commit-first forms, dirty guards, and failure retention | [Form submission contract](https://github.com/zsh-a/NaviWealth/blob/main/apps/mobile/lib/core/forms/form_submission.dart) and the owning domain SSOTs. Health measurements, Execution blocker reasons, Knowledge editing/review, and the affected Finance forms lock pending writes and retain failed inputs. Supported status/Finance mutations offer typed Undo. Scoped device-local input recovery covers expense capture, import preferences, Execution Action/Plan/Progress capture, and Knowledge Note/Decision capture/editing under the [shared recovery contract](../architecture/lifeos-shell.md); this does not imply recovery for every editor. |
| Personal Intelligence Loop, Memory V1, and confirmed-data recovery | [AI Architecture](../ai/ai-architecture.md), [LifeOS Shell](../architecture/lifeos-shell.md), and [confirmed-memory recovery tests](https://github.com/zsh-a/NaviWealth/blob/main/apps/mobile/test/core/backup/confirmed_memory_recovery_test.dart). Memory provenance and Personal Profile survive supported recovery and shared-history cleanup. |
| Sync compatibility and native durability implementations | [Sync compatibility tests](https://github.com/zsh-a/NaviWealth/blob/main/apps/mobile/test/core/sync/sync_compatibility_test.dart), [schema baseline tests](https://github.com/zsh-a/NaviWealth/blob/main/apps/mobile/test/core/persistence/schema_baseline_test.dart), and [Android integration workflow](https://github.com/zsh-a/NaviWealth/blob/main/.github/workflows/integration-device.yml). Checked-in tests and harnesses do not establish a passing packaged-device run or a real release stability window. |

Life currently receives Finance budget/journal signals, Health signals, and
Execution signals. Financial Inbox has additional Finance detectors; Knowledge
has source routing and memory indexing but no `lifeSignalBuilder`. A shared
Action control does not make Life a complete cross-domain review inbox.

## Now

Keep at most three initiatives here. N1 and N2 retain their identities because
Finance and the product-discovery SSOT refer to them. Engineering changes
support observed failures while N1 collects real samples and N2 collects user
evidence; completed delivery batches live in the owning SSOTs.

### N1. Real-World Statement Ingestion Quality

Outcome: reduce correction cost in repeated imports while keeping every
accepted row reviewable and explicitly confirmed.

Status: representative Alipay, measured WeChat XLSX, and measured CMB
credit-card layout fixtures are implemented. New-provider expansion awaits a
real redacted sample or confirmed demand. Finance owns parser details through
[its F1 initiative](roadmap-finance.md#f1-representative-statement-corpus-and-import-correctness).

Remaining scope:

- Reproduce observed parsing, account-assignment, and duplicate-review failures
  against the existing representative corpus before adding new formats.
- Add a representative bank-debit fixture only when its source sample or
  confirmed user need is available; do not label synthetic fixtures measured.
- Keep unsupported trade-principal and transfer/refund rows rejected. Accepting
  them requires a separately scoped typed destination and confirmation design.

Exit evidence:

- Each supported representative fixture pins provider detection, accepted and
  rejected counts, direction, currency, normalization, and status filtering.
- Accepted expense/income paths pin account selection, exact/likely duplicate
  outcomes, and explicit confirmation. Unsupported destinations stay closed.
- Record the bank-debit result as supported with a fixture, or explicitly
  deferred after N2; a missing sample must not hold open a speculative parser
  implementation indefinitely.

Owner: FinanceOS. Product signal: correction/rejection/deduplication counts
and second/third import-cycle use, using existing opt-in aggregates.

### N2. Six-Week Product Discovery Study

Outcome: establish whether import → review → Runway → Action/review gives
users a reason to return before expanding templates, detectors, or domains.

Status: activation, repeated-close comparisons, parser-quality reports, and
local product aggregates are implemented. This refresh does not contain
participant results or a demand-validation pass.

Remaining scope and exit evidence:

- Run the [existing study](product-direction-and-demand-validation.md#six-week-demand-validation-plan)
  with 15–20 target participants and its three tasks: close a statement period,
  answer the next-90-day cash-safety question, and compare a real decision.
- Record time, corrections, abandonment, external tool switches, follow-up
  actions, and repeat use. Use existing local opt-in reports; keep financial
  values, source ids, and Health/Knowledge content out of product analytics.
- Apply all five existing validation gates and record an explicit
  continue/narrow/stop decision with the study evidence. Competitor features
  and aggregate population surveys do not satisfy this exit.

Owner: product research with domain task support. Code changes address
observed task failures or correctness gaps; the study does not need
another analytics platform to begin.

## Next

Release evidence can be collected alongside N1/N2; it does not require
restarting implemented infrastructure projects.

### Release Acceptance: Recovery, Encryption, And Sync

This is the shared delivery-risk note referenced by Finance F2. Current code
has restore validation/atomicity, SQLCipher/Keystore migration and unlock
handling, confirmed Memory/Profile recovery, and mixed-version Sync replay.
The remaining deliverable is attributable runtime evidence.

| Gate | Required remaining evidence | Authority |
|---|---|---|
| Android portability and encryption | A successful packaged Android emulator run proves cipher availability, encrypted bytes, key persistence and wrong/missing-key handling, legacy migration, and backup/restore. The two-process force-stop test proves recovery after interruption with its required evidence marker/JSON. | [Device workflow](https://github.com/zsh-a/NaviWealth/blob/main/.github/workflows/integration-device.yml), [integration runner](https://github.com/zsh-a/NaviWealth/blob/main/apps/mobile/tool/run-android-integration.sh), [interruption runner](https://github.com/zsh-a/NaviWealth/blob/main/apps/mobile/tool/run-android-backup-interruption.sh) |
| Sync v3 release stability | Export a real release window with at least 10 cycles spanning 14 days, ≥95% success, zero fatal protocol failures, and zero generation-reset failures. Owner-scoped UTC-day aggregates retain 30 days and exact cycle counts; insufficient coverage remains collecting. | [Stability contract](../sync/sync-v3.md#production-stability-gate), `apps/mobile/lib/core/sync/sync_stability.dart` |

Remote CI results and production stability exports were not verified in this
refresh. Keep the gates pending evidence until a dated run/report and build
identity are recorded; do not infer pass or failure from harness existence.
Sync E2EE remains gated on the release stability result and a recovery design.

### Platform Workflow Acceptance

Outcome: the existing decision/Action/review loop works across supported
window sizes and platform capabilities.

The Web harness uses a real local-only identity and Flutter semantics to create
accounts, Knowledge notes, and Execution actions. Record content, concrete
detail URLs, reload, browser history, domain enablement, and cross-tab reads are
executable checks. Harness implementation is not evidence for every supported
browser or native interaction.

Remaining acceptance:

- Attach passing release-build results for the supported browser matrix.
  Keep real Safari/PWA acceptance for platform interactions unavailable to
  the browser harness.
- Chromium covers shell/layout breakpoints; WebKit/Firefox cover routing,
  persistence, and supported-domain capability behavior. Web acceptance never
  requires an AI runtime or Health platform integration.
- Native acceptance covers keyboard-safe form actions, large text, system back,
  foreground/resume, and failure retry. Desktop covers focus and keyboard use.
- Performance work starts from traces on representative devices. Use the
  display's frame budget (about 8.3 ms at 120 Hz) and evidence of sustained
  scrolling; already fixed Activity/Chat flattening is not reopened without a
  new measured regression.

Owner: app shell, design system, and domain UI. Test-layer details remain in
[Testing Strategy](../development/testing-strategy.md) and
[Web Compatibility](../development/web-compat-matrix.md).

## Function Directions Awaiting Demand Evidence

Official sources were rechecked on 2026-10-01 in the
[product-discovery SSOT](product-direction-and-demand-validation.md#external-demand-evidence).
Its updated findings are planning inputs, not proof of NaviWealth demand.
These candidates are outside Now/Next until their triggers are recorded. The
order below is the recommended research order, not a dated delivery promise.

| Candidate | Current starting point and smallest extension | Promotion evidence and stop condition |
|---|---|---|
| Explain forecast versus later observation | Runway already records 30/90-day forecasts, evaluates due snapshots, and displays aggregate error. Target-day comparability and balance completeness now gate error statistics; prototype one review of changed assumptions only after observed user confusion. Finance owns calculations. | N2 participants repeatedly cannot explain a consequential forecast deviation. Late/missing observations must remain distinguishable from forecast error; defer explanatory features if no recurring confusion is observed. |
| Compose one high-value decision workflow | Finance already stores baseline, assumptions, selected result, review evidence, and an Action. Knowledge already stores rationale, alternatives, and actual outcome. Prototype source-preserving navigation between existing records for one observed life event rather than creating another Decision aggregate. | N2 identifies repeated context switching or lost rationale in a specific decision. Promote only the narrow workflow with task evidence; stop if source links and existing review are sufficient. |
| Make repeated import review require fewer corrections | The representative corpus, duplicate checks, Monthly Close, and quality reports already exist. Prototype one confirmed correction rule or focused field editor for the most frequent observed pattern. | N1/N2 provide redacted correction examples and a measured repeated cost. Keep mappings explicit and reversible; defer new providers without samples and rule-learning without repetition. |
| Bring consequential due reviews into Life | Financial Inbox has more detectors than its Life contribution, and Knowledge due reviews have no Life signal contribution. Reuse one domain-owned due result through `DomainPack` after a concrete missed-review problem is observed. | Users repeatedly miss the same consequential review despite the owning domain's existing entry. Verify freshness, inactive-domain gating, source routing, and attention de-duplication; stop if it only duplicates existing reminders. |
| Test a small Health behavior experiment | Reuse a Knowledge Note/Decision for the hypothesis, an Execution Plan/Progress for follow-through, and existing Health windows for observations. Start with a manual prototype and explicit review; an Experiment entity or recurring-task engine is not assumed. | Opt-in Health users complete at least two repeated experiment cycles and use the evidence to keep/revise a routine. Sparse data stays inconclusive and observations remain non-causal; defer if logging cost exceeds review value. |

Runway's [Finance contract](../domains/financeos-domain.md) distinguishes the
forecast target day from the actual observation time. Only comparable,
complete, same-currency observations on the target UTC day affect error and
confidence; late observations remain evidence, not reconstructed historical
balances. Explanation UI still requires the demand trigger above.

## Triggered Architecture And Capability Work

| Area | Trigger and required decision |
|---|---|
| Cross-device duplicate Actions | Reproducible concurrent-offline creation plus user confusion. Add convergence/owner-scope evidence before designing a user-confirmed cleanup; local source matching does not authorize silent history deletion or a Sync protocol rewrite. |
| Sync E2EE | Passing release stability evidence, threat model, device onboarding, key loss/recovery, and migration ADR. Local database encryption is a separate capability. |
| Additional editors requiring draft recovery | Repeated measured loss of substantial drafts. Reuse the shared local store with editor-specific payloads, restoration confirmation, and revision guards where needed. Existing supported editors follow its retention, owner isolation, and cleanup rules. |
| Speech expansion | Measured voice use plus a specific language/platform failure. Extend the existing speech/session seam with model/capability and target-device evidence; generic realtime/omni competition is not a trigger. |
| Bank connectivity, tax export, or broker writes | Confirmed import-retention blocker, first jurisdiction, or explicit execution demand respectively; each needs its scoped permission, custody, and failure-recovery design in the Finance roadmap. |
| iOS native distribution | iOS returns to active delivery scope; require simulator/device and native-dependency CI evidence. |
| Wider native engine or a future domain | A demonstrated current capability need and the Northstar's ADR requirements. |
| Household sharing or collaboration | Validated permission/payment needs and an explicit Northstar change. Current single-user ownership is not expanded by incidental UI work. |

## Roadmap Operating Rules

- Separate implementation evidence, packaged-device evidence, release-window
  evidence, and user-study evidence. One does not substitute for another.
- Every promoted item names an owner, current gap, minimum scope, dependency,
  exit evidence, and stop/defer condition. Now contains at most three items.
- Collect platform workflow and release acceptance alongside N1/N2; deepen
  implemented workflows only for observed correctness or usability gaps.
- New functionality must enter through a recorded measured problem. It does
  not displace Now because a competitor has launched a similar feature.
- Keep domain calculations and authoritative records in their owning domain.
  Cross-domain UI uses registered source references and composition seams.
- Remove finished delivery items after updating the owning SSOT. Keep only the
  baseline needed to explain unfinished work; do not rebuild a release archive.
- Source code cites stable SSOTs/tests rather than mutable roadmap numbers.
