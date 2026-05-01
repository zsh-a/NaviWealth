# Market data providers — scope and licensing

NaviWealth uses three external market-data providers (Yahoo Finance,
CoinGecko, Sina) but they sit on **different code paths with different
trust levels**. This note pins down which path each call belongs to and
what we are allowed to do with the response.

## The two paths

### 1. Valuation main path — `getQuote` / `getHistorical`

Used by holdings valuation, dashboard, FIRE projections, benchmark
comparison, etc. This path is allowed to run unattended (background
refresh, periodic recompute).

- Cached aggressively per `MarketCachePolicy`.
- Falls back to a stale cache + freshness badge when offline; never
  blocks a UI render on a network round-trip.
- The user explicitly opted in to having quotes fetched the moment they
  added a security to their portfolio.

### 2. Metadata enrichment path — `searchSymbol` (FIR-78)

Used **only** for one-shot, user-initiated metadata import:

- The "从网络导入" button in the manual-add security sheet
  (`ManualSecuritySheet`).
- The "同步元数据" action on the equity asset detail page
  (`_EquityAssetDetailPage`).
- Future AI tool calls that request enrichment on behalf of the user.

Constraints on this path:

- Never invoked from a background task or main-path render. A user
  action is required.
- A failure (offline, upstream outage, no result) collapses to a
  non-blocking message — the form must still save without it.
- Imported metadata fills **only empty fields** on the existing asset
  row (`SecuritiesAssetRepository.enrichMetadata`); user-edited fields
  are never overwritten.
- The "trade entry" form does **not** call `searchSymbol`; it reads
  from the local FTS catalog (FIR-76) and writes the manual-add row
  via `upsertSecurity` (FIR-75). A fresh install is fully usable
  offline.

## Why the split exists

Yahoo Finance's TOS forbids commercial redistribution of its quotes
(see comments in `yfinance_provider.dart`). CoinGecko's free tier has a
30 req/min ceiling. Putting either provider on the main entry path —
where every trade record would have triggered a fetch — would have made
the app's primary flow:

1. Externally-dependent (offline trade entry breaks).
2. Legally fragile (commercial redistribution of free-tier Yahoo data).
3. Operationally fragile (CoinGecko throttling cascades into the user's
   data entry).

Demoting `searchSymbol` to user-initiated enrichment keeps the
trade-entry / record-keeping path local-first and offline-clean while
still letting motivated users pull metadata when they want it.

## Pointer for future contributors

If you find yourself wiring `searchSymbol` into a render path,
background job, or anything that runs without an explicit user gesture,
stop and re-read this note. The valuation path (`getQuote` /
`getHistorical`) is the right place; the enrichment path is not.
