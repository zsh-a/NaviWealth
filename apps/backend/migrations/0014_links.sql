-- 0014_links.sql — Analytical 层 P1 (docs/ai-architecture.md §4.3.3)
--
-- device-sourced：端侧 refundMatcher / transferMatcher (Wave 2-B) 跑
-- 启发式 → ContextPack.analytical_uploads → 后端镜像。两表同 schema
-- 但语义不同：
--  - refund_links: 原交易 → 退款；asymmetric (a 是 original, b 是 refund)
--  - transfer_links: 账户 A → 账户 B；asymmetric by direction (a 是 from, b 是 to)
--
-- 复合 id 形如 '{a_txn_id}|{b_txn_id}'：upsert key，端侧再次上报同
-- 一对配对时不重复入库。

CREATE TABLE IF NOT EXISTS read_model_refund_links (
  user_id              TEXT NOT NULL,
  id                   TEXT NOT NULL,         -- '{original_txn_id}|{refund_txn_id}'
  payload              TEXT NOT NULL,
  original_txn_id      TEXT,
  refund_txn_id        TEXT,
  amount_minor         TEXT,
  currency             TEXT,
  source_device_id     TEXT,
  source_hlc_watermark TEXT NOT NULL,
  refreshed_at         TEXT NOT NULL,
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS read_model_refund_links_user_currency
  ON read_model_refund_links (user_id, currency);

CREATE TABLE IF NOT EXISTS read_model_transfer_links (
  user_id              TEXT NOT NULL,
  id                   TEXT NOT NULL,         -- '{from_txn_id}|{to_txn_id}'
  payload              TEXT NOT NULL,
  from_txn_id          TEXT,
  to_txn_id            TEXT,
  amount_minor         TEXT,
  currency             TEXT,
  source_device_id     TEXT,
  source_hlc_watermark TEXT NOT NULL,
  refreshed_at         TEXT NOT NULL,
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS read_model_transfer_links_user_currency
  ON read_model_transfer_links (user_id, currency);
