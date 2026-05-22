-- 0021_sync_v2_rows.sql — sync v2 (row-state). See docs/sync-v2.md.
--
-- Clean break from the v1 OpLog. v2 syncs the *current state* of each row
-- (a per-row last-writer-wins register), not a stream of ops. The server
-- becomes a schema-agnostic versioned blob store: one table, one row per
-- business row, no history, no per-table materialisation.

-- ---------------------------------------------------------------------------
-- The entire server-side sync schema.
--
-- `seq` is the SQLite rowid with AUTOINCREMENT, so it is strictly increasing
-- and never reused. Rows are written with `INSERT OR REPLACE`, so an update
-- deletes the old row and re-inserts, minting a fresh higher `seq` — that is
-- how a changed row becomes visible to a `since`-cursor pull. AUTOINCREMENT
-- makes `seq` assignment atomic, so no counter row is needed.
--
-- `version` is the client LWW stamp (wall-clock millis, ~1.7e12 — outside the
-- i32 range worker-rs binds, so it travels as TEXT; LWW compares it
-- numerically in Rust, never in SQL). `payload` is opaque JSON the server
-- never inspects.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Drop the v1 OpLog + per-table materialised tables (docs/sync-v2.md §9).
-- v2 has no on-wire compatibility with v1; these tables are dead.
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS op_log;
DROP TABLE IF EXISTS sync_state;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS assets;
DROP TABLE IF EXISTS journal_entries;
DROP TABLE IF EXISTS postings;
DROP TABLE IF EXISTS prices;
DROP TABLE IF EXISTS recurring_transactions;
DROP TABLE IF EXISTS liabilities;
DROP TABLE IF EXISTS amortization_entries;
DROP TABLE IF EXISTS fx_rates;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS tag_links;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS settings;
DROP TABLE IF EXISTS goals;
DROP TABLE IF EXISTS synced_devices;
DROP TABLE IF EXISTS synced_users;
DROP TABLE IF EXISTS options_strategy_profile;
DROP TABLE IF EXISTS approved_underlyings;
DROP TABLE IF EXISTS options_trade_journal;
