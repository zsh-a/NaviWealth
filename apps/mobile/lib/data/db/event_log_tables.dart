/// Raw-SQL DDL for the `domain_event_log` table (FIR-125).
///
/// `domain_event_log` is an append-only audit ledger for entity state
/// changes (creations, field-level mutations, soft deletes, restores).
/// Unlike `op_outbox`, rows here are NEVER deleted by the sync engine —
/// the outbox is a transport buffer, this is the truth source for
/// "what was the value before".
///
/// The table is local-only by design (issue FIR-125 strategy (a)): it
/// does not flow through the sync protocol. Each device thus has its
/// own view of "what *I* did". Cross-device merging of event histories
/// is left to a follow-up.
///
/// Kept as raw `customStatement` strings — same rationale as
/// `core/sync/sync_tables.dart` — so adding the table doesn't require
/// regenerating Drift's `.g.dart` and the migration step stays minimal.
library;

const String createDomainEventLog = '''
CREATE TABLE IF NOT EXISTS domain_event_log (
  id              TEXT PRIMARY KEY NOT NULL,
  entity_table    TEXT NOT NULL,
  entity_id       TEXT NOT NULL,
  event_kind      TEXT NOT NULL CHECK (
    event_kind IN ('created','field_changed','soft_deleted','restored')
  ),
  actor_user_id   TEXT NOT NULL,
  actor_device_id TEXT NOT NULL,
  recorded_at     TEXT NOT NULL,        -- ISO8601 UTC wall time
  hlc             TEXT NOT NULL,        -- canonical Hlc.toString() form
  before_json     TEXT,                 -- JSON object of changed fields' old values, NULL for 'created'
  after_json      TEXT,                 -- JSON object of changed fields' new values, NULL for 'soft_deleted'
  reason          TEXT                  -- optional user-provided rationale
)
''';

/// Hot path for the detail-page view: "give me every event for this
/// entity ordered by HLC ascending." HLC text sort already matches the
/// causal order (`Hlc` wire format §3.1).
const String createDomainEventLogEntityIndex = '''
CREATE INDEX IF NOT EXISTS idx_domain_event_log_entity
  ON domain_event_log(entity_table, entity_id, hlc)
''';

/// Diagnostic / sweep index: "show me everything this device wrote
/// after timestamp X." Used by the local maintenance entry point and by
/// debug tooling that wants to bound the scan.
const String createDomainEventLogRecordedIndex = '''
CREATE INDEX IF NOT EXISTS idx_domain_event_log_recorded
  ON domain_event_log(recorded_at)
''';

const List<String> domainEventLogDdl = [
  createDomainEventLog,
  createDomainEventLogEntityIndex,
  createDomainEventLogRecordedIndex,
];
