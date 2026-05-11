//! Snapshot 层 P0 — 月度净资产快照（每用户 × 每年月 × 每币种）。
//!
//! 数据来源:
//!  - `assets` 给出资产 id 集合（用于排除资产 leg）
//!  - `journal_entries.payload.date` 给月份
//!  - `postings.payload.unit` 不在 `asset_ids` ⇒ 现金 leg
//!  - `postings.payload.units` 是 signed —— 收入正、支出负
//!
//! Phase 1 简化:
//!  - 粒度是月（YYYY-MM），不是 per-day —— 后者存储 365× + 重算成本
//!    不划算。granularity=day/week 的查询仍走 inline 旧路径。
//!  - 不减负债（liabilities 是 point-in-time balance，模型不同；现有
//!    compute_net_worth 按"当前 principal sum"减一次，把这部分留在
//!    tool 层做。
//!  - 单一 currency 维度 —— 不在 projection 内做 FX。
//!
//! 刷新策略: Lazy。

use std::collections::{HashMap, HashSet};

use chrono::Datelike;
use serde::Deserialize;
use serde_json::Value;
use worker::{D1Database, D1Type};

use crate::error::AppError;

use super::freshness::Freshness;
use super::projection::{
    latest_op_log_hlc, now_iso, upsert_freshness_meta, Projection,
};

const NAME: &str = "net_worth_snapshot";
const SCHEMA_VERSION: u32 = 1;
const CALCULATION_VERSION: u32 = 1;

pub struct NetWorthSnapshot;

impl Projection for NetWorthSnapshot {
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
        let asset_ids: HashSet<String> = assets.into_iter().map(|(id, _)| id).collect();
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
pub struct NetWorthRow {
    pub year_month: String,
    pub currency: String,
    pub cumulative_minor: i64,
    pub net_flow_minor: i64,
}

/// 工具读路径：返回某币种在 [from_ym, to_ym] 闭区间内的所有月度行。
/// 当 currency 为空字符串时返回所有币种。
pub async fn query_range(
    db: &D1Database,
    user_id: &str,
    from_ym: &str,
    to_ym: &str,
    currency: Option<&str>,
) -> Result<Vec<NetWorthRow>, AppError> {
    let stmt = match currency {
        Some(c) => db
            .prepare(
                "SELECT year_month, currency, cumulative_minor, net_flow_minor
                 FROM read_model_net_worth_snapshot
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
                "SELECT year_month, currency, cumulative_minor, net_flow_minor
                 FROM read_model_net_worth_snapshot
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
        .map(|r| NetWorthRow {
            year_month: r.year_month,
            currency: r.currency,
            cumulative_minor: r.cumulative_minor.parse().unwrap_or(0),
            net_flow_minor: r.net_flow_minor.parse().unwrap_or(0),
        })
        .collect())
}

// ── pure aggregation logic ─────────────────────────────────────────────────

pub(crate) fn aggregate(
    entries: &[(String, Value)],
    postings: &[(String, Value)],
    asset_ids: &HashSet<String>,
) -> Vec<NetWorthRow> {
    // 1. entry_id → year_month
    let mut entry_ym: HashMap<&str, String> = HashMap::new();
    for (id, p) in entries {
        let Some(d) = payload_str(p, "date").and_then(parse_iso) else {
            continue;
        };
        entry_ym.insert(
            id.as_str(),
            format!("{:04}-{:02}", d.year(), d.month()),
        );
    }

    // 2. (year_month, currency) → net_flow_minor
    let mut flows: HashMap<(String, String), i128> = HashMap::new();
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
        let minor = (units * 100.0).round() as i128;
        let key = (ym.clone(), unit.to_string());
        *flows.entry(key).or_insert(0) += minor;
    }

    // 3. per-currency 时间序列：按 ym 排序，累加得到 cumulative
    // 先按 currency 分组
    let mut by_currency: HashMap<String, Vec<(String, i64)>> = HashMap::new();
    for ((ym, currency), net) in flows {
        by_currency
            .entry(currency)
            .or_default()
            .push((ym, net as i64));
    }
    let mut out: Vec<NetWorthRow> = Vec::new();
    for (currency, mut series) in by_currency {
        series.sort_by(|a, b| a.0.cmp(&b.0));
        let mut running: i64 = 0;
        for (ym, net) in series {
            running = running.saturating_add(net);
            out.push(NetWorthRow {
                year_month: ym,
                currency: currency.clone(),
                cumulative_minor: running,
                net_flow_minor: net,
            });
        }
    }
    out.sort_by(|a, b| a.year_month.cmp(&b.year_month).then_with(|| a.currency.cmp(&b.currency)));
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
    cumulative_minor: String,
    net_flow_minor: String,
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
    rows: &[NetWorthRow],
    watermark: &str,
    refreshed_at: &str,
    schema_version: u32,
    calculation_version: u32,
) -> Result<(), AppError> {
    db.prepare("DELETE FROM read_model_net_worth_snapshot WHERE user_id = ?1")
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
            let cum_str = r.cumulative_minor.to_string();
            let flow_str = r.net_flow_minor.to_string();
            db.prepare(
                "INSERT INTO read_model_net_worth_snapshot
                    (user_id, year_month, currency, cumulative_minor, net_flow_minor,
                     source_hlc_watermark, refreshed_at, schema_version, calculation_version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(&r.year_month),
                &D1Type::Text(&r.currency),
                &D1Type::Text(&cum_str),
                &D1Type::Text(&flow_str),
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

// ── helpers (private duplicates) ───────────────────────────────────────────

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
                .map(|dt| chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(dt, chrono::Utc))
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
    fn cumulative_runs_forward_per_currency() {
        let entries = vec![
            entry("e_jan", "2026-01-15T10:00:00Z"),
            entry("e_feb", "2026-02-10T10:00:00Z"),
            entry("e_mar", "2026-03-05T10:00:00Z"),
        ];
        // 1月 +1000，2月 -300，3月 +500
        let postings = vec![
            posting("e_jan", "USD", 1000.0),
            posting("e_feb", "USD", -300.0),
            posting("e_mar", "USD", 500.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&[]));
        assert_eq!(rows.len(), 3);
        // 排序: by year_month
        assert_eq!(rows[0].year_month, "2026-01");
        assert_eq!(rows[0].cumulative_minor, 100_000); // 1000.00 → 100_000 minor
        assert_eq!(rows[0].net_flow_minor, 100_000);
        assert_eq!(rows[1].year_month, "2026-02");
        assert_eq!(rows[1].cumulative_minor, 70_000); // 1000 - 300
        assert_eq!(rows[1].net_flow_minor, -30_000);
        assert_eq!(rows[2].year_month, "2026-03");
        assert_eq!(rows[2].cumulative_minor, 120_000); // 1000 - 300 + 500
    }

    #[test]
    fn currencies_run_independently() {
        let entries = vec![
            entry("e_jan_usd", "2026-01-10T10:00:00Z"),
            entry("e_jan_cny", "2026-01-15T10:00:00Z"),
            entry("e_feb_cny", "2026-02-10T10:00:00Z"),
        ];
        let postings = vec![
            posting("e_jan_usd", "USD", 100.0),
            posting("e_jan_cny", "CNY", 700.0),
            posting("e_feb_cny", "CNY", -200.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&[]));
        // 3 行: 2026-01 USD, 2026-01 CNY, 2026-02 CNY
        assert_eq!(rows.len(), 3);
        let by_key: HashMap<(String, String), &NetWorthRow> = rows
            .iter()
            .map(|r| ((r.year_month.clone(), r.currency.clone()), r))
            .collect();
        assert_eq!(by_key[&("2026-01".into(), "USD".into())].cumulative_minor, 10_000);
        assert_eq!(by_key[&("2026-01".into(), "CNY".into())].cumulative_minor, 70_000);
        assert_eq!(by_key[&("2026-02".into(), "CNY".into())].cumulative_minor, 50_000);
    }

    #[test]
    fn ignores_asset_legs() {
        let entries = vec![entry("buy", "2026-04-15T10:00:00Z")];
        let postings = vec![
            posting("buy", "asset_aapl", 10.0),  // asset leg, ignored
            posting("buy", "USD", -1500.0),       // cash debit
        ];
        let rows = aggregate(&entries, &postings, &assets(&["asset_aapl"]));
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].currency, "USD");
        // Note: 资产买入对应的 cash leg 是 -1500（cash 减少）
        assert_eq!(rows[0].net_flow_minor, -150_000);
    }

    #[test]
    fn ignores_orphan_postings() {
        // posting 引用不存在的 entry
        let postings = vec![posting("ghost", "USD", 100.0)];
        let rows = aggregate(&[], &postings, &assets(&[]));
        assert!(rows.is_empty());
    }

    #[test]
    fn sums_multiple_postings_in_same_month() {
        let entries = vec![
            entry("e1", "2026-04-05T10:00:00Z"),
            entry("e2", "2026-04-15T10:00:00Z"),
            entry("e3", "2026-04-25T10:00:00Z"),
        ];
        let postings = vec![
            posting("e1", "USD", 50.0),
            posting("e2", "USD", -20.0),
            posting("e3", "USD", 30.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&[]));
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].net_flow_minor, 6000); // 50 - 20 + 30 = 60.00
        assert_eq!(rows[0].cumulative_minor, 6000);
    }

    #[test]
    fn empty_input_yields_no_rows() {
        let rows = aggregate(&[], &[], &assets(&[]));
        assert!(rows.is_empty());
    }
}
