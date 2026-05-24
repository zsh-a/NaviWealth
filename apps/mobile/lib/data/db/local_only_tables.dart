/// Raw-SQL DDL for local-only tables that never ride the sync protocol.
///
/// - `options_opportunity_cache` — scoring engine output. Each device
///   computes its own opportunities from its own chain pull
///   (`docs/options-income.md` §6.2).
/// - `memories` + `memory_embeddings` + `events` — Memory Runtime
///   (`docs/lifeos-shell.md` §6, D-1.7b). Typed records with
///   lifecycle, vectors in a side table so embedder swap doesn't have
///   to rewrite memory rows.
///
/// See also the parallel pattern in `event_log_tables.dart`.
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

// ----------------------------------------------------------------------
// Memory Runtime (D-1.7b)
// ----------------------------------------------------------------------

/// Typed memory records. Vectors live in a separate table so swapping
/// the embedder doesn't have to touch payload/lifecycle fields.
///
/// `entities_json` is a JSON array of strings; small enough that
/// in-Dart filtering is fine and indexing it would be wasteful.
const String createMemories = '''
CREATE TABLE IF NOT EXISTS memories (
  id               TEXT PRIMARY KEY,
  kind             TEXT NOT NULL,            -- event|semantic|episodic|procedural
  scope            TEXT NOT NULL DEFAULT '*',
  owner_user_id    TEXT NOT NULL,
  source           TEXT,                     -- e.g. 'options_trade_journal'
  source_id        TEXT,                     -- back-pointer to origin entity
  source_event_id  TEXT,                     -- back-pointer to events.id when derived
  title            TEXT NOT NULL,
  summary          TEXT NOT NULL,            -- embedded text
  payload_json     TEXT NOT NULL,
  entities_json    TEXT NOT NULL,            -- JSON array of strings
  importance       REAL NOT NULL DEFAULT 0.5,
  confidence       REAL NOT NULL DEFAULT 0.8,
  valid_from       INTEGER,                  -- millis since epoch
  valid_until      INTEGER,
  created_at       INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL,
  last_accessed_at INTEGER
)
''';

/// Owner+kind path used by per-kind retrieval (e.g. "all my semantic
/// preferences").
const String createMemoriesOwnerKindIndex = '''
CREATE INDEX IF NOT EXISTS idx_memories_owner_kind
  ON memories(owner_user_id, kind)
''';

/// Owner+scope path used by ContextBuilder when assembling "applicable
/// rules" for a domain like options_trading.
const String createMemoriesOwnerScopeIndex = '''
CREATE INDEX IF NOT EXISTS idx_memories_owner_scope
  ON memories(owner_user_id, scope)
''';

/// Back-pointer lookup used by extractors to find an existing memory
/// for a given origin entity (so they can skip vs re-embed).
const String createMemoriesSourceIndex = '''
CREATE INDEX IF NOT EXISTS idx_memories_source
  ON memories(source, source_id)
''';

/// Vectors keyed by memory id. 1:1 with memories (FK CASCADE). Stored
/// as little-endian Float32 BLOB (32-d stub = 128 bytes; 384-d MiniLM
/// = 1.5 KB).
const String createMemoryEmbeddings = '''
CREATE TABLE IF NOT EXISTS memory_embeddings (
  memory_id    TEXT PRIMARY KEY,
  fingerprint  TEXT NOT NULL,                -- Embedder.fingerprint
  dimension    INTEGER NOT NULL,
  vector_bytes BLOB NOT NULL,
  FOREIGN KEY (memory_id) REFERENCES memories(id) ON DELETE CASCADE
)
''';

/// Fingerprint scan used by [MemoryRuntime.dropStaleVectors] after
/// swapping the embedder.
const String createMemoryEmbeddingsFingerprintIndex = '''
CREATE INDEX IF NOT EXISTS idx_memory_embeddings_fingerprint
  ON memory_embeddings(fingerprint)
''';

/// Cross-domain event log. Append-mostly; events older than the
/// recency window are still kept (retention policy is separate from
/// this DDL).
const String createEvents = '''
CREATE TABLE IF NOT EXISTS events (
  id            TEXT PRIMARY KEY,
  type          TEXT NOT NULL,
  timestamp     INTEGER NOT NULL,            -- millis since epoch
  source        TEXT NOT NULL,
  owner_user_id TEXT NOT NULL,
  title         TEXT,
  summary       TEXT NOT NULL,
  payload_json  TEXT NOT NULL,
  entities_json TEXT NOT NULL,
  importance    REAL NOT NULL DEFAULT 0.5
)
''';

const String createEventsOwnerTimeIndex = '''
CREATE INDEX IF NOT EXISTS idx_events_owner_time
  ON events(owner_user_id, timestamp DESC)
''';

const String createEventsOwnerTypeIndex = '''
CREATE INDEX IF NOT EXISTS idx_events_owner_type
  ON events(owner_user_id, type, timestamp DESC)
''';

const String createEventsOwnerSourceIndex = '''
CREATE INDEX IF NOT EXISTS idx_events_owner_source
  ON events(owner_user_id, source, timestamp DESC)
''';

const List<String> memoryRuntimeDdl = [
  createMemories,
  createMemoriesOwnerKindIndex,
  createMemoriesOwnerScopeIndex,
  createMemoriesSourceIndex,
  createMemoryEmbeddings,
  createMemoryEmbeddingsFingerprintIndex,
  createEvents,
  createEventsOwnerTimeIndex,
  createEventsOwnerTypeIndex,
  createEventsOwnerSourceIndex,
];
