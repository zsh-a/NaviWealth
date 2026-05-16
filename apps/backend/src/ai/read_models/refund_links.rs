//! Analytical 层 P1 — `refund_links` (device-sourced)。
//!
//! 端侧 `refundMatcher` (Wave 2-B) 把 "原交易 + 后续退款" 配成一对，
//! 通过 ContextPack.analytical_uploads (kind='refund_link') 上报，
//! 本模块镜像入表。
//!
//! payload schema (v1):
//!   { original_txn_id, refund_txn_id, amount_minor, currency }

use serde::Deserialize;
use serde_json::Value;
use worker::{D1Database, D1Type};

use crate::error::AppError;

use super::freshness::Freshness;
use super::projection::{now_iso, upsert_freshness_meta};

pub const NAME: &str = "refund_links";
pub const SCHEMA_VERSION: u32 = 1;
pub const CALCULATION_VERSION: u32 = 1;

#[derive(Debug, Clone)]
pub struct RefundLinkUpload<'a> {
    pub id: &'a str,
    pub payload: &'a Value,
    pub source_device_id: Option<&'a str>,
}

#[derive(Debug, Clone)]
pub struct RefundLinkRow {
    pub id: String,
    pub original_txn_id: Option<String>,
    pub refund_txn_id: Option<String>,
    pub amount_minor: Option<i64>,
    pub currency: Option<String>,
    pub payload: Value,
}

pub async fn ingest(
    db: &D1Database,
    user_id: &str,
    device_hlc: &str,
    uploads: &[RefundLinkUpload<'_>],
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
            let original = payload_str(u.payload, "original_txn_id");
            let refund = payload_str(u.payload, "refund_txn_id");
            let amount = payload_amount_minor(u.payload, "amount_minor");
            let currency = payload_str(u.payload, "currency");
            db.prepare(
                "INSERT INTO read_model_refund_links
                    (user_id, id, payload, original_txn_id, refund_txn_id,
                     amount_minor, currency, source_device_id,
                     source_hlc_watermark, refreshed_at,
                     schema_version, calculation_version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
                 ON CONFLICT (user_id, id) DO UPDATE SET
                    payload              = excluded.payload,
                    original_txn_id      = excluded.original_txn_id,
                    refund_txn_id        = excluded.refund_txn_id,
                    amount_minor         = excluded.amount_minor,
                    currency             = excluded.currency,
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
                &nullable_text(original),
                &nullable_text(refund),
                &nullable_text_owned(&amount),
                &nullable_text(currency),
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
) -> Result<Vec<RefundLinkRow>, AppError> {
    let stmt = match currency {
        Some(c) => db
            .prepare(
                "SELECT id, payload, original_txn_id, refund_txn_id, amount_minor, currency
                 FROM read_model_refund_links
                 WHERE user_id = ?1 AND currency = ?2
                 ORDER BY refreshed_at DESC",
            )
            .bind_refs([&D1Type::Text(user_id), &D1Type::Text(c)])
            .map_err(|e| AppError::Internal(format!("bind: {e}")))?,
        None => db
            .prepare(
                "SELECT id, payload, original_txn_id, refund_txn_id, amount_minor, currency
                 FROM read_model_refund_links
                 WHERE user_id = ?1
                 ORDER BY refreshed_at DESC",
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
        .map(|r| RefundLinkRow {
            id: r.id,
            original_txn_id: r.original_txn_id,
            refund_txn_id: r.refund_txn_id,
            amount_minor: r.amount_minor.and_then(|s| s.parse().ok()),
            currency: r.currency,
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
    original_txn_id: Option<String>,
    refund_txn_id: Option<String>,
    amount_minor: Option<String>,
    currency: Option<String>,
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
