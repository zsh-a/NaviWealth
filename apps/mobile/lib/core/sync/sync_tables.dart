/// Raw-SQL DDL for the sync-engine bookkeeping tables.
///
/// Kept as plain `customStatement` strings rather than Drift `Table` classes
/// so adding them never requires regenerating `app_database.g.dart`.
library;

/// Dirty-pointer log (`docs/sync-v2.md` §7.1).
///
/// One entry per local mutation — just enough to point the sync engine at a
/// dirty row. The engine pushes that row's current state and deletes the
/// entry once the server acknowledges it.
const String createOpOutbox = '''
CREATE TABLE IF NOT EXISTS op_outbox (
  op_id        TEXT PRIMARY KEY NOT NULL,
  table_name   TEXT NOT NULL,
  row_id       TEXT NOT NULL,
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
