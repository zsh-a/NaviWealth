//! Function-calling tool surface exposed to the LLM.
//!
//! Two families of tools live here:
//!
//! - **Read tools** (`get_*`, `compute_*`): feed the model real numbers from
//!   D1 so it doesn't have to invent any. Tool outputs are deterministic
//!   given the data, so any figure the assistant echoes traces back to
//!   [`dispatch`], not the model's head.
//! - **Write proposal tools** (`propose_*`, FIR-66): the model is still
//!   forbidden from writing directly. These tools resolve user-supplied
//!   references (account name, asset symbol, expense category) and return a
//!   structured *plan* the mobile client renders into a confirmation UI;
//!   only after the human taps "确认" does the client invoke the existing
//!   repositories (`JournalEntryRepository`, `AccountRepository`, etc.) to
//!   persist the row. The plan envelope is built in `proposals.rs`.
//!
//! The model is forbidden from inventing financial values (see
//! `guardrails::SYSTEM_PROMPT`).
//!
//! ## Design
//!
//! - All tools take a `ToolCtx` (user id + D1 handle) and a JSON `input`
//!   (already validated by Anthropic against `ToolSchema::input_schema`).
//! - Computations run off the materialised sync tables (`journal_entries`,
//!   `postings`, `assets`, etc.), parsing the JSON `payload` column into a
//!   serde_json::Value. The mobile client owns the canonical types; we keep
//!   the server side schema-light so a payload field added on mobile shows
//!   up here without a backend deploy.
//! - Money is reported with explicit currency metadata. Cross-currency totals
//!   are only returned when a client `portfolio_snapshot` supplies base-currency
//!   values; otherwise the tool returns conversion gaps instead of fabricating
//!   FX.
//!
//! When the model asks for analytics that genuinely need the FIR-48 holding
//! engine (cost basis with FIFO/LIFO/AvgCost, corporate actions, lot
//! tracking), we return a coarse approximation here and tag the response
//! with `"approximation": true` so the assistant can disclose that to the
//! user. The proper engine will replace these stubs once it's ported to the
//! Worker.

use chrono::{DateTime, Datelike, Duration, Utc};
use serde::Deserialize;
use serde_json::{json, Map, Value};
use worker::{D1Database, D1Type};

use super::adapters::anthropic::wire::ToolSchema;
use super::context::BudgetTier;
use super::policy::{check_tool_call, lookup, PolicyDecision};
use crate::error::AppError;

pub mod propose_account_create;
pub mod propose_asset_valuation;
pub mod propose_expense;
pub mod propose_liability_payment;
pub mod propose_trade;
pub mod registry;

pub struct ToolCtx<'a> {
    pub user_id: &'a str,
    pub db: &'a D1Database,
    pub portfolio_snapshot: Option<&'a Value>,
    /// Budget tier reported by the client's [`ContextPack`]. `None`
    /// for legacy clients that haven't adopted Phase 2-A yet.
    pub context_tier: Option<BudgetTier>,
}

pub fn registry() -> registry::ToolRegistry {
    registry::ToolRegistry::new([
        std::sync::Arc::new(propose_trade::ProposeTradeTool) as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(propose_expense::ProposeExpenseTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(propose_liability_payment::ProposeLiabilityPaymentTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(propose_account_create::ProposeAccountCreateTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(propose_asset_valuation::ProposeAssetValuationTool)
            as std::sync::Arc<dyn registry::Tool>,
    ])
}

/// Static catalogue. Kept as a function (not a `static` constant) because
/// `ToolSchema` carries `serde_json::Value` and isn't `const`-constructible.
pub fn schemas() -> Vec<ToolSchema> {
    let mut schemas = vec![
        ToolSchema {
            name: "get_holdings".into(),
            description: "返回当前持仓快照。优先使用客户端 portfolio_snapshot 中的持仓引擎结果；\
                          缺失时从 journal_entries / postings 推导近似值。".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "as_of": {
                        "type": "string",
                        "description": "ISO-8601 截止时刻（含），不传则到当前时间。"
                    },
                    "base_currency": {
                        "type": "string",
                        "description": "希望返回的折算基准币种；snapshot 已带 base 值时会使用。"
                    }
                }
            }),
        },
        // get_journal_entries 已废弃 (docs/ai-architecture.md §4.3.4)。
        // 不再向 LLM 暴露 schema —— 新对话不会发起调用；旧 chat 续推时
        // dispatch 仍处理以保持向后兼容（直到下一个主版本）。改用
        // Scoped Detail 工具族（read_category_window 等）。
        ToolSchema {
            name: "compute_xirr".into(),
            description: "对指定范围内的现金流计算 XIRR（年化内部收益率）。\
                          backend 实现为单币种简化版：从 postings 中抽取现金流，\
                          以 Newton 法求解贴现率。跨币种精确版本由 postings-derived returns read model 提供。".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "scope": {
                        "type": "string",
                        "enum": ["portfolio", "asset"],
                        "default": "portfolio"
                    },
                    "asset_id": {
                        "type": "string",
                        "description": "scope=asset 时必填"
                    },
                    "from": { "type": "string", "description": "ISO-8601 lower bound" },
                    "to":   { "type": "string", "description": "ISO-8601 upper bound" },
                    "base_currency": {
                        "type": "string",
                        "description": "需要跨币种汇总时的目标币种；优先使用 portfolio_snapshot 中的 base 折算。"
                    }
                }
            }),
        },
        ToolSchema {
            name: "compute_net_worth".into(),
            description: "净资产时间序列：在指定区间内按粒度采样，每个采样点上把账户的累计现金流减去负债余额。\
                          返回 list of {date, value, currency}。".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "from":        { "type": "string", "description": "ISO-8601 起始（含）" },
                    "to":          { "type": "string", "description": "ISO-8601 结束（含）" },
                    "granularity": { "type": "string", "enum": ["day", "week", "month"], "default": "month" },
                    "base_currency": {
                        "type": "string",
                        "description": "需要跨币种汇总时的目标币种；优先使用 portfolio_snapshot 中的当前 base 市值。"
                    }
                }
            }),
        },
        ToolSchema {
            name: "get_industry_breakdown".into(),
            description: "按 asset.industry 分组聚合当前股票/ETF 持仓的记账成本，返回每个行业的占比与币种。".into(),
            input_schema: json!({"type": "object", "properties": {}}),
        },
        ToolSchema {
            name: "get_geo_breakdown".into(),
            description: "按 asset.region 分组聚合当前持仓的记账成本，返回每个地区的占比。".into(),
            input_schema: json!({"type": "object", "properties": {}}),
        },
        ToolSchema {
            name: "get_market_cap_breakdown".into(),
            description: "按市值分类（large/mid/small/unknown）聚合当前股票持仓的记账成本。\
                          分类来自 asset.metadata_json.market_cap，缺失时归入 unknown。".into(),
            input_schema: json!({"type": "object", "properties": {}}),
        },
        ToolSchema {
            name: "get_risk_alerts".into(),
            description: "扫描当前持仓集中度并返回风险预警列表：单一资产或单一行业占比 > 20% 即触发 warning。".into(),
            input_schema: json!({"type": "object", "properties": {}}),
        },
        ToolSchema {
            name: "get_monthly_spend_by_category".into(),
            description: "返回某月（YYYY-MM）按类目 × 币种聚合的支出。\
                          数据来自 AI Read Model（`monthly_spend_by_category`，Snapshot 层 P0），\
                          首次调用会同步刷新；后续命中缓存。\
                          类目在内置 9 类（food/transport/housing/entertainment/medical/education/shopping/travel/other）。\
                          外部导入数据可能落到自定义 category 字符串。".into(),
            input_schema: json!({
                "type": "object",
                "required": ["year_month"],
                "properties": {
                    "year_month": {
                        "type": "string",
                        "description": "YYYY-MM，例如 '2026-04'",
                        "pattern": "^[0-9]{4}-[0-9]{2}$"
                    },
                    "category": {
                        "type": "string",
                        "description": "可选；只看某一类目的数字。"
                    }
                }
            }),
        },
        ToolSchema {
            name: "get_net_worth_summary".into(),
            description: "返回最近 N 个月的净现金流累计（月度净资产快照）。\
                          数据来自 AI Read Model `net_worth_snapshot`（Snapshot 层 P0）—— 月粒度，\
                          每月按币种独立累积。Phase 1 不减负债 / 不算资产市值（这两个走 compute_net_worth）。\
                          适合场景：「最近半年净现金流趋势」「上半年现金净流入多少」等月度问题。\
                          需要 day/week 粒度或资产市值时改用 compute_net_worth.".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "months_back": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 60,
                        "default": 12,
                        "description": "返回最近多少个月。默认 12。"
                    },
                    "currency": {
                        "type": "string",
                        "description": "可选；只返回某一币种。默认返回所有币种。"
                    }
                }
            }),
        },
        ToolSchema {
            name: "get_anomaly_flags".into(),
            description: "返回端侧 detector 检测到的支出 / 现金流异常。\
                          数据来自 AI Read Model `anomaly_flags`（Analytical 层 P1）—— \
                          device-sourced：端侧（如 expenseAnomalyInsightProvider）跑启发式 → \
                          ContextPack.analytical_uploads 上报 → 后端镜像。\
                          payload.kind 包含 monthly_spike / subscription_price_up / cashflow_anomaly 等。\
                          可选 severity_min 过滤（info ≤ warn ≤ critical）。".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "severity_min": {
                        "type": "string",
                        "enum": ["info", "warn", "critical"],
                        "description": "最低严重度（含），默认全部。"
                    }
                }
            }),
        },
        ToolSchema {
            name: "get_refund_links".into(),
            description: "返回端侧 refundMatcher 检测到的「原交易 ↔ 退款」配对。\
                          数据来自 AI Read Model `refund_links`（Analytical P1，device-sourced）。\
                          payload 含 original_txn_id / refund_txn_id / amount_minor / currency。\
                          典型问题：「哪些退款还在路上」「最近退了多少」「这笔退款对应哪次买入」。".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "currency": { "type": "string", "description": "可选；只看某一币种。" }
                }
            }),
        },
        ToolSchema {
            name: "get_transfer_links".into(),
            description: "返回端侧 transferMatcher 检测到的「账户 A → 账户 B」转账配对。\
                          数据来自 AI Read Model `transfer_links`（Analytical P1，device-sourced）。\
                          payload 含 from_txn_id / to_txn_id / amount_minor / currency。\
                          典型问题：「最近转了几笔」「哪些钱在不同账户之间挪动」。\
                          这些配对是端侧启发式匹配（同币种 + ±2 天窗口 + 50 minor 容差）。".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "currency": { "type": "string", "description": "可选；只看某一币种。" }
                }
            }),
        },
        ToolSchema {
            name: "get_subscription_changes".into(),
            description: "返回端侧 detectSubscriptionChanges 检测到的订阅价格变动\
                          （早窗口 median vs 晚窗口 median 差值超 10% 且 >=$1 等价）。\
                          数据来自 AI Read Model `subscription_changes`（Analytical P1，device-sourced）。\
                          payload 含 merchant_key / cadence / currency / prev_amount_minor / \
                          new_amount_minor / delta_ratio / since。\
                          典型问题：「哪些订阅最近涨价了」「Netflix 涨了多少」。\
                          注意：检测窗口仅限于本次 chat 上报的 expenses，未持久化跨会话状态。".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "currency": { "type": "string", "description": "可选；只看某一币种。" }
                }
            }),
        },
        ToolSchema {
            name: "get_investment_performance".into(),
            description: "返回 per-asset 当前持仓表现：market_value / cost_basis / unrealized_pnl / weight。\
                          数据来自 AI Read Model `investment_performance`（Analytical P1，device-sourced）—— \
                          端侧 holdingsSnapshotProvider 算出 per-asset 持仓后通过 \
                          ContextPack.analytical_uploads 镜像到云端表，AI 不需要再做计算。\
                          每行: asset_id / asset_currency / base_currency / market_value_base / \
                          cost_basis_base / unrealized_pnl_base / weight / holding_days? / as_of。\
                          典型问题：「我现在赚最多的是哪个标的」「AAPL 持仓现值」「未实现盈亏总计」。\
                          需要全时间窗口 XIRR 走 get_xirr_summary；自定义时间窗 XIRR 走 compute_xirr。".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "base_currency": {
                        "type": "string",
                        "description": "可选；只看某一 base currency（一般用户的整个 portfolio 都是同一个）。"
                    }
                }
            }),
        },
        ToolSchema {
            name: "get_recurring_patterns".into(),
            description: "返回端侧 detector 检测到的周期性支出（月度/周度订阅、定期账单等）。\
                          数据来自 AI Read Model `recurring_patterns`（Analytical 层 P1）—— \
                          这是 device-sourced read model：端侧 recurring_detector 跑启发式产生，\
                          通过 ContextPack.analytical_uploads 镜像到云端表（避免 Dart/Rust 双份漂移）。\
                          典型问题：「我有哪些订阅」「每月定期支出多少」「哪些订阅最近涨价了」（最后这个需配合 subscription_changes，待落）。\
                          可选 currency / cadence 过滤。".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "currency": {
                        "type": "string",
                        "description": "可选；只看某一币种。"
                    },
                    "cadence": {
                        "type": "string",
                        "enum": ["weekly", "monthly"],
                        "description": "可选；只看某一周期。"
                    }
                }
            }),
        },
        ToolSchema {
            name: "get_xirr_summary".into(),
            description: "返回当前 portfolio + 每个有现金流的 asset 的年化 XIRR (全时间窗口)。\
                          数据来自 AI Read Model `xirr_snapshot`（Analytical P2，cloud-projected —— \
                          与 device-sourced 不同，XIRR 是 Newton-Raphson 确定性算法，云端能直接 project）。\
                          每行: scope (portfolio 或 asset_id) + xirr (可能 null：单边/不收敛/数据不足) + \
                          flow_count + primary_currency + multi_currency。\
                          需要自定义时间窗的 XIRR 仍走 compute_xirr (legacy inline path).".into(),
            input_schema: json!({
                "type": "object",
                "properties": {}
            }),
        },
        ToolSchema {
            name: "get_asset_allocation".into(),
            description: "按 asset.type（stock / etf / crypto / cash / ...）+ currency 双键聚合\
                          当前持仓的 cost_basis_minor。数据来自 AI Read Model \
                          `asset_allocation_snapshot`（Snapshot 层 P1，cloud-projected）。\
                          weight 在同 currency 内归一（sum==1 within currency），\
                          跨币种不直接相加（云端没有 FX 源）。\
                          典型问题：「我的股票/加密占比」「USD 仓位最大头是哪类」「股票总成本多少」。\
                          单位是 **成本** 而非市值；市值需配合端侧价格数据计算。".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "bucket_dim": {
                        "type": "string",
                        "enum": ["asset_type"],
                        "default": "asset_type",
                        "description": "桶维度。当前只有 asset_type。预留 industry / region。"
                    }
                }
            }),
        },
        ToolSchema {
            name: "get_cashflow_buckets".into(),
            description: "返回最近 N 个月的现金 inflow / outflow 分桶。\
                          数据来自 AI Read Model `cashflow_buckets`（Snapshot 层 P1）—— \
                          月粒度，每月按币种独立累加 inflow (units > 0) 与 outflow (abs(units < 0))，\
                          各自带笔数。与 net_worth_snapshot 互补：本工具回答\
                          「钱从哪来、往哪去」，net_worth 回答「累计净走向」。\
                          典型问题：「上个月主要支出方向」「每月平均收入多少」「这季度有几次大额支出」。".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "months_back": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 24,
                        "default": 6,
                        "description": "返回最近多少个月。默认 6。"
                    },
                    "currency": {
                        "type": "string",
                        "description": "可选；只返回某一币种。默认所有币种。"
                    }
                }
            }),
        },
        ToolSchema {
            name: "read_account_window".into(),
            description: "Scoped Detail：返回某账户在指定窗口内的交易明细（drill-down）。\
                          只在用户问「这张卡上花了哪些」需要例证时调用；首选 Snapshot 工具回答聚合性问题。\
                          硬限额：窗口 ≤ 31 天，limit ≤ 50。明细字段已脱敏：merchant_hashed + category。\
                          purpose 必填，用于 AiTrace 审计。可选 category / min_amount_minor / max_amount_minor。".into(),
            input_schema: json!({
                "type": "object",
                "required": ["account_id", "from", "to", "purpose"],
                "properties": {
                    "account_id": { "type": "string" },
                    "from":       { "type": "string", "description": "ISO 起点（包含）" },
                    "to":         { "type": "string", "description": "ISO 终点（不包含），to - from ≤ 31 天" },
                    "purpose": {
                        "type": "string",
                        "enum": [
                            "drill_down_expense", "drill_down_investment",
                            "refund_matching", "anomaly_explain",
                            "recurring_detect", "other"
                        ]
                    },
                    "limit":            { "type": "integer", "minimum": 1, "maximum": 50, "default": 20 },
                    "category":         { "type": "string", "description": "可选；按类目二次过滤" },
                    "min_amount_minor": { "type": "integer", "description": "可选；最小 signed minor units" },
                    "max_amount_minor": { "type": "integer", "description": "可选；最大 signed minor units" }
                }
            }),
        },
        ToolSchema {
            name: "read_asset_window".into(),
            description: "Scoped Detail：返回某资产在指定窗口内的交易腿（数量变动 + 单价）。\
                          适合「AAPL 这个月有几次买卖」「这只 ETF 最近调仓」之类的 drill-down。\
                          硬限额：窗口 ≤ 31 天，limit ≤ 50。返回 qty_delta（signed）+ side (buy/sell) + cost_per_unit + currency；\
                          天然脱敏（不含 merchant 信息）。purpose 必填。".into(),
            input_schema: json!({
                "type": "object",
                "required": ["asset_id", "from", "to", "purpose"],
                "properties": {
                    "asset_id": { "type": "string" },
                    "from":     { "type": "string" },
                    "to":       { "type": "string" },
                    "purpose": {
                        "type": "string",
                        "enum": [
                            "drill_down_expense", "drill_down_investment",
                            "refund_matching", "anomaly_explain",
                            "recurring_detect", "other"
                        ]
                    },
                    "limit": { "type": "integer", "minimum": 1, "maximum": 50, "default": 20 }
                }
            }),
        },
        ToolSchema {
            name: "read_category_window".into(),
            description: "Scoped Detail 工具：返回某一类目在指定时间窗口内的交易明细（drill-down）。\
                          只在用户问「为什么 / 哪些」需要例证时调用 —— 默认应当先用 \
                          get_monthly_spend_by_category 的聚合结果回答。\
                          硬限额：窗口 ≤ 31 天，limit ≤ 50。明细字段已脱敏：\
                          merchant_hashed（同用户内稳定，跨用户不可逆）+ account_kind（不返名字）。\
                          purpose 必填，用于 AiTrace 审计。".into(),
            input_schema: json!({
                "type": "object",
                "required": ["category", "from", "to", "purpose"],
                "properties": {
                    "category": {
                        "type": "string",
                        "description": "类目（如 food / transport / shopping）"
                    },
                    "from": {
                        "type": "string",
                        "description": "ISO 日期或时间，包含；窗口起点"
                    },
                    "to": {
                        "type": "string",
                        "description": "ISO 日期或时间，不包含；窗口终点。to - from ≤ 31 天"
                    },
                    "purpose": {
                        "type": "string",
                        "enum": [
                            "drill_down_expense", "drill_down_investment",
                            "refund_matching", "anomaly_explain",
                            "recurring_detect", "other"
                        ],
                        "description": "调用动机；写入 AiTrace 审计"
                    },
                    "limit": {
                        "type": "integer",
                        "minimum": 1,
                        "maximum": 50,
                        "default": 20
                    },
                    "merchant_substring": {
                        "type": "string",
                        "description": "可选；按 note 的子串过滤（hash 后明细只能数 distinct 不能搜，所以匹配在原文上做）"
                    }
                }
            }),
        },
    ];
    schemas.extend(registry().schemas());
    schemas
}

/// Dispatch a tool call by name. Returns the JSON result the LLM will see in
/// the next `tool_result` block. Errors here surface to the model as a
/// `tool_result` with `is_error=true` rather than a 500 — the conversation
/// can recover.
///
/// Each individual tool is bounded by [`PER_TOOL_TIMEOUT_MS`]. If the inner
/// future doesn't complete in time (D1 read stuck, JS micro-task starved,
/// upstream call hung) we synthesize a structured `tool_timeout` error so
/// the model sees a parseable failure and can retry / wrap up rather than
/// the entire SSE stream stalling at the route layer.
pub async fn dispatch(ctx: &ToolCtx<'_>, name: &str, input: &Value) -> Value {
    use futures_util::future::{select, Either};
    use gloo_timers::future::TimeoutFuture;

    // Wave 21: policy is now ENFORCED (advisory → enforced). Denied
    // calls synthesize a structured tool_result so the model sees a
    // parseable failure and can pivot, rather than the dispatch
    // silently running. The synthesized result matches the shape of
    // an ordinary tool error (`{error: {...}}`) so existing model-side
    // error handling kicks in unchanged.
    let registry_descriptor = {
        let registry = registry();
        registry.get(name).map(|tool| tool.descriptor())
    };
    let descriptor = registry_descriptor.as_ref().or_else(|| lookup(name));
    match check_tool_call(descriptor, ctx.context_tier) {
        PolicyDecision::Allowed => {}
        PolicyDecision::Denied(reason) => {
            worker::console_log!(
                "tool_policy denied: tool={name} reason={reason:?} client_tier={:?}",
                ctx.context_tier
            );
            return policy_denied_result(name, &reason);
        }
    }

    let work = async {
        match name {
            "get_holdings" => get_holdings(ctx, input).await,
            "get_journal_entries" => get_journal_entries(ctx, input).await,
            "compute_xirr" => compute_xirr(ctx, input).await,
            "compute_net_worth" => compute_net_worth(ctx, input).await,
            "get_industry_breakdown" => get_breakdown(ctx, BreakdownDim::Industry).await,
            "get_geo_breakdown" => get_breakdown(ctx, BreakdownDim::Region).await,
            "get_market_cap_breakdown" => get_breakdown(ctx, BreakdownDim::MarketCap).await,
            "get_risk_alerts" => get_risk_alerts(ctx).await,
            "get_monthly_spend_by_category" => get_monthly_spend_by_category(ctx, input).await,
            "get_net_worth_summary" => get_net_worth_summary(ctx, input).await,
            "get_cashflow_buckets" => get_cashflow_buckets(ctx, input).await,
            "get_asset_allocation" => get_asset_allocation(ctx, input).await,
            "get_recurring_patterns" => get_recurring_patterns(ctx, input).await,
            "get_anomaly_flags" => get_anomaly_flags(ctx, input).await,
            "get_refund_links" => get_refund_links(ctx, input).await,
            "get_transfer_links" => get_transfer_links(ctx, input).await,
            "get_investment_performance" => get_investment_performance(ctx, input).await,
            "get_subscription_changes" => get_subscription_changes(ctx, input).await,
            "get_xirr_summary" => get_xirr_summary(ctx, input).await,
            "read_account_window" => read_account_window(ctx, input).await,
            "read_asset_window" => read_asset_window(ctx, input).await,
            "read_category_window" => read_category_window(ctx, input).await,
            // FIR-66 write proposals — routed through the trait registry.
            name if name.starts_with("propose_") => {
                let registry = registry();
                registry
                    .get(name)
                    .ok_or_else(|| AppError::BadRequest(format!("unknown tool: {name}")))?
                    .invoke(ctx, input.clone())
                    .await
            }
            _ => Err(AppError::BadRequest(format!("unknown tool: {name}"))),
        }
    };
    let work = Box::pin(work);
    let timeout = Box::pin(TimeoutFuture::new(PER_TOOL_TIMEOUT_MS));
    let result = match select(work, timeout).await {
        Either::Left((result, _)) => result,
        Either::Right(_) => {
            return json!({
                "error":   format!("tool '{name}' timed out after {}ms", PER_TOOL_TIMEOUT_MS),
                "code":    "tool_timeout",
                "tool":    name,
            });
        }
    };
    match result {
        Ok(v) => v,
        Err(e) => json!({
            "error": e.to_string(),
            "code":  e.code(),
        }),
    }
}

/// Per-tool timeout. Sized so a healthy D1 read of the user's full ledger
/// (under 100k rows) plus any in-process JSON crunching always fits, while
/// catching the pathological "D1 hang under spawn_local context" case
/// before it stalls the whole conversation.
const PER_TOOL_TIMEOUT_MS: u32 = 15_000;

/// Wave 21 — synthesised `tool_result` body when policy denies dispatch.
/// Shape mirrors a normal tool error (`{error: {code, message}}`) so the
/// LLM's existing error handling kicks in without special-casing.
fn policy_denied_result(tool_name: &str, reason: &super::policy::PolicyReason) -> Value {
    json!({
        "error": {
            "code":     "policy_denied",
            "policy":   reason.code(),
            "tool":     tool_name,
            "message":  reason.message(),
        },
        "policy_denied": true,
    })
}

// ---------------------------------------------------------------------------
// D1 row helpers — we read the materialised tables directly. The protocol
// stores entity bodies as JSON in `payload`; we parse into Value so a new
// field on mobile becomes visible here without a backend deploy.
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct PayloadRow {
    id: String,
    payload: String,
}

async fn load_payloads(
    db: &D1Database,
    user_id: &str,
    table: &str,
) -> Result<Vec<(String, Value)>, AppError> {
    let sql = format!(
        "SELECT id, payload FROM {table} \
         WHERE user_id = ?1 AND deleted_at IS NULL"
    );
    let rows: Vec<PayloadRow> = db
        .prepare(&sql)
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        .all()
        .await
        .map_err(|e| AppError::Internal(format!("d1 all: {e}")))?
        .results()
        .map_err(|e| AppError::Internal(format!("d1 results: {e}")))?;
    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        let v: Value = serde_json::from_str(&r.payload).unwrap_or(Value::Null);
        out.push((r.id, v));
    }
    Ok(out)
}

fn parse_iso(s: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|d| d.with_timezone(&Utc))
}

fn payload_str<'a>(p: &'a Value, key: &str) -> Option<&'a str> {
    p.get(key).and_then(|v| v.as_str())
}

/// Pull a numeric field that may have been serialized as a JSON number
/// *or* as a string (Drift round-trips Decimal via its string form, so the
/// payload often has `"quantity": "100.0"` rather than `100.0`).
fn payload_num(p: &Value, key: &str) -> Option<f64> {
    match p.get(key)? {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.parse().ok(),
        _ => None,
    }
}

fn value_num(v: &Value) -> Option<f64> {
    match v {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.parse().ok(),
        _ => None,
    }
}

fn requested_base_currency(input: &Value, snapshot: Option<&Value>) -> Option<String> {
    input
        .get("base_currency")
        .and_then(|v| v.as_str())
        .or_else(|| {
            snapshot
                .and_then(|s| s.get("base_currency"))
                .and_then(|v| v.as_str())
        })
        .map(|s| s.trim().to_uppercase())
        .filter(|s| !s.is_empty())
}

fn snapshot_holdings(snapshot: Option<&Value>) -> Option<&Map<String, Value>> {
    snapshot?.get("holdings").and_then(|v| v.as_object())
}

fn snapshot_base_currency(snapshot: Option<&Value>) -> Option<&str> {
    snapshot?.get("base_currency").and_then(|v| v.as_str())
}

fn holding_value_base(h: &Value, key: &str, base_currency: &str) -> Option<f64> {
    let holding_base = h
        .get("base_currency")
        .and_then(|v| v.as_str())
        .map(|s| s.to_uppercase())?;
    if holding_base != base_currency.to_uppercase() {
        return None;
    }
    h.get(key).and_then(value_num)
}

fn snapshot_total_base(snapshot: Option<&Value>, key: &str, base_currency: &str) -> Option<f64> {
    let holdings = snapshot_holdings(snapshot)?;
    let mut total = 0.0;
    let mut saw = false;
    for h in holdings.values() {
        if let Some(value) = holding_value_base(h, key, base_currency) {
            total += value;
            saw = true;
        }
    }
    saw.then_some(total)
}

// ---------------------------------------------------------------------------
// get_holdings — Read Model 主通道入口（§4.3.2）+ client snapshot fast-path
// ---------------------------------------------------------------------------

async fn get_holdings(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::holdings_snapshot::{query_all, HoldingsSnapshot};
    use super::read_models::projection::ensure_fresh;

    let requested_base = requested_base_currency(input, ctx.portfolio_snapshot);

    // Client portfolio_snapshot 是最准的来源（端侧持仓引擎含 FX + 多
    // lot），优先返回。这是 freshness gate "device 数据更新" 的特殊
    // 形态：端侧主动上传完整快照，云端无须再算。
    if let Some(snapshot) = ctx.portfolio_snapshot {
        if let Some(holdings) = snapshot.get("holdings").and_then(|v| v.as_object()) {
            let snapshot_base = snapshot_base_currency(Some(snapshot)).map(|s| s.to_string());
            return Ok(json!({
                "as_of": input
                    .get("as_of")
                    .and_then(|v| v.as_str())
                    .or_else(|| snapshot.get("as_of").and_then(|v| v.as_str()))
                    .map(|s| s.to_string())
                    .unwrap_or_else(|| Utc::now().to_rfc3339()),
                "base_currency": requested_base.as_deref().or(snapshot_base.as_deref()),
                "snapshot_base_currency": snapshot_base,
                "holdings": Value::Object(holdings.clone()),
                "approximation": false,
                "source": "client_portfolio_snapshot",
                "conversion_source": "client_portfolio_snapshot",
            }));
        }
    }

    // 没有 client snapshot —— 走 Read Model (主通道, §4.3.2)。
    // ensure_fresh 在 op_log watermark 推进或 schema/calculation_version
    // 不匹配时同步重算；否则命中缓存。
    let proj = HoldingsSnapshot;
    let freshness = ensure_fresh(ctx.db, ctx.user_id, &proj).await?;
    let holdings_rows = query_all(ctx.db, ctx.user_id).await?;

    // 拿 asset 元数据做 symbol/name/type 注释（不是 read model 一部分；
    // 名字易变，不进 projection 避免反复刷）。
    let assets = load_payloads(ctx.db, ctx.user_id, "assets").await?;
    let asset_lookup: std::collections::HashMap<String, &Value> =
        assets.iter().map(|(k, v)| (k.clone(), v)).collect();

    let mut accs: Map<String, Value> = Map::new();
    for h in &holdings_rows {
        let cost_basis = (h.cost_basis_minor as f64) / 100.0;
        let avg_cost = if h.net_qty > 0.0 {
            cost_basis / h.net_qty
        } else {
            0.0
        };
        let asset = asset_lookup.get(&h.asset_id);
        accs.insert(
            h.asset_id.clone(),
            json!({
                "asset_id":      h.asset_id,
                "symbol":        asset.and_then(|a| payload_str(a, "symbol")),
                "name":          asset.and_then(|a| payload_str(a, "name")),
                "type":          asset.and_then(|a| payload_str(a, "type")),
                "net_quantity":  h.net_qty,
                "avg_unit_cost": avg_cost,
                "cost_basis":    cost_basis,
                "currency":      h.cost_currency,
            }),
        );
    }

    Ok(json!({
        "as_of":         freshness.refreshed_at,
        "base_currency": requested_base,
        "holdings":      Value::Object(accs),
        "approximation": true,
        "source":        "read_model",
        "freshness":     freshness,
        "note":          "数量与成本来自 holdings_snapshot read model（postings 加权平均）；精确 lot/FIFO 收益请由端侧 portfolio_snapshot 提供。",
    }))
}

// ---------------------------------------------------------------------------
// get_journal_entries — filtered list, newest first.
// ---------------------------------------------------------------------------

async fn get_journal_entries(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    let unit = input.get("unit").and_then(|v| v.as_str());
    let account_id = input.get("account_id").and_then(|v| v.as_str());
    let from = input
        .get("from")
        .and_then(|v| v.as_str())
        .and_then(parse_iso);
    let to = input.get("to").and_then(|v| v.as_str()).and_then(parse_iso);
    let limit = input
        .get("limit")
        .and_then(|v| v.as_u64())
        .unwrap_or(50)
        .min(200) as usize;

    let entries = load_payloads(ctx.db, ctx.user_id, "journal_entries").await?;
    let postings = load_payloads(ctx.db, ctx.user_id, "postings").await?;
    let mut postings_by_entry: std::collections::HashMap<String, Vec<Value>> =
        std::collections::HashMap::new();
    for (id, p) in postings {
        let mut row = p.clone();
        if let Some(obj) = row.as_object_mut() {
            obj.insert("id".into(), Value::String(id));
        }
        if let Some(entry_id) = payload_str(&p, "journal_entry_id") {
            postings_by_entry
                .entry(entry_id.to_string())
                .or_default()
                .push(row);
        }
    }
    for rows in postings_by_entry.values_mut() {
        rows.sort_by_key(|p| p.get("position").and_then(|v| v.as_i64()).unwrap_or(0));
    }

    let mut filtered: Vec<(DateTime<Utc>, Value)> = Vec::new();
    for (id, p) in entries {
        let Some(date) = payload_str(&p, "date").and_then(parse_iso) else {
            continue;
        };
        if let Some(b) = from {
            if date < b {
                continue;
            }
        }
        if let Some(b) = to {
            if date > b {
                continue;
            }
        }
        let legs = postings_by_entry.get(&id).cloned().unwrap_or_default();
        if let Some(needle) = unit {
            if !legs
                .iter()
                .any(|leg| payload_str(leg, "unit") == Some(needle))
            {
                continue;
            }
        }
        if let Some(needle) = account_id {
            if !legs
                .iter()
                .any(|leg| payload_str(leg, "account_id") == Some(needle))
            {
                continue;
            }
        }
        let mut row = p.clone();
        if let Some(obj) = row.as_object_mut() {
            obj.insert("id".into(), Value::String(id));
            obj.insert("postings".into(), Value::Array(legs));
        }
        filtered.push((date, row));
    }
    filtered.sort_by_key(|b| std::cmp::Reverse(b.0));
    let truncated = filtered.len() > limit;
    filtered.truncate(limit);
    let items: Vec<Value> = filtered.into_iter().map(|(_, v)| v).collect();
    Ok(json!({
        "journal_entries": items,
        "truncated":    truncated,
    }))
}

// ---------------------------------------------------------------------------
// compute_xirr — see `xirr` submodule for the Newton-Raphson core (Wave 25).
// ---------------------------------------------------------------------------

mod xirr;
use self::xirr::{xirr, CashFlow};

async fn compute_xirr(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    let scope = input
        .get("scope")
        .and_then(|v| v.as_str())
        .unwrap_or("portfolio");
    let asset_filter = input.get("asset_id").and_then(|v| v.as_str());
    if scope == "asset" && asset_filter.is_none() {
        return Err(AppError::BadRequest(
            "compute_xirr scope=asset requires asset_id".into(),
        ));
    }
    let from = input
        .get("from")
        .and_then(|v| v.as_str())
        .and_then(parse_iso);
    let to = input.get("to").and_then(|v| v.as_str()).and_then(parse_iso);
    let base_currency = requested_base_currency(input, ctx.portfolio_snapshot);
    let snapshot_base = snapshot_base_currency(ctx.portfolio_snapshot).map(|s| s.to_uppercase());

    let assets = load_payloads(ctx.db, ctx.user_id, "assets").await?;
    let asset_ids: std::collections::HashSet<String> =
        assets.iter().map(|(id, _)| id.clone()).collect();
    let entries = load_payloads(ctx.db, ctx.user_id, "journal_entries").await?;
    let postings = load_payloads(ctx.db, ctx.user_id, "postings").await?;
    let mut postings_by_entry: std::collections::HashMap<String, Vec<&Value>> =
        std::collections::HashMap::new();
    for (_, p) in &postings {
        if let Some(entry_id) = payload_str(p, "journal_entry_id") {
            postings_by_entry
                .entry(entry_id.to_string())
                .or_default()
                .push(p);
        }
    }
    let mut flows: Vec<CashFlow> = Vec::new();
    let mut currency: Option<String> = None;
    let mut conversion_gaps: Vec<Value> = Vec::new();
    let mut residual_qty: f64 = 0.0;
    let mut last_price: f64 = 0.0;
    for (entry_id, entry) in &entries {
        let Some(date) = payload_str(entry, "date").and_then(parse_iso) else {
            continue;
        };
        if let Some(b) = from {
            if date < b {
                continue;
            }
        }
        if let Some(b) = to {
            if date > b {
                continue;
            }
        }
        let legs = postings_by_entry.get(entry_id).cloned().unwrap_or_default();
        if scope == "asset" {
            let Some(asset_id) = asset_filter else {
                continue;
            };
            if !legs
                .iter()
                .any(|p| payload_str(p, "unit") == Some(asset_id))
            {
                continue;
            }
        }
        let mut cash_flow = 0.0;
        for p in legs.iter() {
            let Some(unit) = payload_str(p, "unit") else {
                continue;
            };
            if asset_ids.contains(unit) {
                continue;
            }
            let amount = payload_num(p, "units").unwrap_or(0.0);
            if let Some(base) = &base_currency {
                if unit.eq_ignore_ascii_case(base) {
                    cash_flow += amount;
                } else {
                    conversion_gaps.push(json!({
                        "date": date.to_rfc3339(),
                        "unit": unit,
                        "amount": amount,
                        "reason": "missing_fx_rate_or_snapshot_cash_conversion",
                    }));
                }
            } else {
                cash_flow += amount;
            }
        }
        if cash_flow.abs() > 1e-12 {
            flows.push(CashFlow {
                when: date,
                amount: cash_flow,
            });
        }
        if currency.is_none() {
            currency = if let Some(base) = &base_currency {
                Some(base.clone())
            } else {
                legs.iter().find_map(|p| {
                    let unit = payload_str(p, "unit")?;
                    (!asset_ids.contains(unit)).then(|| unit.to_string())
                })
            };
        }
        if scope == "asset" {
            let asset_id = asset_filter.unwrap();
            for p in &legs {
                if payload_str(p, "unit") != Some(asset_id) {
                    continue;
                }
                let qty = payload_num(p, "units").unwrap_or(0.0);
                residual_qty += qty;
                if let Some(price) =
                    payload_num(p, "price_per_unit").or_else(|| payload_num(p, "cost_per_unit"))
                {
                    last_price = price.max(last_price);
                }
            }
        }
    }

    if scope == "asset" && residual_qty > 0.0 {
        let terminal = to.unwrap_or_else(Utc::now);
        let snapshot_terminal = base_currency.as_deref().and_then(|base| {
            if snapshot_base.as_deref() != Some(base) {
                return None;
            }
            let asset_id = asset_filter?;
            snapshot_holdings(ctx.portfolio_snapshot)?
                .get(asset_id)
                .and_then(|h| holding_value_base(h, "market_value_base", base))
        });
        let terminal_amount =
            snapshot_terminal.or_else(|| (last_price > 0.0).then_some(residual_qty * last_price));
        if let Some(amount) = terminal_amount {
            flows.push(CashFlow {
                when: terminal,
                amount,
            });
        }
    }

    let rate = xirr(&flows);
    Ok(json!({
        "scope":         scope,
        "asset_id":      asset_filter,
        "from":          from.map(|d| d.to_rfc3339()),
        "to":            to.map(|d| d.to_rfc3339()),
        "rate":          rate,
        "flows":         flows.iter().map(|f| json!({"date": f.when.to_rfc3339(), "amount": f.amount})).collect::<Vec<_>>(),
        "currency":      currency,
        "base_currency": base_currency,
        "conversion_source": if conversion_gaps.is_empty() { "native_or_snapshot_base" } else { "partial" },
        "conversion_gaps": conversion_gaps,
        "approximation": true,
        "note":          "Newton 法近似；指定 base_currency 时仅汇总同币种现金流，并优先使用客户端 snapshot 的期末 base 市值。conversion_gaps 列出缺少 FX 的现金流。",
    }))
}

// ---------------------------------------------------------------------------
// compute_net_worth — sample cumulative cash flow at granularity points.
// ---------------------------------------------------------------------------

fn next_step(d: DateTime<Utc>, granularity: &str) -> DateTime<Utc> {
    match granularity {
        "day" => d + Duration::days(1),
        "week" => d + Duration::days(7),
        _ => {
            // month: bump month, clamp day to 28 to avoid month-overflow.
            let mut y = d.year();
            let mut m = d.month() + 1;
            if m > 12 {
                m = 1;
                y += 1;
            }
            DateTime::parse_from_rfc3339(&format!("{:04}-{:02}-01T00:00:00Z", y, m))
                .map(|x| x.with_timezone(&Utc))
                .unwrap_or(d + Duration::days(30))
        }
    }
}

async fn compute_net_worth(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    let granularity = input
        .get("granularity")
        .and_then(|v| v.as_str())
        .unwrap_or("month");

    // Wave 7: month 走 net_worth_snapshot (monthly)
    // Wave 14: day/week 走 net_worth_daily —— inline path now retired.
    // 任何其他 granularity 字符串 fall through 到 inline 兜底逻辑。
    match granularity {
        "month" => return compute_net_worth_monthly(ctx, input).await,
        "day" | "week" => return compute_net_worth_from_daily(ctx, input, granularity).await,
        _ => {} // fall through to inline
    }

    let now = Utc::now();
    let from = input
        .get("from")
        .and_then(|v| v.as_str())
        .and_then(parse_iso)
        .unwrap_or(now - Duration::days(365));
    let to = input
        .get("to")
        .and_then(|v| v.as_str())
        .and_then(parse_iso)
        .unwrap_or(now);
    let base_currency = requested_base_currency(input, ctx.portfolio_snapshot);

    let assets = load_payloads(ctx.db, ctx.user_id, "assets").await?;
    let asset_ids: std::collections::HashSet<String> =
        assets.iter().map(|(id, _)| id.clone()).collect();
    let entries = load_payloads(ctx.db, ctx.user_id, "journal_entries").await?;
    let postings = load_payloads(ctx.db, ctx.user_id, "postings").await?;
    let liabilities = load_payloads(ctx.db, ctx.user_id, "liabilities").await?;

    let entry_dates: std::collections::HashMap<String, DateTime<Utc>> = entries
        .iter()
        .filter_map(|(id, p)| {
            payload_str(p, "date")
                .and_then(parse_iso)
                .map(|d| (id.clone(), d))
        })
        .collect();

    // Cash position ≈ cumulative fiat postings up to t.
    let mut events: Vec<(DateTime<Utc>, f64, Option<String>)> = Vec::new();
    let mut conversion_gaps: Vec<Value> = Vec::new();
    for (_, p) in &postings {
        let Some(unit) = payload_str(p, "unit") else {
            continue;
        };
        if asset_ids.contains(unit) {
            continue;
        }
        let Some(entry_id) = payload_str(p, "journal_entry_id") else {
            continue;
        };
        let Some(date) = entry_dates.get(entry_id).copied() else {
            continue;
        };
        let amount = payload_num(p, "units").unwrap_or(0.0);
        if let Some(base) = &base_currency {
            if !unit.eq_ignore_ascii_case(base) {
                conversion_gaps.push(json!({
                    "date": date.to_rfc3339(),
                    "unit": unit,
                    "amount": amount,
                    "reason": "missing_fx_rate_or_snapshot_cash_conversion",
                }));
                continue;
            }
        }
        events.push((date, amount, Some(unit.to_string())));
    }
    events.sort_by_key(|a| a.0);

    let total_liabilities: f64 = liabilities
        .iter()
        .map(|(_, p)| payload_num(p, "principal").unwrap_or(0.0))
        .sum();
    let current_holdings_base = base_currency
        .as_deref()
        .and_then(|base| snapshot_total_base(ctx.portfolio_snapshot, "market_value_base", base));

    let mut series = Vec::new();
    let mut cursor = from;
    let mut idx = 0usize;
    let mut running = 0.0f64;
    let mut currency: Option<String> = None;
    while cursor <= to {
        while idx < events.len() && events[idx].0 <= cursor {
            running += events[idx].1;
            if currency.is_none() {
                currency = events[idx].2.clone();
            }
            idx += 1;
        }
        let value = running - total_liabilities;
        series.push(json!({
            "date":     cursor.to_rfc3339(),
            "value":    value,
            "currency": currency,
            "base_currency": base_currency.as_deref(),
        }));
        let next = next_step(cursor, granularity);
        if next == cursor {
            break;
        }
        cursor = next;
    }

    Ok(json!({
        "from":          from.to_rfc3339(),
        "to":            to.to_rfc3339(),
        "granularity":   granularity,
        "series":        series,
        "base_currency": base_currency.as_deref(),
        "current_snapshot": current_holdings_base.map(|holdings| json!({
            "as_of": ctx.portfolio_snapshot.and_then(|s| s.get("as_of")).and_then(|v| v.as_str()),
            "holdings_market_value_base": holdings,
            "base_currency": base_currency.as_deref(),
            "source": "client_portfolio_snapshot",
        })),
        "conversion_source": if conversion_gaps.is_empty() { "native_or_snapshot_base" } else { "partial" },
        "conversion_gaps": conversion_gaps,
        "approximation": true,
        "note":          "使用累计现金流 - 当前负债余额近似净资产；指定 base_currency 时只汇总同币种现金流，并附带客户端 snapshot 的当前持仓 base 市值。conversion_gaps 列出缺少 FX 的现金流。",
    }))
}

// ---------------------------------------------------------------------------
// compute_net_worth — Read Model 主通道（day / week）
// ---------------------------------------------------------------------------

async fn compute_net_worth_from_daily(
    ctx: &ToolCtx<'_>,
    input: &Value,
    granularity: &str,
) -> Result<Value, AppError> {
    use super::read_models::net_worth_daily::{query_range, NetWorthDaily};
    use super::read_models::projection::ensure_fresh;

    let now = Utc::now();
    let from = input
        .get("from")
        .and_then(|v| v.as_str())
        .and_then(parse_iso)
        .unwrap_or(now - Duration::days(90));
    let to = input
        .get("to")
        .and_then(|v| v.as_str())
        .and_then(parse_iso)
        .unwrap_or(now);
    let base_currency = requested_base_currency(input, ctx.portfolio_snapshot);

    let proj = NetWorthDaily;
    let freshness = ensure_fresh(ctx.db, ctx.user_id, &proj).await?;

    let from_str = format!("{:04}-{:02}-{:02}", from.year(), from.month(), from.day());
    let to_str = format!("{:04}-{:02}-{:02}", to.year(), to.month(), to.day());

    let rows = query_range(
        ctx.db,
        ctx.user_id,
        &from_str,
        &to_str,
        base_currency.as_deref(),
    )
    .await?;

    // 负债 inline（balance 模型不在 read_model 范围）
    let liabilities = load_payloads(ctx.db, ctx.user_id, "liabilities").await?;
    let total_liabilities: f64 = liabilities
        .iter()
        .map(|(_, p)| payload_num(p, "principal").unwrap_or(0.0))
        .sum();

    let current_holdings_base = base_currency
        .as_deref()
        .and_then(|base| snapshot_total_base(ctx.portfolio_snapshot, "market_value_base", base));

    // Week granularity: 重采样 —— 选 date 与 `from` 相隔 7n 天的行。
    // Day granularity: 直接全部输出。
    let series: Vec<Value> = if granularity == "week" {
        let mut out: Vec<Value> = Vec::new();
        let from_naive = from.date_naive();
        for r in &rows {
            let Some(d) = chrono::NaiveDate::parse_from_str(&r.yyyy_mm_dd, "%Y-%m-%d").ok() else {
                continue;
            };
            let days = (d - from_naive).num_days();
            if days < 0 || days % 7 != 0 {
                continue;
            }
            let value = (r.cumulative_minor as f64) / 100.0 - total_liabilities;
            out.push(json!({
                "date":          format!("{}T00:00:00+00:00", r.yyyy_mm_dd),
                "value":         value,
                "currency":      r.currency,
                "base_currency": base_currency.as_deref(),
            }));
        }
        out
    } else {
        // day
        rows.iter()
            .map(|r| {
                let value = (r.cumulative_minor as f64) / 100.0 - total_liabilities;
                json!({
                    "date":          format!("{}T00:00:00+00:00", r.yyyy_mm_dd),
                    "value":         value,
                    "currency":      r.currency,
                    "base_currency": base_currency.as_deref(),
                })
            })
            .collect()
    };

    Ok(json!({
        "from":          from.to_rfc3339(),
        "to":            to.to_rfc3339(),
        "granularity":   granularity,
        "series":        series,
        "base_currency": base_currency.as_deref(),
        "current_snapshot": current_holdings_base.map(|holdings| json!({
            "as_of": ctx.portfolio_snapshot.and_then(|s| s.get("as_of")).and_then(|v| v.as_str()),
            "holdings_market_value_base": holdings,
            "base_currency": base_currency.as_deref(),
            "source": "client_portfolio_snapshot",
        })),
        "conversion_source": "read_model",
        "freshness":     freshness,
        "approximation": true,
        "note":          "数据源 net_worth_daily Read Model（day 粒度 + week 重采样）；负债仍 inline 算。指定 base_currency 时只取同币种行。",
    }))
}

// ---------------------------------------------------------------------------
// compute_net_worth — Read Model 主通道（granularity=month）
// ---------------------------------------------------------------------------

async fn compute_net_worth_monthly(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::net_worth_snapshot::{query_range, NetWorthSnapshot};
    use super::read_models::projection::ensure_fresh;

    let now = Utc::now();
    let from = input
        .get("from")
        .and_then(|v| v.as_str())
        .and_then(parse_iso)
        .unwrap_or(now - Duration::days(365));
    let to = input
        .get("to")
        .and_then(|v| v.as_str())
        .and_then(parse_iso)
        .unwrap_or(now);
    let base_currency = requested_base_currency(input, ctx.portfolio_snapshot);

    let proj = NetWorthSnapshot;
    let freshness = ensure_fresh(ctx.db, ctx.user_id, &proj).await?;

    let from_ym = format!("{:04}-{:02}", from.year(), from.month());
    let to_ym = format!("{:04}-{:02}", to.year(), to.month());

    let rows = query_range(
        ctx.db,
        ctx.user_id,
        &from_ym,
        &to_ym,
        base_currency.as_deref(),
    )
    .await?;

    // 负债仍 inline 算（balance 模型不在 read_model 范围；§4.3.2 表脚注）
    let liabilities = load_payloads(ctx.db, ctx.user_id, "liabilities").await?;
    let total_liabilities: f64 = liabilities
        .iter()
        .map(|(_, p)| payload_num(p, "principal").unwrap_or(0.0))
        .sum();

    let current_holdings_base = base_currency
        .as_deref()
        .and_then(|base| snapshot_total_base(ctx.portfolio_snapshot, "market_value_base", base));

    let series: Vec<Value> = rows
        .iter()
        .map(|r| {
            let value = (r.cumulative_minor as f64) / 100.0 - total_liabilities;
            // Read model 月粒度 —— 标记到月初 00:00 UTC，对应 ISO 字符串
            // 与 inline 路径 next_step() 起点一致。
            let date_str = format!("{}-01T00:00:00+00:00", r.year_month);
            json!({
                "date":          date_str,
                "value":         value,
                "currency":      r.currency,
                "base_currency": base_currency.as_deref(),
            })
        })
        .collect();

    Ok(json!({
        "from":          from.to_rfc3339(),
        "to":            to.to_rfc3339(),
        "granularity":   "month",
        "series":        series,
        "base_currency": base_currency.as_deref(),
        "current_snapshot": current_holdings_base.map(|holdings| json!({
            "as_of": ctx.portfolio_snapshot.and_then(|s| s.get("as_of")).and_then(|v| v.as_str()),
            "holdings_market_value_base": holdings,
            "base_currency": base_currency.as_deref(),
            "source": "client_portfolio_snapshot",
        })),
        "conversion_source": "read_model",
        "freshness":     freshness,
        "approximation": true,
        "note":          "数据源 net_worth_snapshot Read Model（月粒度，每币种累计现金流）— 当前负债余额仍是 inline 算；指定 base_currency 时只取同币种行（无 conversion_gaps，未匹配的币种被服务端过滤）。",
    }))
}

// ---------------------------------------------------------------------------
// Breakdown helpers (industry / region / market_cap).
// ---------------------------------------------------------------------------

#[derive(Copy, Clone)]
enum BreakdownDim {
    Industry,
    Region,
    MarketCap,
}

fn dim_label(asset: &Value, dim: BreakdownDim) -> String {
    match dim {
        BreakdownDim::Industry => payload_str(asset, "industry")
            .unwrap_or("unknown")
            .to_string(),
        BreakdownDim::Region => payload_str(asset, "region")
            .unwrap_or("unknown")
            .to_string(),
        BreakdownDim::MarketCap => {
            let raw = payload_str(asset, "metadataJson").unwrap_or("");
            serde_json::from_str::<Value>(raw)
                .ok()
                .as_ref()
                .and_then(|v| v.get("market_cap"))
                .and_then(|v| v.as_str())
                .unwrap_or("unknown")
                .to_string()
        }
    }
}

async fn get_breakdown(ctx: &ToolCtx<'_>, dim: BreakdownDim) -> Result<Value, AppError> {
    // Reuse the holdings tool with an empty input; it already sums cost basis
    // off the holdings_snapshot Read Model (Wave 3, docs/ai-architecture.md §4.3.2).
    // The breakdown is a thin projection over those rows joined with
    // asset metadata; freshness is shared with the underlying read model
    // and propagated through to the caller.
    let holdings = get_holdings(ctx, &Value::Object(Map::new())).await?;
    let assets = load_payloads(ctx.db, ctx.user_id, "assets").await?;
    let asset_lookup: std::collections::HashMap<String, &Value> =
        assets.iter().map(|(k, v)| (k.clone(), v)).collect();

    // Capture freshness + source before we lose ownership at the empty
    // holdings early return.
    let inherited_freshness = holdings.get("freshness").cloned();
    let inherited_source = holdings.get("source").cloned();

    let Some(holdings_obj) = holdings.get("holdings").and_then(|v| v.as_object()) else {
        let mut empty = json!({
            "buckets":       [],
            "approximation": true,
        });
        attach_inherited(&mut empty, inherited_freshness, inherited_source);
        return Ok(empty);
    };

    let mut buckets: std::collections::HashMap<String, (f64, Option<String>)> =
        std::collections::HashMap::new();
    let mut total = 0.0f64;
    let base_currency = holdings
        .get("base_currency")
        .and_then(|v| v.as_str())
        .map(|s| s.to_uppercase());
    for (asset_id, h) in holdings_obj {
        let Some(asset) = asset_lookup.get(asset_id) else {
            continue;
        };
        let cost = base_currency
            .as_deref()
            .and_then(|base| holding_value_base(h, "cost_basis_base", base))
            .or_else(|| h.get("cost_basis").and_then(|v| v.as_f64()))
            .or_else(|| h.get("cost_basis_asset_currency").and_then(value_num))
            .unwrap_or(0.0);
        let currency = base_currency.clone().or_else(|| {
            h.get("currency")
                .or_else(|| h.get("asset_currency"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
        });
        let label = dim_label(asset, dim);
        let entry = buckets.entry(label).or_insert((0.0, None));
        entry.0 += cost;
        if entry.1.is_none() {
            entry.1 = currency;
        }
        total += cost;
    }
    let mut items: Vec<Value> = buckets
        .into_iter()
        .map(|(label, (cost, currency))| {
            json!({
                "label":      label,
                "cost_basis": cost,
                "share":      if total > 0.0 { cost / total } else { 0.0 },
                "currency":   currency,
            })
        })
        .collect();
    items.sort_by(|a, b| {
        b.get("cost_basis")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0)
            .partial_cmp(&a.get("cost_basis").and_then(|v| v.as_f64()).unwrap_or(0.0))
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    let mut out = json!({
        "total":         total,
        "base_currency": base_currency,
        "buckets":       items,
        "approximation": true,
        "note":          "占比基于记账成本；有客户端 snapshot base 成本时使用 base 折算，否则使用原币近似。",
    });
    attach_inherited(&mut out, inherited_freshness, inherited_source);
    Ok(out)
}

/// 把 `get_holdings` 透出的 `freshness` + `source` 字段挂回派生工具
/// 的输出，让 Wave 5/6 的 freshness gate 在 breakdown / risk_alerts
/// 这类「holdings 投影」工具上同样工作。
fn attach_inherited(out: &mut Value, freshness: Option<Value>, source: Option<Value>) {
    if let Value::Object(map) = out {
        if let Some(f) = freshness {
            map.insert("freshness".into(), f);
        }
        if let Some(s) = source {
            map.insert("source".into(), s);
        }
    }
}

// ---------------------------------------------------------------------------
// get_risk_alerts — concentration warnings.
// ---------------------------------------------------------------------------

async fn get_risk_alerts(ctx: &ToolCtx<'_>) -> Result<Value, AppError> {
    let holdings = get_holdings(ctx, &Value::Object(Map::new())).await?;
    // Inherit freshness from holdings; risk_alerts is purely derived
    // (concentration thresholds over the same cost basis).
    let inherited_freshness = holdings.get("freshness").cloned();
    let inherited_source = holdings.get("source").cloned();
    let industry = get_breakdown(ctx, BreakdownDim::Industry).await?;
    let mut alerts: Vec<Value> = Vec::new();
    let total: f64 = holdings
        .get("holdings")
        .and_then(|v| v.as_object())
        .map(|m| {
            m.values()
                .filter_map(|h| {
                    holdings
                        .get("base_currency")
                        .and_then(|v| v.as_str())
                        .and_then(|base| holding_value_base(h, "cost_basis_base", base))
                        .or_else(|| h.get("cost_basis").and_then(|x| x.as_f64()))
                        .or_else(|| h.get("cost_basis_asset_currency").and_then(value_num))
                })
                .sum()
        })
        .unwrap_or(0.0);
    if let Some(map) = holdings.get("holdings").and_then(|v| v.as_object()) {
        for (asset_id, h) in map {
            let cost = holdings
                .get("base_currency")
                .and_then(|v| v.as_str())
                .and_then(|base| holding_value_base(h, "cost_basis_base", base))
                .or_else(|| h.get("cost_basis").and_then(|v| v.as_f64()))
                .or_else(|| h.get("cost_basis_asset_currency").and_then(value_num))
                .unwrap_or(0.0);
            let share = if total > 0.0 { cost / total } else { 0.0 };
            if share > 0.20 {
                alerts.push(json!({
                    "kind":     "asset_concentration",
                    "asset_id": asset_id,
                    "symbol":   h.get("symbol"),
                    "share":    share,
                    "threshold": 0.20,
                    "severity": if share > 0.40 { "high" } else { "medium" },
                    "message":  format!("单一持仓占比 {:.1}% 超过 20% 警戒线", share * 100.0),
                }));
            }
        }
    }
    if let Some(buckets) = industry.get("buckets").and_then(|v| v.as_array()) {
        for b in buckets {
            let share = b.get("share").and_then(|v| v.as_f64()).unwrap_or(0.0);
            if share > 0.20 {
                alerts.push(json!({
                    "kind":     "industry_concentration",
                    "industry": b.get("label"),
                    "share":    share,
                    "threshold": 0.20,
                    "severity": if share > 0.40 { "high" } else { "medium" },
                    "message":  format!("单一行业占比 {:.1}% 超过 20% 警戒线", share * 100.0),
                }));
            }
        }
    }
    let mut out = json!({
        "alerts":        alerts,
        "approximation": true,
    });
    attach_inherited(&mut out, inherited_freshness, inherited_source);
    Ok(out)
}

// ---------------------------------------------------------------------------
// get_asset_allocation — Snapshot P1 (§4.3.2, cloud-projected)
// ---------------------------------------------------------------------------

async fn get_asset_allocation(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::asset_allocation_snapshot::{query_all, AssetAllocationSnapshot};
    use super::read_models::projection::ensure_fresh;
    let bucket_dim = input
        .get("bucket_dim")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty());

    let proj = AssetAllocationSnapshot;
    let freshness = ensure_fresh(ctx.db, ctx.user_id, &proj).await?;
    let buckets = query_all(ctx.db, ctx.user_id, bucket_dim).await?;
    let rows: Vec<Value> = buckets
        .iter()
        .map(|b| {
            json!({
                "bucket_dim":       b.bucket_dim,
                "bucket_key":       b.bucket_key,
                "currency":         b.currency,
                "total_cost_minor": b.total_cost_minor.to_string(),
                "position_count":   b.position_count,
                "weight":           b.weight,
            })
        })
        .collect();
    Ok(json!({
        "buckets":   rows,
        "count":     rows.len(),
        "freshness": freshness,
        "note":      "cost basis（非市值；云端无 FX 源）；weight 在同 currency 内归一。",
    }))
}

// ---------------------------------------------------------------------------
// get_monthly_spend_by_category — Read Model 主通道入口（§4.3）
// ---------------------------------------------------------------------------

async fn get_monthly_spend_by_category(
    ctx: &ToolCtx<'_>,
    input: &Value,
) -> Result<Value, AppError> {
    use super::read_models::monthly_spend_by_category::{query, MonthlySpendByCategory};
    use super::read_models::projection::ensure_fresh;

    let year_month = input
        .get("year_month")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest("year_month required (YYYY-MM)".into()))?;
    if year_month.len() != 7
        || !year_month
            .as_bytes()
            .iter()
            .enumerate()
            .all(|(i, b)| match i {
                0..=3 => b.is_ascii_digit(),
                4 => *b == b'-',
                5..=6 => b.is_ascii_digit(),
                _ => false,
            })
    {
        return Err(AppError::BadRequest("year_month must be YYYY-MM".into()));
    }
    let category = input.get("category").and_then(|v| v.as_str());

    let proj = MonthlySpendByCategory;
    let freshness = ensure_fresh(ctx.db, ctx.user_id, &proj).await?;
    let buckets = query(ctx.db, ctx.user_id, year_month, category).await?;

    let rows: Vec<Value> = buckets
        .iter()
        .map(|b| {
            json!({
                "year_month":  b.year_month,
                "category":    b.category,
                "currency":    b.currency,
                "total_minor": b.total_minor.to_string(),
                "txn_count":   b.txn_count,
            })
        })
        .collect();
    let summary = summarize_buckets(&buckets);

    Ok(json!({
        "year_month": year_month,
        "rows":       rows,
        "summary":    summary,
        "freshness":  freshness,
    }))
}

// ---------------------------------------------------------------------------
// get_net_worth_summary — Read Model 月度净现金流（§4.3.2）
// ---------------------------------------------------------------------------

async fn get_net_worth_summary(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::net_worth_snapshot::{query_range, NetWorthSnapshot};
    use super::read_models::projection::ensure_fresh;

    let months_back = input
        .get("months_back")
        .and_then(|v| v.as_u64())
        .map(|n| n.clamp(1, 60))
        .unwrap_or(12) as i32;
    let currency = input
        .get("currency")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_uppercase())
        .filter(|s| !s.is_empty());

    let proj = NetWorthSnapshot;
    let freshness = ensure_fresh(ctx.db, ctx.user_id, &proj).await?;

    // Compute (from_ym, to_ym) inclusive window ending at current month.
    let now = Utc::now();
    let to_ym = format!("{:04}-{:02}", now.year(), now.month());
    let mut from_y = now.year();
    let mut from_m = now.month() as i32 - (months_back - 1);
    while from_m < 1 {
        from_m += 12;
        from_y -= 1;
    }
    let from_ym = format!("{:04}-{:02}", from_y, from_m);

    let rows = query_range(ctx.db, ctx.user_id, &from_ym, &to_ym, currency.as_deref()).await?;

    let series: Vec<Value> = rows
        .iter()
        .map(|r| {
            json!({
                "year_month":       r.year_month,
                "currency":         r.currency,
                "cumulative_minor": r.cumulative_minor.to_string(),
                "net_flow_minor":   r.net_flow_minor.to_string(),
            })
        })
        .collect();

    Ok(json!({
        "from":      from_ym,
        "to":        to_ym,
        "currency":  currency,
        "series":    series,
        "freshness": freshness,
        "note":      "月粒度；不减负债，不算资产市值。day/week 粒度或负债 / 市值需要 compute_net_worth.",
    }))
}

// ---------------------------------------------------------------------------
// get_xirr_summary — Analytical P2 (§4.3.3, cloud-projected)
// ---------------------------------------------------------------------------

async fn get_xirr_summary(ctx: &ToolCtx<'_>, _input: &Value) -> Result<Value, AppError> {
    use super::read_models::projection::ensure_fresh;
    use super::read_models::xirr_snapshot::{query_all, XirrSnapshot};

    let proj = XirrSnapshot;
    let freshness = ensure_fresh(ctx.db, ctx.user_id, &proj).await?;
    let rows = query_all(ctx.db, ctx.user_id).await?;

    let series: Vec<Value> = rows
        .iter()
        .map(|r| {
            json!({
                "scope":            r.scope,
                "xirr":             r.xirr,
                "flow_count":       r.flow_count,
                "primary_currency": r.primary_currency,
                "multi_currency":   r.multi_currency,
                "approximation":    r.approximation,
            })
        })
        .collect();

    Ok(json!({
        "rows":      series,
        "count":     series.len(),
        "freshness": freshness,
        "source":    "read_model",
        "note":      "全时间窗口 XIRR；自定义 from/to 走 compute_xirr。multi_currency=true 时算法跨币种相加，结果仅作粗略参考。",
    }))
}

// ---------------------------------------------------------------------------
// get_anomaly_flags — Analytical P1 (§4.3.3, device-sourced)
// ---------------------------------------------------------------------------

async fn get_anomaly_flags(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::anomaly_flags::{current_freshness, query_all};

    let severity_min = input
        .get("severity_min")
        .and_then(|v| v.as_str())
        .filter(|s| matches!(*s, "info" | "warn" | "critical"));

    let freshness = current_freshness(ctx.db, ctx.user_id).await?;
    let rows = query_all(ctx.db, ctx.user_id, severity_min).await?;

    let flags: Vec<Value> = rows
        .iter()
        .map(|r| {
            json!({
                "id":          r.id,
                "category":    r.category,
                "kind":        r.kind,
                "delta_pct":   r.delta_pct,
                "severity":    r.severity,
                "detected_at": r.detected_at,
                "payload":     r.payload,
            })
        })
        .collect();

    Ok(json!({
        "flags":     flags,
        "count":     flags.len(),
        "freshness": freshness,
        "source":    "device_analytical_read_model",
        "note":      "device-sourced：端侧 detector 检测，通过 ContextPack.analytical_uploads 上报。空结果可能是端侧还没上报 / 没有异常。",
    }))
}

// ---------------------------------------------------------------------------
// get_refund_links / get_transfer_links — Analytical P1 (§4.3.3, device-sourced)
// ---------------------------------------------------------------------------

async fn get_refund_links(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::refund_links::{current_freshness, query_all};
    let currency = input
        .get("currency")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_uppercase())
        .filter(|s| !s.is_empty());
    let freshness = current_freshness(ctx.db, ctx.user_id).await?;
    let rows = query_all(ctx.db, ctx.user_id, currency.as_deref()).await?;
    let links: Vec<Value> = rows
        .iter()
        .map(|r| {
            json!({
                "id":              r.id,
                "original_txn_id": r.original_txn_id,
                "refund_txn_id":   r.refund_txn_id,
                "amount_minor":    r.amount_minor.map(|n| n.to_string()),
                "currency":        r.currency,
                "payload":         r.payload,
            })
        })
        .collect();
    Ok(json!({
        "links":     links,
        "count":     links.len(),
        "freshness": freshness,
        "source":    "device_analytical_read_model",
        "note":      "device-sourced：端侧 refundMatcher 检测，通过 ContextPack.analytical_uploads 上报。空结果可能是端侧没检到或没退款。",
    }))
}

async fn get_transfer_links(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::transfer_links::{current_freshness, query_all};
    let currency = input
        .get("currency")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_uppercase())
        .filter(|s| !s.is_empty());
    let freshness = current_freshness(ctx.db, ctx.user_id).await?;
    let rows = query_all(ctx.db, ctx.user_id, currency.as_deref()).await?;
    let links: Vec<Value> = rows
        .iter()
        .map(|r| {
            json!({
                "id":           r.id,
                "from_txn_id":  r.from_txn_id,
                "to_txn_id":    r.to_txn_id,
                "amount_minor": r.amount_minor.map(|n| n.to_string()),
                "currency":     r.currency,
                "payload":      r.payload,
            })
        })
        .collect();
    Ok(json!({
        "links":     links,
        "count":     links.len(),
        "freshness": freshness,
        "source":    "device_analytical_read_model",
        "note":      "device-sourced：端侧 transferMatcher 检测（同币种 + ±2 天窗口 + 50 minor 容差）。空结果可能是端侧没检到。",
    }))
}

// ---------------------------------------------------------------------------
// get_subscription_changes — Analytical P1 (§4.3.3, device-sourced)
// ---------------------------------------------------------------------------

async fn get_subscription_changes(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::subscription_changes::{current_freshness, query_all};
    let currency = input
        .get("currency")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_uppercase())
        .filter(|s| !s.is_empty());
    let freshness = current_freshness(ctx.db, ctx.user_id).await?;
    let rows = query_all(ctx.db, ctx.user_id, currency.as_deref()).await?;
    let changes: Vec<Value> = rows
        .iter()
        .map(|r| {
            json!({
                "id":                 r.id,
                "merchant_key":       r.merchant_key,
                "cadence":            r.cadence,
                "currency":           r.currency,
                "prev_amount_minor":  r.prev_amount_minor.map(|n| n.to_string()),
                "new_amount_minor":   r.new_amount_minor.map(|n| n.to_string()),
                "delta_ratio":        r.delta_ratio,
                "since":              r.since,
                "payload":            r.payload,
            })
        })
        .collect();
    Ok(json!({
        "changes":   changes,
        "count":     changes.len(),
        "freshness": freshness,
        "source":    "device_analytical_read_model",
        "note":      "device-sourced：端侧 detectSubscriptionChanges 在本次 chat 上报的 expense 窗口内对比 earlier vs later median。跨会话历史需要 OpLog 持久化 recurring_patterns 后扩展。",
    }))
}

// ---------------------------------------------------------------------------
// get_investment_performance — Analytical P1 (§4.3.3, device-sourced)
// ---------------------------------------------------------------------------

async fn get_investment_performance(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::investment_performance::{current_freshness, query_all};
    let base_currency = input
        .get("base_currency")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_uppercase())
        .filter(|s| !s.is_empty());
    let freshness = current_freshness(ctx.db, ctx.user_id).await?;
    let rows = query_all(ctx.db, ctx.user_id, base_currency.as_deref()).await?;
    let assets: Vec<Value> = rows
        .iter()
        .map(|r| {
            json!({
                "id":                  r.id,
                "asset_id":            r.asset_id,
                "asset_currency":      r.asset_currency,
                "base_currency":       r.base_currency,
                "market_value_base":   r.market_value_base,
                "cost_basis_base":     r.cost_basis_base,
                "unrealized_pnl_base": r.unrealized_pnl_base,
                "weight":              r.weight,
                "holding_days":        r.holding_days,
                "as_of":               r.as_of,
                "payload":             r.payload,
            })
        })
        .collect();
    Ok(json!({
        "assets":    assets,
        "count":     assets.len(),
        "freshness": freshness,
        "source":    "device_analytical_read_model",
        "note":      "device-sourced：端侧 holdingsSnapshotProvider 算出 per-asset 持仓快照后上报。decimal 字段为字符串避免精度丢失。XIRR 不在此 read model，走 get_xirr_summary。",
    }))
}

// ---------------------------------------------------------------------------
// get_recurring_patterns — Analytical P1 (§4.3.3, device-sourced)
// ---------------------------------------------------------------------------

async fn get_recurring_patterns(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::recurring_patterns::{current_freshness, query_all};

    let currency = input
        .get("currency")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_uppercase())
        .filter(|s| !s.is_empty());
    let cadence = input
        .get("cadence")
        .and_then(|v| v.as_str())
        .filter(|s| matches!(*s, "weekly" | "monthly"));

    // device-sourced：没有 ensure_fresh —— 端侧通过下一次 chat 的
    // analytical_uploads 上报新结果；本工具只读最新已知的快照。
    let freshness = current_freshness(ctx.db, ctx.user_id).await?;
    let rows = query_all(ctx.db, ctx.user_id, currency.as_deref(), cadence).await?;

    let patterns: Vec<Value> = rows
        .iter()
        .map(|r| {
            json!({
                "id":                  r.id,
                "merchant_key":        r.merchant_key,
                "cadence":             r.cadence,
                "currency":            r.currency,
                "median_amount_minor": r.median_amount_minor.map(|n| n.to_string()),
                "occurrences":         r.occurrences,
                "last_seen_at":        r.last_seen_at,
                "payload":             r.payload,
            })
        })
        .collect();

    Ok(json!({
        "patterns":  patterns,
        "count":     patterns.len(),
        "freshness": freshness,
        "source":    "device_analytical_read_model",
        "note":      "device-sourced：端侧 recurring_detector 检测，通过 ContextPack.analytical_uploads 上报。当结果为空时，可能是端侧还没上报过 / 端侧检测不到稳定周期 / 用户没有订阅。",
    }))
}

// ---------------------------------------------------------------------------
// get_cashflow_buckets — Read Model P1（§4.3.2）
// ---------------------------------------------------------------------------

async fn get_cashflow_buckets(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::cashflow_buckets::{query_range, CashflowBuckets};
    use super::read_models::projection::ensure_fresh;

    let months_back = input
        .get("months_back")
        .and_then(|v| v.as_u64())
        .map(|n| n.clamp(1, 24))
        .unwrap_or(6) as i32;
    let currency = input
        .get("currency")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_uppercase())
        .filter(|s| !s.is_empty());

    let proj = CashflowBuckets;
    let freshness = ensure_fresh(ctx.db, ctx.user_id, &proj).await?;

    let now = Utc::now();
    let to_ym = format!("{:04}-{:02}", now.year(), now.month());
    let mut from_y = now.year();
    let mut from_m = now.month() as i32 - (months_back - 1);
    while from_m < 1 {
        from_m += 12;
        from_y -= 1;
    }
    let from_ym = format!("{:04}-{:02}", from_y, from_m);

    let rows = query_range(ctx.db, ctx.user_id, &from_ym, &to_ym, currency.as_deref()).await?;

    let series: Vec<Value> = rows
        .iter()
        .map(|r| {
            let net = r.inflow_minor - r.outflow_minor;
            json!({
                "year_month":     r.year_month,
                "currency":       r.currency,
                "inflow_minor":   r.inflow_minor.to_string(),
                "outflow_minor":  r.outflow_minor.to_string(),
                "net_minor":      net.to_string(),
                "inflow_count":   r.inflow_count,
                "outflow_count":  r.outflow_count,
            })
        })
        .collect();

    Ok(json!({
        "from":      from_ym,
        "to":        to_ym,
        "currency":  currency,
        "series":    series,
        "freshness": freshness,
        "source":    "read_model",
        "note":      "月粒度 inflow / outflow 分桶；net_minor = inflow - outflow（与 net_worth_snapshot.net_flow 同源但形态不同，本工具拆分桶不累计）。",
    }))
}

// ---------------------------------------------------------------------------
// read_category_window — Scoped Detail (§4.3.4)
// ---------------------------------------------------------------------------

async fn read_category_window(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::scoped_detail::category_window;
    let parsed = category_window::parse_input(input)?;
    category_window::run(ctx.db, ctx.user_id, &parsed).await
}

async fn read_account_window(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::scoped_detail::account_window;
    let parsed = account_window::parse_input(input)?;
    account_window::run(ctx.db, ctx.user_id, &parsed).await
}

async fn read_asset_window(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use super::read_models::scoped_detail::asset_window;
    let parsed = asset_window::parse_input(input)?;
    asset_window::run(ctx.db, ctx.user_id, &parsed).await
}

fn summarize_buckets(buckets: &[super::read_models::monthly_spend_by_category::Bucket]) -> Value {
    use std::collections::BTreeMap;
    // 按币种合计；不跨币种汇总（避免假装会 FX）。
    let mut by_currency: BTreeMap<&str, (i128, u32)> = BTreeMap::new();
    for b in buckets {
        let entry = by_currency.entry(b.currency.as_str()).or_insert((0, 0));
        entry.0 += b.total_minor as i128;
        entry.1 += b.txn_count;
    }
    let totals: Vec<Value> = by_currency
        .into_iter()
        .map(|(c, (total, count))| {
            json!({
                "currency":    c,
                "total_minor": total.to_string(),
                "txn_count":   count,
            })
        })
        .collect();
    json!({
        "row_count": buckets.len(),
        "by_currency": totals,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn policy_denied_result_has_stable_shape() {
        // The model side branches on `error.code == "policy_denied"`,
        // so this shape is a wire contract.
        let v = policy_denied_result(
            "get_journal_entries",
            &super::super::policy::PolicyReason::UnknownTool,
        );
        assert_eq!(v["error"]["code"], "policy_denied");
        assert_eq!(v["error"]["tool"], "get_journal_entries");
        assert_eq!(v["error"]["policy"], "unknown_tool");
        assert_eq!(v["policy_denied"], true);
        // Message is human-readable, non-empty.
        assert!(v["error"]["message"].as_str().unwrap().len() > 5);
    }

    #[test]
    fn policy_denied_result_distinguishes_reasons() {
        let v1 = policy_denied_result(
            "x",
            &super::super::policy::PolicyReason::ExternalWriteRequiresConsent,
        );
        let v2 = policy_denied_result(
            "x",
            &super::super::policy::PolicyReason::ContextTierTooLow {
                client: BudgetTier::Small,
                required: BudgetTier::Standard,
            },
        );
        assert_eq!(v1["error"]["policy"], "external_write_requires_consent");
        assert_eq!(v2["error"]["policy"], "context_tier_too_low");
    }

    // Wave 25: xirr core tests live with the implementation in
    // `tools/xirr.rs`. Tests here exercise the dispatcher's surrounding
    // behaviour, not the algorithm.

    #[test]
    fn snapshot_total_base_sums_string_base_values() {
        let snapshot = json!({
            "base_currency": "CNY",
            "holdings": {
                "a": {"base_currency": "CNY", "market_value_base": "12.5"},
                "b": {"base_currency": "CNY", "market_value_base": 7.5}
            }
        });
        assert_eq!(
            snapshot_total_base(Some(&snapshot), "market_value_base", "CNY"),
            Some(20.0)
        );
    }

    #[test]
    fn snapshot_total_base_rejects_wrong_base_currency() {
        let snapshot = json!({
            "base_currency": "USD",
            "holdings": {
                "a": {"base_currency": "USD", "market_value_base": "12.5"}
            }
        });
        assert_eq!(
            snapshot_total_base(Some(&snapshot), "market_value_base", "CNY"),
            None
        );
    }

    #[test]
    fn schemas_advertise_all_dispatch_targets() {
        // get_journal_entries 已废弃（docs/ai-architecture.md §4.3.4），
        // 不再 advertise schema —— 但 dispatch 仍处理该名以支持旧 chat
        // 续推。新 chat 应当走 read_category_window / Snapshot 工具族。
        let names: Vec<String> = schemas().into_iter().map(|s| s.name).collect();
        for expected in [
            "get_holdings",
            "compute_xirr",
            "compute_net_worth",
            "get_industry_breakdown",
            "get_geo_breakdown",
            "get_market_cap_breakdown",
            "get_risk_alerts",
            "get_monthly_spend_by_category",
            "get_net_worth_summary",
            "get_cashflow_buckets",
            "get_asset_allocation",
            "get_recurring_patterns",
            "get_anomaly_flags",
            "get_refund_links",
            "get_transfer_links",
            "get_investment_performance",
            "get_subscription_changes",
            "get_xirr_summary",
            "read_account_window",
            "read_asset_window",
            "read_category_window",
            "propose_trade",
            "propose_expense",
            "propose_liability_payment",
            "propose_account_create",
            "propose_asset_valuation",
        ] {
            assert!(names.iter().any(|n| n == expected), "missing {expected}");
        }
        assert!(
            !names.iter().any(|n| n == "get_journal_entries"),
            "get_journal_entries should be deprecated (no schema)"
        );
    }

    #[test]
    fn propose_schemas_have_required_fields_marked() {
        let by_name: std::collections::HashMap<String, ToolSchema> =
            schemas().into_iter().map(|s| (s.name.clone(), s)).collect();
        for (name, expected_required) in [
            ("propose_trade", &["type", "quantity"][..]),
            ("propose_expense", &["amount"][..]),
            ("propose_liability_payment", &["amount"][..]),
            ("propose_account_create", &["name", "type"][..]),
            ("propose_asset_valuation", &["new_value"][..]),
        ] {
            let schema = by_name.get(name).expect(name);
            let req = schema
                .input_schema
                .get("required")
                .and_then(|v| v.as_array())
                .unwrap_or_else(|| panic!("{name} missing required[]"));
            for f in expected_required {
                assert!(
                    req.iter().any(|v| v.as_str() == Some(*f)),
                    "{name} required[] missing {f}"
                );
            }
        }
    }
}
