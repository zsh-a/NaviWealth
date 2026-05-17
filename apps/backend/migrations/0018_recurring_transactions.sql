-- 0018_recurring_transactions.sql
--
-- Adds the only persisted planning entity for the cashflow/dividend epic.
-- The table uses the standard sync materialised-row shape: the server keeps
-- an opaque JSON payload plus HLC metadata and applies row-level LWW through
-- the generic sync materialiser.

CREATE TABLE IF NOT EXISTS recurring_transactions (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);
