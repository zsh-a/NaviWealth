-- FIR-29: single-user auth schema.
-- Account rows are inserted directly by the operator (wrangler / D1 console);
-- there is no public registration endpoint.

CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY NOT NULL,
  email         TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- One row per active session. id == JWT `did` claim, doubles as HLC node_id.
-- Logout (or remote revoke) sets revoked_at; refresh rotates jti.
CREATE TABLE IF NOT EXISTS devices (
  id           TEXT PRIMARY KEY NOT NULL,
  user_id      TEXT NOT NULL,
  name         TEXT,
  jti          TEXT NOT NULL,
  created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  last_seen_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  revoked_at   TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);
