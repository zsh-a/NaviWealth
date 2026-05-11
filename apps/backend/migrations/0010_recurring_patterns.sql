-- 0010_recurring_patterns.sql — Analytical 层 P1 第一张表 (docs/ai-architecture.md §4.3.3)
--
-- 与 Snapshot 层不同：Analytical 层是 "device-sourced"。
-- - Snapshot: 云端从 postings 现算 → 物化 (write-side projection)
-- - Analytical: 端侧 detector 产生（recurring/anomaly/refund 等启发式）
--               → 通过 ContextPack.analytical_uploads 推到云端 → 镜像到此表
--
-- 这样做的原因（文档 §10 关键取舍）：启发式逻辑写两份（Dart + Rust）
-- 必然漂移，让端是唯一计算者。云端只是订阅者。
--
-- payload 列保留 device 上报的完整 JSON；前缀的 denorm 列从 payload
-- 抽出来加速 query。schema 公约（§4.3.5）适用。

CREATE TABLE IF NOT EXISTS read_model_recurring_patterns (
  user_id              TEXT NOT NULL,
  id                   TEXT NOT NULL,         -- '<merchant_key>|<currency>'（设备约定）
  payload              TEXT NOT NULL,         -- 完整 JSON 原文
  -- denorm 字段：从 payload 抽出来便于工具 ORDER BY / WHERE
  merchant_key         TEXT,
  cadence              TEXT,                  -- 'weekly' / 'monthly'
  currency             TEXT,
  median_amount_minor  TEXT,
  occurrences          INTEGER,
  last_seen_at         TEXT,                  -- ISO datetime
  source_device_id     TEXT,                  -- 哪台设备最近上报的
  -- schema 公约
  source_hlc_watermark TEXT NOT NULL,
  refreshed_at         TEXT NOT NULL,
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS read_model_recurring_patterns_user_merchant
  ON read_model_recurring_patterns (user_id, merchant_key);
