//! Function-calling tool surface exposed to the LLM.
//!
//! The model is forbidden from inventing financial values (see
//! `guardrails::SYSTEM_PROMPT`). Instead it calls one of the tools defined
//! here — the dispatcher reads the user's synced data from D1, computes
//! the answer server-side, and returns a structured JSON document. Tool
//! outputs are deterministic given the data, so the user can trust that any
//! number echoed by the assistant came out of [`dispatch`], not the model's
//! head.
//!
//! ## Design
//!
//! - All tools take a `ToolCtx` (user id + D1 handle) and a JSON `input`
//!   (already validated by Anthropic against `ToolSchema::input_schema`).
//! - Computations run off the materialised sync tables (`assets`,
//!   `transactions`, etc.), parsing the JSON `payload` column into a
//!   serde_json::Value. The mobile client owns the canonical types; we keep
//!   the server side schema-light so a payload field added on mobile shows
//!   up here without a backend deploy.
//! - Money is reported in the user's recorded currency on each row. We do
//!   *not* fabricate cross-currency totals — multi-currency consolidation
//!   needs FX rates and is an explicit follow-up. The system prompt warns the
//!   model accordingly.
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

use super::anthropic::ToolSchema;
use crate::error::AppError;

pub struct ToolCtx<'a> {
    pub user_id: &'a str,
    pub db: &'a D1Database,
}

/// Static catalogue. Kept as a function (not a `static` constant) because
/// `ToolSchema` carries `serde_json::Value` and isn't `const`-constructible.
pub fn schemas() -> Vec<ToolSchema> {
    vec![
        ToolSchema {
            name: "get_holdings".into(),
            description: "返回当前持仓快照：每个资产的累计买入数量、累计卖出数量、净持仓、记账成本与币种。\
                          数量与成本仅基于 transactions 求和，未做拆股 / 公司行为调整，结果带 approximation=true。".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "as_of": {
                        "type": "string",
                        "description": "ISO-8601 截止时刻（含），不传则到当前时间。"
                    }
                }
            }),
        },
        ToolSchema {
            name: "get_transactions".into(),
            description: "查询交易历史，支持按资产、账户、类型、日期范围过滤，并按 trade_date 降序返回。".into(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "asset_id":   { "type": "string" },
                    "account_id": { "type": "string" },
                    "type":       { "type": "string", "description": "transaction type, e.g. buy/sell/dividend" },
                    "from":       { "type": "string", "description": "ISO-8601 lower bound (inclusive)" },
                    "to":         { "type": "string", "description": "ISO-8601 upper bound (inclusive)" },
                    "limit":      { "type": "integer", "minimum": 1, "maximum": 200, "default": 50 }
                }
            }),
        },
        ToolSchema {
            name: "compute_xirr".into(),
            description: "对指定范围内的现金流计算 XIRR（年化内部收益率）。\
                          backend 实现为单币种简化版：把买入/卖出/分红看作有符号现金流，\
                          以 Newton 法求解贴现率。跨币种或带费用的精确版本由 FIR-55 提供。".into(),
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
                    "to":   { "type": "string", "description": "ISO-8601 upper bound" }
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
                    "granularity": { "type": "string", "enum": ["day", "week", "month"], "default": "month" }
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
    ]
}

/// Dispatch a tool call by name. Returns the JSON result the LLM will see in
/// the next `tool_result` block. Errors here surface to the model as a
/// `tool_result` with `is_error=true` rather than a 500 — the conversation
/// can recover.
pub async fn dispatch(ctx: &ToolCtx<'_>, name: &str, input: &Value) -> Value {
    let result = match name {
        "get_holdings" => get_holdings(ctx, input).await,
        "get_transactions" => get_transactions(ctx, input).await,
        "compute_xirr" => compute_xirr(ctx, input).await,
        "compute_net_worth" => compute_net_worth(ctx, input).await,
        "get_industry_breakdown" => get_breakdown(ctx, BreakdownDim::Industry).await,
        "get_geo_breakdown" => get_breakdown(ctx, BreakdownDim::Region).await,
        "get_market_cap_breakdown" => get_breakdown(ctx, BreakdownDim::MarketCap).await,
        "get_risk_alerts" => get_risk_alerts(ctx).await,
        _ => Err(AppError::BadRequest(format!("unknown tool: {name}"))),
    };
    match result {
        Ok(v) => v,
        Err(e) => json!({
            "error": e.to_string(),
            "code":  e.code(),
        }),
    }
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
    DateTime::parse_from_rfc3339(s).ok().map(|d| d.with_timezone(&Utc))
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

// ---------------------------------------------------------------------------
// get_holdings — sum signed transaction quantities per asset.
// ---------------------------------------------------------------------------

#[derive(Default)]
struct HoldingAcc {
    asset_id: String,
    bought_qty: f64,
    sold_qty: f64,
    cost_basis: f64,
    proceeds: f64,
    currency: Option<String>,
}

fn signed_qty_factor(tx_type: &str) -> Option<(f64, bool)> {
    // (qty sign, is_proceeds_side)
    match tx_type {
        "buy" | "transferIn" | "reinvest" => Some((1.0, false)),
        "sell" | "transferOut" => Some((-1.0, true)),
        _ => None,
    }
}

async fn get_holdings(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    let as_of = input
        .get("as_of")
        .and_then(|v| v.as_str())
        .and_then(parse_iso);
    let assets = load_payloads(ctx.db, ctx.user_id, "assets").await?;
    let txns = load_payloads(ctx.db, ctx.user_id, "transactions").await?;

    let mut accs: Map<String, Value> = Map::new();
    let mut tracker: std::collections::HashMap<String, HoldingAcc> = std::collections::HashMap::new();

    for (_, p) in &txns {
        let Some(asset_id) = payload_str(p, "assetId") else { continue };
        let Some(tx_type) = payload_str(p, "type") else { continue };
        let Some(qty) = payload_num(p, "quantity") else { continue };
        let price = payload_num(p, "price").unwrap_or(0.0);
        let currency = payload_str(p, "currency").map(|s| s.to_string());
        if let Some(date) = payload_str(p, "tradeDate").and_then(parse_iso) {
            if let Some(cutoff) = as_of {
                if date > cutoff {
                    continue;
                }
            }
        }
        let Some((sign, is_proceeds)) = signed_qty_factor(tx_type) else { continue };
        let entry = tracker
            .entry(asset_id.to_string())
            .or_insert_with(|| HoldingAcc {
                asset_id: asset_id.to_string(),
                ..Default::default()
            });
        let signed = qty * sign;
        if signed > 0.0 {
            entry.bought_qty += signed;
            entry.cost_basis += signed * price;
        } else {
            entry.sold_qty += -signed;
            if is_proceeds {
                entry.proceeds += -signed * price;
            }
        }
        if entry.currency.is_none() {
            entry.currency = currency;
        }
    }

    let asset_lookup: std::collections::HashMap<String, &Value> =
        assets.iter().map(|(k, v)| (k.clone(), v)).collect();

    for (id, h) in tracker {
        if h.bought_qty - h.sold_qty <= 0.0 {
            continue;
        }
        let net = h.bought_qty - h.sold_qty;
        let avg_cost = if h.bought_qty > 0.0 {
            h.cost_basis / h.bought_qty
        } else {
            0.0
        };
        let asset = asset_lookup.get(&id);
        accs.insert(
            id.clone(),
            json!({
                "asset_id":     h.asset_id,
                "symbol":       asset.and_then(|a| payload_str(a, "symbol")),
                "name":         asset.and_then(|a| payload_str(a, "name")),
                "type":         asset.and_then(|a| payload_str(a, "type")),
                "net_quantity": net,
                "avg_unit_cost": avg_cost,
                "cost_basis":   net * avg_cost,
                "currency":     h.currency,
            }),
        );
    }

    Ok(json!({
        "as_of":         as_of.map(|d| d.to_rfc3339()).unwrap_or_else(|| Utc::now().to_rfc3339()),
        "holdings":      Value::Object(accs),
        "approximation": true,
        "note":          "数量为买入累计 - 卖出累计；成本为加权平均买入价。未应用拆股、公司行为或 FIFO/LIFO 调整。"
    }))
}

// ---------------------------------------------------------------------------
// get_transactions — filtered list, newest first.
// ---------------------------------------------------------------------------

async fn get_transactions(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    let asset_id = input.get("asset_id").and_then(|v| v.as_str());
    let account_id = input.get("account_id").and_then(|v| v.as_str());
    let tx_type = input.get("type").and_then(|v| v.as_str());
    let from = input
        .get("from")
        .and_then(|v| v.as_str())
        .and_then(parse_iso);
    let to = input
        .get("to")
        .and_then(|v| v.as_str())
        .and_then(parse_iso);
    let limit = input
        .get("limit")
        .and_then(|v| v.as_u64())
        .unwrap_or(50)
        .min(200) as usize;

    let txns = load_payloads(ctx.db, ctx.user_id, "transactions").await?;
    let mut filtered: Vec<(DateTime<Utc>, Value)> = Vec::new();
    for (id, p) in txns {
        if let Some(needle) = asset_id {
            if payload_str(&p, "assetId") != Some(needle) {
                continue;
            }
        }
        if let Some(needle) = account_id {
            if payload_str(&p, "accountId") != Some(needle) {
                continue;
            }
        }
        if let Some(needle) = tx_type {
            if payload_str(&p, "type") != Some(needle) {
                continue;
            }
        }
        let Some(date) = payload_str(&p, "tradeDate").and_then(parse_iso) else { continue };
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
        let mut row = p.clone();
        if let Some(obj) = row.as_object_mut() {
            obj.insert("id".into(), Value::String(id));
        }
        filtered.push((date, row));
    }
    filtered.sort_by(|a, b| b.0.cmp(&a.0));
    let truncated = filtered.len() > limit;
    filtered.truncate(limit);
    let items: Vec<Value> = filtered.into_iter().map(|(_, v)| v).collect();
    Ok(json!({
        "transactions": items,
        "truncated":    truncated,
    }))
}

// ---------------------------------------------------------------------------
// compute_xirr — Newton-Raphson on the cash-flow series.
// ---------------------------------------------------------------------------

#[derive(Clone, Copy)]
struct CashFlow {
    when: DateTime<Utc>,
    amount: f64,
}

fn cash_flow_amount(tx_type: &str, qty: f64, price: f64, fee: f64) -> Option<f64> {
    match tx_type {
        // Outflows from the user's perspective: negative.
        "buy" | "reinvest" => Some(-(qty * price + fee)),
        // Inflows.
        "sell" => Some(qty * price - fee),
        "dividend" | "interest" => Some(qty * price - fee),
        _ => None,
    }
}

fn xirr(flows: &[CashFlow]) -> Option<f64> {
    if flows.len() < 2 {
        return None;
    }
    // All same sign → XIRR is undefined (no break-even rate).
    let any_pos = flows.iter().any(|f| f.amount > 0.0);
    let any_neg = flows.iter().any(|f| f.amount < 0.0);
    if !(any_pos && any_neg) {
        return None;
    }
    let t0 = flows.iter().map(|f| f.when).min()?;
    let years: Vec<f64> = flows
        .iter()
        .map(|f| (f.when - t0).num_seconds() as f64 / (365.25 * 86400.0))
        .collect();

    let f = |r: f64| -> f64 {
        flows
            .iter()
            .zip(&years)
            .map(|(cf, &t)| cf.amount / (1.0 + r).powf(t))
            .sum()
    };
    let df = |r: f64| -> f64 {
        flows
            .iter()
            .zip(&years)
            .map(|(cf, &t)| -t * cf.amount / (1.0 + r).powf(t + 1.0))
            .sum()
    };
    let mut r = 0.1_f64;
    for _ in 0..64 {
        let val = f(r);
        if val.abs() < 1e-9 {
            return Some(r);
        }
        let d = df(r);
        if d.abs() < 1e-12 {
            return None;
        }
        let next = r - val / d;
        if !next.is_finite() || next <= -0.999_999 {
            return None;
        }
        if (next - r).abs() < 1e-9 {
            return Some(next);
        }
        r = next;
    }
    None
}

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
    let to = input
        .get("to")
        .and_then(|v| v.as_str())
        .and_then(parse_iso);

    let txns = load_payloads(ctx.db, ctx.user_id, "transactions").await?;
    let mut flows: Vec<CashFlow> = Vec::new();
    let mut currency: Option<String> = None;
    let mut residual_qty: f64 = 0.0;
    let mut last_price: f64 = 0.0;
    for (_, p) in &txns {
        let Some(tx_type) = payload_str(p, "type") else { continue };
        if scope == "asset" {
            if payload_str(p, "assetId") != asset_filter {
                continue;
            }
        }
        let Some(date) = payload_str(p, "tradeDate").and_then(parse_iso) else { continue };
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
        let qty = payload_num(p, "quantity").unwrap_or(0.0);
        let price = payload_num(p, "price").unwrap_or(0.0);
        let fee = payload_num(p, "fee").unwrap_or(0.0);
        if let Some(amt) = cash_flow_amount(tx_type, qty, price, fee) {
            flows.push(CashFlow { when: date, amount: amt });
        }
        if currency.is_none() {
            currency = payload_str(p, "currency").map(|s| s.to_string());
        }
        // Track residual units to add a synthetic terminal valuation flow at
        // the asset's last known price — without it XIRR for an asset that's
        // still held is undefined.
        if scope == "asset" {
            match tx_type {
                "buy" | "transferIn" | "reinvest" => residual_qty += qty,
                "sell" | "transferOut" => residual_qty -= qty,
                _ => {}
            }
            last_price = price.max(last_price);
        }
    }

    if scope == "asset" && residual_qty > 0.0 && last_price > 0.0 {
        let terminal = to.unwrap_or_else(Utc::now);
        flows.push(CashFlow {
            when: terminal,
            amount: residual_qty * last_price,
        });
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
        "approximation": true,
        "note":          "单币种 Newton 法近似；持仓未平仓时使用 transactions 中的最高价作为期末估值。",
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
            DateTime::parse_from_rfc3339(&format!(
                "{:04}-{:02}-01T00:00:00Z",
                y, m
            ))
            .map(|x| x.with_timezone(&Utc))
            .unwrap_or(d + Duration::days(30))
        }
    }
}

async fn compute_net_worth(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
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
    let granularity = input
        .get("granularity")
        .and_then(|v| v.as_str())
        .unwrap_or("month");

    let txns = load_payloads(ctx.db, ctx.user_id, "transactions").await?;
    let liabilities = load_payloads(ctx.db, ctx.user_id, "liabilities").await?;

    // Cash position ≈ sum of signed cash transaction amounts up to t.
    // We treat deposits + dividends + interest + sells as +; buys + fees
    // + taxes + withdraws as -.
    let mut events: Vec<(DateTime<Utc>, f64, Option<String>)> = Vec::new();
    for (_, p) in &txns {
        let Some(tx_type) = payload_str(p, "type") else { continue };
        let Some(date) = payload_str(p, "tradeDate").and_then(parse_iso) else { continue };
        let qty = payload_num(p, "quantity").unwrap_or(0.0);
        let price = payload_num(p, "price").unwrap_or(0.0);
        let fee = payload_num(p, "fee").unwrap_or(0.0);
        let tax = payload_num(p, "tax").unwrap_or(0.0);
        let currency = payload_str(p, "currency").map(|s| s.to_string());
        let amount = match tx_type {
            "deposit" | "dividend" | "interest" | "sell" | "transferIn" => {
                qty * price - fee - tax
            }
            "buy" | "reinvest" => -(qty * price + fee + tax),
            "withdraw" | "fee" | "tax" | "liabilityPayment" | "transferOut" => {
                -(qty * price + fee + tax)
            }
            _ => continue,
        };
        events.push((date, amount, currency));
    }
    events.sort_by(|a, b| a.0.cmp(&b.0));

    let total_liabilities: f64 = liabilities
        .iter()
        .map(|(_, p)| payload_num(p, "principal").unwrap_or(0.0))
        .sum();

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
        "approximation": true,
        "note":          "使用累计现金流 - 当前负债余额近似净资产；未做市值重估、跨币种折算或汇率调整。",
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
    // Reuse the holdings tool with an empty input; it already sums cost basis.
    let holdings = get_holdings(ctx, &Value::Object(Map::new())).await?;
    let assets = load_payloads(ctx.db, ctx.user_id, "assets").await?;
    let asset_lookup: std::collections::HashMap<String, &Value> =
        assets.iter().map(|(k, v)| (k.clone(), v)).collect();

    let Some(holdings_obj) = holdings.get("holdings").and_then(|v| v.as_object()) else {
        return Ok(json!({
            "buckets":       [],
            "approximation": true,
        }));
    };

    let mut buckets: std::collections::HashMap<String, (f64, Option<String>)> =
        std::collections::HashMap::new();
    let mut total = 0.0f64;
    for (asset_id, h) in holdings_obj {
        let Some(asset) = asset_lookup.get(asset_id) else { continue };
        let cost = h.get("cost_basis").and_then(|v| v.as_f64()).unwrap_or(0.0);
        let currency = h
            .get("currency")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());
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
    Ok(json!({
        "total":         total,
        "buckets":       items,
        "approximation": true,
        "note":          "占比基于记账成本，未做币种折算。",
    }))
}

// ---------------------------------------------------------------------------
// get_risk_alerts — concentration warnings.
// ---------------------------------------------------------------------------

async fn get_risk_alerts(ctx: &ToolCtx<'_>) -> Result<Value, AppError> {
    let holdings = get_holdings(ctx, &Value::Object(Map::new())).await?;
    let industry = get_breakdown(ctx, BreakdownDim::Industry).await?;
    let mut alerts: Vec<Value> = Vec::new();
    let total: f64 = holdings
        .get("holdings")
        .and_then(|v| v.as_object())
        .map(|m| {
            m.values()
                .filter_map(|h| h.get("cost_basis").and_then(|x| x.as_f64()))
                .sum()
        })
        .unwrap_or(0.0);
    if let Some(map) = holdings.get("holdings").and_then(|v| v.as_object()) {
        for (asset_id, h) in map {
            let cost = h.get("cost_basis").and_then(|v| v.as_f64()).unwrap_or(0.0);
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
    Ok(json!({
        "alerts":        alerts,
        "approximation": true,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xirr_matches_excel_simple_case() {
        // -1000 today, +1100 in one year ≈ 10%.
        let t0 = DateTime::parse_from_rfc3339("2025-01-01T00:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let t1 = DateTime::parse_from_rfc3339("2026-01-01T00:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let rate = xirr(&[
            CashFlow { when: t0, amount: -1000.0 },
            CashFlow { when: t1, amount: 1100.0 },
        ])
        .unwrap();
        assert!((rate - 0.10).abs() < 1e-3, "rate = {rate}");
    }

    #[test]
    fn xirr_returns_none_for_single_sign() {
        let t0 = Utc::now();
        let rate = xirr(&[
            CashFlow { when: t0, amount: -1.0 },
            CashFlow { when: t0 + Duration::days(30), amount: -2.0 },
        ]);
        assert!(rate.is_none());
    }

    #[test]
    fn schemas_advertise_all_dispatch_targets() {
        let names: Vec<String> = schemas().into_iter().map(|s| s.name).collect();
        for expected in [
            "get_holdings",
            "get_transactions",
            "compute_xirr",
            "compute_net_worth",
            "get_industry_breakdown",
            "get_geo_breakdown",
            "get_market_cap_breakdown",
            "get_risk_alerts",
        ] {
            assert!(names.iter().any(|n| n == expected), "missing {expected}");
        }
    }
}
