//! Snapshot 层 P0 — 持仓快照（每 asset 净数量 + 加权平均成本）。
//!
//! 数据来源:
//!  - `assets` 表给出此用户的合法 asset_id 集合
//!  - `postings.payload.unit ∈ asset_ids` 算资产 leg
//!  - `postings.payload.units` 是 signed 数量（买 +，卖 -）
//!  - `postings.payload.cost_per_unit` (fallback `price_per_unit`) 是成本
//!  - 货币从 `cost_currency` (fallback `price_currency`) 取
//!  - 净 qty ≤ 0 的 asset（已平仓）从输出剔除
//!
//! Phase 1 简化:
//!  - 不区分 lot / FIFO / LIFO —— 用加权平均成本（同 get_holdings 旧路径）
//!  - 不算市值（需要价格源 + FX）。市值由专门 read model 或端侧补
//!  - 单 asset 仅记一种 cost_currency；多币种成本场景下用首条 posting 的币种
//!
//! 刷新策略: Lazy。

use std::collections::{HashMap, HashSet};

use serde::Deserialize;
use serde_json::Value;
use worker::{D1Database, D1Type};

use crate::error::AppError;

use super::freshness::Freshness;
use super::projection::{
    latest_op_log_hlc, now_iso, upsert_freshness_meta, Projection,
};

const NAME: &str = "holdings_snapshot";
const SCHEMA_VERSION: u32 = 1;
const CALCULATION_VERSION: u32 = 1;

pub struct HoldingsSnapshot;

impl Projection for HoldingsSnapshot {
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
        let watermark = latest_op_log_hlc(db, user_id)
            .await?
            .unwrap_or_default();
        let assets = load_payloads(db, user_id, "assets").await?;
        let postings = load_payloads(db, user_id, "postings").await?;

        let asset_ids: HashSet<String> = assets.iter().map(|(id, _)| id.clone()).collect();
        let holdings = aggregate(&postings, &asset_ids);

        let refreshed_at = now_iso();
        write_holdings(
            db,
            user_id,
            &holdings,
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
pub struct Holding {
    pub asset_id: String,
    pub net_qty: f64,
    pub cost_basis_minor: i64,
    pub cost_currency: String,
}

/// 工具读路径：从 read model 表查全部持仓。
pub async fn query_all(db: &D1Database, user_id: &str) -> Result<Vec<Holding>, AppError> {
    let stmt = db
        .prepare(
            "SELECT asset_id, net_qty, cost_basis_minor, cost_currency
             FROM read_model_holdings_snapshot
             WHERE user_id = ?1
             ORDER BY asset_id",
        )
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?;
    let rows: Vec<HoldingRow> = stmt
        .all()
        .await
        .map_err(|e| AppError::Internal(format!("query: {e}")))?
        .results::<HoldingRow>()
        .map_err(|e| AppError::Internal(format!("results: {e}")))?;
    Ok(rows
        .into_iter()
        .map(|r| Holding {
            asset_id: r.asset_id,
            net_qty: r.net_qty.parse().unwrap_or(0.0),
            cost_basis_minor: r.cost_basis_minor.parse().unwrap_or(0),
            cost_currency: r.cost_currency,
        })
        .collect())
}

// ── pure aggregation logic ─────────────────────────────────────────────────

pub(crate) fn aggregate(
    postings: &[(String, Value)],
    asset_ids: &HashSet<String>,
) -> Vec<Holding> {
    struct Acc {
        net_qty: f64,
        cost: f64,
        currency: Option<String>,
    }
    let mut tracker: HashMap<&str, Acc> = HashMap::new();
    for (_, p) in postings {
        let Some(unit) = payload_str(p, "unit") else {
            continue;
        };
        if !asset_ids.contains(unit) {
            continue;
        }
        let Some(units) = payload_num(p, "units") else {
            continue;
        };
        let unit_cost =
            payload_num(p, "cost_per_unit").or_else(|| payload_num(p, "price_per_unit"));
        let currency = payload_str(p, "cost_currency")
            .or_else(|| payload_str(p, "price_currency"))
            .map(str::to_string);

        let acc = tracker.entry(unit).or_insert(Acc {
            net_qty: 0.0,
            cost: 0.0,
            currency: None,
        });
        acc.net_qty += units;
        if let Some(c) = unit_cost {
            // 卖出 (units < 0) 也累计 negative cost，最终 cost_basis 仍是
            // 净成本；和 get_holdings 旧路径一致。
            acc.cost += units * c;
        }
        if acc.currency.is_none() {
            acc.currency = currency;
        }
    }

    let mut out: Vec<Holding> = tracker
        .into_iter()
        .filter_map(|(asset_id, acc)| {
            if acc.net_qty <= 0.0 {
                return None; // 已平仓不入快照
            }
            Some(Holding {
                asset_id: asset_id.to_string(),
                net_qty: acc.net_qty,
                cost_basis_minor: (acc.cost * 100.0).round() as i64,
                cost_currency: acc.currency.unwrap_or_default(),
            })
        })
        .collect();
    out.sort_by(|a, b| a.asset_id.cmp(&b.asset_id));
    out
}

// ── DB plumbing ────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct PayloadRow {
    id: String,
    payload: String,
}

#[derive(Deserialize)]
struct HoldingRow {
    asset_id: String,
    net_qty: String,
    cost_basis_minor: String,
    cost_currency: String,
}

async fn load_payloads(
    db: &D1Database,
    user_id: &str,
    table: &str,
) -> Result<Vec<(String, Value)>, AppError> {
    debug_assert!(matches!(table, "assets" | "postings"));
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
async fn write_holdings(
    db: &D1Database,
    user_id: &str,
    holdings: &[Holding],
    watermark: &str,
    refreshed_at: &str,
    schema_version: u32,
    calculation_version: u32,
) -> Result<(), AppError> {
    db.prepare("DELETE FROM read_model_holdings_snapshot WHERE user_id = ?1")
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind del: {e}")))?
        .run()
        .await
        .map_err(|e| AppError::Internal(format!("del: {e}")))?;

    if holdings.is_empty() {
        return Ok(());
    }
    let stmts: Result<Vec<_>, AppError> = holdings
        .iter()
        .map(|h| {
            let qty_str = h.net_qty.to_string();
            let cost_str = h.cost_basis_minor.to_string();
            db.prepare(
                "INSERT INTO read_model_holdings_snapshot
                    (user_id, asset_id, net_qty, cost_basis_minor, cost_currency,
                     source_hlc_watermark, refreshed_at, schema_version, calculation_version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(&h.asset_id),
                &D1Type::Text(&qty_str),
                &D1Type::Text(&cost_str),
                &D1Type::Text(&h.cost_currency),
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

// ── helpers (private duplicate of tools.rs to avoid coupling) ──────────────

fn payload_str<'a>(p: &'a Value, key: &str) -> Option<&'a str> {
    p.get(key).and_then(|v| v.as_str())
}

fn payload_num(p: &Value, key: &str) -> Option<f64> {
    p.get(key).and_then(|v| v.as_f64())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn posting(unit: &str, units: f64, cost_per_unit: f64, cost_currency: &str) -> (String, Value) {
        (
            format!("p_{unit}_{units}"),
            json!({
                "journal_entry_id": "e1",
                "unit":             unit,
                "units":            units,
                "cost_per_unit":    cost_per_unit,
                "cost_currency":    cost_currency,
            }),
        )
    }

    fn assets(ids: &[&str]) -> HashSet<String> {
        ids.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn aggregates_a_single_buy() {
        let postings = vec![posting("AAPL", 10.0, 150.0, "USD")];
        let h = aggregate(&postings, &assets(&["AAPL"]));
        assert_eq!(h.len(), 1);
        assert_eq!(h[0].asset_id, "AAPL");
        assert_eq!(h[0].net_qty, 10.0);
        // 10 × 150 = 1500.00 → 150_000 minor
        assert_eq!(h[0].cost_basis_minor, 150_000);
        assert_eq!(h[0].cost_currency, "USD");
    }

    #[test]
    fn weighted_average_across_buys() {
        let postings = vec![
            posting("AAPL", 10.0, 100.0, "USD"),
            posting("AAPL", 10.0, 200.0, "USD"),
        ];
        let h = aggregate(&postings, &assets(&["AAPL"]));
        assert_eq!(h.len(), 1);
        assert_eq!(h[0].net_qty, 20.0);
        // 10 × 100 + 10 × 200 = 3000 → 300_000 minor
        assert_eq!(h[0].cost_basis_minor, 300_000);
    }

    #[test]
    fn sells_reduce_net_qty_and_cost() {
        let postings = vec![
            posting("AAPL", 10.0, 100.0, "USD"),
            posting("AAPL", -3.0, 100.0, "USD"),
        ];
        let h = aggregate(&postings, &assets(&["AAPL"]));
        assert_eq!(h[0].net_qty, 7.0);
        // 10×100 - 3×100 = 700 → 70_000 minor
        assert_eq!(h[0].cost_basis_minor, 70_000);
    }

    #[test]
    fn fully_closed_positions_drop_out() {
        let postings = vec![
            posting("AAPL", 10.0, 100.0, "USD"),
            posting("AAPL", -10.0, 100.0, "USD"),
        ];
        let h = aggregate(&postings, &assets(&["AAPL"]));
        assert!(h.is_empty(), "net_qty == 0 should be excluded");
    }

    #[test]
    fn ignores_unknown_assets() {
        // Postings reference an asset_id that's not in the assets set —
        // could be a fiat currency leg, or a stale reference.
        let postings = vec![
            posting("AAPL", 10.0, 100.0, "USD"),
            posting("USD", -1000.0, 1.0, "USD"), // cash leg
        ];
        let h = aggregate(&postings, &assets(&["AAPL"]));
        assert_eq!(h.len(), 1);
        assert_eq!(h[0].asset_id, "AAPL");
    }

    #[test]
    fn falls_back_to_price_fields_when_cost_missing() {
        let p = (
            "p1".to_string(),
            json!({
                "journal_entry_id": "e1",
                "unit":             "AAPL",
                "units":            10.0,
                "price_per_unit":   125.0,
                "price_currency":   "USD",
            }),
        );
        let h = aggregate(&[p], &assets(&["AAPL"]));
        assert_eq!(h[0].cost_basis_minor, 125_000);
        assert_eq!(h[0].cost_currency, "USD");
    }

    #[test]
    fn multiple_assets_sorted_by_id() {
        let postings = vec![
            posting("TSLA", 5.0, 200.0, "USD"),
            posting("AAPL", 10.0, 150.0, "USD"),
        ];
        let h = aggregate(&postings, &assets(&["AAPL", "TSLA"]));
        assert_eq!(h.len(), 2);
        assert_eq!(h[0].asset_id, "AAPL");
        assert_eq!(h[1].asset_id, "TSLA");
    }

    #[test]
    fn missing_cost_yields_zero_basis_not_dropped() {
        let p = (
            "p1".into(),
            json!({
                "journal_entry_id": "e1",
                "unit":             "AAPL",
                "units":            10.0,
                // no cost_per_unit / price_per_unit
            }),
        );
        let h = aggregate(&[p], &assets(&["AAPL"]));
        // qty still > 0 → keep; cost_basis falls back to 0.
        assert_eq!(h.len(), 1);
        assert_eq!(h[0].net_qty, 10.0);
        assert_eq!(h[0].cost_basis_minor, 0);
    }
}
