# Market data providers — scope and licensing

NaviWealth's quote/search layer uses **two code paths with different trust
levels**. Android/macOS A-share valuation uses the standalone Rust `market-data-rs`
SDK (Tencent, Sina, Eastmoney); other market/platform routes and metadata
search use the Dart adapters. Their Dart chain contains Yahoo Finance
and CoinGecko; Sina is registered only on the remaining platforms.
Corporate-action reference data adds a separate provider-neutral path backed
by Yahoo and, on native platforms, Eastmoney. This note pins which call belongs
to which path and what we may do with the response.

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

## Android/macOS A-share SDK integration

`marketDataServiceProvider` selects `NativeMarketDataService` on native Android
and macOS. It handles A-share quotes and **raw daily history** through the
versioned JSON FRB surface in `lifeos_native/src/api/market.rs`. Unsupported
weekly/monthly requests fail explicitly. iOS, Web, Windows/Linux, other markets,
metadata search, and corporate-action reference routes retain their existing
implementations.

The native engine is process-wide and lazy. Android initializes the platform
TLS verifier through its application hook; macOS initializes the Rust crypto
provider without JNI. macOS Debug/Profile and Release entitlements permit
outbound networking. Neither path initializes an AI model. Rust owns capability routing, provider quotas,
retries, and circuit breakers; Dart does not retry or run the old A-share chain
after it fails. Explicit market filters never fan out to unrelated providers
when no provider supports that market. The SDK deadline is 25 seconds (including queueing); the bridge
has a 30-second timeout and cancels the matching native request. Identical Dart
requests share a pending future.

The SDK is currently vendored at `third_party/market-data-rs` from the revision
recorded in `VENDORED.md`, with unchanged SDK sources and MIT license. The app's
Cargo.lock pins resolved dependencies. It does not depend on a developer's
sibling directory or an unpublished remote URL. Replace the snapshot with a
pinned upstream dependency once that repository is published.

Drift owns the rebuildable `market_data_snapshots` cache (schema v95). It stores
whole response envelopes, limited to 256 entries, so actual source, fetch and
observation times, warnings, attempts, raw adjustment, and coverage survive
restarts. Exact history windows are cached independently; bars from different
fetches or providers are never spliced. This table is excluded from sync and
logical backups and included in FinanceOS cache cleanup. The embedded SDK uses
`NoCache`. Fresh/stale lifetimes follow `MarketCachePolicy`; refresh failure can
serve an explicitly stale entry only within its permitted age.

Internal request/cache identity uses canonical symbols such as `600519.SH` and
`920002.BJ`; returned Dart Quote/Bar symbols preserve the caller's normalized
identifier so existing watchlist identity checks continue to work. Existing
asset IDs and ledger records are not rewritten. Old Dart caches are not reused
on this route because their identity/adjustment metadata is insufficient.
`MarketResponse.diagnostics` preserves the canonical symbol and SDK quality
metadata. Decimal prices remain strings across FFI, quote instants are UTC, and
daily trading dates become UTC-midnight labels without subtracting UTC+8.

History coverage is calendar-gap screening, **not exchange-session completeness
certification**. Partial windows and adjustment substitutions are rejected.
The raw close is suitable for quantity-based simulation/valuation that applies
corporate actions separately; it is not a total-return series. Current-day bars
may be unfinished, and completed-day consumers must continue to exclude them.

Focused validation from `apps/mobile`:

```bash
rtk flutter test test/features/finance/data/market/native test/core/persistence/market_data_migration_test.dart
rtk flutter test integration_test/native_market_data_integration_test.dart -d <android-device-or-macos> --dart-define=LIVE_MARKET_DATA=true
```

The integration test is opt-in because it accesses live upstream endpoints. It
uses the production provider registration and verifies native FRB/TLS, three
exchange quote identities, raw daily history, and Drift cache reuse. No login,
AI profile, or embedding model is needed. A passing emulator run does not
establish physical-device or other-platform validation.

Verified on 2026-09-28: the Android API 36.1 arm64 emulator fetched
`600519.SH`, `000001.SZ`, and `920002.BJ` through Tencent, returned 21 raw daily
bars for the smoke-test window, and reused the quote through its alternate
`SH600519` spelling from Drift. Dart analysis, adapter/platform-routing tests,
v94-to-v95 cache migration, market/watchlist regression tests, and the native
Rust unit suite passed. The arm64 release APK built with
`--android-project-arg=naviwealth-arm64-only=true`; the repository's
`tool/check-android-native-libs.sh` validated all 12 packaged native libraries,
the Android TLS initializer export, and 16 KiB ELF/ZIP alignment.
Physical-device validation remains outstanding. These are local validation
builds, not published releases.

On the same date, the macOS 27 Apple Silicon host passed the live integration
test through the production FRB route: all three exchange quotes came from
Tencent, raw history returned 21 bars, and `SH600519` reused the Drift entry.
The focused adapter, platform-routing, composite-service, and watchlist suite
passed 42 tests. Local testing used a temporary Xcode configuration with ad-hoc
signing and a copy of the Debug entitlements without `keychain-access-groups`;
the checked-in signing settings and entitlements were not changed. This smoke
test needs outbound networking but does not exercise Keychain storage. The
macOS Release build also passed (final app and native framework: arm64), using
the corresponding temporary Release entitlement copy. After local ad-hoc
re-signing, `codesign --verify --deep --strict` passed. Dart analysis reported
no issues and all six architecture gates passed. This app has not been
notarized or published; Intel Mac runtime verification remains outstanding.

## Why the split exists

Yahoo's TOS forbids commercial redistribution of its quotes (see `yfinance_provider.dart`); CoinGecko's free tier caps at 30 req/min. Putting either on the main entry path would have made the primary flow externally-dependent (offline trade entry breaks), legally fragile, and operationally fragile (CoinGecko throttling cascading into data entry).

Demoting `searchSymbol` to user-initiated keeps the record-keeping path local-first while still letting motivated users pull metadata when they want it.

## Pointer

If you find yourself wiring `searchSymbol` into a render path, background job, or anything that runs without an explicit user gesture — stop and re-read. The valuation path (`getQuote` / `getHistorical`) is the right place; the enrichment path is not.
