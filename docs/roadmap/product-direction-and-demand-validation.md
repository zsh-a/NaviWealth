# Product Direction And Demand Validation

Status: active product-discovery SSOT.

Last reviewed: 2026-07-19.

This document records the product hypotheses that should be validated before
they change delivery sequencing. It is intentionally separate from the active
LifeOS and FinanceOS roadmaps:

- `roadmap-lifeos.md` and `roadmap-finance.md` own committed sequencing.
- This document owns target-user, problem, positioning, and demand-validation
  hypotheses.
- A direction enters a roadmap only after its trigger and evidence are
  recorded.
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
- Decision, assumption, experiment, routine, action, project, commitment, and
  progress objects.
- Device-only AI, Memory Runtime, named agents, proposals, Sync v3, encrypted
  backup, and database-at-rest encryption work.

These capabilities create three product risks:

1. **Activation risk.** First-run onboarding chooses local or cloud mode, but
   does not yet guide a user through a first complete value-producing workflow.
2. **Retention risk.** A wide set of dashboards and tools does not by itself
   create a weekly or monthly return event.
3. **Positioning risk.** Local-first budgeting, net worth, investments, FIRE,
   and AI insights are increasingly available from focused competitors.

Engineering correctness remains mandatory, especially for financial import,
recovery, encryption, and Sync. It is a release condition, not by itself a
reason for a user to adopt or retain the product.

## External Demand Evidence

### Cashflow uncertainty is a real user problem

The US Federal Reserve's report on household economic well-being in 2024
found that:

- 19 percent of adults spent more than their income in the prior month.
- 17 percent did not pay all bills in full in the prior month.
- 11 percent had struggled to pay bills during the year because income varied.
- Only 51 percent spent less than their income in the prior month.

Source: [Federal Reserve, Economic Well-Being of U.S. Households in 2024](https://www.federalreserve.gov/publications/2025-economic-well-being-of-us-households-in-2024-income-and-expenses.htm).

The direct user questions are therefore forward-looking:

- Will cash run short before the next income event?
- Which bills and subscriptions are already committed?
- Is a discretionary purchase safe now?
- How long will emergency reserves last?
- What changes if income falls, a large expense occurs, or a life plan moves?

Historical categorization and reporting are inputs to these questions, not the
end product.

### Import friction is validated, but import alone is crowded

Chinese personal-finance products repeatedly lead with WeChat Pay and Alipay
recognition, automated entry, import/export, privacy, and local protection.
Examples include [Momi](https://www.momisapp.com/),
[Billbook](https://billbook.net.cn/), and
[Mini Accounting](https://miniexp.com/).

This supports three hypotheses:

- Fragmented payment records create recurring reconciliation work.
- Users do not want to enter every transaction manually.
- Import correctness and privacy can influence adoption.

It also shows that adding another generic accounting interface or another
isolated parser is not a durable differentiator. Imported data must produce a
better forecast, decision, or action.

### Personal-finance dashboards are becoming commodity capabilities

Current competitors validate demand while narrowing NaviWealth's whitespace:

- [Monarch household collaboration](https://www.monarchmoney.com/features/collaboration)
  combines separate and joint accounts, transaction review, budgets, and
  shared goals. Its 2026 Shared Views update adds account and transaction
  ownership for household members.
- [Copilot Money](https://www.copilot.money/faq) combines spending, budgets,
  investments, net worth, subscriptions, categorization, and conversational
  AI.
- [Actual Budget](https://actualbudget.org/docs/getting-started/sync/) provides
  a local-first data model and optional end-to-end encrypted sync.
- [Wealthfolio](https://wealthfolio.app/docs/introduction/) now covers local
  investments, net worth, spending, goals, and FIRE planning.
- [ProjectionLab](https://projectionlab.com/pricing) demonstrates willingness
  to pay for life-event modeling, Monte Carlo analysis, cashflow projections,
  and what-if comparison.

The inference is that "local-first plus budget plus net worth plus FIRE" is
not enough positioning. NaviWealth must win through the combination of
region-appropriate ingestion, private computation, forward-looking decisions,
and verified follow-through.

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

| Direction | Demand | Current product fit | Recommendation |
|---|---:|---:|---|
| Financial inbox and monthly close | High | Very high | Build and validate first |
| 30/90-day money runway | High | Very high | Make the core product loop |
| Life-event decision room | High-value, lower-frequency | High | Second product phase |
| Household and partner finance | High | Low to medium | Research before architecture work |
| Personal health experiments | Medium | High | Use as a cross-domain loop |

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

FIRE, goals, Knowledge decisions, assumptions, and Execution actions should be
composed into a small number of opinionated scenarios:

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

HealthOS should not compete on displaying more wearable metrics or another
generic readiness score. Oura and platform health apps already offer daily
readiness, sleep summaries, guidance, and habit associations. See the
[current Oura app guide](https://support.ouraring.com/hc/en-us/articles/42987005571859-How-to-Use-the-Oura-App).

NaviWealth's stronger opportunity is a reviewable behavior experiment:

```text
Record a hypothesis such as "late caffeine reduces sleep quality"
  -> define a 14-day experiment
  -> create one concrete daily action
  -> compare wearable signals and subjective check-ins
  -> review the evidence
  -> keep, revise, or reject the routine
```

Wearable interventions are more useful when self-monitoring is combined with
specific goals, feedback, and goal review. See this
[systematic review and meta-analysis](https://pmc.ncbi.nlm.nih.gov/articles/PMC6120856/).

This direction uses existing Health, Knowledge, and Execution capabilities
without making diagnostic or causal claims. Current source-preserving and
observational outcome rules continue to apply.

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

### Implementation Baseline (2026-07-19)

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
  the signal.
- Monthly Close is evidence-driven. Account statement balances are compared
  with the exact period-end ledger sum; balanced, mismatched, and explicitly
  overridden facts are synced. A close stores its evidence and aggregate
  snapshot instead of manual checklist state. Open close sessions resume
  after navigation or restart, account coverage is explicit, and subsequent
  closes compare new and cleared signals plus the previous completion time.
- Money Runway excludes brokerage value from default spendable cash, includes
  unpaid amortization rows, deduplicates matching scheduled outflows, runs
  purchase/income-delay/income-reduction stress cases, and records daily
  30/90-day forecast snapshots when the Runway workspace evaluates current
  evidence.
- Saved financial decisions create a source-preserving review action. Due
  reviews enter Financial Inbox and store the observed source families and
  data-completeness score alongside the actual outcome.
- Opt-in product evidence uses local 90-day daily buckets plus cumulative
  counters. Settings can explicitly copy the privacy-safe aggregate report;
  no financial values, labels, routes, or row identifiers are included.

The next product step is therefore the six-week task study below. The current
activation, Inbox, and repeated-close paths are the instrumentation surface
for that study; more signal types, scenario templates, or domains should be
driven by observed failures rather than feature-count goals.

### Phase 1: Activation And Repeated Close

Target window: first 0 to 3 months after product discovery begins.

- Turn onboarding into a real first task rather than a feature tour.
- Deliver the first trustworthy result within ten minutes.
- Build the unified Financial Inbox.
- Compose existing data into a 30/90-day Money Runway.
- Allow a confirmed risk or opportunity to become an Execution action.
- Add privacy-safe, opt-in local product-funnel measurement.

### Phase 2: High-Value Decisions

Target window: 3 to 6 months, only after Phase 1 evidence.

- Add two or three validated life-event templates.
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
