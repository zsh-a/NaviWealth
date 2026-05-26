-- 0018_sync_row_namespace.sql — D-1.4 LifeOS domain prefix
-- (docs/lifeos-shell.md §8).
--
-- Every row crossing the sync wire is tagged with its LifeOS domain
-- prefix (`fin:` today, `health:` once D-2 lands) so the active-domain
-- set is observable in `sync_rows` and a future per-domain pull filter
-- (D-1.5) can short-circuit on the auth layer.
--
-- Before this migration every row stored its bare Drift table name
-- (`accounts`, `journal_entries`, ...). After this migration each
-- legacy row is rewritten to `fin:<original>`. New writes from a
-- D-1.4+ client carry the prefix from the start.
--
-- Idempotency: rows that already contain a `:` are left alone so this
-- migration can be re-applied safely against a database that was
-- already updated (e.g. mixed-version preview environments).

UPDATE sync_rows
SET    table_name = 'fin:' || table_name
WHERE  table_name NOT LIKE '%:%';
