/// Raw-SQL DDL for local-only tables that never ride the sync protocol.
///
/// - `agent_runs` — product-level lifecycle state for scheduled LifeOS
///   agents. This is local device state; agent output can be regenerated and
///   should not sync.
/// - `agent_artifacts` — user-visible briefing/review/alert records produced
///   by agents. Local-only, with evidence/actions encoded as compact JSON.
///   Dismiss/snooze state hides the current result without deleting history.
/// - `agent_preferences` — per-user local Agent enablement. Proactive
///   notification policy is global and lives in the attention layer.
/// - `agent_runtime_checkpoints` — resumable Rust-owned runtime snapshots and
///   host-effect journals. These are high-frequency local execution records,
///   never product sync objects.
/// - `agent_runtime_chat_snapshots` — versioned chat-turn state and tool
///   dispatch journals used to recover after Android process reclamation.
/// - `conversation_checkpoints` — structured, source-fingerprinted summaries
///   of the chat prefix omitted from the current model context. These are
///   local caches, not durable user memory and never sync.
/// - `memory_candidates` — AI-proposed long-term memory changes staged for
///   explicit user review. Only an applied candidate may materialize a row in
///   `memories`.
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
/// - `developer_issues` — explicit, local-only dogfood reports. Exports omit
///   account identity and never create remote issues without another user
///   action.
///
/// See also the parallel pattern in `event_log_tables.dart`.
library;

const String createPersonalProfileFacts = '''
CREATE TABLE IF NOT EXISTS personal_profile_facts (
  id                  TEXT PRIMARY KEY,
  owner_user_id       TEXT NOT NULL,
  kind                TEXT NOT NULL CHECK (
    kind IN ('goal', 'preference', 'constraint', 'rule')
  ),
  fact_key            TEXT NOT NULL,
  value_json          TEXT NOT NULL,
  summary             TEXT NOT NULL,
  domain_scope        TEXT,
  authority           TEXT NOT NULL CHECK (authority = 'user_confirmed'),
  provenance_json     TEXT NOT NULL,
  confidence          REAL NOT NULL,
  confirmed_at        INTEGER NOT NULL,
  valid_from          INTEGER NOT NULL,
  valid_until         INTEGER,
  supersedes_fact_id  TEXT,
  created_at          INTEGER NOT NULL,
  updated_at          INTEGER NOT NULL
)
''';

const String createPersonalProfileFactsActiveIndex = '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_personal_profile_facts_active_key
ON personal_profile_facts(
  owner_user_id,
  COALESCE(domain_scope, ''),
  kind,
  fact_key
)
WHERE valid_until IS NULL
''';

const String createPersonalProfileFactsOwnerIndex = '''
CREATE INDEX IF NOT EXISTS idx_personal_profile_facts_owner_updated
ON personal_profile_facts(owner_user_id, updated_at DESC)
''';

const List<String> personalProfileDdl = <String>[
  createPersonalProfileFacts,
  createPersonalProfileFactsActiveIndex,
  createPersonalProfileFactsOwnerIndex,
];

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
// Developer-mode dogfood issue capture
// ----------------------------------------------------------------------

const String createDeveloperIssues = '''
CREATE TABLE IF NOT EXISTS developer_issues (
  id                TEXT PRIMARY KEY,
  owner_user_id     TEXT NOT NULL,
  description       TEXT NOT NULL,
  route             TEXT NOT NULL,
  domain            TEXT,
  app_version       TEXT NOT NULL,
  build_number      TEXT NOT NULL,
  commit_sha        TEXT NOT NULL,
  trace_id          TEXT,
  tool_errors_json  TEXT NOT NULL,
  screenshot_path   TEXT,
  created_at        INTEGER NOT NULL,
  exported_at       INTEGER
)
''';

const String createDeveloperIssuesOwnerIndex = '''
CREATE INDEX IF NOT EXISTS idx_developer_issues_owner_created
  ON developer_issues(owner_user_id, created_at DESC)
''';

const List<String> developerIssueDdl = <String>[
  createDeveloperIssues,
  createDeveloperIssuesOwnerIndex,
];

// ----------------------------------------------------------------------
// Conversation context checkpoints
// ----------------------------------------------------------------------

const String createConversationCheckpoints = '''
CREATE TABLE IF NOT EXISTS conversation_checkpoints (
  session_id                    TEXT PRIMARY KEY,
  owner_user_id                 TEXT NOT NULL,
  summary_through_message_id    TEXT NOT NULL,
  summary_through_created_at    INTEGER NOT NULL,
  source_fingerprint            TEXT NOT NULL,
  checkpoint_version            INTEGER NOT NULL,
  source_message_count          INTEGER NOT NULL,
  payload_json                  TEXT NOT NULL,
  created_at                    INTEGER NOT NULL,
  updated_at                    INTEGER NOT NULL,
  FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
)
''';

const String createConversationCheckpointsOwnerIndex = '''
CREATE INDEX IF NOT EXISTS idx_conversation_checkpoints_owner_updated
  ON conversation_checkpoints(owner_user_id, updated_at DESC)
''';

const List<String> conversationCheckpointDdl = <String>[
  createConversationCheckpoints,
  createConversationCheckpointsOwnerIndex,
];

const String createMemoryCandidates = '''
CREATE TABLE IF NOT EXISTS memory_candidates (
  id                 TEXT PRIMARY KEY,
  proposal_id        TEXT NOT NULL UNIQUE,
  owner_user_id      TEXT NOT NULL,
  target_type        TEXT NOT NULL CHECK (
    target_type IN ('memory', 'profile_fact')
  ),
  operation          TEXT NOT NULL CHECK (
    operation IN ('create', 'supersede', 'forget')
  ),
  status             TEXT NOT NULL CHECK (
    status IN ('pending', 'applying', 'applied', 'rejected', 'undone', 'failed')
  ),
  target_record_id   TEXT,
  applied_record_id  TEXT,
  payload_json       TEXT NOT NULL,
  created_at         INTEGER NOT NULL,
  updated_at         INTEGER NOT NULL,
  decided_at         INTEGER,
  error_message      TEXT
)
''';

const String createMemoryCandidatesOwnerIndex = '''
CREATE INDEX IF NOT EXISTS idx_memory_candidates_owner_status
  ON memory_candidates(owner_user_id, status, updated_at DESC)
''';

const List<String> memoryCandidateDdl = <String>[
  createMemoryCandidates,
  createMemoryCandidatesOwnerIndex,
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
  trigger       TEXT NOT NULL,     -- persisted execution provenance
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

const String createAgentRuntimeChatSnapshots = '''
CREATE TABLE IF NOT EXISTS agent_runtime_chat_snapshots (
  owner_user_id    TEXT NOT NULL,
  turn_id          TEXT NOT NULL,
  snapshot_version INTEGER NOT NULL,
  revision         INTEGER NOT NULL DEFAULT 0,
  status           TEXT NOT NULL,
  snapshot_json    TEXT NOT NULL,
  created_at       INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL,
  expires_at       INTEGER,
  PRIMARY KEY (owner_user_id, turn_id),
  CHECK (revision >= 0),
  CHECK (status IN (
    'ready_for_model',
    'requires_tool_results',
    'requires_interaction',
    'completed',
    'cancelled',
    'failed'
  ))
)
''';

const String createAgentRuntimeChatSnapshotsPendingIndex = '''
CREATE INDEX IF NOT EXISTS idx_agent_runtime_chat_snapshots_pending
  ON agent_runtime_chat_snapshots(owner_user_id, status, updated_at DESC)
''';

const List<String> agentRuntimeChatSnapshotDdl = <String>[
  createAgentRuntimeChatSnapshots,
  createAgentRuntimeChatSnapshotsPendingIndex,
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

const String createAgentFindings = '''
CREATE TABLE IF NOT EXISTS agent_findings (
  owner_user_id       TEXT NOT NULL,
  id                  TEXT NOT NULL,
  agent_id            TEXT NOT NULL,
  domain              TEXT NOT NULL,
  kind                TEXT NOT NULL,
  status              TEXT NOT NULL CHECK (
    status IN ('open', 'resolved', 'ignored', 'snoozed')
  ),
  severity            TEXT NOT NULL,
  confidence          REAL NOT NULL,
  evidence_fingerprint TEXT NOT NULL,
  payload_json        TEXT NOT NULL,
  first_seen_at       INTEGER NOT NULL,
  last_seen_at        INTEGER NOT NULL,
  resolved_at         INTEGER,
  snoozed_until       INTEGER,
  PRIMARY KEY (owner_user_id, id)
)
''';

const String createAgentFindingsAgentStatusIndex = '''
CREATE INDEX IF NOT EXISTS idx_agent_findings_agent_status
  ON agent_findings(owner_user_id, agent_id, status, last_seen_at DESC)
''';

const List<String> agentFindingDdl = <String>[
  createAgentFindings,
  createAgentFindingsAgentStatusIndex,
];

const String createAgentFeedback = '''
CREATE TABLE IF NOT EXISTS agent_feedback (
  id                       TEXT PRIMARY KEY,
  owner_user_id            TEXT NOT NULL,
  artifact_id              TEXT NOT NULL,
  agent_id                 TEXT NOT NULL,
  domain                   TEXT NOT NULL,
  kind                     TEXT NOT NULL CHECK (
    kind IN ('accepted', 'dismissed', 'snoozed', 'completed', 'undone')
  ),
  action_kind              TEXT,
  life_context_fingerprint TEXT,
  finding_fingerprint      TEXT,
  attention_decision_id    TEXT,
  payload_json             TEXT NOT NULL,
  created_at               INTEGER NOT NULL
)
''';

const String createAgentFeedbackArtifactIndex = '''
CREATE INDEX IF NOT EXISTS idx_agent_feedback_artifact_created
  ON agent_feedback(owner_user_id, artifact_id, created_at DESC)
''';

const String createAgentFeedbackAgentIndex = '''
CREATE INDEX IF NOT EXISTS idx_agent_feedback_agent_created
  ON agent_feedback(owner_user_id, agent_id, created_at DESC)
''';

const List<String> agentFeedbackDdl = <String>[
  createAgentFeedback,
  createAgentFeedbackArtifactIndex,
  createAgentFeedbackAgentIndex,
];

const String createAttentionDecisions = '''
CREATE TABLE IF NOT EXISTS attention_decisions (
  id                  TEXT PRIMARY KEY,
  owner_user_id       TEXT NOT NULL,
  candidate_id        TEXT NOT NULL,
  agent_id            TEXT NOT NULL,
  finding_fingerprint TEXT NOT NULL,
  level               TEXT NOT NULL CHECK (
    level IN ('silent', 'surface', 'interrupt')
  ),
  candidate_json      TEXT NOT NULL,
  reasons_json        TEXT NOT NULL,
  created_at          INTEGER NOT NULL
)
''';

const String createAttentionDecisionsOwnerIndex = '''
CREATE INDEX IF NOT EXISTS idx_attention_decisions_owner_created
  ON attention_decisions(owner_user_id, created_at DESC)
''';

const String createAttentionDecisionsInterruptIndex = '''
CREATE INDEX IF NOT EXISTS idx_attention_decisions_interrupt_budget
  ON attention_decisions(owner_user_id, level, created_at DESC)
''';

const List<String> attentionDecisionDdl = <String>[
  createAttentionDecisions,
  createAttentionDecisionsOwnerIndex,
  createAttentionDecisionsInterruptIndex,
];

const String createAgentPreferences = '''
CREATE TABLE IF NOT EXISTS agent_preferences (
  owner_user_id         TEXT NOT NULL,
  agent_id              TEXT NOT NULL,
  enabled               INTEGER NOT NULL DEFAULT 1,
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
  strategy           TEXT NOT NULL,        -- cash_secured_put | covered_call | leaps_call
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
  leaps_metrics_json TEXT,                 -- LeapsOpportunityMetrics JSON,
                                           -- set only for leaps_call rows
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
  role             TEXT NOT NULL,            -- decision|episode|pattern|guidance|legacy
  authority        TEXT NOT NULL,            -- user_confirmed|source_fact|deterministic_derived|model_derived|legacy_unknown
  provenance_json  TEXT NOT NULL,
  supersedes_id    TEXT,
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

const String createMemoriesSupersedesIndex = '''
CREATE INDEX IF NOT EXISTS idx_memories_supersedes
  ON memories(supersedes_id)
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
  id                 TEXT PRIMARY KEY,
  domain             TEXT,
  kind               TEXT NOT NULL,
  occurred_at        INTEGER NOT NULL,       -- millis since epoch
  observed_at        INTEGER NOT NULL,
  source_family      TEXT NOT NULL,
  source_row_id      TEXT NOT NULL,
  source_fingerprint TEXT NOT NULL,
  owner_user_id      TEXT NOT NULL,
  title              TEXT,
  summary            TEXT NOT NULL,
  facts_json         TEXT NOT NULL,
  entities_json      TEXT NOT NULL,
  importance         REAL NOT NULL DEFAULT 0.5,
  confidence         REAL NOT NULL DEFAULT 1.0
)
''';

const String createEventsOwnerTimeIndex = '''
CREATE INDEX IF NOT EXISTS idx_events_owner_time
  ON events(owner_user_id, occurred_at DESC)
''';

const String createEventsOwnerTypeIndex = '''
CREATE INDEX IF NOT EXISTS idx_events_owner_type
  ON events(owner_user_id, kind, occurred_at DESC)
''';

const String createEventsOwnerSourceIndex = '''
CREATE INDEX IF NOT EXISTS idx_events_owner_source
  ON events(owner_user_id, source_family, occurred_at DESC)
''';

const String createEventsOwnerDomainOccurredIndex = '''
CREATE INDEX IF NOT EXISTS idx_events_owner_domain_occurred
  ON events(owner_user_id, domain, occurred_at DESC)
''';

const List<String> memoryStorageDdl = [
  createMemories,
  createMemoriesOwnerKindIndex,
  createMemoriesOwnerScopeIndex,
  createMemoriesSourceIndex,
  createMemoriesSupersedesIndex,
  createMemoryEmbeddings,
  createMemoryEmbeddingsFingerprintIndex,
];

const List<String> eventRuntimeDdl = [
  createEvents,
  createEventsOwnerTimeIndex,
  createEventsOwnerTypeIndex,
  createEventsOwnerSourceIndex,
  createEventsOwnerDomainOccurredIndex,
];

const List<String> memoryRuntimeDdl = [...memoryStorageDdl, ...eventRuntimeDdl];

// ----------------------------------------------------------------------
// Money Runway forecast evaluation (derived, local-only)
// ----------------------------------------------------------------------
const List<String> forecastEvaluationDdl = [
  '''
CREATE TABLE IF NOT EXISTS runway_forecast_snapshots (
  id TEXT PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  as_of_day TEXT NOT NULL,
  target_at INTEGER NOT NULL,
  horizon_days INTEGER NOT NULL,
  currency TEXT NOT NULL,
  starting_balance TEXT NOT NULL,
  predicted_balance TEXT NOT NULL,
  actual_balance TEXT,
  absolute_error TEXT,
  data_completeness REAL NOT NULL,
  evidence_json TEXT NOT NULL,
  evaluated_at INTEGER,
  UNIQUE(owner_user_id, as_of_day, horizon_days)
)
''',
  '''
CREATE INDEX IF NOT EXISTS idx_runway_forecast_due
ON runway_forecast_snapshots(owner_user_id, evaluated_at, target_at)
''',
  '''
CREATE TABLE IF NOT EXISTS dividend_forecast_snapshots (
  id TEXT PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  as_of_day TEXT NOT NULL,
  window_start INTEGER NOT NULL,
  target_at INTEGER NOT NULL,
  horizon_days INTEGER NOT NULL,
  currency TEXT NOT NULL,
  predicted_net TEXT NOT NULL,
  actual_net TEXT,
  absolute_error TEXT,
  strategy TEXT NOT NULL,
  confidence TEXT NOT NULL,
  evidence_json TEXT NOT NULL,
  evaluated_at INTEGER,
  UNIQUE(owner_user_id, as_of_day, horizon_days)
)
''',
  '''
CREATE INDEX IF NOT EXISTS idx_dividend_forecast_due
ON dividend_forecast_snapshots(owner_user_id, evaluated_at, target_at)
''',
];
