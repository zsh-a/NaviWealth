# NaviWealth FinanceOS Roadmap

Status: active FinanceOS domain roadmap.

FinanceOS is the always-on seed domain for NaviWealth. This document owns
Finance-specific sequencing. Cross-domain shell, Memory Runtime, sync
namespace, agents, and domain opt-in work belongs in `roadmap-lifeos.md` and
`lifeos-shell.md`.

## Current Baseline

FinanceOS already includes:

- Accounts, assets, liabilities, expenses, investments, activity, and wealth
  views.
- FIRE planning through Phase 0-5.
- Budget and cashflow MVP.
- Options Income through wheel lifecycle.
- Watchlist, event timeline, DCA simulator, analytics, and command palette.
- Device-only Finance AI tools under Finance-owned feature paths.
- Sync v2 row-state support with `fin:` row-family prefix.

## Near-Term Priorities

### 1. Data Ingestion

Highest product leverage is reducing manual entry:

- Add provider-specific CSV/statement parsers only after real sample files
  or user demand.
- The parser entry point is now provider-aware (`statement_ingest_parser.dart`)
  for Alipay, WeChat Pay, and bank debit/credit exports; new providers should
  extend that detection layer rather than adding ad hoc UI parsing.
- Keep imported rows in reviewable draft state.
- Use deterministic parsing first; LLM/OCR can suggest, not silently commit.
- Add dedup coverage for account, expense, trade, and transfer imports.

### 2. Budget And FIRE Connection

Budget data is present; FIRE should consume it through the existing
`monthlyBudgetSignalProvider` seam rather than taking a repository
dependency.

Goals:

- Show budget strain in FIRE review surfaces.
- Keep the dependency one-way: FIRE reads the signal, Budget owns budget
  tables and summaries.
- Add focused tests for no-data, comfortable, strained, and over-budget
  states in FIRE UI.

### 3. Investment And Tax Decisions

Advanced investment work is decision-gated:

- Choose tax export priority before building export pipeline:
  IRS Schedule D, China individual income tax, or generic CSV.
- Keep tax policy code jurisdiction-specific and explicit.
- Do not add broker write/execution paths without typed confirmation and a
  clear external-side-effect proposal path.

### 4. Options Income P5

Tradier OAuth and real greeks remain gated by backend proxy design.

Rules:

- Any proxy must be schema-agnostic and must not write business tables.
- Broker credentials must not enter sync payloads or backup exports.
- External trade actions require typed confirmation.

### 5. Reporting And Export

FinanceOS should make user data portable:

- Prioritize backup/restore and generic export reliability before niche
  report formats.
- Add task-level tests for export and restore paths.
- Keep currency and money formatting behind shared formatters.

## Triggered Work

These stay out of scheduled work until their trigger is met:

| Area | Trigger |
|---|---|
| FIRE plan sync | A real multi-device FIRE inconsistency report |
| Sync E2EE | Sync v2 stable for the agreed production window |
| Provider-specific imports | User sample files or repeated manual-entry pain |
| Extra locales | A real non-English/Chinese user group |
| Household or multi-user finance | Explicit user request plus design review |

## FinanceOS Boundaries

- Finance feature slices may keep their legacy sibling layout, but new
  cross-domain composition belongs in `features/finance/` or `app/`.
- Finance tools belong in Finance-owned `ai_tools/` barrels.
- Finance rows use `fin:` only at the sync boundary.
- Finance code must not import HealthOS or KnowledgeOS business entities.
