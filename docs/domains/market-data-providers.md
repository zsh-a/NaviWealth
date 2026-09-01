# Market data providers — scope and licensing

NaviWealth's quote/search layer talks to Yahoo Finance, CoinGecko, and Sina on **two code paths with different trust levels**. Corporate-action reference data adds a separate provider-neutral path backed by Yahoo and, on native platforms, Eastmoney. This note pins which call belongs to which path and what we may do with the response.

## 1. Valuation main path — `getQuote` / `getHistorical`

Drives holdings valuation, dashboard, FIRE projections, benchmark comparison. Allowed to run unattended (background refresh, periodic recompute).

- Cached aggressively per `MarketCachePolicy`.
- Falls back to a stale cache + freshness badge when offline; never blocks UI on a network round-trip.
- The user opted in by adding the security to their portfolio.

## 2. Metadata enrichment path — `searchSymbol`

**Only** for one-shot, user-initiated metadata import:

- "从网络导入" button in the manual-add security sheet (`ManualSecuritySheet`).
- "同步元数据" action on the equity asset detail page (`_EquityAssetDetailPage`).
- AI tool calls that explicitly request enrichment on the user's behalf.

Constraints:

- Never invoked from a background task or render path. A user gesture is required.
- A failure (offline, upstream outage, no result) collapses to a non-blocking message — the form must still save.
- Imported metadata fills **only empty fields** on the existing asset row (`SecuritiesAssetRepository.enrichMetadata`); user-edited fields are never overwritten.
- Trade-entry does **not** call `searchSymbol`; it reads from the local FTS catalog and writes via `upsertSecurity`. A fresh install is fully usable offline.

## 3. Corporate-action reference path

`CorporateActionsService` routes provider-neutral requests through
`CorporateActionProvider` implementations:

- Yahoo supplies dividend/split timeline events for US and Hong Kong symbols.
- Eastmoney `RPT_SHAREBONUS_DET` supplies A-share distribution plans on native
  platforms. Its per-ten-share cash and stock ratios are normalized to
  per-share `Decimal` values at the provider boundary.
- Web treats the Eastmoney adapter as unsupported because the upstream endpoint
  does not provide a dependable browser CORS contract. It must not silently
  route an A-share request to an unrelated provider.

External corporate actions are public reference candidates, not user financial
facts. The service may feed read-only timelines, paper-simulation candidates,
or a user-confirmed entry flow, but it must never write directly to real
accounts, lots, journal entries, or postings. Provider failures, unsupported
markets, authoritative empty responses, and partial/malformed payloads remain
distinct result states. For Yahoo, a structurally valid empty events block is
`authoritativeEmpty`, mixed valid and malformed rows are `partial`, and an
invalid envelope or all-malformed event block is a failure. Provider event keys
remain part of Yahoo's source-scoped identity so two same-day events do not
collapse into one candidate.

The cache and single-flight layer sits above provider adapters. Normalized
candidates and fetch-state metadata persist in the device-local
`market_corporate_action_candidates` and
`market_corporate_action_fetch_states` tables. They are rebuildable cache rows,
remain outside Sync v3 and encrypted backups, and are cleared with FinanceOS
cache cleanup. An expired successful cache may be returned only as an explicit
`stale` result after refresh failure; it must never masquerade as fresh data.
Provider source identity and normalized revision hashes survive persistence so
later consumers can deduplicate revisions deterministically. Explicit
simulation baseline ranges remain uncached for now: only a complete successful
range may establish quantity-based entitlement, while an existing trusted
entitlement can advance its date-driven paper lifecycle locally without a
network refresh.

## Why the split exists

Yahoo's TOS forbids commercial redistribution of its quotes (see `yfinance_provider.dart`); CoinGecko's free tier caps at 30 req/min. Putting either on the main entry path would have made the primary flow externally-dependent (offline trade entry breaks), legally fragile, and operationally fragile (CoinGecko throttling cascading into data entry).

Demoting `searchSymbol` to user-initiated keeps the record-keeping path local-first while still letting motivated users pull metadata when they want it.

## Pointer

If you find yourself wiring `searchSymbol` into a render path, background job, or anything that runs without an explicit user gesture — stop and re-read. The valuation path (`getQuote` / `getHistorical`) is the right place; the enrichment path is not.
