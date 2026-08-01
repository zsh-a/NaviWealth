# FinanceOS Domain SSOT

Status: active domain entry point.

Last reviewed: 2026-08-01.

## Document Contract

Owns FinanceOS scope, composition, data ownership, and routing to focused
Finance SSOTs. It does not own cross-domain architecture, Sync v3 wire
semantics, or roadmap sequencing.

Code authority:

- `apps/mobile/lib/app/domain_packs/finance_pack.dart`
- `apps/mobile/lib/features/finance/`
- `apps/mobile/lib/core/sync/sync_table_registry.dart`

Read this before changing Finance composition or deciding which Finance topic
document applies. Use focused feature tests plus the composition and boundary
gates for verification.

## Scope

FinanceOS is the always-on seed domain. It owns accounts, assets, liabilities,
journal activity, cashflow and budgets, investments, portfolio strategy, FIRE,
financial decisions, market-data consumption, and options income.

FinanceOS does not own Health, Knowledge, or Execution entities. Cross-domain
coordination uses domain-neutral Life signals, source references, proposals,
Memory records, and app-level composition.

## Composition

`kFinancePack` registers FinanceOS once through the production `DomainPack`
inventory. It contributes:

- Today, Activity, Wealth, and Plan shell tabs;
- Finance device tools, descriptors, intents, and prompt block;
- proposal kinds and Finance apply/undo routing;
- Finance agents and presentation metadata;
- trade-journal memory indexing and Finance background work;
- command palette, settings, data management, share ingestion, Life signals,
  and source-route resolution.

The registry and composition tests are authoritative for the exact inventory;
do not duplicate full tool or route lists here.

## Data And Sync

Finance repositories own Finance business-table access even though Drift table
declarations are centralized under `core/persistence/`. Syncable Finance rows
receive the `fin:` prefix only at the Sync v3 boundary. Derived opportunity
caches, diagnostics, AI traces, and Memory embeddings remain local unless an
owning SSOT explicitly says otherwise.

Money calculations use `Money` and `Decimal`; localized strings and floating
point values are presentation or provider-boundary concerns, not accounting
truth. Finance Ingest is the staged-input exception: it persists signed integer
minor units and must route decimal parsing and formatting through
`features/finance/ingest/domain/minor_unit_amount.dart` without floating-point
rounding.

## Topic Routing

| Concern | Authoritative document |
|---|---|
| Current Finance sequencing | [FinanceOS Roadmap](../roadmap/roadmap-finance.md) |
| Income-plan intent and allocation | [Income Strategy](income-strategy.md) |
| Options scanning, scoring, Wheel, journal, and risk rules | [Options Income](options-income.md) |
| Portfolio strategy grouping and rebalance ownership | [Portfolio Strategy Groups](portfolio-strategy-groups.md) |
| Quote/search/options provider boundaries and licensing | [Market Data Providers](market-data-providers.md) |
| Cross-domain shell and proposal composition | [LifeOS Shell](../architecture/lifeos-shell.md) |
| Sync wire behavior | [Sync v3](../sync/sync-v3.md) |

## Change Rules

- Put new Finance business behavior under `features/finance/`; legacy Finance
  slices may remain until touched by a real migration.
- Export tools and agents through the Finance pack instead of adding manual
  unions in bootstrap or shared code.
- Keep deterministic calculations out of the LLM and Backend.
- Route AI writes through the registered proposal/confirmation seam.
- Keep cross-domain references primitive and source-preserving; never import a
  sibling domain business model.
- Add sync registrations deliberately and test owner scope, primary key,
  backfill, backup, and reset behavior where applicable.

## Verification

Choose focused repository, application, AI-tool, Agent, or widget tests for the
changed feature. When composition or ownership changes, also run:

```bash
rtk ./tool/lint-cross-feature-imports.sh
rtk ./tool/lint-finance-domain-data-imports.sh
rtk ./tool/lint-ingest-money-conversions.sh
rtk ./tool/lint-domain-neutral-contracts.sh
cd apps/mobile
rtk flutter test test/app/domain_composition_test.dart
```
