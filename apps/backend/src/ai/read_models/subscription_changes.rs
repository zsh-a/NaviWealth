//! Analytical 层 P1 — `subscription_changes` (device-sourced)。
//!
//! 端侧 `detectSubscriptionChanges` 跑在 recurring_detector 的输出上：
//! 把每个 recurring 模式的 occurrences 按时间一分为二，比较 earlier
//! 与 later half 的 median 金额差。超过 (10% AND 100 minor) 的就上报。
//!
//! payload schema (v1):
//!   { merchant_key, cadence, currency,
//!     prev_amount_minor, new_amount_minor, delta_ratio, since }

use serde::Deserialize;
use serde_json::Value;
use worker::{D1Database, D1Type};

use crate::error::AppError;

use super::freshness::Freshness;
use super::projection::{now_iso, upsert_freshness_meta};

pub const NAME: &str = "subscription_changes";
pub const SCHEMA_VERSION: u32 = 1;
pub const CALCULATION_VERSION: u32 = 1;

#[derive(Debug, Clone)]
pub struct SubscriptionChangeUpload<'a> {
    pub id: &'a str,
    pub payload: &'a Value,
    pub source_device_id: Option<&'a str>,
}

#[derive(Debug, Clone)]
pub struct SubscriptionChangeRow {
    pub id: String,
    pub merchant_key: Option<String>,
    pub cadence: Option<String>,
    pub currency: Option<String>,
    pub prev_amount_minor: Option<i64>,
    pub new_amount_minor: Option<i64>,
    pub delta_ratio: Option<f64>,
    pub since: Option<String>,
    pub payload: Value,
}

pub async fn ingest(
    db: &D1Database,
    user_id: &str,
    device_hlc: &str,
    uploads: &[SubscriptionChangeUpload<'_>],
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
            let merchant = payload_str(u.payload, "merchant_key");
            let cadence = payload_str(u.payload, "cadence");
            let currency = payload_str(u.payload, "currency");
            let prev_amt = payload_amount_minor(u.payload, "prev_amount_minor");
            let new_amt = payload_amount_minor(u.payload, "new_amount_minor");
            let delta_ratio = payload_decimal_str(u.payload, "delta_ratio");
            let since = payload_str(u.payload, "since");
            db.prepare(
                "INSERT INTO read_model_subscription_changes
                    (user_id, id, payload, merchant_key, cadence, currency,
                     prev_amount_minor, new_amount_minor, delta_ratio, since,
                     source_device_id, source_hlc_watermark, refreshed_at,
                     schema_version, calculation_version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)
                 ON CONFLICT (user_id, id) DO UPDATE SET
                    payload              = excluded.payload,
                    merchant_key         = excluded.merchant_key,
                    cadence              = excluded.cadence,
                    currency             = excluded.currency,
                    prev_amount_minor    = excluded.prev_amount_minor,
                    new_amount_minor     = excluded.new_amount_minor,
                    delta_ratio          = excluded.delta_ratio,
                    since                = excluded.since,
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
                &nullable_text(merchant),
                &nullable_text(cadence),
                &nullable_text(currency),
                &nullable_text_owned(&prev_amt),
                &nullable_text_owned(&new_amt),
                &nullable_text_owned(&delta_ratio),
                &nullable_text(since),
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
    currency: Option<&str>,
) -> Result<Vec<SubscriptionChangeRow>, AppError> {
    let stmt = match currency {
        Some(c) => db
            .prepare(
                "SELECT id, payload, merchant_key, cadence, currency,
                        prev_amount_minor, new_amount_minor, delta_ratio, since
                 FROM read_model_subscription_changes
                 WHERE user_id = ?1 AND currency = ?2
                 ORDER BY CAST(delta_ratio AS REAL) DESC",
            )
            .bind_refs([&D1Type::Text(user_id), &D1Type::Text(c)])
            .map_err(|e| AppError::Internal(format!("bind: {e}")))?,
        None => db
            .prepare(
                "SELECT id, payload, merchant_key, cadence, currency,
                        prev_amount_minor, new_amount_minor, delta_ratio, since
                 FROM read_model_subscription_changes
                 WHERE user_id = ?1
                 ORDER BY CAST(delta_ratio AS REAL) DESC",
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
        .map(|r| SubscriptionChangeRow {
            id: r.id,
            merchant_key: r.merchant_key,
            cadence: r.cadence,
            currency: r.currency,
            prev_amount_minor: r.prev_amount_minor.and_then(|s| s.parse().ok()),
            new_amount_minor: r.new_amount_minor.and_then(|s| s.parse().ok()),
            delta_ratio: r.delta_ratio.and_then(|s| s.parse().ok()),
            since: r.since,
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
    merchant_key: Option<String>,
    cadence: Option<String>,
    currency: Option<String>,
    prev_amount_minor: Option<String>,
    new_amount_minor: Option<String>,
    delta_ratio: Option<String>,
    since: Option<String>,
}

fn payload_str<'a>(p: &'a Value, key: &str) -> Option<&'a str> {
    p.get(key).and_then(|v| v.as_str())
}

fn payload_amount_minor(p: &Value, key: &str) -> Option<String> {
    let v = p.get(key)?;
    if let Some(s) = v.as_str() {
        return Some(s.to_string());
    }
    if let Some(n) = v.as_i64() {
        return Some(n.to_string());
    }
    if let Some(n) = v.as_f64() {
        return Some((n as i64).to_string());
    }
    None
}

fn payload_decimal_str(p: &Value, key: &str) -> Option<String> {
    let v = p.get(key)?;
    if let Some(s) = v.as_str() {
        return Some(s.to_string());
    }
    if let Some(n) = v.as_f64() {
        return Some(n.to_string());
    }
    if let Some(n) = v.as_i64() {
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
