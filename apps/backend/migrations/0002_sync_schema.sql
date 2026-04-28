-- 0002_sync_schema.sql — sync schema (FIR-36).
--
-- Mirrors the client tables that participate in sync per docs/sync-protocol.md
-- (accounts, assets, transactions, liabilities, fx_rates, tags, goals,
-- devices) plus the cross-cutting `op_log` + `sync_state`. The `users` and
-- the auth-session `devices` tables are owned by FIR-29 in
-- `0001_users_devices.sql`.
--
-- The protocol's `devices` syncable table maps to the SQL table
-- `synced_devices` here, since the SQL name `devices` is already taken by the
-- auth-session registry. Wire-side, ops still travel as `table = "devices"`;
-- the materialiser translates wire name → SQL name.
--
-- Materialised business rows store the row payload as JSON. Sync semantics
-- only need the metadata triple (hlc_text, updated_by_device, deleted_at)
-- plus `(user_id, row_id)` for per-row LWW; columns inside `payload` are
-- opaque to the server. The op_log preserves the original `fields_diff`
-- regardless, so a future schema migration can re-materialise stronger types
-- (see docs/sync-protocol.md §K-4).

-- ---------------------------------------------------------------------------
-- Server-side HLC clock state, one row per user.
-- ---------------------------------------------------------------------------
-- `server_phys_ms` is Unix milliseconds (~1.7e12) — well outside the i32
-- range that worker-rs D1Type::Integer accepts, so it travels the wire as
-- TEXT (canonical decimal). SQLite happily stores it that way; sync_state
-- is never queried with arithmetic comparisons.
CREATE TABLE IF NOT EXISTS sync_state (
  user_id        TEXT PRIMARY KEY,
  server_phys_ms TEXT NOT NULL,
  server_logical INTEGER NOT NULL,
  updated_at     TEXT NOT NULL
);

-- ---------------------------------------------------------------------------
-- OpLog — append-only ledger. Pull/push both read and write here.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS op_log (
  op_id        TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL,
  table_name   TEXT NOT NULL,
  row_id       TEXT NOT NULL,
  op_type      TEXT NOT NULL CHECK (op_type IN ('insert','update','delete')),
  fields_diff  TEXT,
  hlc_text     TEXT NOT NULL,
  client_hlc   TEXT NOT NULL,
  device_id    TEXT NOT NULL,
  created_at   TEXT NOT NULL
);

-- Range-scan index for `GET /sync/pull` (since-cursor traversal).
CREATE INDEX IF NOT EXISTS op_log_pull
  ON op_log (user_id, hlc_text);

-- Per-row index for materialisation LWW lookup during push.
CREATE INDEX IF NOT EXISTS op_log_row
  ON op_log (user_id, table_name, row_id, hlc_text);

-- ---------------------------------------------------------------------------
-- Materialised business tables. JSON payload + sync metadata triple.
-- Composite PK is (user_id, id) so the same row_id under different users
-- never collides (futureproofing — v1 is single-user).
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounts (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS assets (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS transactions (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS liabilities (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS fx_rates (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS tags (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS goals (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);

-- Wire `table = "devices"` materialises into `synced_devices` (see header).
CREATE TABLE IF NOT EXISTS synced_devices (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);
