-- Data-only reset: clear every app row, keep the schema and the
-- d1_migrations history. Tables are listed children-first so foreign-key
-- constraints (where present) do not reject a delete.
--
-- Keep this list in sync with the active CREATE TABLE statements in
-- apps/backend/migrations/*.sql.

-- Sync v3 row-state store.
DELETE FROM sync_rows;
DELETE FROM sqlite_sequence WHERE name = 'sync_rows';

-- AI/read-model tables.
DELETE FROM read_model_subscription_changes;
DELETE FROM read_model_asset_allocation_snapshot;
DELETE FROM read_model_investment_performance;
DELETE FROM read_model_transfer_links;
DELETE FROM read_model_refund_links;
DELETE FROM read_model_net_worth_daily;
DELETE FROM read_model_xirr_snapshot;
DELETE FROM read_model_anomaly_flags;
DELETE FROM read_model_recurring_patterns;
DELETE FROM read_model_cashflow_buckets;
DELETE FROM read_model_net_worth_snapshot;
DELETE FROM read_model_holdings_snapshot;
DELETE FROM read_model_monthly_spend_by_category;
DELETE FROM read_model_freshness_meta;
DELETE FROM ai_request_log;

-- Auth identities live in `users` / `devices`. Wiping them logs every client
-- out and forces a fresh `tool/register-user/register.sh`.
DELETE FROM devices;
DELETE FROM users;
