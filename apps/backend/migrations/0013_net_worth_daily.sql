-- 0013_net_worth_daily.sql — Snapshot 层 P1 (docs/ai-architecture.md §4.3.2)
--
-- 与 net_worth_snapshot (per-month) 互补：本表存 per-day 累计净现金流，
-- 服务 compute_net_worth 的 day/week granularity 查询。
--
-- 存储考量: 2 年活动 × 3 币种 ≈ 2200 行/用户，D1 足够轻。
-- Week granularity 通过对 day 行重采样获得，避免单独建 weekly 表。

CREATE TABLE IF NOT EXISTS read_model_net_worth_daily (
  user_id              TEXT NOT NULL,
  yyyy_mm_dd           TEXT NOT NULL,         -- 'YYYY-MM-DD'
  currency             TEXT NOT NULL,
  cumulative_minor     TEXT NOT NULL,         -- 累计净现金流 (minor units, signed)
  net_flow_minor       TEXT NOT NULL,         -- 该日净流入
  -- schema 公约
  source_hlc_watermark TEXT NOT NULL,
  refreshed_at         TEXT NOT NULL,
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, yyyy_mm_dd, currency)
);

CREATE INDEX IF NOT EXISTS read_model_net_worth_daily_user_date
  ON read_model_net_worth_daily (user_id, yyyy_mm_dd);
