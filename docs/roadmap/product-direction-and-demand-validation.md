# Product Direction And Demand Validation

Status: active product-discovery SSOT.

Last reviewed: 2026-10-01 (code baseline `0809735fc`; the official external
sources cited below were rechecked on this date).

This document records the product hypotheses that should be validated before
they change delivery sequencing. It is intentionally separate from the active
LifeOS and FinanceOS roadmaps:

- `roadmap-lifeos.md` and `roadmap-finance.md` own committed sequencing.
- This document owns target-user, problem, positioning, and demand-validation
  hypotheses.
- A direction enters a roadmap only after its trigger and evidence are
  recorded. The six-week study is sequenced as LifeOS `Now` N2; FinanceOS
  `Next` Demand-Validation Operations defers code changes until that study
  delivers an explicit decision.
- Architecture Northstar changes still require an ADR and explicit review.

## Executive Conclusion

NaviWealth should not continue expanding primarily by adding more domains,
agents, charts, or object types. The product already has broad FinanceOS,
HealthOS, KnowledgeOS, and ExecutionOS capabilities. Its next constraint is
not feature coverage; it is whether a user can reach a valuable result quickly
and has a high-frequency reason to return.

The recommended product promise is:

> Turn fragmented personal financial data into a trustworthy view of the
> future, a concrete next action, and a later review of what actually changed.

FinanceOS remains the acquisition and activation surface. HealthOS,
KnowledgeOS, and ExecutionOS should primarily strengthen the
decision-to-action-to-review loop rather than compete as standalone generic
health, notes, or task products.

"Personal LifeOS" remains a useful architecture description. The first-level
user proposition should be more concrete:

> A private financial decision system that helps users understand the next 90
> days, evaluate important life choices, and follow through.

## Why Direction Must Change

The current product already includes:

- Accounts, assets, liabilities, expenses, investments, net worth, budgets,
  cashflow, FIRE planning, goals, and Options Income.
- Recurring transactions, subscription detection, cashflow calendar, dividend
  forecasts, and anomaly review.
- Statement capture, deterministic parsing, deduplication, review, and
  explicit confirmation.
- HealthKit, Health Connect, and Garmin-derived recovery signals.
- Knowledge Notes, Decisions, and Relations; Execution Plans, Actions, and
  Progress. Assumptions and experiments can be expressed within these existing
  records; they are not separate current domain entities.
- Device-only AI, Memory Runtime, named agents, proposals, Sync v3, encrypted
  backup, and database-at-rest encryption work.

These capabilities create three product risks:

1. **Activation risk.** A resumable Finance first-task path now connects import,
   review, and the first Money Runway result. Whether users complete it quickly
   and trust the result still requires the task study below.
2. **Retention risk.** A wide set of dashboards and tools does not by itself
   create a weekly or monthly return event.
3. **Positioning risk.** Local-first budgeting, net worth, investments, FIRE,
   and AI insights are increasingly available from focused competitors.

Engineering correctness remains mandatory, especially for financial import,
recovery, encryption, and Sync. It is a release condition, not by itself a
reason for a user to adopt or retain the product.

## External Demand Evidence

This review uses population research and official product documentation. The
former describes a broad problem; the latter establishes advertised product
capabilities. Neither proves NaviWealth adoption, willingness to pay, Chinese
target-user demand, or successful participant tasks. No new interview or
retention results are recorded by this refresh.

### Cashflow uncertainty remains a research priority

The Federal Reserve's May 2026 report covers US households in 2025. It reports
that 30 percent of adults had income that varied at least occasionally, 11
percent struggled to pay bills because of income variability, and 41 percent
always or often had money left at month end. These are the current report's
measures; the last measure is not the earlier report's spending-less-than-income
question. [Federal Reserve, Income and Expenses](https://www.federalreserve.gov/publications/2026-economic-well-being-of-us-households-in-2025-Income-and-Expenses.htm).

Inference: timing of available cash, delayed income, committed outflows, and
the affordability of a decision remain useful research questions. US population
figures do not identify NaviWealth's first regional segment. N2 must establish
whether the existing 30/90-day Runway answers these questions using reviewed
data, and whether users return to compare it with later observations.

### Repeated import correction is the local workflow hypothesis

Billbook's current FAQ describes CSV/XLSX statement import, Excel/CSV export,
recurring entry, budgets/assets, and platform-specific capture requiring user
activation. This is direct regional product evidence for a broad recording
workflow, not evidence that its users want NaviWealth or that it is entirely
local. [Billbook FAQ](https://billbook.net.cn/faq/).

Inference: another parser or capture shortcut is unlikely to be sufficient
positioning. Test whether NaviWealth's reviewed imports make the second and
third close faster, preserve correct account/duplicate decisions, and lead to
a useful forecast. Add a correction rule, field editor, or provider only when
measured correction patterns or real redacted samples justify it.

### Scenario comparison already has mature alternatives

Monarch's June 16, 2026 release describes saved forecasting scenarios and
cashflow drill-ins. This is evidence that these capabilities were announced
in that release, without measuring their adoption or user outcomes.
[Monarch June product update](https://www.monarch.com/blog/june-product-update).

ProjectionLab documents baseline/alternative comparison and creates progress
points when current balances are updated. These pages establish comparison
and observation capabilities; listed prices or feature availability alone
cannot establish payment intent for NaviWealth.
[ProjectionLab comparison](https://projectionlab.com/help/using-what-if),
[ProjectionLab balance updates and progress](https://projectionlab.com/help/update-account-balances).

Inference: NaviWealth should research one decision's assumptions, rationale,
confirmed follow-up, and later source evidence. Finance already stores saved
decisions and review evidence, while Knowledge already stores rationale and
actual outcomes. The remaining hypothesis is whether source-preserving
composition saves context switching; it does not justify a new calculator,
duplicate Decision record, or many unvalidated life-event templates.

### Privacy includes recovery and credential boundaries

Actual Budget documents local copies with optional encrypted sync. It also
states that bank-sync credentials are outside that encryption and describes
the consequences of losing the encryption password and local copy. These are
separate boundaries, not a blanket claim that every stored datum is encrypted.
[Actual sync and encryption](https://actualbudget.org/docs/getting-started/sync/).

Inference: NaviWealth must verify portability, database-key handling, and Sync
stability independently. E2EE is a conditional architecture decision after its
existing stability gate; copying a competitor's encryption feature does not
resolve onboarding, migration, key recovery, or credential custody.

### Health correlations require an explicit review workflow

Oura's Discovery Hub documents tag/biometric correlations and a baseline of at
least 14 of the past 30 days. It explicitly acknowledges other contributing
factors. This threshold belongs to Oura's product; it is not a clinical rule or
a proposed NaviWealth coverage threshold.
[Oura Discovery Hub](https://support.ouraring.com/hc/en-us/articles/30697762898323-Discovery-Hub).

Inference: test a manual behavior-experiment workflow using existing Knowledge,
Execution, and Health records before designing new entities or automatic
insights. The candidate must earn repeated use through reviewable observations
and manageable logging cost. Correlation and completed tasks do not establish
causation or diagnostic value.

## Target User Hypothesis

The primary target user should be:

> A privacy-conscious, financially intentional individual aged roughly 28 to
> 45 with multiple payment or asset accounts who periodically reconciles money
> and is facing decisions such as buying a home, having a child, changing work,
> taking a sabbatical, moving, or pursuing financial independence.

Likely early-user characteristics:

- Uses several of WeChat Pay, Alipay, bank cards, brokers, and manual assets.
- Has outgrown a simple expense tracker but does not want a professional
  accounting system.
- Values local ownership enough to accept reviewed file import when reliable
  bank connectivity is unavailable or undesirable.
- Wants an answer or decision, not only a categorized ledger.
- Is willing to perform a weekly or monthly review when the maintenance cost
  is lower than the value received.

Secondary segments may include self-directed FIRE or investment users.
General-purpose beginner budgeting, generic personal productivity, and generic
note-taking should not be the initial acquisition segments.

## Priority Opportunity Areas

| Direction | Current baseline | Unvalidated extension | Sequencing |
|---|---|---|---|
| Financial Inbox and Monthly Close | Implemented, with repeated-close evidence and import reports | Lower repeated correction cost | N1/N2; code follows an observed failure |
| 30/90-day Money Runway | Forecast snapshots, due evaluation, and aggregate error already exist | Explain deviations with trustworthy observation dates and completeness | First research follow-up after N2 |
| High-value decision workflow | Finance scenarios/saved reviews and Knowledge Decisions exist | Preserve rationale across the source-linked follow-up and review | One observed life event before more templates |
| Consequential due reviews in Life | Domain review entries exist; Life contributions are partial | Project one repeatedly missed domain-owned review | Measured missed work before another Life signal |
| Personal Health experiments | Health windows plus Knowledge/Execution records exist | Manual experiment and evidence review | At least two repeated cycles before structured expansion |
| Household and partner finance | Current single-user boundary | Permission-aware shared decisions | Discovery and a Northstar change before architecture work |

### 1. Financial Inbox And Monthly Close

Statement ingestion should become a recurring financial-maintenance ritual,
not remain an isolated import tool.

The target journey is:

```text
Import payment, bank, or broker statement
  -> detect provider and parse locally
  -> match an account and remove duplicates
  -> ask the user only about exceptions
  -> update balances, spending, subscriptions, and forecasts
  -> surface the three most important follow-ups
  -> create confirmed Execution actions when useful
```

A single Financial Inbox should collect unresolved work such as:

- Missing account assignment.
- Likely duplicate or uncertain transfer.
- New recurring payment or price increase.
- Anomalous spending.
- Balance mismatch.
- Missing asset valuation.
- Drafts waiting for confirmation.

The desired return loop is a lightweight weekly inbox and a more complete
monthly close. Success means that repeated reviews get faster as deterministic
rules and confirmed mappings improve.

### 2. Thirty- And Ninety-Day Money Runway

The highest-priority user-facing question should be "Is the next 90 days
safe?"

Existing recurring transactions, cashflow calendar, budgets, liabilities,
income, dividends, and balances provide much of the required base. They should
be composed into:

- Expected minimum cash balance over 30, 60, and 90 days.
- Risk of a gap before the next known income event.
- Committed recurring expenses and subscriptions.
- Emergency-fund coverage in months.
- Deterministic known values versus inferred estimates.
- Missing-data and confidence explanations.
- Small what-if questions such as a purchase, delayed income, or temporary
  income reduction.

This is different from a rear-looking budget. It supports a decision at the
moment it is needed. The system must show uncertainty and must not present
estimated dates or amounts as guaranteed facts.

### 3. Life-Event Decision Room

FIRE, goals, Finance scenario assumptions, Knowledge Decisions and their revisit
conditions, and Execution Actions should be composed into a small number of
opinionated scenarios. Finance owns scenario calculations and saved financial
outcomes; Knowledge owns decision rationale and recall. Cross-domain links use
source references rather than duplicate authoritative records:

- Buy versus continue renting.
- Change jobs or take a sabbatical.
- Support a child or a period of single income.
- Repay debt versus continue investing.
- Move to a new city or country.
- Change a financial-independence date.
- Make or delay a large discretionary purchase.

Each scenario should preserve:

1. Current facts and missing inputs.
2. Two or three comparable alternatives.
3. Cashflow, net-worth, goal-date, and risk differences.
4. The user's choice and explicit assumptions.
5. Concrete next actions.
6. A scheduled review of predictions, assumptions, and actual outcomes.

The calculation layer should remain deterministic. AI may explain results,
identify missing information, and draft alternatives, but it must not invent
financial facts or silently alter source data.

### 4. Household And Partner Finance

Household finance is a credible high-demand direction, but it is not a small
feature. Real needs include:

- Mine, yours, and shared accounts or transactions.
- Sharing balances and goals without exposing every personal transaction.
- Assigning transaction review to a partner.
- Joint budgets, emergency reserves, and goals.
- Switching between individual and household views.

The current ownership, authorization, Sync, backup, deletion, and domain-opt-in
models assume a substantially simpler user boundary. Household work therefore
requires discovery, an ADR, a threat model, explicit permission semantics, and
a change to the current collaboration non-goal.

Do not implement household sharing until interviews establish which data must
be shared, which must remain private, and whether users will pay for the
result. A minimum discovery sample is 8 to 10 couples or households.

### 5. HealthOS As A Personal Experiment System

HealthOS has recovery and trend views. Oura already documents habit/biometric
associations in its [Discovery Hub](https://support.ouraring.com/hc/en-us/articles/30697762898323-Discovery-Hub).
The extension to research is whether an explicit hypothesis, manageable
follow-through, and a later review are more useful than another metric view.

The candidate workflow to test is a reviewable behavior experiment:

```text
Record a hypothesis such as "late caffeine reduces sleep quality"
  -> define a 14-day experiment
  -> create one concrete daily action
  -> compare wearable signals and subjective check-ins
  -> review the evidence
  -> keep, revise, or reject the routine
```

Begin with a manual prototype using existing records. It must distinguish
missing observations from no change and record the user's subjective review
without automatic clinical or causal conclusions. Oura's baseline requirement
is a competitor implementation detail, not NaviWealth's experiment policy.
Repeated use and logging cost are the entry evidence for structured expansion.

## Explicit Depriorities

Until the core loop has demand evidence, do not prioritize:

- TimeOS, LivingOS, or another speculative domain.
- More agents without a measured user workflow and caller.
- Generic AI-chat capability competition.
- More dashboards, charts, or Knowledge object types.
- New statement providers without a real redacted sample or repeated demand.
- A generic task manager, rich note editor, knowledge graph, or publishing
  surface.
- Cloud AI fallback, social features, communities, or content feeds.

KnowledgeOS and ExecutionOS should not independently compete with products
such as Obsidian, Notion, Todoist, Jira, or Linear. Their differentiating role
is preserving important decisions and completing follow-up work generated by
financial and health evidence.

## Recommended Product Sequence

### Implementation Baseline (reviewed 2026-10-01)

The first two phases now have an executable validation baseline. This is
implementation evidence, not demand evidence:

- Finance activation is a resumable first-task path: import data, clear the
  review queue, then inspect the first Money Runway result. The confirmed
  import milestone is device-local and owner-scoped, so draft retention and
  app restarts do not reset progress. Opt-in metrics measure completion of the
  full first-useful-result path rather than treating import review as success.
- Financial Inbox persists stable signals and now composes import review,
  runway risk, missing FX, balance mismatch, expense anomaly, subscription
  change, stale valuation, and due decision-review facts. Incomplete provider
  loading never resolves an existing signal. Each item exposes its evidence
  and detection window, links back to the source repair route, and can create
  a source-preserving Execution action whose lifecycle remains visible from
  the signal. Completing that action now triggers a later Finance evaluation:
  a complete scan can clear the signal, a redetection keeps it open, and an
  incomplete scan records an inconclusive result instead of guessing. Dropped
  actions leave the source signal open and allow a replacement action.
- Monthly Close is evidence-driven. Account statement balances are compared
  with the exact period-end ledger sum; balanced, mismatched, and explicitly
  overridden facts are synced. A close stores its evidence and aggregate
  snapshot instead of manual checklist state. Open close sessions resume
  after navigation or restart, account coverage is explicit, and subsequent
  closes compare new, cleared, and carried-forward exceptions plus the
  previous completion time. A compact close history makes repeated-close
  speed and unresolved exception carry-over visible without exposing values.
- Money Runway excludes brokerage value from default spendable cash, includes
  unpaid amortization rows, deduplicates matching scheduled outflows, runs
  purchase/income-delay/income-reduction stress cases, and records daily
  30/90-day forecast snapshots when the Runway workspace evaluates current
  evidence.
- Saved financial decisions create a source-preserving review action. Due
  reviews enter Financial Inbox and store the observed source families and
  data-completeness score alongside the actual outcome.
- Life, Financial Inbox, and Knowledge Decision now share source-linked Action
  controls. Direct confirmed creation does not require AI; open/Done Actions
  are reused, Dropped replacement is confirmed, and retry preserves a committed
  Action id. These are implemented lifecycle guarantees, not evidence that the
  source problem has cleared or that cross-device duplicate creation is impossible.
- Health measurement, Execution blocker, and Knowledge edit/review submissions
  lock pending work and retain failed drafts. These current forms do not imply
  draft recovery after process death. The remaining outcome/detail consistency
  work is scoped as LifeOS N3.
- Opt-in product evidence uses local 90-day daily buckets plus cumulative
  counters. Settings can explicitly copy the privacy-safe aggregate report;
  no financial values, labels, routes, or row identifiers are included.
  Version 5 adds import-cycle retention, accepted/rejected/deduplicated row
  counts, account-review corrections, action completion/drop outcomes, and
  post-action signal revalidation outcomes. Import review can also explicitly
  copy a parser-quality report containing only stable source/issue enums and
  counts—never source rows, descriptions, amounts, currencies, or account ids.

The next product step is therefore the six-week task study below. The current
activation, Inbox, and repeated-close paths are the instrumentation surface
for that study; more signal types, scenario templates, or domains should be
driven by observed failures rather than feature-count goals.

### Phase 1: Activation And Repeated Close

Implementation baseline exists. The six-week study must now validate completion,
trust, correction cost, and repeated use of the existing path:

- Measure whether the first-task path delivers a trustworthy result within ten
  minutes.
- Validate repeated use of Financial Inbox and Monthly Close.
- Validate whether the 30/90-day Money Runway answers a real cash-safety question.
- Measure whether confirmed follow-up Actions lead to a later source review.
- Use the existing privacy-safe, opt-in local product-funnel measurement.

### Phase 2: High-Value Decisions

Basic deterministic scenarios, saved decisions, and review Actions already
exist. Further templates and workflow expansion require Phase 1 demand evidence:

- Select or refine two or three life-event templates based on observed demand.
- Connect FIRE and goals to scenario comparison rather than a separate
  calculator-only journey.
- Preserve assumptions, choice, review date, and actual outcome.
- Compare predicted and actual cashflow without false causal attribution.
- Use AI for explanation and question generation around deterministic results.

### Phase 3: Triggered Expansion

- Household finance requires validated permission needs and payment intent.
- Jurisdiction-specific tax export requires a confirmed first jurisdiction.
- Bank connectivity requires evidence that repeated file import is the main
  retention blocker.
- Health experiments require users to complete at least two repeated
  experiment cycles.
- A future domain requires a frequent need that cannot fit an existing domain.

## Product Evidence And Metrics

Engineering and protocol metrics remain necessary. Product decisions should
add the following privacy-safe evidence:

- Time from first launch to first useful outcome.
- First-import and review completion rate.
- Import correction, rejection, and deduplication rate.
- Weekly Financial Inbox clearance rate.
- Monthly close completion rate.
- Second and third import-cycle retention.
- 30-day forecast error and data-completeness score.
- Proposal-to-action conversion rate.
- Action completion rate.
- Whether a later evaluation still detects the original source signal.
- Repeated use of a decision scenario with real data.

AI message count, agent-run count, model-token usage, and number of generated
insights are not primary success metrics. They measure activity, not outcomes.

Telemetry must remain opt-in and privacy-safe. Prefer local aggregation and
explicit export of counters, durations, stable enums, and success states. Do
not collect transaction contents, balances, decision text, source row ids, or
health values for product analytics.

## Six-Week Demand Validation Plan

### Recruitment

Recruit 15 to 20 participants matching the target-user hypothesis. Include
users with multiple payment sources, assets, or a current life decision. Do not
recruit only developers or existing local-first enthusiasts.

### Research Method

Ask participants to demonstrate their last real workflow rather than list
desired features:

- The last time they reconciled a month of spending.
- The last time they worried about near-term cashflow.
- The last large financial or life decision they evaluated.
- Which bank, payment, spreadsheet, note, and calculator surfaces they used.
- Which information they refused to upload to an external service.

Use the existing product or a narrow prototype to complete three tasks:

1. Import and close one real or safely redacted statement period.
2. Answer whether the next 90 days are financially safe.
3. Compare alternatives for one real decision.

Record time, corrections, abandoned steps, missing inputs, external tool
switches, and whether the result caused a real follow-up action.

### Validation Gates

The direction is strong enough to enter committed roadmap sequencing when:

- At least 70 percent of participants reach a trustworthy first imported
  result within ten minutes.
- More than half choose to repeat the workflow in the next week or month.
- At least one third convert a result into a real action.
- Forecast or decision value is consistently rated above the value of the
  historical report alone.
- Multiple participants make a real payment commitment, such as a refundable
  preorder or paid pilot, rather than only stating willingness.

Failure to meet a gate is evidence to narrow the segment, simplify the
workflow, or reject the direction. It is not a reason to add more features.

## Roadmap Promotion Rules

A discovery item moves into an active roadmap only when its entry includes:

- The measured user problem and target segment.
- The smallest workflow that changes the user outcome.
- Baseline and target metrics.
- Representative privacy-safe fixtures or task evidence.
- Required architecture decision, if any.
- Explicit stop condition.

Product discovery must not bypass the current local-first, device-AI,
source-preserving, explicit-confirmation, observational-outcome, or
domain-boundary guarantees. A finding that genuinely requires changing one of
those guarantees must be proposed as a Northstar decision, not introduced as
an incidental feature implementation.
