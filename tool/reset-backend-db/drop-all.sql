-- Full reset: drop every app table plus d1's migration ledger so the next
-- `wrangler d1 migrations apply` rebuilds the schema from scratch.
--
-- Keep this list in sync with active CREATE TABLE statements in
-- apps/backend/migrations/*.sql.

-- Current sync v3 schema.
DROP TABLE IF EXISTS sync_rows;

-- Current AI/read-model tables.
DROP TABLE IF EXISTS read_model_subscription_changes;
DROP TABLE IF EXISTS read_model_asset_allocation_snapshot;
DROP TABLE IF EXISTS read_model_investment_performance;
DROP TABLE IF EXISTS read_model_transfer_links;
DROP TABLE IF EXISTS read_model_refund_links;
DROP TABLE IF EXISTS read_model_net_worth_daily;
DROP TABLE IF EXISTS read_model_xirr_snapshot;
DROP TABLE IF EXISTS read_model_anomaly_flags;
DROP TABLE IF EXISTS read_model_recurring_patterns;
DROP TABLE IF EXISTS read_model_cashflow_buckets;
DROP TABLE IF EXISTS read_model_net_worth_snapshot;
DROP TABLE IF EXISTS read_model_holdings_snapshot;
DROP TABLE IF EXISTS read_model_monthly_spend_by_category;
DROP TABLE IF EXISTS read_model_freshness_meta;
DROP TABLE IF EXISTS ai_request_log;

-- Auth tables.
DROP TABLE IF EXISTS devices;
DROP TABLE IF EXISTS users;

-- D1's migration ledger. Drop it last so a re-apply replays every file in
-- apps/backend/migrations/ from 0001.
DROP TABLE IF EXISTS d1_migrations;
