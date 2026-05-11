//! AI Read Models — Cloud planner 的主数据通道。
//!
//! 文档: `docs/ai-architecture.md` §4.3。
//!
//! 三层访问模型:
//!  - Layer 1 — Snapshot: 高速摘要（holdings / net_worth / monthly_spend）
//!  - Layer 2 — Analytical: 预分析中间结果（recurring / anomaly / xirr）
//!  - Layer 3 — Scoped Detail: 受控明细（read_transaction_slice 等）
//!
//! Phase 1 落地: monthly_spend_by_category（Snapshot P0）+ 共享的
//! Freshness/Projection 抽象。后续 holdings_snapshot / net_worth_snapshot
//! 复用同一套 trait 与 schema 公约。
//!
//! 刷新策略: Phase 1 全部走 lazy refresh — 工具调用时检查 watermark，
//! 落后于 op_log 时同步重算。后续 hot read model 可改为 write-side 触发
//! 同步刷新 (§4.3.6)。

pub mod cashflow_buckets;
pub mod freshness;
pub mod holdings_snapshot;
pub mod monthly_spend_by_category;
pub mod net_worth_snapshot;
pub mod projection;
pub mod scoped_detail;
