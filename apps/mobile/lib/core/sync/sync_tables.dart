/// Raw-SQL DDL for the sync-engine bookkeeping tables.
///
/// Kept as plain `customStatement` strings rather than Drift `Table` classes
/// so adding them never requires regenerating `app_database.g.dart`. The
/// queries against them are trivial (`SELECT … ORDER BY`, `INSERT`,
/// `DELETE … WHERE op_id = ?`).
library;

/// Pending-change log (`docs/sync-v2.md` §7.1).
///
/// One entry per local mutation. The sync engine reads only the
/// `(table_name, row_id)` set out of it and pushes each row's *current*
/// state — `op_type` is kept for diagnostics, nothing else is interpreted.
/// Entries are deleted once the server acknowledges the row.
const String createOpOutbox = '''
CREATE TABLE IF NOT EXISTS op_outbox (
  op_id        TEXT PRIMARY KEY NOT NULL,
  hlc_text     TEXT NOT NULL,
  device_id    TEXT NOT NULL,
  table_name   TEXT NOT NULL,
  row_id       TEXT NOT NULL,
  op_type      TEXT NOT NULL CHECK (op_type IN ('insert','update','delete')),
  created_at   TEXT NOT NULL
)
''';

const String createOpOutboxIndex = '''
CREATE INDEX IF NOT EXISTS idx_op_outbox_created
  ON op_outbox(created_at, op_id)
''';

/// Single-row key/value store for SyncEngine state — pull cursor
/// (`sync.cursor`), local HLC (`sync.local_hlc`), applier version.
const String createSyncMeta = '''
CREATE TABLE IF NOT EXISTS sync_meta (
  key   TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
)
''';

const List<String> syncTableDdl = [
  createOpOutbox,
  createOpOutboxIndex,
  createSyncMeta,
];
