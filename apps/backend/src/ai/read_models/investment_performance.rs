//! Analytical 层 P1 — `investment_performance` (device-sourced)。
//!
//! 端侧 `holdingsSnapshotProvider` (FIR-21) 算出当前 per-asset 持仓
//! (quantity / market_value / cost_basis / unrealized_pnl / weight)；
//! chat 准备阶段把每个 asset 当作 `AnalyticalUpload(kind='investment_performance')`
//! 上报。本模块镜像入表，AI 可直接读 "AAPL 现在赚多少" 而无需重算。
//!
//! 与 `xirr_snapshot` 的关系：
//!  - `xirr_snapshot`：cloud-projected，per-scope 全时间窗口 XIRR
//!  - `investment_performance`：device-sourced，per-asset 当前持仓状态
//!    (含 base + asset 双币种视图)
//!
//! payload schema (v1):
//!   {
//!     asset_id, asset_currency, base_currency, as_of,
//!     quantity,
//!     cost_basis_in_asset_currency, market_value_in_asset_currency,
//!     cost_basis_in_base, market_value_in_base, unrealized_pnl_in_base,
//!     weight,
//!     holding_days?
//!   }

use serde::Deserialize;
use serde_json::Value;
use worker::{D1Database, D1Type};

use crate::error::AppError;

use super::freshness::Freshness;
use super::projection::{now_iso, upsert_freshness_meta};

pub const NAME: &str = "investment_performance";
pub const SCHEMA_VERSION: u32 = 1;
pub const CALCULATION_VERSION: u32 = 1;

#[derive(Debug, Clone)]
pub struct InvestmentPerformanceUpload<'a> {
    pub id: &'a str,
    pub payload: &'a Value,
    pub source_device_id: Option<&'a str>,
}

#[derive(Debug, Clone)]
pub struct InvestmentPerformanceRow {
    pub id: String,
    pub asset_id: Option<String>,
    pub asset_currency: Option<String>,
    pub base_currency: Option<String>,
    pub market_value_base: Option<String>,
    pub cost_basis_base: Option<String>,
    pub unrealized_pnl_base: Option<String>,
    pub weight: Option<String>,
    pub holding_days: Option<i64>,
    pub as_of: Option<String>,
    pub payload: Value,
}

pub async fn ingest(
    db: &D1Database,
    user_id: &str,
    device_hlc: &str,
    uploads: &[InvestmentPerformanceUpload<'_>],
) -> Result<usize, AppError> {
    if uploads.is_empty() {
        return Ok(0);
    }
    let refreshed_at = now_iso();
    let stmts: Result<Vec<_>, AppError> = uploads
        .iter()
        .map(|u| {
            let payload_json = serde_json::to_string(u.payload)
                .map_err(|e| AppError::Internal(format!("payload ser: {e}")))?;
            let asset_id = payload_str(u.payload, "asset_id");
            let asset_currency = payload_str(u.payload, "asset_currency");
            let base_currency = payload_str(u.payload, "base_currency");
            let mv = payload_decimal_str(u.payload, "market_value_in_base");
            let cb = payload_decimal_str(u.payload, "cost_basis_in_base");
            let pnl = payload_decimal_str(u.payload, "unrealized_pnl_in_base");
            let weight = payload_decimal_str(u.payload, "weight");
            let holding_days = u
                .payload
                .get("holding_days")
                .and_then(|v| v.as_i64())
                .map(|n| n as i32);
            let as_of = payload_str(u.payload, "as_of");
            db.prepare(
                "INSERT INTO read_model_investment_performance
                    (user_id, id, payload, asset_id, asset_currency, base_currency,
                     market_value_base, cost_basis_base, unrealized_pnl_base,
                     weight, holding_days, as_of, source_device_id,
                     source_hlc_watermark, refreshed_at,
                     schema_version, calculation_version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)
                 ON CONFLICT (user_id, id) DO UPDATE SET
                    payload              = excluded.payload,
                    asset_id             = excluded.asset_id,
                    asset_currency       = excluded.asset_currency,
                    base_currency        = excluded.base_currency,
                    market_value_base    = excluded.market_value_base,
                    cost_basis_base      = excluded.cost_basis_base,
                    unrealized_pnl_base  = excluded.unrealized_pnl_base,
                    weight               = excluded.weight,
                    holding_days         = excluded.holding_days,
                    as_of                = excluded.as_of,
                    source_device_id     = excluded.source_device_id,
                    source_hlc_watermark = excluded.source_hlc_watermark,
                    refreshed_at         = excluded.refreshed_at,
                    schema_version       = excluded.schema_version,
                    calculation_version  = excluded.calculation_version",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(u.id),
                &D1Type::Text(&payload_json),
                &nullable_text(asset_id),
                &nullable_text(asset_currency),
                &nullable_text(base_currency),
                &nullable_text_owned(&mv),
                &nullable_text_owned(&cb),
                &nullable_text_owned(&pnl),
                &nullable_text_owned(&weight),
                &nullable_integer(holding_days),
                &nullable_text(as_of),
                &nullable_text(u.source_device_id),
                &D1Type::Text(device_hlc),
                &D1Type::Text(&refreshed_at),
                &D1Type::Integer(SCHEMA_VERSION as i32),
                &D1Type::Integer(CALCULATION_VERSION as i32),
            ])
            .map_err(|e| AppError::Internal(format!("bind: {e}")))
        })
        .collect();
    let stmts = stmts?;
    let count = stmts.len();
    db.batch(stmts)
        .await
        .map_err(|e| AppError::Internal(format!("batch: {e}")))?;

    let freshness = Freshness::new(
        NAME,
        device_hlc.to_string(),
        refreshed_at,
        SCHEMA_VERSION,
        CALCULATION_VERSION,
    );
    upsert_freshness_meta(db, user_id, &freshness).await?;
    Ok(count)
}

pub async fn query_all(
    db: &D1Database,
    user_id: &str,
    base_currency: Option<&str>,
) -> Result<Vec<InvestmentPerformanceRow>, AppError> {
    let stmt = match base_currency {
        Some(c) => db
            .prepare(
                "SELECT id, payload, asset_id, asset_currency, base_currency,
                        market_value_base, cost_basis_base, unrealized_pnl_base,
                        weight, holding_days, as_of
                 FROM read_model_investment_performance
                 WHERE user_id = ?1 AND base_currency = ?2
                 ORDER BY CAST(market_value_base AS REAL) DESC",
            )
            .bind_refs([&D1Type::Text(user_id), &D1Type::Text(c)])
            .map_err(|e| AppError::Internal(format!("bind: {e}")))?,
        None => db
            .prepare(
                "SELECT id, payload, asset_id, asset_currency, base_currency,
                        market_value_base, cost_basis_base, unrealized_pnl_base,
                        weight, holding_days, as_of
                 FROM read_model_investment_performance
                 WHERE user_id = ?1
                 ORDER BY CAST(market_value_base AS REAL) DESC",
            )
            .bind_refs([&D1Type::Text(user_id)])
            .map_err(|e| AppError::Internal(format!("bind: {e}")))?,
    };
    let raw: Vec<RowSelect> = stmt
        .all()
        .await
        .map_err(|e| AppError::Internal(format!("query: {e}")))?
        .results::<RowSelect>()
        .map_err(|e| AppError::Internal(format!("results: {e}")))?;
    Ok(raw
        .into_iter()
        .map(|r| InvestmentPerformanceRow {
            id: r.id,
            asset_id: r.asset_id,
            asset_currency: r.asset_currency,
            base_currency: r.base_currency,
            market_value_base: r.market_value_base,
            cost_basis_base: r.cost_basis_base,
            unrealized_pnl_base: r.unrealized_pnl_base,
            weight: r.weight,
            holding_days: r.holding_days,
            as_of: r.as_of,
            payload: serde_json::from_str(&r.payload).unwrap_or(Value::Null),
        })
        .collect())
}

pub async fn current_freshness(
    db: &D1Database,
    user_id: &str,
) -> Result<Option<Freshness>, AppError> {
    super::projection::load_freshness_meta(db, user_id, NAME).await
}

#[derive(Deserialize)]
struct RowSelect {
    id: String,
    payload: String,
    asset_id: Option<String>,
    asset_currency: Option<String>,
    base_currency: Option<String>,
    market_value_base: Option<String>,
    cost_basis_base: Option<String>,
    unrealized_pnl_base: Option<String>,
    weight: Option<String>,
    holding_days: Option<i64>,
    as_of: Option<String>,
}

fn payload_str<'a>(p: &'a Value, key: &str) -> Option<&'a str> {
    p.get(key).and_then(|v| v.as_str())
}

/// Decimal-flavoured field — accept either Dart-side string serialisation
/// or numeric JSON. Always emitted as string for D1 to avoid float loss.
fn payload_decimal_str(p: &Value, key: &str) -> Option<String> {
    let v = p.get(key)?;
    if let Some(s) = v.as_str() {
        return Some(s.to_string());
    }
    if let Some(n) = v.as_i64() {
        return Some(n.to_string());
    }
    if let Some(n) = v.as_f64() {
        return Some(n.to_string());
    }
    None
}

fn nullable_text(s: Option<&str>) -> D1Type<'_> {
    match s {
        Some(t) => D1Type::Text(t),
        None => D1Type::Null,
    }
}

fn nullable_text_owned(s: &Option<String>) -> D1Type<'_> {
    match s {
        Some(t) => D1Type::Text(t.as_str()),
        None => D1Type::Null,
    }
}

fn nullable_integer(n: Option<i32>) -> D1Type<'static> {
    match n {
        Some(v) => D1Type::Integer(v),
        None => D1Type::Null,
    }
}
