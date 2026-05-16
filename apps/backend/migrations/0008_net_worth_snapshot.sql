-- 0008_net_worth_snapshot.sql — Snapshot 层 P0 第三张表 (docs/ai-architecture.md §4.3.2)
--
-- 每用户 × 每年月 × 每币种的「累计净现金流」。
--
-- Phase 1 简化：粒度是月（不是文档原计划的 day —— 365 倍存储 + lazy 重算
-- 成本不划算）。granularity=week/day 的 compute_net_worth 调用仍走 inline
-- 旧路径，document gap。
--
-- 累计语义：cumulative_minor[ym] = sum(net_flow[..=ym])。新月份增量更新
-- 时只需重算最新一行 + 每月增量；Phase 1 用全量重算保持简单。

CREATE TABLE IF NOT EXISTS read_model_net_worth_snapshot (
  user_id              TEXT NOT NULL,
  year_month           TEXT NOT NULL,         -- 'YYYY-MM'
  currency             TEXT NOT NULL,
  cumulative_minor     TEXT NOT NULL,         -- 累计净现金流 (minor units, 含 sign)
  net_flow_minor       TEXT NOT NULL,         -- 该月净流入 (income - expense)，便于增量
  -- schema 公约
  source_hlc_watermark TEXT NOT NULL,
  refreshed_at         TEXT NOT NULL,
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, year_month, currency)
);

CREATE INDEX IF NOT EXISTS read_model_net_worth_user_ym
  ON read_model_net_worth_snapshot (user_id, year_month);
