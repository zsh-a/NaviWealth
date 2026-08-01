# NaviWealth FinanceOS Roadmap

Status: active FinanceOS sequencing SSOT.

Last reviewed: 2026-08-01.

FinanceOS is the always-on seed domain. This document contains only
Finance-specific product sequencing. Cross-domain shell, Memory Runtime,
agents, sync infrastructure, native distribution, and domain opt-in work
belongs in `roadmap-lifeos.md` and the architecture SSOTs.

## Product Snapshot

FinanceOS currently includes accounts, assets, liabilities, expenses,
investments, activity, wealth, FIRE planning, budget and cashflow, Options
Income through the Wheel lifecycle, analytics, backup/restore/export, and
device-only Finance AI tools. Finance rows use the `fin:` prefix only at the
Sync v3 boundary.

Budget already feeds FIRE through the one-way `monthlyBudgetSignalProvider`
read-model seam. FIRE renders and tests no-data, comfortable, strained, and
over-budget states; this is baseline rather than future work.

## Now

### F1. Representative Statement Corpus And Import Correctness

Outcome: make high-frequency Finance data entry fast while keeping imports
deterministic, reviewable, private, and reversible.

Current evidence:

- `statement_ingest_parser.dart` detects Alipay, WeChat Pay, bank, broker, and
  generic formats.
- Privacy-safe representative Alipay, WeChat Pay, and CMB credit-card files
  are checked in with auto-discovered expectation manifests that pin every
  accepted and rejected row. The WeChat fixture preserves the structure and
  row semantics of a measured XLSX export; the CMB fixture preserves the text
  layout and transaction mix of a measured PDF statement.
- XLSX capture is decoded locally into the deterministic CSV lane. CMB
  statement text uses a dedicated row parser; binary PDF capture continues to
  use the existing provider-Vision lane.
- Confirmation requires a selected statement account; duplicate and
  likely-duplicate drafts are excluded from batch confirmation. Trade
  principal and transfer/refund inputs remain rejected before draft creation
  until typed destinations exist.

Exit evidence:

- Add a representative bank debit fixture after a real sample or confirmed
  demand is available.
- Pin provider, accepted/rejected counts, status handling, amount direction,
  currency, description/payee normalization, and raw-text-free diagnostics for
  every representative file.
- Keep account selection and expense/income duplicate outcomes covered at the
  confirmation boundary. When typed trade or transfer destinations are added,
  add their dedup and confirmation contracts before accepting those rows.
- Imported rows remain drafts until explicit confirmation; deterministic
  parsing remains primary and LLM/OCR suggestions never silently commit.

Owner: FinanceOS. Cross-domain sequencing for this initiative lives in
`roadmap-lifeos.md` N1; this document owns the parser, fixture, and Finance
workflow details.

## Next

These are accepted follow-ups but are not allowed to displace `Now` work
without an explicit reorder.

### F2. Portability And Recovery Correctness

Outcome: users can recover or move Finance data under realistic failure
conditions, not merely navigate to an export screen.

Current evidence:

- Backup, restore, and export have task-level flows.
- Android on-device integration opens the production file-backed database and
  restores encrypted bytes through `BackupService`.
- Logical payloads are fully validated before destructive work. Wrong
  passphrases, corrupt/truncated archives, incomplete archives, and insertion
  failures preserve existing rows; inserts and Sync outbox pointers roll back
  together.
- Older known-table archives preserve Sync metadata, and a deterministic
  1,000-row restore stays inside a ten-second test budget.
- A native file-backed failure test starts destructive restore work, forces an
  insert error, then closes and reopens the database to prove the previous
  account and outbox pointer were durably rolled back. Android emulator CI
  owns the device run.
- The two-process Android interruption runner now proves it targeted a live
  app PID, confirms `am force-stop` removed it, rejects skipped verification,
  and writes a privacy-safe evidence JSON only after the fresh process proves
  the preserved account and outbox pointer.
- Generic encrypted export pins currency and money semantics with a
  cross-currency liability fixture. ISO currency plus high-precision decimal
  principal, rate, and payment fields survive decrypt/restore exactly, without
  localized symbols or grouping separators.

Exit evidence:

- Prove interruption recovery on the production Android file-backed database.
- Expand the representative dataset only when measured production exports
  exceed the current 1,000-row boundary.

### Demand-Validation Operations

Use the implemented activation, repeated import, Inbox-to-action, and Monthly
Close loops in the six-week task study defined in `roadmap-lifeos.md`. The
next Finance code change must address an observed failure in those sessions. In
particular:

- Add per-row import editing only if real corrections show a repeated
  field-level pattern.
- Add another statement provider only with a redacted representative fixture.
- Add more Inbox detectors only when users repeatedly miss the same
  consequential work.

The study can use the local aggregate export and per-import privacy-safe
diagnostic report. It must not add transaction contents, balances, labels,
account ids, or source row ids to telemetry.

### Investment Decision Portability

Before adding a jurisdiction-specific tax export, collect enough product
evidence to choose one first target. Generic data portability remains more
important than speculative tax-policy breadth.

## Triggered Bets

| Area | Trigger | Required decision |
|---|---|---|
| Additional statement provider | Redacted real file or repeated measured entry pain | Parser scope and representative fixture |
| Tax export | Confirmed user jurisdiction and workflow priority | IRS Schedule D, China individual income tax, or generic tax CSV |
| Tradier OAuth / real greeks | Confirmed need for authenticated options data | Credential custody, schema-agnostic proxy, revocation, typed confirmation |
| Broker write/execution | Explicit demand and external-side-effect design review | Proposal mode, typed confirmation, audit and failure recovery |
| FIRE plan sync | A real multi-device FIRE inconsistency report | Source of truth and migration behavior |
| Extra locales | A real non-English/Chinese user group | Localization scope and support policy |
| Household/multi-user finance | Explicit request plus design review | Ownership, permissions, privacy and sync model |

Broker credentials must never enter Sync payloads or backup exports. Any
future proxy stays schema-agnostic and must not normalize, score, or write
Finance business data.

## Completed Baseline

- Deterministic current-month budget pressure participates in the Life →
  Execution loop. Strained or over-budget posture preserves the `fin:budgets`
  month aggregate source; a later settled budget read reports only whether the
  same signal is still detected, without causal attribution.
- Accounts, assets, liabilities, expenses, investments, activity, and wealth
  workflows.
- FIRE planning through Phase 0–5.
- Budget and cashflow MVP, including the tested Budget → FIRE signal seam.
- Options Income through Wheel lifecycle, with local deterministic scoring and
  read-cache-only AI behavior.
- Watchlist, event timeline, DCA simulator, analytics, and command palette.
- Device-only Finance tools and four Finance agent result surfaces registered
  through the Finance `DomainPack`.
- Sync v3 row-state coverage with the `fin:` row-family prefix and reset
  generation.
- Backup, restore, and export navigation/task baselines.
- Evidence-driven Financial Inbox and Monthly Close: account statement
  reconciliation, explicit difference overrides, durable close snapshots, and
  signals for import, runway, FX, balance, anomaly, subscription, valuation,
  and due decision review. Inbox items expose evidence and detection history,
  route to source repair, and retain linked Execution action state. Completed
  and dropped actions feed a domain-neutral close-out seam; Finance then
  persists cleared, still-detected, inconclusive, or action-dropped
  revalidation without inferring causality from incomplete data. Monthly Close
  resumes an open period, compares coverage, signal changes, carried-forward
  exceptions, and completion time, and presents recent close history.
- Resumable Finance activation from first import through review clearance to a
  trustworthy Money Runway result, with an owner-scoped device milestone and
  opt-in first-useful-result timing.
- Thirty-/ninety-day Money Runway with spendable-cash policy, scheduled
  liability payments, deterministic stress scenarios, daily forecast
  sampling from the Runway workspace, and observed forecast error.
- Versioned life-event decisions with deterministic alternatives,
  source-preserving Execution review actions, due-review Inbox signals, and
  observed outcome evidence.
- Opt-in local product-evidence reports with bounded daily buckets, repeat
  import/action/revalidation counters, and explicit privacy-safe copy actions.
  Import diagnostics export stable enums and counts only; financial source
  contents and identifiers are excluded by construction and test.

## FinanceOS Boundaries

- Finance feature slices may keep their legacy sibling layout, but new
  cross-domain composition belongs in `features/finance/` or `app/`.
- Finance tools and agents belong in Finance-owned feature paths and are
  exported through the Finance `DomainPack`.
- Finance rows use `fin:` only at the sync boundary.
- Finance code must not import sibling domain business entities.
- Architecture rules are owned by the Northstar and LifeOS Shell; do not copy
  mutable architecture inventories into this roadmap.
