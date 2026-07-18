# NaviWealth FinanceOS Roadmap

Status: active FinanceOS sequencing SSOT.

Last reviewed: 2026-07-18.

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
- A privacy-safe representative Alipay file is checked in with an
  auto-discovered expectation manifest that pins every accepted and rejected
  row. WeChat Pay and bank parser tests use synthetic inputs and do not
  establish production-format support.
- Confirmation requires a selected statement account; duplicate and
  likely-duplicate drafts are excluded from batch confirmation. Trade
  principal and transfer/refund inputs remain rejected before draft creation
  until typed destinations exist.

Exit evidence:

- Add a redacted representative WeChat Pay fixture after a real sample or
  confirmed demand is available.
- Add representative bank debit and credit fixtures after real samples or
  confirmed demand are available.
- Pin provider, accepted/rejected counts, status handling, amount direction,
  currency, description/payee normalization, and raw-text-free diagnostics for
  every representative file.
- Keep account selection and expense/income duplicate outcomes covered at the
  confirmation boundary. When typed trade or transfer destinations are added,
  add their dedup and confirmation contracts before accepting those rows.
- Imported rows remain drafts until explicit confirmation; deterministic
  parsing remains primary and LLM/OCR suggestions never silently commit.

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

Exit evidence:

- Prove interruption recovery on the production Android file-backed database.
- Expand the representative dataset only when measured production exports
  exceed the current 1,000-row boundary.
- Generic export preserves currency and money semantics through shared
  formatters and machine-readable values.

## Next

### Finance Outcome Interpretation

Add Finance-specific before/after interpretation to the Life → Execution loop
only where the signal is deterministic, such as budget posture or a stale
import queue. Preserve source references and observational language; action
completion must not be presented as proof of financial causality.

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

## FinanceOS Boundaries

- Finance feature slices may keep their legacy sibling layout, but new
  cross-domain composition belongs in `features/finance/` or `app/`.
- Finance tools and agents belong in Finance-owned feature paths and are
  exported through the Finance `DomainPack`.
- Finance rows use `fin:` only at the sync boundary.
- Finance code must not import sibling domain business entities.
- Architecture rules are owned by the Northstar and LifeOS Shell; do not copy
  mutable architecture inventories into this roadmap.
