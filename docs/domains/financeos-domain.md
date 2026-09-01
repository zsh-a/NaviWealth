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

The command palette favors frequent Finance work. FIRE, Income Strategy,
Options, Wheel lifecycle, and strategy statistics remain available through the
Plan tab's progressive disclosure instead of competing as global commands.
Their Assistant tools are likewise added only while the user is on the owning
Plan route.

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

### Watchlist Paper Simulations

Watchlist simulations are a separate paper-only aggregate backed by
`watchlist_simulations`, positions, effective-dated allocation versions,
virtual holding versions, and action entries. They may reference a watchlist
collection and canonical watchlist-item ids, but must never reuse or write
`InvestmentPortfolio`, accounts, lots, journal entries, postings, or trade
execution state. All paper source rows sync under `fin:` and participate in
encrypted backup; local observations remain derived.

Existing simulations retain `weightedDailyChangeV1`. New simulations created
with quote evidence use `holdingsTotalReturnV2`: creation captures raw price,
price currency/date/source, target weight, and a virtual `Decimal` quantity
only when the quote is non-stale and its currency equals the simulation base
currency. Quantity evidence also requires canonical market/symbol identity,
a non-empty source, and a non-future quote timestamp. Missing, stale,
identity-mismatched, provenance-free, or cross-currency quotes keep quantity
and `fx_to_base` null; the system never assumes missing FX equals one.
Unchanged allocation saves are no-ops and preserve trusted quantities. Real
reallocations create a new effective-dated version but leave quantity unknown
until a trustworthy capital base is available, rather than deriving holdings
from the legacy projection curve. Record-date lookup first selects the active
allocation version and then its holding child, so a removed symbol cannot
silently reuse an older quantity.

Implemented provider dividends materialize automatically as deterministic
synced `watchlist_simulation_action_entries`. Reconciliation requests an
uncached provider range from the simulation baseline so record-date quantity
can apply trusted intervening split and implemented stock-distribution ratios.
Only a complete successful range may create or revise a quantity-based
entitlement; partial/stale refreshes may add reference terms but cannot
downgrade a previously trusted entitlement. Provider source key, revision
hash, dates, currency, and per-share terms always survive. Holdings V2 resolves
the latest virtual holding at the record date and may record eligible quantity
and gross paper entitlement. Quantity adjustments require an explicit ex-date;
missing or boundary-ambiguous dates and conflicting stock-distribution ratios
leave the entitlement reference-only. After a trusted entitlement exists, a
provider-independent local reducer advances it monotonically: at ex-date the
same gross amount becomes a paper receivable; at pay-date it moves to gross
paper cash pending tax, clearing the receivable rather than adding a second
amount. Offline refreshes and earlier device clocks cannot move it backward.
Both lifecycle balances are informational and excluded from NAV. Unknown
withholding tax, net cash,
base-currency value, and NAV application remain null. Legacy or incomplete
holdings stay `referenceOnly`. Provider cancellation updates the same paper
row even when coverage is incomplete; disappearance from a feed does not
delete history. No materialization path may write real investment or ledger
tables.

The current projection applies available point-in-time daily percentage moves
to virtual target weights. Missing or stale quotes reduce priced coverage, and
only quotes from the latest shared UTC observation day are combined; older
quote days are treated as missing rather than attributed to a newer day. A
local-only `watchlist_simulation_observations` read model records the creation
baseline and at most one observation per UTC day. A synced/restored simulation
rehydrates that baseline locally before recording a later observation.
Same-day refreshes replace that day's projection from the prior observation,
while allocation changes affect only future observations. These derived rows
do not sync, are FinanceOS cache data, and are deleted when a simulation is
tombstoned locally or through Sync v3.

The observation curve is not historical NAV or actual return: it begins only
when the simulation exists, treats missing quotes as flat, and does not infer FX
history, split, or dividend adjustments. A future backfilled performance
simulation must first define one authoritative FX series, missing-bar policy,
and corporate-action adjustment policy.

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
