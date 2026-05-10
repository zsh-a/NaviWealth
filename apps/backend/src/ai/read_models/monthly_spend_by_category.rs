//! Snapshot 层 P0 — 月 × 类目 × 币种 的支出聚合。
//!
//! 数据来源:
//!  - `journal_entries.payload.category` 必须存在（典型来自 propose_expense
//!    或导入的支出条目；transfer / 投资交易没有 category 字段，自然被排除）。
//!  - `journal_entries.payload.date` 取 year_month。
//!  - `postings.payload.unit` 不在 `assets.id` 集合中（即 fiat 币种）。
//!  - `postings.payload.units` 仅取正值（debit / 支出端）。负值是付款账户
//!    的 credit leg，sum 全部会重复计数。
//!
//! Phase 1 简化:
//!  - txn_count 按 posting 计数（不去重 entry）。一笔典型支出对应一条
//!    fiat 正向 posting，差异极小；后续 Schema v2 可改成 entry-distinct。
//!  - currency 直接用 posting.unit 字符串，不做 normalization。
//!  - 跨币种支出不合并；每种币种独立成行。
//!
//! 刷新策略: Lazy（[`super::Projection::refresh_mode`] 默认值）。

use std::collections::{HashMap, HashSet};

use chrono::{DateTime, Datelike, Utc};
use serde::Deserialize;
use serde_json::Value;
use worker::{D1Database, D1Type};

use crate::error::AppError;

use super::freshness::Freshness;
use super::projection::{
    latest_op_log_hlc, now_iso, upsert_freshness_meta, Projection,
};

const NAME: &str = "monthly_spend_by_category";
const SCHEMA_VERSION: u32 = 1;
const CALCULATION_VERSION: u32 = 1;

pub struct MonthlySpendByCategory;

impl Projection for MonthlySpendByCategory {
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
        // 1. 抓 watermark on entry — 并发的新 op 会让下次 ensure_fresh 触发
        //    再次刷新，正确性优先。
        let watermark = latest_op_log_hlc(db, user_id)
            .await?
            .unwrap_or_default();

        // 2. 读取依赖的 sync 表。
        let assets = load_payloads(db, user_id, "assets").await?;
        let asset_ids: HashSet<String> = assets.into_iter().map(|(id, _)| id).collect();
        let entries = load_payloads(db, user_id, "journal_entries").await?;
        let postings = load_payloads(db, user_id, "postings").await?;

        // 3. 纯函数聚合（可测）。
        let buckets = aggregate(&entries, &postings, &asset_ids);

        // 4. 写库 — DELETE 当前用户全部行 + 重建 + 更新 meta，一个 batch。
        let refreshed_at = now_iso();
        write_buckets(
            db,
            user_id,
            &buckets,
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

/// 一行聚合结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Bucket {
    pub year_month: String,
    pub category: String,
    pub currency: String,
    pub total_minor: i64,
    pub txn_count: u32,
}

/// 工具读路径：从 read model 表查 (year_month, category 可选) 的结果。
/// 调用前应先经 `ensure_fresh` 保证 freshness_meta 最新。
pub async fn query(
    db: &D1Database,
    user_id: &str,
    year_month: &str,
    category: Option<&str>,
) -> Result<Vec<Bucket>, AppError> {
    let stmt = match category {
        Some(c) => db
            .prepare(
                "SELECT year_month, category, currency, total_minor, txn_count
                 FROM read_model_monthly_spend_by_category
                 WHERE user_id = ?1 AND year_month = ?2 AND category = ?3
                 ORDER BY currency",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(year_month),
                &D1Type::Text(c),
            ])
            .map_err(|e| AppError::Internal(format!("bind: {e}")))?,
        None => db
            .prepare(
                "SELECT year_month, category, currency, total_minor, txn_count
                 FROM read_model_monthly_spend_by_category
                 WHERE user_id = ?1 AND year_month = ?2
                 ORDER BY total_minor DESC",
            )
            .bind_refs([&D1Type::Text(user_id), &D1Type::Text(year_month)])
            .map_err(|e| AppError::Internal(format!("bind: {e}")))?,
    };
    let rows: Vec<BucketRow> = stmt
        .all()
        .await
        .map_err(|e| AppError::Internal(format!("query: {e}")))?
        .results::<BucketRow>()
        .map_err(|e| AppError::Internal(format!("results: {e}")))?;
    Ok(rows
        .into_iter()
        .map(|r| Bucket {
            year_month: r.year_month,
            category: r.category,
            currency: r.currency,
            total_minor: r.total_minor.parse().unwrap_or(0),
            txn_count: r.txn_count,
        })
        .collect())
}

// ── pure aggregation logic (testable) ──────────────────────────────────────

/// 把 `(entries, postings, asset_ids)` 聚合成 buckets。纯函数，无 IO。
pub(crate) fn aggregate(
    entries: &[(String, Value)],
    postings: &[(String, Value)],
    asset_ids: &HashSet<String>,
) -> Vec<Bucket> {
    let mut entry_meta: HashMap<&str, EntryMeta> = HashMap::new();
    for (id, p) in entries {
        let category = payload_str(p, "category").map(str::to_string);
        let date = payload_str(p, "date").and_then(parse_iso);
        if let (Some(cat), Some(d)) = (category, date) {
            if cat.is_empty() {
                continue;
            }
            entry_meta.insert(
                id.as_str(),
                EntryMeta {
                    category: cat,
                    year_month: format!("{:04}-{:02}", d.year(), d.month()),
                },
            );
        }
    }

    let mut buckets: HashMap<(String, String, String), (i128, u32)> = HashMap::new();
    for (_, p) in postings {
        let Some(unit) = payload_str(p, "unit") else {
            continue;
        };
        if asset_ids.contains(unit) {
            continue; // 资产 leg 不算支出
        }
        let Some(entry_id) = payload_str(p, "journal_entry_id") else {
            continue;
        };
        let Some(meta) = entry_meta.get(entry_id) else {
            continue; // 没有 category 的 entry 跳过（transfer / 资产交易）
        };
        let units = payload_num(p, "units").unwrap_or(0.0);
        if units <= 0.0 {
            continue; // 只取 debit (支出) leg；负的是付款账户的对侧
        }
        let amount_minor = (units * 100.0).round() as i128;
        let key = (
            meta.year_month.clone(),
            meta.category.clone(),
            unit.to_string(),
        );
        let entry = buckets.entry(key).or_insert((0, 0));
        entry.0 += amount_minor;
        entry.1 += 1;
    }

    let mut out: Vec<Bucket> = buckets
        .into_iter()
        .map(|((year_month, category, currency), (total_minor, count))| Bucket {
            year_month,
            category,
            currency,
            total_minor: total_minor as i64,
            txn_count: count,
        })
        .collect();
    out.sort_by(|a, b| {
        a.year_month
            .cmp(&b.year_month)
            .then_with(|| a.category.cmp(&b.category))
            .then_with(|| a.currency.cmp(&b.currency))
    });
    out
}

struct EntryMeta {
    category: String,
    year_month: String,
}

// ── DB plumbing ────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct PayloadRow {
    id: String,
    payload: String,
}

#[derive(Deserialize)]
struct BucketRow {
    year_month: String,
    category: String,
    currency: String,
    total_minor: String,
    txn_count: u32,
}

async fn load_payloads(
    db: &D1Database,
    user_id: &str,
    table: &str,
) -> Result<Vec<(String, Value)>, AppError> {
    // SQL 注入防护: table 是常量字符串集合（'assets' / 'journal_entries' /
    // 'postings'），调用方负责。这里不接受任意输入。
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
        match serde_json::from_str::<Value>(&r.payload) {
            Ok(v) => out.push((r.id, v)),
            Err(_) => continue, // 跳过 corrupt payload
        }
    }
    Ok(out)
}

#[allow(clippy::too_many_arguments)]
async fn write_buckets(
    db: &D1Database,
    user_id: &str,
    buckets: &[Bucket],
    watermark: &str,
    refreshed_at: &str,
    schema_version: u32,
    calculation_version: u32,
) -> Result<(), AppError> {
    // 先 DELETE 用户所有行（保证淘汰已没的桶），再批量 INSERT。
    db.prepare("DELETE FROM read_model_monthly_spend_by_category WHERE user_id = ?1")
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind del: {e}")))?
        .run()
        .await
        .map_err(|e| AppError::Internal(format!("del: {e}")))?;

    if buckets.is_empty() {
        return Ok(());
    }

    // D1 支持 batch ≤ 1000 条；典型用户 ~ 200 buckets，单 batch 够。
    let stmts: Result<Vec<_>, AppError> = buckets
        .iter()
        .map(|b| {
            let total_str = b.total_minor.to_string();
            db.prepare(
                "INSERT INTO read_model_monthly_spend_by_category
                    (user_id, year_month, category, currency, total_minor,
                     txn_count, source_hlc_watermark, refreshed_at,
                     schema_version, calculation_version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(&b.year_month),
                &D1Type::Text(&b.category),
                &D1Type::Text(&b.currency),
                &D1Type::Text(&total_str),
                &D1Type::Integer(b.txn_count as i32),
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

// ── small helpers (private; duplicated from tools.rs to avoid coupling) ────

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
            // YYYY-MM-DD 也接受
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

    fn entry(id: &str, date: &str, category: &str) -> (String, Value) {
        (
            id.into(),
            json!({ "date": date, "category": category }),
        )
    }

    fn posting(entry_id: &str, unit: &str, units: f64) -> (String, Value) {
        (
            format!("p_{entry_id}_{unit}"),
            json!({
                "journal_entry_id": entry_id,
                "unit": unit,
                "units": units,
            }),
        )
    }

    fn assets(ids: &[&str]) -> HashSet<String> {
        ids.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn aggregates_a_simple_food_expense() {
        let entries = vec![entry("e1", "2026-04-15T10:00:00Z", "food")];
        let postings = vec![
            posting("e1", "USD", 12.50),  // expense leg (debit)
            posting("e1", "USD", -12.50), // payment account leg (credit)
        ];
        let buckets = aggregate(&entries, &postings, &assets(&[]));
        assert_eq!(buckets.len(), 1);
        let b = &buckets[0];
        assert_eq!(b.year_month, "2026-04");
        assert_eq!(b.category, "food");
        assert_eq!(b.currency, "USD");
        assert_eq!(b.total_minor, 1250);
        assert_eq!(b.txn_count, 1);
    }

    #[test]
    fn ignores_entries_without_category() {
        // Transfers / asset trades have no `category` in payload.
        let entries = vec![(
            "transfer_1".into(),
            json!({ "date": "2026-04-15T10:00:00Z" }),
        )];
        let postings = vec![
            posting("transfer_1", "USD", 1000.0),
            posting("transfer_1", "USD", -1000.0),
        ];
        let buckets = aggregate(&entries, &postings, &assets(&[]));
        assert!(buckets.is_empty());
    }

    #[test]
    fn ignores_postings_against_assets() {
        // Buying AAPL: postings include the asset leg (unit = asset id).
        // Even if the buy entry had a category, asset legs are skipped.
        let entries = vec![entry("buy_1", "2026-04-15T10:00:00Z", "shopping")];
        let postings = vec![
            posting("buy_1", "asset_aapl", 10.0), // qty leg, NOT an expense
            posting("buy_1", "USD", 1500.0),      // cash debit
            posting("buy_1", "USD", -1500.0),     // payment credit
        ];
        let buckets = aggregate(&entries, &postings, &assets(&["asset_aapl"]));
        assert_eq!(buckets.len(), 1);
        assert_eq!(buckets[0].currency, "USD");
        assert_eq!(buckets[0].total_minor, 150_000);
    }

    #[test]
    fn separates_currencies() {
        let entries = vec![
            entry("e_us", "2026-04-15T10:00:00Z", "food"),
            entry("e_cn", "2026-04-16T10:00:00Z", "food"),
        ];
        let postings = vec![
            posting("e_us", "USD", 10.0),
            posting("e_cn", "CNY", 70.0),
        ];
        let buckets = aggregate(&entries, &postings, &assets(&[]));
        assert_eq!(buckets.len(), 2);
        let by_curr: HashMap<&str, &Bucket> =
            buckets.iter().map(|b| (b.currency.as_str(), b)).collect();
        assert_eq!(by_curr["USD"].total_minor, 1000);
        assert_eq!(by_curr["CNY"].total_minor, 7000);
    }

    #[test]
    fn separates_year_months() {
        let entries = vec![
            entry("e_apr", "2026-04-15T10:00:00Z", "food"),
            entry("e_may", "2026-05-15T10:00:00Z", "food"),
        ];
        let postings = vec![
            posting("e_apr", "USD", 10.0),
            posting("e_may", "USD", 20.0),
        ];
        let buckets = aggregate(&entries, &postings, &assets(&[]));
        assert_eq!(buckets.len(), 2);
        // 排序: year_month 升序
        assert_eq!(buckets[0].year_month, "2026-04");
        assert_eq!(buckets[1].year_month, "2026-05");
    }

    #[test]
    fn sums_multiple_postings_in_same_bucket() {
        let entries = vec![
            entry("e1", "2026-04-01T10:00:00Z", "food"),
            entry("e2", "2026-04-15T10:00:00Z", "food"),
            entry("e3", "2026-04-20T10:00:00Z", "food"),
        ];
        let postings = vec![
            posting("e1", "USD", 5.0),
            posting("e2", "USD", 12.5),
            posting("e3", "USD", 3.0),
        ];
        let buckets = aggregate(&entries, &postings, &assets(&[]));
        assert_eq!(buckets.len(), 1);
        let b = &buckets[0];
        assert_eq!(b.total_minor, 5_00 + 12_50 + 3_00);
        assert_eq!(b.txn_count, 3);
    }

    #[test]
    fn empty_inputs_produce_no_buckets() {
        let buckets = aggregate(&[], &[], &assets(&[]));
        assert!(buckets.is_empty());
    }

    #[test]
    fn ignores_orphan_postings() {
        // Posting refers to entry_id we don't have meta for.
        let postings = vec![posting("ghost", "USD", 99.0)];
        let buckets = aggregate(&[], &postings, &assets(&[]));
        assert!(buckets.is_empty());
    }

    #[test]
    fn parse_iso_accepts_date_only() {
        let d = parse_iso("2026-04-15").expect("parse");
        assert_eq!(d.year(), 2026);
        assert_eq!(d.month(), 4);
        assert_eq!(d.day(), 15);
    }
}
