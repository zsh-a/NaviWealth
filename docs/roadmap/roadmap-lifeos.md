# NaviWealth LifeOS Roadmap

Status: active cross-domain sequencing SSOT.

Last reviewed: 2026-10-01 against code baseline `0809735fc`.

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
| Activation, Financial Inbox, Monthly Close, Runway, and saved financial decisions | [FinanceOS Roadmap](roadmap-finance.md) and [Finance task flows](https://github.com/zsh-a/NaviWealth/tree/0809735fc/apps/mobile/test/flow/). These workflows are available for study; adoption and repeated-use evidence are still required. |
| Shared source-linked Action creation and navigation | [SourceActionControl](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/lib/core/lifeos/ui/source_action_control.dart), [Execution source repository](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/lib/features/execution/data/execution_repository_actions.dart), and [repository tests](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/test/features/execution/data/execution_repository_test.dart). Direct user-confirmed creation works without an AI proposal; open/Done Actions are reused and Dropped replacement is confirmed. De-duplication is local, not cross-device uniqueness. |
| Commit-first forms, dirty guards, and failure retention | [Form submission contract](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/lib/core/forms/form_submission.dart) and the owning domain SSOTs. Health measurements, Execution blocker reasons, Knowledge editing/review, and the affected Finance forms lock pending writes and retain failed inputs. Supported status/Finance mutations offer typed Undo; persistent draft recovery after process death is not implied. |
| Personal Intelligence Loop, Memory V1, and confirmed-data recovery | [AI Architecture](../ai/ai-architecture.md), [LifeOS Shell](../architecture/lifeos-shell.md), and [confirmed-memory recovery tests](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/test/core/backup/confirmed_memory_recovery_test.dart). Memory provenance and Personal Profile survive supported recovery and shared-history cleanup. |
| Sync compatibility and native durability implementations | [Sync compatibility tests](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/test/core/sync/sync_compatibility_test.dart), [v95→v96 migration tests](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/test/core/persistence/sync_compatibility_migration_test.dart), and [Android integration workflow](https://github.com/zsh-a/NaviWealth/blob/0809735fc/.github/workflows/integration-device.yml). Checked-in tests and harnesses do not establish a passing packaged-device run or a real release stability window. |

Life currently receives Finance budget/journal signals, Health signals, and
Execution signals. Financial Inbox has additional Finance detectors; Knowledge
has source routing and memory indexing but no `lifeSignalBuilder`. A shared
Action control does not make Life a complete cross-domain review inbox.

## Now

Keep at most three initiatives here. N1 and N2 retain their identities because
Finance and the product-discovery SSOT refer to them. N3 is the next bounded
engineering batch; it improves existing workflows while N1 collects real
samples and N2 collects user evidence.

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
observed task failures or correctness gaps such as N3; the study does not need
another analytics platform to begin.

### N3. Consistent Action Outcomes And Recoverable Details

Outcome: users can tell whether an Action is complete, whether its source
problem remains, and how to recover when the supporting data is unavailable.

Current gaps:

- [Outcome summaries](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/lib/core/lifeos/action_outcome.dart)
  represent cleared/still-active observations. Execution Review consumes them,
  but the shared source control and Action detail do not present the same
  evaluation. Missing summaries alone cannot explain pending, incomplete,
  failed, or unsupported evaluation.
- [Execution detail](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/lib/features/execution/ui/execution_detail_page.dart)
  converts unavailable Plan actions into an empty list for header counts;
  related-action and progress errors have no section retry.

First delivery slice:

- Present the same authoritative source result and observation time in source
  controls, Action detail, and Review. Distinguish Action state from source
  evaluation; a completed Action never implies clearance.
- Expose pending, incomplete, failed, and unsupported evaluation only when
  the owning source can distinguish them. Never derive them from a missing
  map entry. Knowledge outcomes remain explicit user-authored reviews.
- Add source-owned retry/review access where a real handler exists. Keep
  cross-domain composition in `app/` and use the existing neutral seams.

Second delivery slice:

- Separate loading, error, empty, and successful data in Execution details.
  Unknown counts must not appear as zero. Preserve prior content during
  refresh where available and retry only the failed section.
- Explain deleted sources, missing objects, and inactive domains through
  their existing routes and source-resolution contracts.

Exit evidence:

- Focused widget/composition tests cover delayed reads, section errors/retry,
  complete/incomplete source observations, Action completion/Undo, and source
  reappearance without claiming causality.
- Task flows cover Life/Financial Inbox/Knowledge Decision → Action detail →
  completion or Undo → source return; existing de-duplication, Dropped
  replacement, and committed-id retry remain intact.
- English/Chinese copy and the owning SSOTs describe the resulting behavior.

Owner: app composition and the participating domains. Persistent editor drafts,
new Action types, and a second review/navigation model are outside this batch.

## Next

Accepted follow-ups stay behind the Now engineering batch. Release evidence can
be collected alongside N1/N2; it does not require restarting implemented
infrastructure projects.

### Release Acceptance: Recovery, Encryption, And Sync

This is the shared delivery-risk note referenced by Finance F2. Current code
has restore validation/atomicity, SQLCipher/Keystore migration and unlock
handling, confirmed Memory/Profile recovery, and mixed-version Sync replay.
The remaining deliverable is attributable runtime evidence.

| Gate | Required remaining evidence | Authority |
|---|---|---|
| Android portability and encryption | A successful packaged Android emulator run proves cipher availability, encrypted bytes, key persistence and wrong/missing-key handling, legacy migration, and backup/restore. The two-process force-stop test proves recovery after interruption with its required evidence marker/JSON. | [Device workflow](https://github.com/zsh-a/NaviWealth/blob/0809735fc/.github/workflows/integration-device.yml), [integration runner](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/tool/run-android-integration.sh), [interruption runner](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/tool/run-android-backup-interruption.sh) |
| Sync v3 release stability | Export a real release window with at least 10 cycles spanning 14 days, ≥95% success, zero fatal protocol failures, and zero generation-reset failures. The local rolling window holds the latest 50 cycles; insufficient coverage remains collecting. | [Stability contract](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/lib/core/sync/sync_stability.dart), [stability tests](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/test/core/sync/sync_stability_test.dart) |

Remote CI results and production stability exports were not verified in this
refresh. Keep the gates pending evidence until a dated run/report and build
identity are recorded; do not infer pass or failure from harness existence.
Sync E2EE remains gated on the release stability result and a recovery design.

### Platform Workflow Acceptance

Outcome: the existing decision/Action/review loop works across supported
window sizes and platform capabilities.

Current gap: [Web route smoke](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/web_smoke/tests/router.spec.ts)
primarily checks Finance/Settings URLs and boot errors; the
[responsive matrix](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/web_smoke/tests/responsive.spec.ts)
covers core Finance routes and document overflow. Those assertions do not
prove the correct domain view or complete canvas-rendered workflow.

Exit evidence:

- Deterministic seeded coverage checks opt-in/off behavior, actual destination
  rendering, concrete Knowledge/Execution detail links, reload, and back/forward.
  Keep manual acceptance for interactions unsupported by the browser harness.
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
| Explain forecast versus later observation | Runway already records 30/90-day forecasts, evaluates due snapshots, and displays aggregate error. First verify target date versus actual observation date, comparable balances, and data completeness; then prototype one review of changed assumptions. Finance owns calculations. | N2 participants repeatedly cannot explain a consequential forecast deviation. Late/missing observations must remain distinguishable from forecast error; defer explanatory features if no recurring confusion is observed. |
| Compose one high-value decision workflow | Finance already stores baseline, assumptions, selected result, review evidence, and an Action. Knowledge already stores rationale, alternatives, and actual outcome. Prototype source-preserving navigation between existing records for one observed life event rather than creating another Decision aggregate. | N2 identifies repeated context switching or lost rationale in a specific decision. Promote only the narrow workflow with task evidence; stop if source links and existing review are sufficient. |
| Make repeated import review require fewer corrections | The representative corpus, duplicate checks, Monthly Close, and quality reports already exist. Prototype one confirmed correction rule or focused field editor for the most frequent observed pattern. | N1/N2 provide redacted correction examples and a measured repeated cost. Keep mappings explicit and reversible; defer new providers without samples and rule-learning without repetition. |
| Bring consequential due reviews into Life | Financial Inbox has more detectors than its Life contribution, and Knowledge due reviews have no Life signal contribution. Reuse one domain-owned due result through `DomainPack` after a concrete missed-review problem is observed. | Users repeatedly miss the same consequential review despite the owning domain's existing entry. Verify freshness, inactive-domain gating, source routing, and attention de-duplication; stop if it only duplicates existing reminders. |
| Test a small Health behavior experiment | Reuse a Knowledge Note/Decision for the hypothesis, an Execution Plan/Progress for follow-through, and existing Health windows for observations. Start with a manual prototype and explicit review; an Experiment entity or recurring-task engine is not assumed. | Opt-in Health users complete at least two repeated experiment cycles and use the evidence to keep/revise a routine. Sparse data stays inconclusive and observations remain non-causal; defer if logging cost exceeds review value. |

Forecast observations currently use the liquid balance seen on the next Runway
evaluation after the target date. This is not automatically an exact historical
target-date balance. The [repository](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/lib/features/finance/runway/data/runway_forecast_repository.dart)
and [test](https://github.com/zsh-a/NaviWealth/blob/0809735fc/apps/mobile/test/features/finance/runway/data/runway_forecast_repository_test.dart)
already provide the baseline; future work must preserve that distinction.

## Triggered Architecture And Capability Work

| Area | Trigger and required decision |
|---|---|
| Cross-device duplicate Actions | Reproducible concurrent-offline creation plus user confusion. Add convergence/owner-scope evidence before designing a user-confirmed cleanup; local source matching does not authorize silent history deletion or a Sync protocol rewrite. |
| Sync E2EE | Passing release stability evidence, threat model, device onboarding, key loss/recovery, and migration ADR. Local database encryption is a separate capability. |
| Draft recovery across process death | Repeated measured loss of substantial drafts. Define local retention, owner isolation, cleanup, and restoration confirmation for the specific editor before adding a shared draft store. |
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
- Sequence N3 outcome presentation, then detail recovery, then platform workflow
  acceptance; N1/N2 evidence collection proceeds alongside that engineering work.
- New functionality must enter through a recorded measured problem. It does
  not displace Now because a competitor has launched a similar feature.
- Keep domain calculations and authoritative records in their owning domain.
  Cross-domain UI uses registered source references and composition seams.
- Remove finished delivery items after updating the owning SSOT. Keep only the
  baseline needed to explain unfinished work; do not rebuild a release archive.
- Source code cites stable SSOTs/tests rather than mutable roadmap numbers.
