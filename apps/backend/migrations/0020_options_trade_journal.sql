-- 0020_options_trade_journal.sql
--
-- Options Income Planner P3 (`docs/options-income.md`). One materialised
-- table using the standard sync row shape; the server is opaque to the
-- payload (LWW via the generic sync materialiser).

CREATE TABLE IF NOT EXISTS options_trade_journal (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);
