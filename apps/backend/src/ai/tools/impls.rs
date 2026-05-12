use chrono::{DateTime, Datelike, Duration, Utc};
use serde::Deserialize;
use serde_json::{json, Map, Value};
use worker::{D1Database, D1Type};

use super::ToolCtx;
use crate::error::AppError;

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

pub(crate) async fn get_holdings(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use crate::ai::read_models::holdings_snapshot::{query_all, HoldingsSnapshot};
    use crate::ai::read_models::projection::ensure_fresh;

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

pub(crate) async fn get_journal_entries(
    ctx: &ToolCtx<'_>,
    input: &Value,
) -> Result<Value, AppError> {
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

use super::xirr::{xirr, CashFlow};

pub(crate) async fn compute_xirr(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
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

pub(crate) async fn compute_net_worth(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
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
    use crate::ai::read_models::net_worth_daily::{query_range, NetWorthDaily};
    use crate::ai::read_models::projection::ensure_fresh;

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
    use crate::ai::read_models::net_worth_snapshot::{query_range, NetWorthSnapshot};
    use crate::ai::read_models::projection::ensure_fresh;

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
pub(crate) enum BreakdownDim {
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

pub(crate) async fn get_breakdown(ctx: &ToolCtx<'_>, dim: BreakdownDim) -> Result<Value, AppError> {
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

pub(crate) async fn get_risk_alerts(ctx: &ToolCtx<'_>) -> Result<Value, AppError> {
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

pub(crate) async fn get_asset_allocation(
    ctx: &ToolCtx<'_>,
    input: &Value,
) -> Result<Value, AppError> {
    use crate::ai::read_models::asset_allocation_snapshot::{query_all, AssetAllocationSnapshot};
    use crate::ai::read_models::projection::ensure_fresh;
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

pub(crate) async fn get_monthly_spend_by_category(
    ctx: &ToolCtx<'_>,
    input: &Value,
) -> Result<Value, AppError> {
    use crate::ai::read_models::monthly_spend_by_category::{query, MonthlySpendByCategory};
    use crate::ai::read_models::projection::ensure_fresh;

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

pub(crate) async fn get_net_worth_summary(
    ctx: &ToolCtx<'_>,
    input: &Value,
) -> Result<Value, AppError> {
    use crate::ai::read_models::net_worth_snapshot::{query_range, NetWorthSnapshot};
    use crate::ai::read_models::projection::ensure_fresh;

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

pub(crate) async fn get_xirr_summary(ctx: &ToolCtx<'_>, _input: &Value) -> Result<Value, AppError> {
    use crate::ai::read_models::projection::ensure_fresh;
    use crate::ai::read_models::xirr_snapshot::{query_all, XirrSnapshot};

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

pub(crate) async fn get_anomaly_flags(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use crate::ai::read_models::anomaly_flags::{current_freshness, query_all};

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

pub(crate) async fn get_refund_links(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use crate::ai::read_models::refund_links::{current_freshness, query_all};
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

pub(crate) async fn get_transfer_links(
    ctx: &ToolCtx<'_>,
    input: &Value,
) -> Result<Value, AppError> {
    use crate::ai::read_models::transfer_links::{current_freshness, query_all};
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

pub(crate) async fn get_subscription_changes(
    ctx: &ToolCtx<'_>,
    input: &Value,
) -> Result<Value, AppError> {
    use crate::ai::read_models::subscription_changes::{current_freshness, query_all};
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

pub(crate) async fn get_investment_performance(
    ctx: &ToolCtx<'_>,
    input: &Value,
) -> Result<Value, AppError> {
    use crate::ai::read_models::investment_performance::{current_freshness, query_all};
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

pub(crate) async fn get_recurring_patterns(
    ctx: &ToolCtx<'_>,
    input: &Value,
) -> Result<Value, AppError> {
    use crate::ai::read_models::recurring_patterns::{current_freshness, query_all};

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

pub(crate) async fn get_cashflow_buckets(
    ctx: &ToolCtx<'_>,
    input: &Value,
) -> Result<Value, AppError> {
    use crate::ai::read_models::cashflow_buckets::{query_range, CashflowBuckets};
    use crate::ai::read_models::projection::ensure_fresh;

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

pub(crate) async fn read_category_window(
    ctx: &ToolCtx<'_>,
    input: &Value,
) -> Result<Value, AppError> {
    use crate::ai::read_models::scoped_detail::category_window;
    let parsed = category_window::parse_input(input)?;
    category_window::run(ctx.db, ctx.user_id, &parsed).await
}

pub(crate) async fn read_account_window(
    ctx: &ToolCtx<'_>,
    input: &Value,
) -> Result<Value, AppError> {
    use crate::ai::read_models::scoped_detail::account_window;
    let parsed = account_window::parse_input(input)?;
    account_window::run(ctx.db, ctx.user_id, &parsed).await
}

pub(crate) async fn read_asset_window(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    use crate::ai::read_models::scoped_detail::asset_window;
    let parsed = asset_window::parse_input(input)?;
    asset_window::run(ctx.db, ctx.user_id, &parsed).await
}

fn summarize_buckets(
    buckets: &[crate::ai::read_models::monthly_spend_by_category::Bucket],
) -> Value {
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
    use crate::ai::context::BudgetTier;

    #[test]
    fn policy_denied_result_has_stable_shape() {
        // The model side branches on `error.code == "policy_denied"`,
        // so this shape is a wire contract.
        let v = crate::ai::tools::registry::policy_denied_result(
            "get_journal_entries",
            &crate::ai::policy::PolicyReason::UnknownTool,
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
        let v1 = crate::ai::tools::registry::policy_denied_result(
            "x",
            &crate::ai::policy::PolicyReason::ExternalWriteRequiresConsent,
        );
        let v2 = crate::ai::tools::registry::policy_denied_result(
            "x",
            &crate::ai::policy::PolicyReason::ContextTierTooLow {
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
        let names: Vec<String> = crate::ai::tools::registry()
            .schemas()
            .into_iter()
            .map(|s| s.name)
            .collect();
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
        let by_name: std::collections::HashMap<
            String,
            crate::ai::adapters::anthropic::wire::ToolSchema,
        > = crate::ai::tools::registry()
            .schemas()
            .into_iter()
            .map(|s| (s.name.clone(), s))
            .collect();
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
