-- 0005_add_missing_synced_tables.sql
--
-- Adds materialised tables for the four syncable tables that the client
-- has been emitting but the backend never supported: categories, settings,
-- tag_links, and the user-profile table (mapped to `synced_users` to
-- avoid colliding with the auth `users` table from 0001, mirroring the
-- `devices` → `synced_devices` precedent).
--
-- Schema is the standard materialised-row shape used by every other
-- synced table; the wire→sql mapping lives in src/sync/materialise.rs.

CREATE TABLE IF NOT EXISTS categories (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);

-- `settings` is per-user singleton on the client (PK = userId), so the
-- materialised `id` column ends up holding the user id verbatim. That's
-- harmless given the (user_id, id) composite PK is already user-scoped.
CREATE TABLE IF NOT EXISTS settings (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS tag_links (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS synced_users (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);
