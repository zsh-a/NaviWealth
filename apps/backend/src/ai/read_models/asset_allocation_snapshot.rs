//! Snapshot 层 P1 — 资产配置快照。
//!
//! 把 `read_model_holdings_snapshot` 按 (asset_type, currency) 聚合，
//! 暴露给 AI 让它直接回答 "我的股票/加密 占比"。
//!
//! 设计选择：
//!  - 单位是 **cost_basis**（非市值）。云端没有价格/FX 源，硬要算市值
//!    会引入跨币种相加，AI 信任度反而下降。文档显式说明。
//!  - 按 `cost_currency` 分桶。这样 "USD 股票占 USD 总持仓的 60%" 是
//!    真实的；如果跨币种合并到一个 weight，AI 会被误导。
//!  - bucket_dim 当前固定 'asset_type'，schema 预留 'industry' / 'region'
//!    以便未来无 migration 扩展。
//!
//! 刷新：lazy via [`Projection`].

use std::collections::HashMap;

use serde::Deserialize;
use serde_json::Value;
use worker::{D1Database, D1Type};

use crate::error::AppError;

use super::freshness::Freshness;
use super::holdings_snapshot::{query_all as query_holdings, Holding};
use super::projection::{latest_op_log_hlc, now_iso, upsert_freshness_meta, Projection};
use super::WriteMeta;

const NAME: &str = "asset_allocation_snapshot";
const SCHEMA_VERSION: u32 = 1;
const CALCULATION_VERSION: u32 = 1;
const BUCKET_DIM_ASSET_TYPE: &str = "asset_type";

pub struct AssetAllocationSnapshot;

impl Projection for AssetAllocationSnapshot {
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
        let holdings = query_holdings(db, user_id).await?;
        let assets = load_asset_types(db, user_id).await?;
        let buckets = aggregate(&holdings, &assets);

        let refreshed_at = now_iso();
        write_buckets(
            db,
            user_id,
            &buckets,
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
pub struct AllocationBucket {
    pub bucket_dim: String,
    pub bucket_key: String,
    pub currency: String,
    pub total_cost_minor: i64,
    pub position_count: u32,
    pub weight: f64,
}

pub async fn query_all(
    db: &D1Database,
    user_id: &str,
    bucket_dim: Option<&str>,
) -> Result<Vec<AllocationBucket>, AppError> {
    let dim = bucket_dim.unwrap_or(BUCKET_DIM_ASSET_TYPE);
    let stmt = db
        .prepare(
            "SELECT bucket_dim, bucket_key, currency, total_cost_minor,
                    position_count, weight
             FROM read_model_asset_allocation_snapshot
             WHERE user_id = ?1 AND bucket_dim = ?2
             ORDER BY currency, CAST(weight AS REAL) DESC",
        )
        .bind_refs([&D1Type::Text(user_id), &D1Type::Text(dim)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?;
    let rows: Vec<BucketRow> = stmt
        .all()
        .await
        .map_err(|e| AppError::Internal(format!("query: {e}")))?
        .results::<BucketRow>()
        .map_err(|e| AppError::Internal(format!("results: {e}")))?;
    Ok(rows
        .into_iter()
        .map(|r| AllocationBucket {
            bucket_dim: r.bucket_dim,
            bucket_key: r.bucket_key,
            currency: r.currency,
            total_cost_minor: r.total_cost_minor.parse().unwrap_or(0),
            position_count: r.position_count,
            weight: r.weight.parse().unwrap_or(0.0),
        })
        .collect())
}

// ── pure aggregation ───────────────────────────────────────────────────────

pub(crate) fn aggregate(
    holdings: &[Holding],
    asset_types: &HashMap<String, String>,
) -> Vec<AllocationBucket> {
    // (bucket_key, currency) → (total_cost_minor, count)
    let mut sub: HashMap<(String, String), (i64, u32)> = HashMap::new();
    for h in holdings {
        let bucket_key = asset_types
            .get(&h.asset_id)
            .cloned()
            .unwrap_or_else(|| "unknown".to_string());
        let entry = sub
            .entry((bucket_key, h.cost_currency.clone()))
            .or_insert((0i64, 0u32));
        entry.0 += h.cost_basis_minor;
        entry.1 += 1;
    }

    // per-currency totals for weight
    let mut currency_totals: HashMap<String, i64> = HashMap::new();
    for ((_, c), (total, _)) in &sub {
        *currency_totals.entry(c.clone()).or_insert(0) += *total;
    }

    let mut out: Vec<AllocationBucket> = sub
        .into_iter()
        .map(|((bucket_key, currency), (total, count))| {
            let denom = *currency_totals.get(&currency).unwrap_or(&0);
            let weight = if denom == 0 {
                0.0
            } else {
                total as f64 / denom as f64
            };
            AllocationBucket {
                bucket_dim: BUCKET_DIM_ASSET_TYPE.to_string(),
                bucket_key,
                currency,
                total_cost_minor: total,
                position_count: count,
                weight,
            }
        })
        .collect();
    out.sort_by(|a, b| {
        a.currency.cmp(&b.currency).then_with(|| {
            b.weight
                .partial_cmp(&a.weight)
                .unwrap_or(std::cmp::Ordering::Equal)
        })
    });
    out
}

// ── DB plumbing ────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct AssetPayloadRow {
    id: String,
    payload: String,
}

#[derive(Deserialize)]
struct BucketRow {
    bucket_dim: String,
    bucket_key: String,
    currency: String,
    total_cost_minor: String,
    position_count: u32,
    weight: String,
}

async fn load_asset_types(
    db: &D1Database,
    user_id: &str,
) -> Result<HashMap<String, String>, AppError> {
    let stmt = db
        .prepare("SELECT id, payload FROM assets WHERE user_id = ?1 AND deleted_at IS NULL")
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?;
    let rows: Vec<AssetPayloadRow> = stmt
        .all()
        .await
        .map_err(|e| AppError::Internal(format!("query assets: {e}")))?
        .results::<AssetPayloadRow>()
        .map_err(|e| AppError::Internal(format!("parse assets: {e}")))?;
    let mut out = HashMap::with_capacity(rows.len());
    for r in rows {
        if let Ok(v) = serde_json::from_str::<Value>(&r.payload) {
            if let Some(t) = v.get("type").and_then(|x| x.as_str()) {
                out.insert(r.id, t.to_string());
            }
        }
    }
    Ok(out)
}

async fn write_buckets(
    db: &D1Database,
    user_id: &str,
    buckets: &[AllocationBucket],
    meta: WriteMeta<'_>,
) -> Result<(), AppError> {
    db.prepare("DELETE FROM read_model_asset_allocation_snapshot WHERE user_id = ?1")
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind del: {e}")))?
        .run()
        .await
        .map_err(|e| AppError::Internal(format!("del: {e}")))?;

    if buckets.is_empty() {
        return Ok(());
    }
    let stmts: Result<Vec<_>, AppError> = buckets
        .iter()
        .map(|b| {
            let total_str = b.total_cost_minor.to_string();
            let weight_str = format!("{:.6}", b.weight);
            db.prepare(
                "INSERT INTO read_model_asset_allocation_snapshot
                    (user_id, bucket_dim, bucket_key, currency, total_cost_minor,
                     position_count, weight,
                     source_hlc_watermark, refreshed_at,
                     schema_version, calculation_version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(&b.bucket_dim),
                &D1Type::Text(&b.bucket_key),
                &D1Type::Text(&b.currency),
                &D1Type::Text(&total_str),
                &D1Type::Integer(b.position_count as i32),
                &D1Type::Text(&weight_str),
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

#[cfg(test)]
mod tests {
    use super::*;

    fn h(asset_id: &str, cost_basis: i64, currency: &str) -> Holding {
        Holding {
            asset_id: asset_id.to_string(),
            net_qty: 1.0,
            cost_basis_minor: cost_basis,
            cost_currency: currency.to_string(),
        }
    }

    fn types(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs
            .iter()
            .map(|(a, t)| (a.to_string(), t.to_string()))
            .collect()
    }

    #[test]
    fn groups_by_type_and_currency() {
        let holdings = vec![
            h("AAPL", 100_000, "USD"),
            h("MSFT", 50_000, "USD"),
            h("BTC", 200_000, "USD"),
            h("000300", 30_000, "CNY"),
        ];
        let asset_types = types(&[
            ("AAPL", "stock"),
            ("MSFT", "stock"),
            ("BTC", "crypto"),
            ("000300", "etf"),
        ]);
        let buckets = aggregate(&holdings, &asset_types);
        // (stock,USD): 150_000, (crypto,USD): 200_000, (etf,CNY): 30_000
        assert_eq!(buckets.len(), 3);
        let stock_usd = buckets
            .iter()
            .find(|b| b.bucket_key == "stock" && b.currency == "USD")
            .unwrap();
        assert_eq!(stock_usd.total_cost_minor, 150_000);
        assert_eq!(stock_usd.position_count, 2);
        // weight is within USD: 150k / 350k ≈ 0.4286
        assert!((stock_usd.weight - 150_000.0 / 350_000.0).abs() < 1e-9);

        let etf_cny = buckets
            .iter()
            .find(|b| b.bucket_key == "etf" && b.currency == "CNY")
            .unwrap();
        // Only CNY position so weight = 1.0
        assert!((etf_cny.weight - 1.0).abs() < 1e-9);
    }

    #[test]
    fn unknown_type_when_asset_missing_from_lookup() {
        let holdings = vec![h("X", 10_000, "USD")];
        let asset_types = HashMap::new();
        let buckets = aggregate(&holdings, &asset_types);
        assert_eq!(buckets.len(), 1);
        assert_eq!(buckets[0].bucket_key, "unknown");
        assert!((buckets[0].weight - 1.0).abs() < 1e-9);
    }

    #[test]
    fn empty_holdings_returns_empty() {
        let buckets = aggregate(&[], &HashMap::new());
        assert!(buckets.is_empty());
    }

    #[test]
    fn weight_per_currency_sums_to_one_within_currency() {
        let holdings = vec![
            h("A", 10_000, "USD"),
            h("B", 20_000, "USD"),
            h("C", 30_000, "USD"),
        ];
        let asset_types = types(&[("A", "stock"), ("B", "etf"), ("C", "crypto")]);
        let buckets = aggregate(&holdings, &asset_types);
        let sum: f64 = buckets.iter().map(|b| b.weight).sum();
        assert!((sum - 1.0).abs() < 1e-9, "weight sum was {sum}");
    }
}
