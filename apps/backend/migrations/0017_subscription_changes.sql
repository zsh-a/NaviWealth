-- 0017_subscription_changes.sql — Analytical 层 P1 完结 (docs/ai-architecture.md §4.3.3)
--
-- device-sourced：端侧 detectSubscriptionChanges (Wave 19) 在每次 chat
-- 准备阶段跑一遍，对比同一个 merchant 在 earlier-half / later-half 的
-- median 金额差异；超阈值就上报。云端镜像入此表。
--
-- payload schema (v1):
--   {
--     merchant_key, cadence (weekly/monthly), currency,
--     prev_amount_minor, new_amount_minor, delta_ratio, since
--   }
--
-- 复合 id 形如 '{merchant_key}|{currency}'：同一订阅多次价格变动覆盖
-- 之前的值（最近一次价格变动总是最有用）。

CREATE TABLE IF NOT EXISTS read_model_subscription_changes (
  user_id              TEXT NOT NULL,
  id                   TEXT NOT NULL,         -- '{merchant_key}|{currency}'
  payload              TEXT NOT NULL,
  merchant_key         TEXT,
  cadence              TEXT,
  currency             TEXT,
  prev_amount_minor    TEXT,
  new_amount_minor     TEXT,
  delta_ratio          TEXT,                  -- decimal-as-string
  since                TEXT,                  -- ISO datetime
  source_device_id     TEXT,
  source_hlc_watermark TEXT NOT NULL,
  refreshed_at         TEXT NOT NULL,
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS read_model_subscription_changes_user_currency
  ON read_model_subscription_changes (user_id, currency);
