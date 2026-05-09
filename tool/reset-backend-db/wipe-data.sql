-- Data-only reset: clear every app row, keep the schema and the
-- d1_migrations history. Tables are listed children-first so foreign-key
-- constraints (where present) don't reject a delete.
--
-- Keep this list in sync with the CREATE TABLE statements in
-- apps/backend/migrations/*.sql. Adding a table? Append it here too.

DELETE FROM postings;
DELETE FROM journal_entries;
DELETE FROM amortization_entries;
DELETE FROM tag_links;
DELETE FROM tags;
DELETE FROM prices;
DELETE FROM fx_rates;
DELETE FROM categories;
DELETE FROM settings;
DELETE FROM goals;
DELETE FROM liabilities;
DELETE FROM assets;
DELETE FROM accounts;
DELETE FROM op_log;
DELETE FROM sync_state;
DELETE FROM ai_request_log;

-- Materialised sync mirrors (latest-state copies of synced rows).
DELETE FROM synced_devices;
DELETE FROM synced_users;

-- Auth identities live in `users` / `devices`. Wiping them logs every
-- client out and forces a fresh `tool/register-user/register.sh`.
DELETE FROM devices;
DELETE FROM users;
