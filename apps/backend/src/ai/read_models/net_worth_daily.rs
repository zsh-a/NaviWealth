//! Snapshot 层 P1 — per-day 净现金流累计快照。
//!
//! 与 `net_worth_snapshot` (monthly) 同源 / 同算法，差异只在 bucket
//! 粒度 (per-day vs per-month)。两个表分别物化的原因:
//!  - month: 服务 `compute_net_worth(month)` / `get_net_worth_summary` ——
//!    体量小、查询频繁
//!  - day:   服务 `compute_net_worth(day/week)` —— per-day 写入是 day/week
//!    重采样的最小公倍数
//!
//! Week granularity 通过对 day 行重采样实现（不另外建 weekly 表）；
//! month granularity 仍走 `net_worth_snapshot`（避免单一日表派生月分
//! 时多 30 倍 row scan）。
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

const NAME: &str = "net_worth_daily";
const SCHEMA_VERSION: u32 = 1;
const CALCULATION_VERSION: u32 = 1;

pub struct NetWorthDaily;

impl Projection for NetWorthDaily {
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

#[derive(Debug, Clone, PartialEq)]
pub struct NetWorthDailyRow {
    pub yyyy_mm_dd: String,
    pub currency: String,
    pub cumulative_minor: i64,
    pub net_flow_minor: i64,
}

/// 按日期范围 + 可选币种过滤；闭区间 [from_yyyy_mm_dd, to_yyyy_mm_dd]。
pub async fn query_range(
    db: &D1Database,
    user_id: &str,
    from_yyyy_mm_dd: &str,
    to_yyyy_mm_dd: &str,
    currency: Option<&str>,
) -> Result<Vec<NetWorthDailyRow>, AppError> {
    let stmt = match currency {
        Some(c) => db
            .prepare(
                "SELECT yyyy_mm_dd, currency, cumulative_minor, net_flow_minor
                 FROM read_model_net_worth_daily
                 WHERE user_id = ?1
                   AND yyyy_mm_dd >= ?2
                   AND yyyy_mm_dd <= ?3
                   AND currency = ?4
                 ORDER BY yyyy_mm_dd, currency",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(from_yyyy_mm_dd),
                &D1Type::Text(to_yyyy_mm_dd),
                &D1Type::Text(c),
            ])
            .map_err(|e| AppError::Internal(format!("bind: {e}")))?,
        None => db
            .prepare(
                "SELECT yyyy_mm_dd, currency, cumulative_minor, net_flow_minor
                 FROM read_model_net_worth_daily
                 WHERE user_id = ?1
                   AND yyyy_mm_dd >= ?2
                   AND yyyy_mm_dd <= ?3
                 ORDER BY yyyy_mm_dd, currency",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(from_yyyy_mm_dd),
                &D1Type::Text(to_yyyy_mm_dd),
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
        .map(|r| NetWorthDailyRow {
            yyyy_mm_dd: r.yyyy_mm_dd,
            currency: r.currency,
            cumulative_minor: r.cumulative_minor.parse().unwrap_or(0),
            net_flow_minor: r.net_flow_minor.parse().unwrap_or(0),
        })
        .collect())
}

// ── pure aggregation ───────────────────────────────────────────────────────

pub(crate) fn aggregate(
    entries: &[(String, Value)],
    postings: &[(String, Value)],
    asset_ids: &HashSet<String>,
) -> Vec<NetWorthDailyRow> {
    // entry_id → yyyy-mm-dd
    let mut entry_date: HashMap<&str, String> = HashMap::new();
    for (id, p) in entries {
        let Some(d) = payload_str(p, "date").and_then(parse_iso) else {
            continue;
        };
        entry_date.insert(
            id.as_str(),
            format!("{:04}-{:02}-{:02}", d.year(), d.month(), d.day()),
        );
    }

    // (yyyy-mm-dd, currency) → net_flow_minor
    let mut flows: HashMap<(String, String), i128> = HashMap::new();
    for (_, p) in postings {
        let Some(unit) = payload_str(p, "unit") else {
            continue;
        };
        if asset_ids.contains(unit) {
            continue;
        }
        let Some(eid) = payload_str(p, "journal_entry_id") else {
            continue;
        };
        let Some(date) = entry_date.get(eid) else {
            continue;
        };
        let units = payload_num(p, "units").unwrap_or(0.0);
        let minor = (units * 100.0).round() as i128;
        let key = (date.clone(), unit.to_string());
        *flows.entry(key).or_insert(0) += minor;
    }

    // per-currency 时间序列：按 date 排序，累加得到 cumulative
    let mut by_currency: HashMap<String, Vec<(String, i64)>> = HashMap::new();
    for ((date, currency), net) in flows {
        by_currency
            .entry(currency)
            .or_default()
            .push((date, net as i64));
    }
    let mut out: Vec<NetWorthDailyRow> = Vec::new();
    for (currency, mut series) in by_currency {
        series.sort_by(|a, b| a.0.cmp(&b.0));
        let mut running: i64 = 0;
        for (date, net) in series {
            running = running.saturating_add(net);
            out.push(NetWorthDailyRow {
                yyyy_mm_dd: date,
                currency: currency.clone(),
                cumulative_minor: running,
                net_flow_minor: net,
            });
        }
    }
    out.sort_by(|a, b| {
        a.yyyy_mm_dd
            .cmp(&b.yyyy_mm_dd)
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
    yyyy_mm_dd: String,
    currency: String,
    cumulative_minor: String,
    net_flow_minor: String,
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
    rows: &[NetWorthDailyRow],
    meta: WriteMeta<'_>,
) -> Result<(), AppError> {
    db.prepare("DELETE FROM read_model_net_worth_daily WHERE user_id = ?1")
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
                "INSERT INTO read_model_net_worth_daily
                    (user_id, yyyy_mm_dd, currency, cumulative_minor, net_flow_minor,
                     source_hlc_watermark, refreshed_at, schema_version, calculation_version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(&r.yyyy_mm_dd),
                &D1Type::Text(&r.currency),
                &D1Type::Text(&cum_str),
                &D1Type::Text(&flow_str),
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
    fn cumulative_runs_forward_per_day() {
        let entries = vec![
            entry("e1", "2026-05-01T10:00:00Z"),
            entry("e2", "2026-05-02T10:00:00Z"),
            entry("e3", "2026-05-04T10:00:00Z"),
        ];
        let postings = vec![
            posting("e1", "USD", 100.0),
            posting("e2", "USD", -30.0),
            posting("e3", "USD", 50.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&[]));
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].yyyy_mm_dd, "2026-05-01");
        assert_eq!(rows[0].cumulative_minor, 10_000);
        assert_eq!(rows[1].yyyy_mm_dd, "2026-05-02");
        assert_eq!(rows[1].cumulative_minor, 7_000);
        assert_eq!(rows[2].yyyy_mm_dd, "2026-05-04");
        assert_eq!(rows[2].cumulative_minor, 12_000);
    }

    #[test]
    fn same_day_multiple_entries_collapse_to_one_row() {
        let entries = vec![
            entry("breakfast", "2026-05-01T08:00:00Z"),
            entry("lunch", "2026-05-01T12:00:00Z"),
            entry("dinner", "2026-05-01T19:00:00Z"),
        ];
        let postings = vec![
            posting("breakfast", "USD", -10.0),
            posting("lunch", "USD", -20.0),
            posting("dinner", "USD", -30.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&[]));
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].net_flow_minor, -6_000);
    }

    #[test]
    fn currencies_run_independently() {
        let entries = vec![
            entry("e_usd", "2026-05-01T10:00:00Z"),
            entry("e_cny_1", "2026-05-01T11:00:00Z"),
            entry("e_cny_2", "2026-05-03T10:00:00Z"),
        ];
        let postings = vec![
            posting("e_usd", "USD", 100.0),
            posting("e_cny_1", "CNY", 700.0),
            posting("e_cny_2", "CNY", -200.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&[]));
        // 3 rows: 2026-05-01 USD, 2026-05-01 CNY, 2026-05-03 CNY
        assert_eq!(rows.len(), 3);
        let by_key: HashMap<(String, String), &NetWorthDailyRow> = rows
            .iter()
            .map(|r| ((r.yyyy_mm_dd.clone(), r.currency.clone()), r))
            .collect();
        assert_eq!(
            by_key[&("2026-05-01".into(), "USD".into())].cumulative_minor,
            10_000
        );
        assert_eq!(
            by_key[&("2026-05-01".into(), "CNY".into())].cumulative_minor,
            70_000
        );
        assert_eq!(
            by_key[&("2026-05-03".into(), "CNY".into())].cumulative_minor,
            50_000
        );
    }

    #[test]
    fn ignores_asset_legs() {
        let entries = vec![entry("buy", "2026-04-15T10:00:00Z")];
        let postings = vec![
            posting("buy", "asset_aapl", 10.0),
            posting("buy", "USD", -1500.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&["asset_aapl"]));
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].currency, "USD");
        assert_eq!(rows[0].net_flow_minor, -150_000);
    }

    #[test]
    fn empty_input_yields_no_rows() {
        let rows = aggregate(&[], &[], &assets(&[]));
        assert!(rows.is_empty());
    }

    #[test]
    fn sorts_by_date_then_currency() {
        let entries = vec![
            entry("e_d1_cny", "2026-05-01T11:00:00Z"),
            entry("e_d1_usd", "2026-05-01T10:00:00Z"),
            entry("e_d2_usd", "2026-05-02T10:00:00Z"),
        ];
        let postings = vec![
            posting("e_d1_cny", "CNY", 100.0),
            posting("e_d1_usd", "USD", 100.0),
            posting("e_d2_usd", "USD", 200.0),
        ];
        let rows = aggregate(&entries, &postings, &assets(&[]));
        assert_eq!(rows.len(), 3);
        // (2026-05-01, CNY), (2026-05-01, USD), (2026-05-02, USD)
        let keys: Vec<(String, String)> = rows
            .iter()
            .map(|r| (r.yyyy_mm_dd.clone(), r.currency.clone()))
            .collect();
        assert_eq!(
            keys,
            vec![
                ("2026-05-01".into(), "CNY".into()),
                ("2026-05-01".into(), "USD".into()),
                ("2026-05-02".into(), "USD".into()),
            ]
        );
    }
}
