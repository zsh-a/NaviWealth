//! Snapshot 层 P1 — 每月现金 inflow / outflow 分桶。
//!
//! 数据来源:
//!  - `journal_entries.payload.date` 给月份
//!  - `assets.id` 集合用于剔除资产 leg
//!  - `postings.payload.unit ∉ asset_ids` ⇒ 现金 leg
//!  - `postings.payload.units > 0` ⇒ inflow; `< 0` ⇒ outflow (abs 累加)
//!
//! 与 `net_worth_snapshot` 的对比:
//!  - net_worth_snapshot.net_flow = inflow - outflow (signed, 含累计)
//!  - cashflow_buckets.inflow / .outflow = abs 分桶 (两个独立读模型)
//!
//! 刷新策略: Lazy。

use std::collections::{HashMap, HashSet};

use chrono::Datelike;
use serde::Deserialize;
use serde_json::Value;
use worker::{D1Database, D1Type};

use crate::error::AppError;

use super::freshness::Freshness;
use super::projection::{latest_op_log_hlc, now_iso, upsert_freshness_meta, Projection};
use super::WriteMeta;

const NAME: &str = "cashflow_buckets";
const SCHEMA_VERSION: u32 = 1;
const CALCULATION_VERSION: u32 = 1;

pub struct CashflowBuckets;

impl Projection for CashflowBuckets {
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
        let asset_ids: HashSet<String> = assets.into_iter().map(|(id, _)| id).collect();
        let entries = load_payloads(db, user_id, "journal_entries").await?;
        let postings = load_payloads(db, user_id, "postings").await?;

        let rows = aggregate(&entries, &postings, &asset_ids);

        let refreshed_at = now_iso();
        write_rows(
            db,
            user_id,
            &rows,
            WriteMeta {
                watermark: &watermark,
                refreshed_at: &refreshed_at,
                schema_version: SCHEMA_VERSION,
                calculation_version: CALCULATION_VERSION,
            },
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CashflowRow {
    pub year_month: String,
    pub currency: String,
    pub inflow_minor: i64,
    pub outflow_minor: i64,
    pub inflow_count: u32,
    pub outflow_count: u32,
}

/// 工具读路径：返回某币种在 [from_ym, to_ym] 闭区间的所有月度行。
pub async fn query_range(
    db: &D1Database,
    user_id: &str,
    from_ym: &str,
    to_ym: &str,
    currency: Option<&str>,
) -> Result<Vec<CashflowRow>, AppError> {
    let stmt = match currency {
        Some(c) => db
            .prepare(
                "SELECT year_month, currency, inflow_minor, outflow_minor,
                        inflow_count, outflow_count
                 FROM read_model_cashflow_buckets
                 WHERE user_id = ?1
                   AND year_month >= ?2
                   AND year_month <= ?3
                   AND currency = ?4
                 ORDER BY year_month, currency",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(from_ym),
                &D1Type::Text(to_ym),
                &D1Type::Text(c),
            ])
            .map_err(|e| AppError::Internal(format!("bind: {e}")))?,
        None => db
            .prepare(
                "SELECT year_month, currency, inflow_minor, outflow_minor,
                        inflow_count, outflow_count
                 FROM read_model_cashflow_buckets
                 WHERE user_id = ?1
                   AND year_month >= ?2
                   AND year_month <= ?3
                 ORDER BY year_month, currency",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(from_ym),
                &D1Type::Text(to_ym),
            ])
            .map_err(|e| AppError::Internal(format!("bind: {e}")))?,
    };
    let rows: Vec<RowSelect> = stmt
        .all()
        .await
        .map_err(|e| AppError::Internal(format!("query: {e}")))?
        .results::<RowSelect>()
        .map_err(|e| AppError::Internal(format!("results: {e}")))?;
    Ok(rows
        .into_iter()
        .map(|r| CashflowRow {
            year_month: r.year_month,
            currency: r.currency,
            inflow_minor: r.inflow_minor.parse().unwrap_or(0),
            outflow_minor: r.outflow_minor.parse().unwrap_or(0),
            inflow_count: r.inflow_count,
            outflow_count: r.outflow_count,
        })
        .collect())
}

// ── pure aggregation ───────────────────────────────────────────────────────

pub(crate) fn aggregate(
    entries: &[(String, Value)],
    postings: &[(String, Value)],
    asset_ids: &HashSet<String>,
) -> Vec<CashflowRow> {
    // entry_id → year_month
    let mut entry_ym: HashMap<&str, String> = HashMap::new();
    for (id, p) in entries {
        let Some(d) = payload_str(p, "date").and_then(parse_iso) else {
            continue;
        };
        entry_ym.insert(id.as_str(), format!("{:04}-{:02}", d.year(), d.month()));
    }

    // (ym, currency) → (inflow_minor, outflow_minor, in_count, out_count)
    let mut acc: HashMap<(String, String), [i128; 4]> = HashMap::new();
    for (_, p) in postings {
        let Some(unit) = payload_str(p, "unit") else {
            continue;
        };
        if asset_ids.contains(unit) {
            continue; // skip asset leg
        }
        let Some(eid) = payload_str(p, "journal_entry_id") else {
            continue;
        };
        let Some(ym) = entry_ym.get(eid) else {
            continue;
        };
        let units = payload_num(p, "units").unwrap_or(0.0);
        if units == 0.0 {
            continue;
        }
        let minor = (units * 100.0).round() as i128;
        let key = (ym.clone(), unit.to_string());
        let bucket = acc.entry(key).or_insert([0, 0, 0, 0]);
        if minor > 0 {
            bucket[0] += minor;
            bucket[2] += 1;
        } else {
            bucket[1] += -minor;
            bucket[3] += 1;
        }
    }

    let mut out: Vec<CashflowRow> = acc
        .into_iter()
        .map(
            |((year_month, currency), [inflow, outflow, in_c, out_c])| CashflowRow {
                year_month,
                currency,
                inflow_minor: inflow as i64,
                outflow_minor: outflow as i64,
                inflow_count: in_c as u32,
                outflow_count: out_c as u32,
            },
        )
        .collect();
    out.sort_by(|a, b| {
        a.year_month
            .cmp(&b.year_month)
            .then_with(|| a.currency.cmp(&b.currency))
    });
    out
}

// ── DB plumbing ────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct PayloadRow {
    id: String,
    payload: String,
}

#[derive(Deserialize)]
struct RowSelect {
    year_month: String,
    currency: String,
    inflow_minor: String,
    outflow_minor: String,
    inflow_count: u32,
    outflow_count: u32,
}

async fn load_payloads(
    db: &D1Database,
    user_id: &str,
    table: &str,
) -> Result<Vec<(String, Value)>, AppError> {
    debug_assert!(matches!(table, "assets" | "journal_entries" | "postings"));
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

async fn write_rows(
    db: &D1Database,
    user_id: &str,
    rows: &[CashflowRow],
    meta: WriteMeta<'_>,
) -> Result<(), AppError> {
    db.prepare("DELETE FROM read_model_cashflow_buckets WHERE user_id = ?1")
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
            let in_str = r.inflow_minor.to_string();
            let out_str = r.outflow_minor.to_string();
            db.prepare(
                "INSERT INTO read_model_cashflow_buckets
                    (user_id, year_month, currency, inflow_minor, outflow_minor,
                     inflow_count, outflow_count,
                     source_hlc_watermark, refreshed_at, schema_version, calculation_version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(&r.year_month),
                &D1Type::Text(&r.currency),
                &D1Type::Text(&in_str),
                &D1Type::Text(&out_str),
                &D1Type::Integer(r.inflow_count as i32),
                &D1Type::Integer(r.outflow_count as i32),
                &D1Type::Text(meta.watermark),
                &D1Type::Text(meta.refreshed_at),
                &D1Type::Integer(meta.schema_version as i32),
                &D1Type::Integer(meta.calculation_version as i32),
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

fn parse_iso(s: &str) -> Option<chrono::DateTime<chrono::Utc>> {
    chrono::DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|d| d.with_timezone(&chrono::Utc))
        .or_else(|| {
            chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d")
                .ok()
                .and_then(|d| d.and_hms_opt(0, 0, 0))
                .map(|dt| {
                    chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(dt, chrono::Utc)
                })
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
    fn splits_inflow_and_outflow() {
        let entries = vec![
            entry("salary", "2026-05-01T10:00:00Z"),
            entry("rent", "2026-05-05T10:00:00Z"),
            entry("coffee_1", "2026-05-10T10:00:00Z"),
            entry("coffee_2", "2026-05-12T10:00:00Z"),
        ];
        let postings = vec![
            posting("salary", "USD", 5000.0),
            posting("rent", "USD", -1800.0),
            posting("coffee_1", "USD", -5.5),
            posting("coffee_2", "USD", -4.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&[]));
        assert_eq!(rows.len(), 1);
        let r = &rows[0];
        assert_eq!(r.year_month, "2026-05");
        assert_eq!(r.currency, "USD");
        assert_eq!(r.inflow_minor, 500_000); // 5000.00
        assert_eq!(r.outflow_minor, 180_950); // 1800 + 5.50 + 4.00 = 1809.50
        assert_eq!(r.inflow_count, 1);
        assert_eq!(r.outflow_count, 3);
    }

    #[test]
    fn separates_currencies() {
        let entries = vec![
            entry("e_usd", "2026-05-01T10:00:00Z"),
            entry("e_cny", "2026-05-02T10:00:00Z"),
        ];
        let postings = vec![
            posting("e_usd", "USD", 100.0),
            posting("e_cny", "CNY", -700.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&[]));
        assert_eq!(rows.len(), 2);
        let by_cur: HashMap<&str, &CashflowRow> =
            rows.iter().map(|r| (r.currency.as_str(), r)).collect();
        assert_eq!(by_cur["USD"].inflow_minor, 10_000);
        assert_eq!(by_cur["USD"].outflow_minor, 0);
        assert_eq!(by_cur["CNY"].inflow_minor, 0);
        assert_eq!(by_cur["CNY"].outflow_minor, 70_000);
    }

    #[test]
    fn ignores_asset_legs() {
        // Buy AAPL: cash debit + asset credit. Only cash leg counts.
        let entries = vec![entry("buy_aapl", "2026-04-15T10:00:00Z")];
        let postings = vec![
            posting("buy_aapl", "asset_aapl", 10.0), // asset leg, ignored
            posting("buy_aapl", "USD", -1500.0),     // cash outflow
        ];
        let rows = aggregate(&entries, &postings, &assets(&["asset_aapl"]));
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].outflow_minor, 150_000);
        assert_eq!(rows[0].inflow_minor, 0);
    }

    #[test]
    fn ignores_zero_amount_legs() {
        let entries = vec![entry("e1", "2026-04-15T10:00:00Z")];
        let postings = vec![posting("e1", "USD", 0.0)];
        let rows = aggregate(&entries, &postings, &assets(&[]));
        assert!(rows.is_empty());
    }

    #[test]
    fn ignores_orphan_postings() {
        let postings = vec![posting("ghost", "USD", 100.0)];
        let rows = aggregate(&[], &postings, &assets(&[]));
        assert!(rows.is_empty());
    }

    #[test]
    fn sorts_by_ym_then_currency() {
        let entries = vec![
            entry("e_may_cny", "2026-05-01T10:00:00Z"),
            entry("e_apr_usd", "2026-04-15T10:00:00Z"),
            entry("e_may_usd", "2026-05-02T10:00:00Z"),
        ];
        let postings = vec![
            posting("e_may_cny", "CNY", 100.0),
            posting("e_apr_usd", "USD", 200.0),
            posting("e_may_usd", "USD", 300.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&[]));
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].year_month, "2026-04");
        assert_eq!(rows[0].currency, "USD");
        assert_eq!(rows[1].year_month, "2026-05");
        assert_eq!(rows[1].currency, "CNY");
        assert_eq!(rows[2].year_month, "2026-05");
        assert_eq!(rows[2].currency, "USD");
    }
}
