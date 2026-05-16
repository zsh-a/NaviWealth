-- 0009_cashflow_buckets.sql — Snapshot 层 P1 (docs/ai-architecture.md §4.3.2)
--
-- 每用户 × 每年月 × 每币种的「inflow / outflow 分桶」。
--
-- 与 net_worth_snapshot 的差异：
--  - net_worth_snapshot: net_flow (signed, 含累计) —— 答「现金累计走向」
--  - cashflow_buckets:   inflow + outflow 分别 abs 累加 —— 答「钱从哪来、
--                        往哪走、各几笔」。两个模型同源 (postings 的 fiat
--                        leg)，因 query 形态不同分别物化。
--
-- 文档把它列为 P1（不是 P0）：P0 任务里 net_worth_snapshot 已覆盖
-- 「净值趋势」；P1 才到「现金构成」的颗粒度。

CREATE TABLE IF NOT EXISTS read_model_cashflow_buckets (
  user_id              TEXT NOT NULL,
  year_month           TEXT NOT NULL,         -- 'YYYY-MM'
  currency             TEXT NOT NULL,
  inflow_minor         TEXT NOT NULL,         -- abs sum，minor units
  outflow_minor        TEXT NOT NULL,         -- abs sum，minor units
  inflow_count         INTEGER NOT NULL,
  outflow_count        INTEGER NOT NULL,
  -- schema 公约（§4.3.5）
  source_hlc_watermark TEXT NOT NULL,
  refreshed_at         TEXT NOT NULL,
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, year_month, currency)
);

CREATE INDEX IF NOT EXISTS read_model_cashflow_buckets_user_ym
  ON read_model_cashflow_buckets (user_id, year_month);
