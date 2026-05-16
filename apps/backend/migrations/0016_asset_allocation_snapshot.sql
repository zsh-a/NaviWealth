-- 0016_asset_allocation_snapshot.sql — Snapshot 层 P1 (docs/ai-architecture.md §4.3.2)
--
-- cloud-projected：从 read_model_holdings_snapshot + assets.payload.type 聚合。
-- 没有 FX/价格源，所以汇总单位是 cost_basis_minor（成本而非市值），
-- 且按 cost_currency 分桶（跨币种不直接相加避免误导）。
--
-- 行粒度：(user_id, bucket_dim, bucket_key, currency)
--  - bucket_dim: 当前只有 'asset_type'，预留 'industry' / 'region' 等
--  - bucket_key: asset.type 取值 (stock / etf / crypto / cash / ...) 或 'unknown'
--  - weight: 桶 cost / (同 dim 同 currency 总 cost)，[0, 1]
--
-- 刷新策略：lazy via Projection trait。后续 holdings_snapshot 改 write-side
-- 同步刷新后，本表会随其重算。

CREATE TABLE IF NOT EXISTS read_model_asset_allocation_snapshot (
  user_id              TEXT NOT NULL,
  bucket_dim           TEXT NOT NULL,         -- 'asset_type' | (extensible)
  bucket_key           TEXT NOT NULL,         -- e.g. 'stock' / 'crypto' / 'unknown'
  currency             TEXT NOT NULL,
  total_cost_minor     TEXT NOT NULL,         -- decimal-as-string
  position_count       INTEGER NOT NULL,
  weight               TEXT NOT NULL,         -- decimal-as-string, [0,1]
  source_hlc_watermark TEXT NOT NULL,
  refreshed_at         TEXT NOT NULL,
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, bucket_dim, bucket_key, currency)
);

CREATE INDEX IF NOT EXISTS read_model_asset_allocation_user_dim
  ON read_model_asset_allocation_snapshot (user_id, bucket_dim);
