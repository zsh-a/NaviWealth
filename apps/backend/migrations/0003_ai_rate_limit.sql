-- 0003_ai_rate_limit.sql — AI assistant rate-limit ledger (FIR-59).
--
-- One row per `/ai/chat` request. The chat handler counts rows for the
-- caller in the trailing 1h window and rejects with HTTP 429 once the
-- per-user budget (60 req/h) is exceeded. Old rows are pruned opportunistically
-- on each successful insert so the table stays small without a cron job.
--
-- We keep this in a dedicated table rather than reusing a generic counter
-- because the AI guardrail is the only path with this rate envelope today,
-- and a per-user time-window count is cheaper to implement as a row-count
-- query than as a sliding bucket.

CREATE TABLE IF NOT EXISTS ai_request_log (
  user_id     TEXT NOT NULL,
  request_at  TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS ai_request_log_user_idx
  ON ai_request_log (user_id, request_at);
