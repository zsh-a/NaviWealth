/// Raw-SQL DDL for local-only Income Planner tables.
///
/// `options_opportunity_cache` is the scoring engine's output store. It
/// holds the most recent scan batches and is **never** added to the sync
/// OpLog — every device computes its own opportunities from its own
/// chain pull (`docs/options-income.md` §6.2). See also the parallel
/// pattern in `event_log_tables.dart`.
library;

const String createOptionsOpportunityCache = '''
CREATE TABLE IF NOT EXISTS options_opportunity_cache (
  scan_id            TEXT NOT NULL,
  option_symbol      TEXT NOT NULL,
  owner_user_id      TEXT NOT NULL,
  underlying         TEXT NOT NULL,
  market             TEXT NOT NULL,
  strategy           TEXT NOT NULL,        -- cash_secured_put | covered_call
  expiration         TEXT NOT NULL,        -- ISO8601 UTC midnight
  dte                INTEGER NOT NULL,
  type               TEXT NOT NULL,        -- call | put
  currency           TEXT NOT NULL,
  strike             TEXT NOT NULL,        -- Decimal stringified
  bid                TEXT NOT NULL,
  ask                TEXT NOT NULL,
  mid                TEXT NOT NULL,
  underlying_price   TEXT NOT NULL,
  volume             INTEGER NOT NULL,
  open_interest      INTEGER NOT NULL,
  implied_volatility TEXT,                 -- nullable Decimal stringified
  delta              TEXT,
  bid_ask_spread_pct TEXT NOT NULL,
  premium            TEXT NOT NULL,
  cash_required      TEXT NOT NULL,
  breakeven          TEXT NOT NULL,
  static_return      TEXT NOT NULL,
  annualized_yield   TEXT NOT NULL,
  margin_of_safety   TEXT NOT NULL,
  score              TEXT NOT NULL,
  risk_level         TEXT NOT NULL,        -- low | moderate | elevated
  explanation_json   TEXT NOT NULL,        -- OpportunityExplanation JSON
  scanned_at         TEXT NOT NULL,
  PRIMARY KEY (scan_id, option_symbol)
)
''';

/// Latest-scan-per-user lookup. The reader filters by owner + recency.
const String createOptionsOpportunityCacheOwnerScannedIndex = '''
CREATE INDEX IF NOT EXISTS idx_options_opp_owner_scanned
  ON options_opportunity_cache(owner_user_id, scanned_at DESC)
''';

/// Browse-by-symbol path used by the detail sheet.
const String createOptionsOpportunityCacheSymbolIndex = '''
CREATE INDEX IF NOT EXISTS idx_options_opp_underlying
  ON options_opportunity_cache(owner_user_id, underlying, scanned_at DESC)
''';

const List<String> optionsOpportunityCacheDdl = [
  createOptionsOpportunityCache,
  createOptionsOpportunityCacheOwnerScannedIndex,
  createOptionsOpportunityCacheSymbolIndex,
];
