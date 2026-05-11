-- 0011_anomaly_flags.sql — Analytical 层 P1 第二张表 (docs/ai-architecture.md §4.3.3)
--
-- device-sourced：端侧 expenseAnomalyInsightProvider / 未来更细的
-- detector 检测到异常时，通过 ContextPack.analytical_uploads 上报。
-- 后端镜像入此表。同 (user_id, id) upsert。

CREATE TABLE IF NOT EXISTS read_model_anomaly_flags (
  user_id              TEXT NOT NULL,
  id                   TEXT NOT NULL,         -- e.g. 'expense_monthly_spike|2026-05'
  payload              TEXT NOT NULL,         -- 完整 JSON 原文
  -- denorm 字段（便于工具 ORDER BY / WHERE）
  category             TEXT,                  -- 'all_expense' / 'food' / ...
  kind                 TEXT,                  -- 'monthly_spike' / 'subscription_price_up' / ...
  delta_pct            INTEGER,               -- 偏离基线的百分点（取整）
  severity             TEXT,                  -- 'info' / 'warn' / 'critical'
  detected_at          TEXT,                  -- ISO datetime
  source_device_id     TEXT,
  -- schema 公约
  source_hlc_watermark TEXT NOT NULL,
  refreshed_at         TEXT NOT NULL,
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS read_model_anomaly_flags_user_severity
  ON read_model_anomaly_flags (user_id, severity);
