//! Analytical 层 P2 — XIRR 快照（per-portfolio + per-asset，全时间窗口）。
//!
//! 与 Wave 10/11 的 device-sourced analytical 不同：XIRR 是确定性数学
//! 计算，cloud 可直接从 postings project。文档 §4.3.6 把 XIRR 列为
//! 「nightly/低频刷新」档；Phase 1 走 lazy refresh：tool 调用时检查
//! op_log watermark 决定是否重算。
//!
//! 数据流:
//!  - assets 表：决定 asset leg vs fiat leg
//!  - journal_entries：date + 把 postings 按 entry 分组
//!  - postings：fiat leg 贡献 cash flow（asset leg 跳过）
//!  - 对 entry 按 scope 过滤后，把 fiat 流入 `xirr()`
//!  - 写入 read_model_xirr_snapshot
//!
//! 货币简化（Phase 1）:
//!  - 不做 FX 折算。计算时混合所有币种（与 inline compute_xirr 同行为）。
//!  - 写入时记录 primary_currency（最多 flow 的币种）+ multi_currency 标志。
//!  - `approximation` = !multi_currency（单币种才认作精确）。

use std::collections::{HashMap, HashSet};

use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::Value;
use worker::{D1Database, D1Type};

use crate::error::AppError;

use super::freshness::Freshness;
use super::projection::{
    latest_op_log_hlc, now_iso, upsert_freshness_meta, Projection,
};

const NAME: &str = "xirr_snapshot";
const SCHEMA_VERSION: u32 = 1;
const CALCULATION_VERSION: u32 = 1;

pub struct XirrSnapshot;

impl Projection for XirrSnapshot {
    fn name(&self) -> &'static str {
        NAME
    }
    fn schema_version(&self) -> u32 {
        SCHEMA_VERSION
    }
    fn calculation_version(&self) -> u32 {
        CALCULATION_VERSION
    }

    async fn refresh(&self, db: &D1Database, user_id: &str) -> Result<Freshness, AppError> {
        let watermark = latest_op_log_hlc(db, user_id).await?.unwrap_or_default();
        let assets = load_payloads(db, user_id, "assets").await?;
        let asset_ids: HashSet<String> = assets.iter().map(|(id, _)| id.clone()).collect();
        let entries = load_payloads(db, user_id, "journal_entries").await?;
        let postings = load_payloads(db, user_id, "postings").await?;

        let rows = aggregate(&entries, &postings, &asset_ids);

        let refreshed_at = now_iso();
        write_rows(
            db,
            user_id,
            &rows,
            &watermark,
            &refreshed_at,
            SCHEMA_VERSION,
            CALCULATION_VERSION,
        )
        .await?;

        let freshness = Freshness::new(
            NAME,
            watermark,
            refreshed_at,
            SCHEMA_VERSION,
            CALCULATION_VERSION,
        );
        upsert_freshness_meta(db, user_id, &freshness).await?;
        Ok(freshness)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct XirrRow {
    pub scope: String,           // 'portfolio' OR asset_id
    pub xirr: Option<f64>,
    pub flow_count: u32,
    pub primary_currency: Option<String>,
    pub multi_currency: bool,
    pub approximation: bool,
}

pub async fn query_all(
    db: &D1Database,
    user_id: &str,
) -> Result<Vec<XirrRow>, AppError> {
    let stmt = db
        .prepare(
            "SELECT scope, xirr, flow_count, primary_currency,
                    multi_currency, approximation
             FROM read_model_xirr_snapshot
             WHERE user_id = ?1
             ORDER BY CASE WHEN scope = 'portfolio' THEN 0 ELSE 1 END, scope",
        )
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?;
    let raw: Vec<RowSelect> = stmt
        .all()
        .await
        .map_err(|e| AppError::Internal(format!("query: {e}")))?
        .results::<RowSelect>()
        .map_err(|e| AppError::Internal(format!("results: {e}")))?;
    Ok(raw
        .into_iter()
        .map(|r| XirrRow {
            scope: r.scope,
            xirr: r.xirr,
            flow_count: r.flow_count,
            primary_currency: r.primary_currency,
            multi_currency: r.multi_currency != 0,
            approximation: r.approximation != 0,
        })
        .collect())
}

// ── pure aggregation (testable) ────────────────────────────────────────────

#[derive(Clone, Copy)]
struct CashFlow {
    when: DateTime<Utc>,
    amount: f64,
}

pub(crate) fn aggregate(
    entries: &[(String, Value)],
    postings: &[(String, Value)],
    asset_ids: &HashSet<String>,
) -> Vec<XirrRow> {
    // entry_id → (date, refs to its postings)
    let mut entry_postings: HashMap<&str, Vec<&Value>> = HashMap::new();
    for (_, p) in postings {
        if let Some(eid) = payload_str(p, "journal_entry_id") {
            entry_postings.entry(eid).or_default().push(p);
        }
    }
    let mut entry_date: HashMap<&str, DateTime<Utc>> = HashMap::new();
    for (id, p) in entries {
        if let Some(d) = payload_str(p, "date").and_then(parse_iso) {
            entry_date.insert(id.as_str(), d);
        }
    }

    // portfolio flows + currency counts
    let mut portfolio_flows: Vec<CashFlow> = Vec::new();
    let mut portfolio_currency: HashMap<String, u32> = HashMap::new();

    // per-asset: which entry_ids participated + flows per asset
    let mut asset_flows: HashMap<String, Vec<CashFlow>> = HashMap::new();
    let mut asset_currency: HashMap<String, HashMap<String, u32>> = HashMap::new();

    for (entry_id, p) in entries {
        let Some(date) = payload_str(p, "date").and_then(parse_iso) else {
            continue;
        };
        let Some(legs) = entry_postings.get(entry_id.as_str()) else {
            continue;
        };
        // 收集该 entry 涉及的 asset_id（用于把这条 entry 归到 per-asset XIRR）
        let mut entry_assets: HashSet<&str> = HashSet::new();
        let mut entry_cash_flow = 0.0;
        let mut entry_cash_currency: Option<&str> = None;
        for leg in legs {
            let Some(unit) = payload_str(leg, "unit") else {
                continue;
            };
            if asset_ids.contains(unit) {
                entry_assets.insert(unit);
            } else {
                // fiat leg
                let amount = payload_num(leg, "units").unwrap_or(0.0);
                entry_cash_flow += amount;
                if entry_cash_currency.is_none() {
                    entry_cash_currency = Some(unit);
                }
            }
        }
        if entry_cash_flow.abs() < 1e-12 {
            continue;
        }
        let cf = CashFlow {
            when: date,
            amount: entry_cash_flow,
        };
        portfolio_flows.push(cf);
        if let Some(c) = entry_cash_currency {
            *portfolio_currency.entry(c.to_string()).or_insert(0) += 1;
        }
        for asset_id in &entry_assets {
            asset_flows
                .entry((*asset_id).to_string())
                .or_default()
                .push(cf);
            let c_map = asset_currency
                .entry((*asset_id).to_string())
                .or_default();
            if let Some(c) = entry_cash_currency {
                *c_map.entry(c.to_string()).or_insert(0) += 1;
            }
        }
    }

    let mut out: Vec<XirrRow> = Vec::new();
    out.push(make_row(
        "portfolio",
        &portfolio_flows,
        &portfolio_currency,
    ));
    let mut asset_keys: Vec<String> = asset_flows.keys().cloned().collect();
    asset_keys.sort();
    for asset_id in asset_keys {
        let flows = &asset_flows[&asset_id];
        let cur = asset_currency
            .get(&asset_id)
            .cloned()
            .unwrap_or_default();
        out.push(make_row(&asset_id, flows, &cur));
    }
    out
}

fn make_row(
    scope: &str,
    flows: &[CashFlow],
    currency_counts: &HashMap<String, u32>,
) -> XirrRow {
    let multi_currency = currency_counts.len() > 1;
    let primary_currency = currency_counts
        .iter()
        .max_by_key(|(_, &count)| count)
        .map(|(c, _)| c.clone());
    XirrRow {
        scope: scope.to_string(),
        xirr: xirr(flows),
        flow_count: flows.len() as u32,
        primary_currency,
        multi_currency,
        approximation: multi_currency, // 多币种 = approximation; 单币种 = exact
    }
}

/// Newton-Raphson on cash-flow series. 复制自 `tools::xirr` —— 内核算法
/// 共享逻辑但与 tools 模块解耦，便于未来这一份单独维护。
fn xirr(flows: &[CashFlow]) -> Option<f64> {
    if flows.len() < 2 {
        return None;
    }
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

// ── DB plumbing ────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct PayloadRow {
    id: String,
    payload: String,
}

#[derive(Deserialize)]
struct RowSelect {
    scope: String,
    xirr: Option<f64>,
    flow_count: u32,
    primary_currency: Option<String>,
    multi_currency: i32,
    approximation: i32,
}

async fn load_payloads(
    db: &D1Database,
    user_id: &str,
    table: &str,
) -> Result<Vec<(String, Value)>, AppError> {
    debug_assert!(matches!(
        table,
        "assets" | "journal_entries" | "postings"
    ));
    let sql = format!(
        "SELECT id, payload FROM {table}
         WHERE user_id = ?1 AND deleted_at IS NULL"
    );
    let stmt = db
        .prepare(&sql)
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?;
    let rows: Vec<PayloadRow> = stmt
        .all()
        .await
        .map_err(|e| AppError::Internal(format!("query {table}: {e}")))?
        .results::<PayloadRow>()
        .map_err(|e| AppError::Internal(format!("parse {table}: {e}")))?;
    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        if let Ok(v) = serde_json::from_str::<Value>(&r.payload) {
            out.push((r.id, v));
        }
    }
    Ok(out)
}

#[allow(clippy::too_many_arguments)]
async fn write_rows(
    db: &D1Database,
    user_id: &str,
    rows: &[XirrRow],
    watermark: &str,
    refreshed_at: &str,
    schema_version: u32,
    calculation_version: u32,
) -> Result<(), AppError> {
    db.prepare("DELETE FROM read_model_xirr_snapshot WHERE user_id = ?1")
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind del: {e}")))?
        .run()
        .await
        .map_err(|e| AppError::Internal(format!("del: {e}")))?;
    if rows.is_empty() {
        return Ok(());
    }
    let stmts: Result<Vec<_>, AppError> = rows
        .iter()
        .map(|r| {
            let xirr_param: D1Type = match r.xirr {
                Some(v) if v.is_finite() => D1Type::Real(v),
                _ => D1Type::Null,
            };
            let cur_param: D1Type = match &r.primary_currency {
                Some(c) => D1Type::Text(c),
                None => D1Type::Null,
            };
            db.prepare(
                "INSERT INTO read_model_xirr_snapshot
                    (user_id, scope, xirr, flow_count, primary_currency,
                     multi_currency, approximation,
                     source_hlc_watermark, refreshed_at, schema_version, calculation_version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(&r.scope),
                &xirr_param,
                &D1Type::Integer(r.flow_count as i32),
                &cur_param,
                &D1Type::Integer(if r.multi_currency { 1 } else { 0 }),
                &D1Type::Integer(if r.approximation { 1 } else { 0 }),
                &D1Type::Text(watermark),
                &D1Type::Text(refreshed_at),
                &D1Type::Integer(schema_version as i32),
                &D1Type::Integer(calculation_version as i32),
            ])
            .map_err(|e| AppError::Internal(format!("bind ins: {e}")))
        })
        .collect();
    db.batch(stmts?)
        .await
        .map_err(|e| AppError::Internal(format!("batch: {e}")))?;
    Ok(())
}

// ── helpers ────────────────────────────────────────────────────────────────

fn payload_str<'a>(p: &'a Value, key: &str) -> Option<&'a str> {
    p.get(key).and_then(|v| v.as_str())
}

fn payload_num(p: &Value, key: &str) -> Option<f64> {
    p.get(key).and_then(|v| v.as_f64())
}

fn parse_iso(s: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|d| d.with_timezone(&Utc))
        .or_else(|| {
            chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d")
                .ok()
                .and_then(|d| d.and_hms_opt(0, 0, 0))
                .map(|dt| DateTime::<Utc>::from_naive_utc_and_offset(dt, Utc))
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn entry(id: &str, date: &str) -> (String, Value) {
        (id.into(), json!({ "date": date }))
    }

    fn posting(entry_id: &str, unit: &str, units: f64) -> (String, Value) {
        (
            format!("p_{entry_id}_{unit}_{units}"),
            json!({
                "journal_entry_id": entry_id,
                "unit":             unit,
                "units":            units,
            }),
        )
    }

    fn assets(ids: &[&str]) -> HashSet<String> {
        ids.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn portfolio_row_always_present_even_with_no_entries() {
        let rows = aggregate(&[], &[], &assets(&[]));
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].scope, "portfolio");
        assert_eq!(rows[0].flow_count, 0);
        assert!(rows[0].xirr.is_none());
    }

    #[test]
    fn portfolio_xirr_for_single_buy_then_sell() {
        // -1000 buy AAPL today; +1100 sell exactly 1 year later → ≈10% XIRR
        let entries = vec![
            entry("buy", "2025-01-01T00:00:00Z"),
            entry("sell", "2026-01-01T00:00:00Z"),
        ];
        let postings = vec![
            posting("buy", "AAPL", 10.0), // asset leg
            posting("buy", "USD", -1000.0),
            posting("sell", "AAPL", -10.0),
            posting("sell", "USD", 1100.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&["AAPL"]));
        let port = rows.iter().find(|r| r.scope == "portfolio").unwrap();
        let xirr = port.xirr.expect("XIRR defined");
        assert!((xirr - 0.10).abs() < 1e-3, "expected ~10% got {xirr}");
        assert_eq!(port.flow_count, 2);
        assert_eq!(port.primary_currency.as_deref(), Some("USD"));
        assert!(!port.multi_currency);
    }

    #[test]
    fn per_asset_row_emitted_for_each_asset_touched() {
        let entries = vec![
            entry("e1", "2025-01-01T00:00:00Z"),
            entry("e2", "2026-01-01T00:00:00Z"),
        ];
        let postings = vec![
            posting("e1", "AAPL", 10.0),
            posting("e1", "USD", -1000.0),
            posting("e2", "AAPL", -10.0),
            posting("e2", "USD", 1100.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&["AAPL", "TSLA"]));
        // portfolio + AAPL (TSLA has no flows so it's not emitted)
        let scopes: Vec<&str> = rows.iter().map(|r| r.scope.as_str()).collect();
        assert!(scopes.contains(&"portfolio"));
        assert!(scopes.contains(&"AAPL"));
        assert!(!scopes.contains(&"TSLA"));
    }

    #[test]
    fn single_sign_flows_yield_none_xirr() {
        let entries = vec![entry("buy", "2025-01-01T00:00:00Z")];
        let postings = vec![
            posting("buy", "AAPL", 10.0),
            posting("buy", "USD", -1000.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&["AAPL"]));
        let port = rows.iter().find(|r| r.scope == "portfolio").unwrap();
        assert!(port.xirr.is_none(), "no break-even rate possible");
        assert_eq!(port.flow_count, 1);
    }

    #[test]
    fn mixed_currency_marks_approximation_and_multi() {
        let entries = vec![
            entry("buy_usd", "2025-01-01T00:00:00Z"),
            entry("sell_usd", "2026-01-01T00:00:00Z"),
            entry("buy_cny", "2025-06-01T00:00:00Z"),
        ];
        let postings = vec![
            posting("buy_usd", "AAPL", 10.0),
            posting("buy_usd", "USD", -1000.0),
            posting("sell_usd", "AAPL", -10.0),
            posting("sell_usd", "USD", 1100.0),
            posting("buy_cny", "AAPL", 5.0),
            posting("buy_cny", "CNY", -3500.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&["AAPL"]));
        let port = rows.iter().find(|r| r.scope == "portfolio").unwrap();
        assert!(port.multi_currency);
        assert!(port.approximation);
    }

    #[test]
    fn zero_flow_entries_skipped() {
        // Internal transfer: posting +/-equal cash legs, no asset → cash_flow=0
        let entries = vec![entry("xfer", "2025-06-01T00:00:00Z")];
        let postings = vec![
            posting("xfer", "USD", -1000.0),
            posting("xfer", "USD", 1000.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&[]));
        let port = rows.iter().find(|r| r.scope == "portfolio").unwrap();
        assert_eq!(port.flow_count, 0);
    }

    #[test]
    fn assets_sorted_alphabetically_in_output() {
        let entries = vec![
            entry("e_tsla", "2025-01-01T00:00:00Z"),
            entry("e_aapl", "2025-01-01T00:00:00Z"),
            entry("s_tsla", "2026-01-01T00:00:00Z"),
            entry("s_aapl", "2026-01-01T00:00:00Z"),
        ];
        let postings = vec![
            posting("e_tsla", "TSLA", 5.0),
            posting("e_tsla", "USD", -1000.0),
            posting("s_tsla", "TSLA", -5.0),
            posting("s_tsla", "USD", 1200.0),
            posting("e_aapl", "AAPL", 10.0),
            posting("e_aapl", "USD", -1500.0),
            posting("s_aapl", "AAPL", -10.0),
            posting("s_aapl", "USD", 1700.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&["AAPL", "TSLA"]));
        // portfolio first, then AAPL, then TSLA
        let scopes: Vec<&str> = rows.iter().map(|r| r.scope.as_str()).collect();
        assert_eq!(scopes, vec!["portfolio", "AAPL", "TSLA"]);
    }
}
