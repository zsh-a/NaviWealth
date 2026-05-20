-- 0019_options_income.sql
--
-- Options Income Planner P0 (`docs/options-income.md`). Two new
-- materialised tables using the standard sync row shape (opaque JSON
-- payload + HLC metadata + LWW via the generic sync materialiser):
--
--   * options_strategy_profile  — per-user singleton; the server still
--     stores it under the standard `(user_id, id)` PK with `id` fixed to
--     the user_id by the client. This keeps the server contract uniform
--     across synced tables.
--   * approved_underlyings      — collection keyed by `<market>:<symbol>`.

CREATE TABLE IF NOT EXISTS options_strategy_profile (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS approved_underlyings (
  user_id            TEXT NOT NULL,
  id                 TEXT NOT NULL,
  payload            TEXT NOT NULL,
  hlc_text           TEXT NOT NULL,
  updated_by_device  TEXT NOT NULL,
  deleted_at         TEXT,
  PRIMARY KEY (user_id, id)
);
