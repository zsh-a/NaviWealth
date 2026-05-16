# Market data providers — scope and licensing

NaviWealth talks to three external providers (Yahoo Finance, CoinGecko, Sina) on **two code paths with different trust levels**. This note pins which call belongs to which path and what we may do with the response.

## 1. Valuation main path — `getQuote` / `getHistorical`

Drives holdings valuation, dashboard, FIRE projections, benchmark comparison. Allowed to run unattended (background refresh, periodic recompute).

- Cached aggressively per `MarketCachePolicy`.
- Falls back to a stale cache + freshness badge when offline; never blocks UI on a network round-trip.
- The user opted in by adding the security to their portfolio.

## 2. Metadata enrichment path — `searchSymbol` (FIR-78)

**Only** for one-shot, user-initiated metadata import:

- "从网络导入" button in the manual-add security sheet (`ManualSecuritySheet`).
- "同步元数据" action on the equity asset detail page (`_EquityAssetDetailPage`).
- AI tool calls that explicitly request enrichment on the user's behalf.

Constraints:

- Never invoked from a background task or render path. A user gesture is required.
- A failure (offline, upstream outage, no result) collapses to a non-blocking message — the form must still save.
- Imported metadata fills **only empty fields** on the existing asset row (`SecuritiesAssetRepository.enrichMetadata`); user-edited fields are never overwritten.
- Trade-entry does **not** call `searchSymbol`; it reads from the local FTS catalog (FIR-76) and writes via `upsertSecurity` (FIR-75). A fresh install is fully usable offline.

## Why the split exists

Yahoo's TOS forbids commercial redistribution of its quotes (see `yfinance_provider.dart`); CoinGecko's free tier caps at 30 req/min. Putting either on the main entry path would have made the primary flow externally-dependent (offline trade entry breaks), legally fragile, and operationally fragile (CoinGecko throttling cascading into data entry).

Demoting `searchSymbol` to user-initiated keeps the record-keeping path local-first while still letting motivated users pull metadata when they want it.

## Pointer

If you find yourself wiring `searchSymbol` into a render path, background job, or anything that runs without an explicit user gesture — stop and re-read. The valuation path (`getQuote` / `getHistorical`) is the right place; the enrichment path is not.
