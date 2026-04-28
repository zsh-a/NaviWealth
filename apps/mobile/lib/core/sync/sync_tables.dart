/// Raw-SQL DDL for sync-engine tables (FIR-34).
///
/// We deliberately keep these as plain `customStatement` strings rather than
/// Drift `Table` classes so adding the tables doesn't require regenerating
/// `app_database.g.dart`. The columns and queries used against them are all
/// trivial (`SELECT … LIMIT`, `INSERT`, `DELETE … WHERE op_id = ?`), so the
/// type-safety win from Drift codegen is small.
library;

/// Outbox of locally-generated ops not yet acknowledged by the server.
///
/// FIFO-ordered by `(hlc_text, created_at)`. Per `docs/sync-protocol.md`
/// §7.5 the outbox is append-only between syncs; on `accepted` we delete the
/// row, on a non-recoverable per-op rejection we record into `sync_errors`
/// then delete.
const String createOpOutbox = '''
CREATE TABLE IF NOT EXISTS op_outbox (
  op_id        TEXT PRIMARY KEY NOT NULL,
  hlc_text     TEXT NOT NULL,
  device_id    TEXT NOT NULL,
  table_name   TEXT NOT NULL,
  row_id       TEXT NOT NULL,
  op_type      TEXT NOT NULL CHECK (op_type IN ('insert','update','delete')),
  fields_diff  TEXT,                -- JSON, NULL for delete
  created_at   TEXT NOT NULL,       -- ISO8601 wall time, debugging aid
  attempts     INTEGER NOT NULL DEFAULT 0,
  last_error   TEXT
)
''';

const String createOpOutboxIndex = '''
CREATE INDEX IF NOT EXISTS idx_op_outbox_hlc
  ON op_outbox(hlc_text, created_at)
''';

/// Per-op terminal-failure log for diagnostics. We never retry these.
const String createSyncErrors = '''
CREATE TABLE IF NOT EXISTS sync_errors (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  op_id        TEXT,
  code         TEXT NOT NULL,
  message      TEXT,
  payload      TEXT,
  recorded_at  TEXT NOT NULL
)
''';

/// Single-row key/value store for the SyncEngine's state — local HLC
/// (`sync.hlc`), pull cursor (`sync.cursor`), and any other knobs that
/// survive a process restart but don't deserve their own table.
const String createSyncMeta = '''
CREATE TABLE IF NOT EXISTS sync_meta (
  key   TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
)
''';

const List<String> syncTableDdl = [
  createOpOutbox,
  createOpOutboxIndex,
  createSyncErrors,
  createSyncMeta,
];
