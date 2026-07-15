-- 0002_sync_schema.sql — base row-state storage. See docs/sync/sync-v3.md.
--
-- v2 syncs the current state of each row, not an OpLog stream. The server is
-- schema-agnostic: one table stores every syncable business row as an opaque
-- JSON payload with a client-authored LWW version token.

CREATE TABLE IF NOT EXISTS sync_rows (
  seq         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     TEXT    NOT NULL,
  table_name  TEXT    NOT NULL,
  row_id      TEXT    NOT NULL,
  payload     TEXT    NOT NULL,
  version     TEXT    NOT NULL,
  device_id   TEXT    NOT NULL,
  deleted     INTEGER NOT NULL DEFAULT 0,
  updated_at  TEXT    NOT NULL,
  UNIQUE (user_id, table_name, row_id)
);

-- Range-scan index for the `seq > since` pull cursor.
CREATE INDEX IF NOT EXISTS sync_rows_pull ON sync_rows (user_id, seq);
