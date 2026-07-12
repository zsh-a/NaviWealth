-- Sync v3: per-domain reset generations.
--
-- A permanent domain reset increments the generation and physically removes
-- the old rows. Clients include their generation on every row; stale devices
-- cannot reinsert pre-reset data after coming back online.

ALTER TABLE sync_rows ADD COLUMN generation INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS sync_domain_generations (
  user_id         TEXT    NOT NULL,
  domain          TEXT    NOT NULL,
  generation      INTEGER NOT NULL DEFAULT 0,
  reset_at        TEXT    NOT NULL,
  reset_device_id TEXT    NOT NULL,
  PRIMARY KEY (user_id, domain),
  CHECK (generation >= 0)
);

CREATE INDEX IF NOT EXISTS sync_domain_generations_user
  ON sync_domain_generations(user_id, domain);
