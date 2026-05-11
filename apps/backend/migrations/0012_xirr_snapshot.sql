-- 0012_xirr_snapshot.sql — Analytical 层 P2 (docs/ai-architecture.md §4.3.3)
--
-- 与 Wave 10/11 的 device-sourced analytical 不同：XIRR 是确定性
-- 计算（Newton-Raphson on cash flow series），云端能从 postings
-- 直接 project，不需要端侧上报。文档 §4.3.6 把 XIRR 列为「夜间/低频
-- 刷新」档；Phase 1 走 lazy refresh 即可。
--
-- scope:
--   - 'portfolio': 全组合现金流 XIRR
--   - asset_id (任意非 'portfolio' 字符串): 该资产参与的所有 journal_entry 的现金腿 XIRR
--
-- xirr 列允许 NULL: 当现金流单边、长度不足 2、或 Newton 不收敛时
-- 写 NULL (而不是 0)，以区分"无定义"和"零回报"。

CREATE TABLE IF NOT EXISTS read_model_xirr_snapshot (
  user_id              TEXT NOT NULL,
  scope                TEXT NOT NULL,         -- 'portfolio' OR asset_id
  xirr                 REAL,                  -- 可空：无定义/不收敛
  flow_count           INTEGER NOT NULL,
  primary_currency     TEXT,                  -- 占多数的币种；多币种时还会置 multi_currency=true
  multi_currency       INTEGER NOT NULL DEFAULT 0,  -- 0/1 boolean
  approximation        INTEGER NOT NULL DEFAULT 1,  -- 0/1 boolean，单币种全集时为 0
  -- schema 公约
  source_hlc_watermark TEXT NOT NULL,
  refreshed_at         TEXT NOT NULL,
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, scope)
);
