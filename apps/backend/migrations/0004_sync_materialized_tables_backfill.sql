-- 0004_sync_materialized_tables_backfill.sql
--
-- Some dev D1 databases applied an older copy of 0002 before all
-- materialised sync tables were added. D1 migrations are append-only, so
-- updating 0002 is not enough for those databases; this migration
-- idempotently creates the full materialised table set used by sync + AI.

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

CREATE TABLE IF NOT EXISTS journal_entries (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS postings (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS prices (
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

CREATE TABLE IF NOT EXISTS amortization_entries (
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

CREATE TABLE IF NOT EXISTS synced_devices (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);
