/// Raw-SQL DDL for local-only tables that never ride the sync protocol.
///
/// - `agent_runs` — product-level lifecycle state for scheduled LifeOS
///   agents. This is local device state; agent output can be regenerated and
///   should not sync.
/// - `agent_artifacts` — user-visible briefing/review/alert records produced
///   by agents. Local-only, with evidence/actions encoded as compact JSON.
///   Dismiss/snooze state hides the current result without deleting history.
/// - `agent_preferences` — per-user local agent toggles and notification
///   preferences. These are product preferences, not synced source data.
/// - `agent_runtime_checkpoints` — resumable Rust-owned runtime snapshots and
///   host-effect journals. These are high-frequency local execution records,
///   never product sync objects.
/// - `options_opportunity_cache` — scoring engine output. Each device
///   computes its own opportunities from its own chain pull
///   (`docs/domains/options-income.md` §6.2).
/// - `recurring_pattern_observations` — device analytical read-model history
///   for subscription price-change comparison. Derived from local expenses,
///   re-materializable, never synced.
/// - `memories` + `memory_embeddings` + `events` — Memory Runtime
///   (`docs/architecture/lifeos-shell.md` §6, D-1.7b). Typed records with
///   lifecycle, vectors in a side table so embedder swap doesn't have
///   to rewrite memory rows.
///
/// See also the parallel pattern in `event_log_tables.dart`.
library;

const String createDataMaintenanceRuns = '''
CREATE TABLE IF NOT EXISTS data_maintenance_runs (
  id             TEXT PRIMARY KEY,
  owner_user_id  TEXT NOT NULL,
  action         TEXT NOT NULL,
  domain         TEXT,
  status         TEXT NOT NULL,
  started_at     INTEGER NOT NULL,
  finished_at    INTEGER,
  rows_affected  INTEGER NOT NULL DEFAULT 0,
  detail_json    TEXT NOT NULL DEFAULT '{}',
  error          TEXT
)
''';

const String createDataMaintenanceRunsOwnerIndex = '''
CREATE INDEX IF NOT EXISTS idx_data_maintenance_runs_owner_started
  ON data_maintenance_runs(owner_user_id, started_at DESC)
''';

const List<String> dataMaintenanceRunDdl = <String>[
  createDataMaintenanceRuns,
  createDataMaintenanceRunsOwnerIndex,
];

// ----------------------------------------------------------------------
// Agent framework state
// ----------------------------------------------------------------------

const String createAgentRuns = '''
CREATE TABLE IF NOT EXISTS agent_runs (
  id            TEXT PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  agent_id      TEXT NOT NULL,
  agent_name    TEXT NOT NULL,
  status        TEXT NOT NULL,     -- running|ready|no_finding|failed
  trigger       TEXT NOT NULL,     -- manual|schedule|background_due|catch_up
  started_at    INTEGER NOT NULL,  -- millis since epoch (UTC)
  finished_at   INTEGER,
  summary       TEXT,
  error         TEXT,
  memory_id     TEXT,
  artifact_id   TEXT,
  trace_id      TEXT
)
''';

const String createAgentRunsAgentStartedIndex = '''
CREATE INDEX IF NOT EXISTS idx_agent_runs_agent_started
  ON agent_runs(owner_user_id, agent_id, started_at DESC)
''';

const String createAgentRunsStatusIndex = '''
CREATE INDEX IF NOT EXISTS idx_agent_runs_owner_status
  ON agent_runs(owner_user_id, status, started_at DESC)
''';

const List<String> agentRunDdl = [
  createAgentRuns,
  createAgentRunsAgentStartedIndex,
  createAgentRunsStatusIndex,
];

const String createAgentRuntimeCheckpoints = '''
CREATE TABLE IF NOT EXISTS agent_runtime_checkpoints (
  owner_user_id       TEXT NOT NULL,
  run_id              TEXT NOT NULL,
  agent_id            TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  snapshot_version    INTEGER NOT NULL,
  revision            INTEGER NOT NULL DEFAULT 0,
  status              TEXT NOT NULL,
  snapshot_json       TEXT NOT NULL,
  resume_context_json TEXT,
  effect_kind         TEXT,
  effect_id           TEXT,
  effect_payload_json TEXT,
  created_at          INTEGER NOT NULL,
  updated_at          INTEGER NOT NULL,
  expires_at          INTEGER,
  PRIMARY KEY (owner_user_id, run_id),
  CHECK (revision >= 0),
  CHECK (status IN (
    'awaiting_effect',
    'dispatching',
    'effect_recorded',
    'terminal'
  )),
  CHECK (effect_kind IS NULL OR effect_kind IN ('tool', 'subagent'))
)
''';

const String createAgentRuntimeCheckpointsPendingIndex = '''
CREATE INDEX IF NOT EXISTS idx_agent_runtime_checkpoints_pending
  ON agent_runtime_checkpoints(
    owner_user_id,
    agent_id,
    request_fingerprint,
    status,
    updated_at DESC
  )
''';

const String createAgentRuntimeCheckpointsUpdatedIndex = '''
CREATE INDEX IF NOT EXISTS idx_agent_runtime_checkpoints_updated
  ON agent_runtime_checkpoints(owner_user_id, updated_at DESC)
''';

const List<String> agentRuntimeCheckpointDdl = [
  createAgentRuntimeCheckpoints,
  createAgentRuntimeCheckpointsPendingIndex,
  createAgentRuntimeCheckpointsUpdatedIndex,
];

const String createAgentArtifacts = '''
CREATE TABLE IF NOT EXISTS agent_artifacts (
  id             TEXT PRIMARY KEY,
  owner_user_id  TEXT NOT NULL,
  agent_id       TEXT NOT NULL,
  domain         TEXT NOT NULL,
  kind           TEXT NOT NULL,     -- briefing|review|alert|reminder
  severity       TEXT NOT NULL,     -- info|attention|warning
  title          TEXT NOT NULL,
  summary        TEXT NOT NULL,
  presentation_json TEXT NOT NULL,
  insights_json  TEXT NOT NULL,
  evidence_json  TEXT NOT NULL,
  actions_json   TEXT NOT NULL,
  memory_id      TEXT,
  trace_id       TEXT,
  created_at     INTEGER NOT NULL,  -- millis since epoch (UTC)
  expires_at     INTEGER,
  dismissed_at   INTEGER,
  snoozed_until  INTEGER
)
''';

const String createAgentArtifactsAgentCreatedIndex = '''
CREATE INDEX IF NOT EXISTS idx_agent_artifacts_agent_created
  ON agent_artifacts(owner_user_id, agent_id, created_at DESC)
''';

const String createAgentArtifactsDomainCreatedIndex = '''
CREATE INDEX IF NOT EXISTS idx_agent_artifacts_domain_created
  ON agent_artifacts(owner_user_id, domain, created_at DESC)
''';

const List<String> agentArtifactDdl = [
  createAgentArtifacts,
  createAgentArtifactsAgentCreatedIndex,
  createAgentArtifactsDomainCreatedIndex,
];

const String createAgentPreferences = '''
CREATE TABLE IF NOT EXISTS agent_preferences (
  owner_user_id         TEXT NOT NULL,
  agent_id              TEXT NOT NULL,
  enabled               INTEGER NOT NULL DEFAULT 1,
  notifications_enabled INTEGER NOT NULL DEFAULT 1,
  updated_at            INTEGER NOT NULL,
  PRIMARY KEY (owner_user_id, agent_id)
)
''';

const String createAgentPreferencesOwnerIndex = '''
CREATE INDEX IF NOT EXISTS idx_agent_preferences_owner
  ON agent_preferences(owner_user_id, agent_id)
''';

const List<String> agentPreferenceDdl = [
  createAgentPreferences,
  createAgentPreferencesOwnerIndex,
];

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
// Device analytical recurring-pattern history
// ----------------------------------------------------------------------

/// Append-mostly local observation log for detected recurring patterns.
///
/// The detector can only see stable runs in the current expense window. Keeping
/// historical observations lets `subscription_changes` compare "old stable
/// price" vs "new stable price" across app sessions without promoting derived
/// analytical signals into sync state.
const String createRecurringPatternObservations = '''
CREATE TABLE IF NOT EXISTS recurring_pattern_observations (
  id                  TEXT PRIMARY KEY,
  owner_user_id       TEXT NOT NULL,
  merchant_key        TEXT NOT NULL,
  cadence             TEXT NOT NULL,
  currency            TEXT NOT NULL,
  median_amount_minor INTEGER NOT NULL,
  occurrences         INTEGER NOT NULL,
  occurrence_ids_json TEXT NOT NULL,
  last_seen_at        INTEGER NOT NULL,      -- millis since epoch (UTC)
  observed_at         INTEGER NOT NULL,      -- millis since epoch (UTC)
  payload_json        TEXT NOT NULL
)
''';

const String createRecurringPatternObservationsSeriesIndex = '''
CREATE INDEX IF NOT EXISTS idx_recurring_pattern_obs_series
  ON recurring_pattern_observations(
    owner_user_id,
    merchant_key,
    currency,
    cadence,
    last_seen_at
  )
''';

const String createRecurringPatternObservationsObservedIndex = '''
CREATE INDEX IF NOT EXISTS idx_recurring_pattern_obs_owner_observed
  ON recurring_pattern_observations(owner_user_id, observed_at DESC)
''';

const List<String> recurringPatternObservationDdl = [
  createRecurringPatternObservations,
  createRecurringPatternObservationsSeriesIndex,
  createRecurringPatternObservationsObservedIndex,
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
/// as little-endian Float32 BLOB (32-d stub = 128 bytes; 768-d
/// EmbeddingGemma = 3 KB).
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

// ----------------------------------------------------------------------
// KnowledgeOS inbox triage side-table
// (`docs/domains/knowledgeos-domain.md` §7 + §5 异步 triage flow)
// ----------------------------------------------------------------------
//
// One row per Note that the InboxTriageAgent has looked at. Holds the
// proposal envelopes the agent emitted (classification / tags / link),
// each with its own resolution state so the user can accept one and
// dismiss another. Local-only — proposals are device-derived signals;
// they re-materialise from the note itself on any device.
const String createKnowledgeInboxTriage = '''
CREATE TABLE IF NOT EXISTS knowledge_inbox_triage (
  note_id         TEXT PRIMARY KEY,
  owner_user_id   TEXT NOT NULL,
  last_triaged_at INTEGER NOT NULL,        -- millis since epoch (UTC)
  proposals_json  TEXT NOT NULL            -- JSON array of envelopes (+status)
)
''';

const String createKnowledgeInboxTriageOwnerTriagedIndex = '''
CREATE INDEX IF NOT EXISTS idx_knowledge_inbox_triage_owner_triaged
  ON knowledge_inbox_triage(owner_user_id, last_triaged_at DESC)
''';

const List<String> knowledgeInboxTriageDdl = [
  createKnowledgeInboxTriage,
  createKnowledgeInboxTriageOwnerTriagedIndex,
];
