-- 0015_investment_performance.sql — Analytical 层 P1 (docs/ai-architecture.md §4.3.3)
--
-- device-sourced：端侧 holdingsSnapshotProvider (FIR-21) 在每次 chat 准
-- 备 ContextPack 时把 per-asset 持仓快照通过 analytical_uploads
-- (kind='investment_performance') 上报。后端镜像入表。
--
-- 与 xirr_snapshot 的关系：
--  - xirr_snapshot：cloud-projected，按 scope (portfolio / asset_id)
--    全时间窗口的 XIRR。
--  - investment_performance：device-sourced，per-asset 当前持仓状态
--    (quantity / market_value / cost_basis / unrealized_pnl / weight)，
--    含 base + asset 双币种视图。AI 想问 "AAPL 现在赚多少" 直接读这表，
--    不需要再算。
--
-- payload schema (v1):
--   {
--     asset_id, asset_currency, base_currency, as_of,
--     quantity,
--     cost_basis_in_asset_currency, market_value_in_asset_currency,
--     cost_basis_in_base, market_value_in_base, unrealized_pnl_in_base,
--     weight,
--     holding_days?   (optional — present when device knows earliest lot)
--   }

CREATE TABLE IF NOT EXISTS read_model_investment_performance (
  user_id              TEXT NOT NULL,
  id                   TEXT NOT NULL,         -- asset_id
  payload              TEXT NOT NULL,         -- 完整 JSON 原文
  -- denorm 字段（便于工具 ORDER BY / WHERE）
  asset_id             TEXT,
  asset_currency       TEXT,
  base_currency        TEXT,
  -- 数值列存字符串（与 refund/transfer/xirr 一致避免 D1 浮点丢精度）
  market_value_base    TEXT,
  cost_basis_base      TEXT,
  unrealized_pnl_base  TEXT,
  weight               TEXT,
  holding_days         INTEGER,
  as_of                TEXT,
  source_device_id     TEXT,
  -- schema 公约
  source_hlc_watermark TEXT NOT NULL,
  refreshed_at         TEXT NOT NULL,
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS read_model_investment_performance_user_currency
  ON read_model_investment_performance (user_id, base_currency);
