-- 0007_holdings_snapshot.sql — Snapshot 层 P0 第二张表 (docs/ai-architecture.md §4.3.2)
--
-- 每用户 × 每 asset_id 的当前净持仓 + 加权平均成本。
-- 数据来源：postings.payload (units / cost_per_unit / cost_currency)
--           按 unit ∈ assets.id 聚合。
--
-- 不存 market_value —— 现价依赖 FX/价格源，由查询时端侧或专门工具补全。

CREATE TABLE IF NOT EXISTS read_model_holdings_snapshot (
  user_id              TEXT NOT NULL,
  asset_id             TEXT NOT NULL,
  net_qty              TEXT NOT NULL,         -- decimal-as-string，保留精度
  cost_basis_minor     TEXT NOT NULL,         -- minor units 小数 × 100 后取整
  cost_currency        TEXT NOT NULL,
  -- schema 公约（§4.3.5）
  source_hlc_watermark TEXT NOT NULL,
  refreshed_at         TEXT NOT NULL,
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, asset_id)
);
