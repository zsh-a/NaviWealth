-- Full reset: drop every app table plus d1's migration ledger so the
-- next `wrangler d1 migrations apply` rebuilds the schema from scratch.
--
-- Keep this list in sync with the CREATE TABLE statements in
-- apps/backend/migrations/*.sql. Dropping in children-first order keeps
-- FK constraint complaints quiet on databases that have foreign_keys
-- enforcement on.

DROP TABLE IF EXISTS postings;
DROP TABLE IF EXISTS journal_entries;
DROP TABLE IF EXISTS amortization_entries;
DROP TABLE IF EXISTS tag_links;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS prices;
DROP TABLE IF EXISTS fx_rates;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS settings;
DROP TABLE IF EXISTS goals;
DROP TABLE IF EXISTS liabilities;
DROP TABLE IF EXISTS assets;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS op_log;
DROP TABLE IF EXISTS sync_state;
DROP TABLE IF EXISTS ai_request_log;

-- Sync materialisations.
DROP TABLE IF EXISTS synced_devices;
DROP TABLE IF EXISTS synced_users;

-- Auth tables.
DROP TABLE IF EXISTS devices;
DROP TABLE IF EXISTS users;

-- D1's migration ledger. Drop it last so a re-apply replays every file
-- in apps/backend/migrations/ from 0001.
DROP TABLE IF EXISTS d1_migrations;
