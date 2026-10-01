# FinanceOS Domain SSOT

Status: active domain entry point.

Last reviewed: 2026-08-01.

## Document Contract

The production Weekly Wealth Review is a scheduled LLM assistant registered
through the Finance pack and adapted by app composition. It reads authoritative
Finance tools and generates evidence-backed analysis; deterministic financial
calculations remain tool-owned. The task must not invent weekly returns from
a current snapshot. No model means no generated review, not a rule-based
replacement. Existing agent/report identities are retained.

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
Plan tab's visible workflow entries instead of competing as global commands.
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

### Investment Interaction

The Plan hub keeps cash safety and goals/contributions visible. Advanced
rebalancing and income tools live behind a disclosure, expanded automatically
for active income strategies, Wheel lifecycles, active/attention rebalancing,
or unavailable advanced-source status. Due life-event reviews remain in the
attention list; routine scenario access is consolidated under the cash-runway
"Simulate a change" section alongside the custom stress test. Existing scenario
routes and saved decisions remain available.

DCA plans can be created directly from validated inputs without requesting
market history. Historical simulation is an explicit optional preview; stale
preview parameters and failed previews never block saving the current plan.
The plan duration controls the plan end date; a preview uses the same number
of historical years. Cash runway retains six upcoming flows in its overview
and a full timeline in the detail sheet. Stable workflow rows retain specific
status. The compact attention section keeps its highest-priority item and an
all-items sheet. Optional brief slots contribute spacing only when present.
Dividend history uses year selection rather than reveal/collapse. Phone
liability details keep recent/upcoming installments in the overview and a
live, year-filtered full schedule in a sheet; payment and undo actions retain
their original workflow.

Portfolio scope, investment-plan access, and selected-portfolio management share
one compact toolbar. Supporting cost and gain figures are subordinate to the
headline value; holdings precede returns and event
summaries. Holdings form one continuous lazy list with no reveal/collapse gate.
Concentration risk keeps the highest-severity breach visible; all risks open
in a dismissible detail sheet without shifting the holdings or removing the
rebalance entry. Returns, dividend forecasts, and events show compact summaries
directly, with complete details in sheets. Portfolio configuration and capital
allocation stay in the explicit investment-plan action and portfolio studio,
not inside an insights accordion.
The investment-plan sheet compares portfolios in vertical rows using actual
and target weights, with explicit out-of-band labels. Trend charts and returns
stay in portfolio details. Create and allocation-edit actions replace the
overview sheet instead of stacking another sheet over it.
Completing or cancelling these forms resumes the plan overview with live targets
while preserving the originating portfolio scope. Leaving the originating route
does not reopen the overview.
Allocation editing uses the guarded full-page form pattern: precise percentage
inputs and optional sliders share proportional redistribution with a 100% total.
Typing remains local to the active field; redistribution occurs on blur, keyboard
completion, or save. Invalid input stays visible and blocks saving. Initial-to-draft
comparisons expose target and funding-rule changes. Restore resets targets,
tolerances, and funding rules to the normalized entry snapshot without persisting;
returning to that snapshot clears the unsaved-change guard. Failed saves retain
the draft for retry, and saving blocks duplicate submission and dismissal.
Funding rules use a separate guarded single-item form and apply to the allocation
draft; only saving the parent persists changes. Valuation loading, failure and
unavailable states remain explicit alongside targets, and drift labels state the
direction and percentage-point difference. Studio setup views omit the overview
summary so the current task stays near the page header.
Portfolio-page concentration risk follows the selected capital assignments,
including partial lots and the unassigned scope; global inbox risk remains
independent of that selection. Authored portfolios expose a direct management
entry beside the scope control. Wide layouts align holding metrics in columns;
phone layouts keep quantity and weight on a compact supporting line. Unrealized
P&L and holding return are labeled explicitly, and unsupported portfolio-scoped
XIRR explains its missing historical assignment basis.
Concentration risk uses a compact grouped surface: the worst breach, threshold
and severity stay visible beside a direct rebalance action. When several risks
exist, the summary row opens their sheet without expanding the holding layout.

### Watchlist Navigation And Reminders

Watchlist is available from Wealth's object navigation and the command palette.
Phone rows open the existing asset detail route using the canonical market and
symbol identity. Unowned watched symbols have a read-only quote detail fallback;
opening them must not create assets, holdings, or trades. Desktop retains the
master/detail layout.

Collection, sorting, and filtering use one local preferences-backed view state;
only desktop row selection is encoded in the URL. Deleted collections reset the
scope in the view-state controller. The pinned scope toolbar exposes active
filters and non-default sorting; overview statistics use an expandable daily
breadth summary with abnormal quote states only. Quote rows are lazy-built and
reserve their trend columns even when history is unavailable. Recent daily
close history is shared by row sparklines and the dated detail chart.

Watchlist search is transient and matches symbols and both catalog languages;
it composes with the persisted scope and facets. Bulk organization uses that
same visible result set, with explicit add/remove actions and a pinned footer.
Large collection inventories use a searchable picker. Collection simulations
open from the fixed toolbar, use the entire collection rather than filtered
rows, and remain reachable after its last watched item is removed.

Adding an already-active symbol preserves its original timestamp, alert rules,
and rule revision while adding only missing memberships. Unchanged reminder
saves are no-ops; pause/resume and explicit re-arming are distinct actions.
The editor validates a positive, non-overlapping lower/upper price band and
shows device-local delivery state. History-load failures remain retryable and
are not presented as a successful empty history.

The list publishes quote updates incrementally, reusing per-symbol in-flight
requests and previous prices during refresh. Detail quotes do not wait for the
whole list. Sequential list prefetch and the market service's cache/rate limits
remain in place. Tool results and paper simulations consume completed quote
batches; intermediate UI emissions must not create simulation observations.

Price reminders are foreground-only: check on quote refresh, app resume, and
every 15 minutes while the app is open. There is no background price evaluator.
The UI must state this limit explicitly. Supported, permitted system
notifications use the shared notification service; otherwise the Watchlist page
presents the reminder. Only confirmed delivery consumes a rule revision, and
deduplication is owner-scoped. Stale, future-dated, erroneous, or mismatched quotes
cannot trigger a reminder.

### Watchlist Paper Simulations

Watchlist uses one searchable collection selector independent of collection count,
a labelled simulation entry, and a separate search/sort/filter row. Active filters
stay on one horizontally scrollable line. The collection's paper workspace has
the route `/wealth/watchlist/collections/:collectionId/simulations`; it loads the
entire collection, independent of list filters. Saved simulations and local
history render before quotes finish loading; quote loading, errors, coverage,
fetch time, and refresh stay inline without replacing the workspace. Only a
completed quote batch may record a new live observation. Multiple scenarios use
compact selectable overview rows with currency/capital, recorded cumulative
change, observation date, and incomplete-day warnings. Overview rows read only
stored, lineage-filtered observations; only the selected detail loads historical
quotes, charts, and dividend reconciliation. A single scenario opens directly
as the detail. Saving selects and reveals the returned scenario. Selection and
creation-date/name sorting are device-local preferences scoped by user and
collection. A `simulationId` query parameter opens a particular scenario and
takes precedence over the saved selection. Missing/deleted or other-collection
ids display an unavailable notice; deletion falls back to an available scenario.
Overview name search never changes the selected detail; it explains when that
detail lies outside the search results.
Create and allocation edit use guarded full pages with pinned save bars. Only
lightweight symbol selection uses a sheet, with a pinned confirmation footer.
Busy forms block repeat submission, pointer/keyboard editing, and dismissal;
successful save returns to and reveals the saved scenario in the workspace.
Creation previews the exact equal-weight split after reserving cash, or accepts
custom weights before the first save. Both forms pin the allocation total,
remaining/excess weight, and save action above the keyboard. Filling cash is
disabled with an explanation when position weights are invalid or exceed 100%.
Validation reveals the first invalid field; symbol-selection errors stay inline,
and allocation-total errors stay visible in the pinned summary.
Form actions and selection summaries wrap at large text sizes, while the save
bar remains above the keyboard. Allocation editing displays the scenario's own
currency, independent of later app-preference changes. Currency charts use
distinct range-aware compact ticks and full currency values for inspection,
with measured label widths and deduplicated dates.

Configuration saves update the name and allocation in one local transaction,
including sync outbox pointers. Pending snapshots cannot be edited; a definition
or head change while editing requires reopening the form before saving. Existing
capital is immutable: copying the current form configuration creates a new id,
capital baseline, and observation history while preserving the source simulation.
For older definitions that allowed capital edits, cumulative return uses the
recorded observation baseline rather than the edited definition's amount.

Result cards show quote completeness, missing symbols, and the UTC quote date
before headline numbers. An entirely unpriced invested allocation displays an
unavailable daily move and omits its amount; an all-cash allocation is explicitly
identified. Observation loading/errors never substitute initial capital for a
missing latest value. A baseline-only series is labelled as a creation baseline;
recorded results display their UTC observation date. Historical backfill progress,
available data, partial coverage, empty responses, and request failures are
displayed separately from the existing observation series, with retry for
incomplete or failed fetches. The detail shows the actual UTC record range and
the count of incomplete observed days after the baseline; it does not claim
exchange-calendar completeness. Daily metric labels wrap, and larger text uses
a vertical metric layout. Each holding labels target weight, individual stock
move, and weighted contribution in percentage points separately. Quote
eligibility is shared by the display, projection, and observation request:
loading, failed requests, absent quotes, stale cache, invalid identity/price,
missing previous close, and an older UTC quote day each have a specific reason.
Unusable or unrelated quotes cannot advance the observation day.

Live observation writes show saving, the actual acknowledged UTC date, skipped
writes, or an explicit failure with retry. Writes serialize and coalesce newer
queued inputs; rebuilding async sections cannot repeat the same in-flight
write. Failed writes retain the existing chart and do not retry on every redraw.
Dividend refresh progress and failures remain visible even when saved entries
exist. Refresh retry does not duplicate a pending request, and saved records
remain available during refresh. Local record-read errors and a successfully
refreshed empty dataset have distinct states.

Watchlist simulations are a separate paper-only aggregate backed by
`watchlist_simulations`, legacy compatibility positions, a deterministic
allocation head, immutable effective-dated allocation versions, virtual holding
versions, and action entries. The head row id equals the simulation id, so Sync
v3 LWW selects one complete allocation snapshot atomically instead of merging
independently-authored position rows into an impossible total. Head-first page
arrival is an explicit pending state; values and entitlement materialization
remain blocked until the selected version's cash and holding weights total
exactly 100%. Simulation and compatibility-position protocol markers prevent a
missing or tombstoned head page from being mistaken for legacy data. Concurrent losing
branches remain immutable history but are never projected. They may reference
a watchlist collection and canonical watchlist-item ids, but must never reuse or
write `InvestmentPortfolio`, accounts, lots, journal entries, postings, or trade
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
reallocations create a new effective-dated version, link it to the previously
selected version, and atomically advance the deterministic head. Quantity stays
unknown until a trustworthy capital base is available rather than being derived
from the legacy projection curve. Record-date lookup walks the selected head's
predecessor lineage before reading its holding child, so a concurrent losing
branch or removed symbol cannot silently supply an older quantity. Pre-head
rows retain a deterministic legacy fallback and are linked as virtual
predecessors when the first headed version is introduced; every newly written
version requires an explicit head and can never be selected by fallback
heuristics. Valued action entries and local observations store an allocation
basis key. A head change immediately hides basis-mismatched paper cash and
curve points, while later reconciliation clears or rebuilds those derived
values from the winning lineage.

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
quote days are treated as missing rather than attributed to a newer day. When
the simulation view is opened, completed historical daily bars are also
backfilled from the creation baseline through yesterday when the market
service provides them; adjusted closes are preferred when available. Stale
historical responses cannot create new observations. Retrying may repair an
incomplete day only with increased priced coverage and reduced missing weight
in the same allocation basis; complete days and previous allocation lineages
remain unchanged. Repairs rebuild later derived values in one transaction. A
local-only `watchlist_simulation_observations` read model records the creation
baseline and at most one observation per UTC day. A synced/restored simulation
rehydrates that baseline locally before recording a later observation.
Same-day refreshes replace that day's projection from the prior observation,
while allocation changes affect only future observations. These derived rows
do not sync and are FinanceOS cache data. They survive a tombstone because
deleting a simulation is undoable and a newer write can revive the definition
through last-writer-wins; dropping them on the tombstone would silently restart
the observed curve. They are removed once the definition row itself is gone.

The observation curve is not historical NAV or actual return: it begins only
when the simulation exists, omits days with no priced allocation, and does not
infer FX history or corporate-action adjustments beyond a provider-supplied
adjusted close. Missing symbols reduce priced coverage for that day. These
derived rows do not sync and remain rebuildable FinanceOS cache data.

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

- Keep all Finance business slices and Finance composition under
  `features/finance/`; cross-domain composition belongs in `app/`.
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
