-- 0006_ai_read_models.sql — AI Read Models 主通道（docs/ai-architecture.md §4.3）
--
-- Cloud planner 的主数据通道是 D1 上的预计算视图，而不是每次从
-- journal_entries / postings 现算。每个 read model 表都遵循统一的
-- "schema 公约"（§4.3.5）：source_hlc_watermark + refreshed_at +
-- schema_version + calculation_version。
--
-- Phase 1 仅落第一张表（monthly_spend_by_category，Snapshot 层 P0
-- 三表之一）+ 一张共享的 freshness 元数据表。后续表逐步加入。

-- ---------------------------------------------------------------------------
-- read_model_freshness_meta — 每用户 × 每 read_model 的刷新状态
-- ---------------------------------------------------------------------------
-- 单独存放是为了：
--   1. lazy 刷新时一次查询就能拿到 watermark（无需扫数据表所有行）
--   2. 没有自然「每行 HLC」的 read model（如 cluster / behavior）也能
--      统一描述新鲜度
--   3. 端侧 freshness gate 可以单独 query 这张表做客户端缓存
CREATE TABLE IF NOT EXISTS read_model_freshness_meta (
  user_id              TEXT NOT NULL,
  read_model           TEXT NOT NULL,
  source_hlc_watermark TEXT NOT NULL,   -- 该用户该 read model 已消费到的 op_log HLC
  refreshed_at         TEXT NOT NULL,   -- ISO 时间戳，仅做 debug
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, read_model)
);

-- ---------------------------------------------------------------------------
-- read_model_monthly_spend_by_category — Snapshot 层
-- ---------------------------------------------------------------------------
-- 月 × 类目 × 币种 的支出聚合。
--
-- 数据来源：journal_entries.payload.category + postings.payload.units (currency leg)
--   - 仅算「支出」语义：postings 中 unit 是 fiat 币种且对应 entry 有 expense category
--   - total_minor 是该桶内 |units| 的求和（minor units，即 cents/fen 的整数倍）
--   - 来自 propose_expense 的 9 个内置类目；外部导入数据按其 payload.category 落
--
-- PK 含 currency 因为同一用户可能有多币种支出（CNY + USD），不能合并。
CREATE TABLE IF NOT EXISTS read_model_monthly_spend_by_category (
  user_id              TEXT NOT NULL,
  year_month           TEXT NOT NULL,         -- 'YYYY-MM'
  category             TEXT NOT NULL,         -- 'food' / 'transport' / ... / 'unknown'
  currency             TEXT NOT NULL,
  total_minor          TEXT NOT NULL,         -- decimal-as-string，minor units
  txn_count            INTEGER NOT NULL,
  -- schema 公约（每行都自带，方便下游做 sub-query 时不丢 freshness 信息）
  source_hlc_watermark TEXT NOT NULL,
  refreshed_at         TEXT NOT NULL,
  schema_version       INTEGER NOT NULL,
  calculation_version  INTEGER NOT NULL,
  PRIMARY KEY (user_id, year_month, category, currency)
);

CREATE INDEX IF NOT EXISTS read_model_monthly_spend_user_yearmonth
  ON read_model_monthly_spend_by_category (user_id, year_month);
