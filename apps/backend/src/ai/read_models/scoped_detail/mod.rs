//! Layer 3 — Scoped Detail Tools.
//!
//! 文档: `docs/ai-architecture.md` §4.3.4。Drill-down 路径，仅在 LLM
//! 需要回答「为什么 / 哪些」时才启用。永远不是 raw ledger scan：
//!
//!  - 必填 filter: `category` + `range`（≤ 31 天）
//!  - 硬限额: `limit` ≤ 50
//!  - 必填 `purpose`，写入 AiTrace
//!  - sanitised 字段: `merchant_hashed` / `account_kind`，不返回名字
//!  - 预聚合 `summary` 与明细同发，让 LLM 优先消费聚合
//!
//! Phase 1 落地: `read_category_window` —— 取代 `get_journal_entries`
//! 的「按类目过滤」用法。后续可加 `read_account_window` /
//! `read_asset_window` 共用此模块的 sanitisation + freshness 公约。

pub mod account_window;
pub mod asset_window;
pub mod category_window;
pub mod common;
