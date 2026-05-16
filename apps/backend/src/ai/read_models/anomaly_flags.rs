//! Analytical 层 P1 — `anomaly_flags`。
//!
//! 与 `recurring_patterns` 同形（device-sourced read model）：
//! 端侧 detector 检测到异常 → ContextPack.analytical_uploads (kind=
//! `anomaly_flag`) → 此 ingest 镜像入表。
//!
//! payload schema（约定 v1）:
//!   {
//!     "category":    "all_expense" | "food" | ...,
//!     "kind":        "monthly_spike" | "subscription_price_up" | ...,
//!     "delta_pct":   42,
//!     "severity":    "info" | "warn" | "critical",
//!     "detected_at": "2026-05-12T10:00:00Z",
//!     ...extras
//!   }

use serde::Deserialize;
use serde_json::Value;
use worker::{D1Database, D1Type};

use crate::error::AppError;

use super::freshness::Freshness;
use super::projection::{now_iso, upsert_freshness_meta};

pub const NAME: &str = "anomaly_flags";
pub const SCHEMA_VERSION: u32 = 1;
pub const CALCULATION_VERSION: u32 = 1;

#[derive(Debug, Clone)]
pub struct AnomalyFlagUpload<'a> {
    pub id: &'a str,
    pub payload: &'a Value,
    pub source_device_id: Option<&'a str>,
}

#[derive(Debug, Clone)]
pub struct AnomalyFlagRow {
    pub id: String,
    pub category: Option<String>,
    pub kind: Option<String>,
    pub delta_pct: Option<i32>,
    pub severity: Option<String>,
    pub detected_at: Option<String>,
    pub payload: Value,
}

pub async fn ingest(
    db: &D1Database,
    user_id: &str,
    device_hlc: &str,
    uploads: &[AnomalyFlagUpload<'_>],
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
            let category = payload_str(u.payload, "category");
            let kind = payload_str(u.payload, "kind");
            let delta_pct = u
                .payload
                .get("delta_pct")
                .and_then(|v| v.as_i64())
                .map(|n| n as i32);
            let severity = payload_str(u.payload, "severity");
            let detected_at = payload_str(u.payload, "detected_at");
            let category_param: D1Type = nullable_text(category);
            let kind_param: D1Type = nullable_text(kind);
            let delta_param: D1Type = match delta_pct {
                Some(n) => D1Type::Integer(n),
                None => D1Type::Null,
            };
            let severity_param: D1Type = nullable_text(severity);
            let detected_param: D1Type = nullable_text(detected_at);
            let device_param: D1Type = nullable_text(u.source_device_id);
            db.prepare(
                "INSERT INTO read_model_anomaly_flags
                    (user_id, id, payload, category, kind, delta_pct, severity,
                     detected_at, source_device_id, source_hlc_watermark,
                     refreshed_at, schema_version, calculation_version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
                 ON CONFLICT (user_id, id) DO UPDATE SET
                    payload              = excluded.payload,
                    category             = excluded.category,
                    kind                 = excluded.kind,
                    delta_pct            = excluded.delta_pct,
                    severity             = excluded.severity,
                    detected_at          = excluded.detected_at,
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
                &category_param,
                &kind_param,
                &delta_param,
                &severity_param,
                &detected_param,
                &device_param,
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
    severity_min: Option<&str>,
) -> Result<Vec<AnomalyFlagRow>, AppError> {
    let stmt = match severity_min {
        Some(sev) if matches!(sev, "info" | "warn" | "critical") => {
            // severity rank for SQL filter — explicit list per supported value
            let allowed: &[&str] = match sev {
                "info" => &["info", "warn", "critical"],
                "warn" => &["warn", "critical"],
                "critical" => &["critical"],
                _ => &[],
            };
            // SQLite IN with bind: build placeholders by length
            let placeholders: Vec<String> =
                (2..2 + allowed.len()).map(|i| format!("?{i}")).collect();
            let sql = format!(
                "SELECT id, payload, category, kind, delta_pct, severity, detected_at
                 FROM read_model_anomaly_flags
                 WHERE user_id = ?1 AND severity IN ({})
                 ORDER BY detected_at DESC",
                placeholders.join(", ")
            );
            let mut binds: Vec<D1Type> = vec![D1Type::Text(user_id)];
            for s in allowed {
                binds.push(D1Type::Text(s));
            }
            db.prepare(&sql)
                .bind_refs(&binds)
                .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        }
        _ => db
            .prepare(
                "SELECT id, payload, category, kind, delta_pct, severity, detected_at
                 FROM read_model_anomaly_flags
                 WHERE user_id = ?1
                 ORDER BY detected_at DESC",
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
        .map(|r| AnomalyFlagRow {
            id: r.id,
            category: r.category,
            kind: r.kind,
            delta_pct: r.delta_pct,
            severity: r.severity,
            detected_at: r.detected_at,
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
    category: Option<String>,
    kind: Option<String>,
    delta_pct: Option<i32>,
    severity: Option<String>,
    detected_at: Option<String>,
}

fn payload_str<'a>(p: &'a Value, key: &str) -> Option<&'a str> {
    p.get(key).and_then(|v| v.as_str())
}

fn nullable_text(s: Option<&str>) -> D1Type<'_> {
    match s {
        Some(t) => D1Type::Text(t),
        None => D1Type::Null,
    }
}
