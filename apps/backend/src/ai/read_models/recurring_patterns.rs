//! Analytical 层 P1 — `recurring_patterns`。
//!
//! 这是 **device-sourced** read model（docs/ai-architecture.md §4.3.3）：
//! 端侧 `recurring_detector` 跑启发式（merchant_key + cadence 检测），
//! 上报通过 `ContextPack.task.analytical_uploads`，云端镜像入表。
//!
//! 与 Snapshot 层的差异：
//!  - 没有 `Projection.refresh()`（云端没法重算 device-side 的启发式）
//!  - `ingest()` 在 `routes/ai.rs` 解析 ContextPack 时调用
//!  - `source_hlc_watermark` = device's localHlc at upload time
//!  - freshness gate 触发 force-refresh 时此 read model 是 no-op
//!    （cloud 没东西可刷；端侧下一次 chat 自然上报新结果）

use serde::Deserialize;
use serde_json::Value;
use worker::{D1Database, D1Type};

use crate::error::AppError;

use super::freshness::Freshness;
use super::projection::{now_iso, upsert_freshness_meta};

pub const NAME: &str = "recurring_patterns";
pub const SCHEMA_VERSION: u32 = 1;
pub const CALCULATION_VERSION: u32 = 1;

/// 端侧上报的一条 recurring_pattern 记录。`kind == "recurring_pattern"`
/// 时从 [`crate::ai::context::AnalyticalUpload`] 解析得到。
#[derive(Debug, Clone)]
pub struct RecurringPatternUpload<'a> {
    pub id: &'a str,
    pub payload: &'a Value,
    pub source_device_id: Option<&'a str>,
}

/// 一行查询结果。
#[derive(Debug, Clone)]
pub struct RecurringPatternRow {
    pub id: String,
    pub merchant_key: Option<String>,
    pub cadence: Option<String>,
    pub currency: Option<String>,
    pub median_amount_minor: Option<i64>,
    pub occurrences: Option<u32>,
    pub last_seen_at: Option<String>,
    pub payload: Value,
}

/// 把一批 device 上报写入表。整体原子（batch），upsert by (user_id, id)。
/// `device_hlc` 用作所有行的 `source_hlc_watermark`。
pub async fn ingest(
    db: &D1Database,
    user_id: &str,
    device_hlc: &str,
    uploads: &[RecurringPatternUpload<'_>],
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
            let merchant_key = payload_str(u.payload, "merchant_key");
            let cadence = payload_str(u.payload, "cadence");
            let currency = payload_str(u.payload, "currency");
            let median = payload_amount_minor(u.payload, "median_amount_minor");
            let occurrences = u
                .payload
                .get("occurrences")
                .and_then(|v| v.as_u64())
                .map(|n| n as i32);
            let last_seen = payload_str(u.payload, "last_seen_at");
            let merchant_param: D1Type = match merchant_key {
                Some(s) => D1Type::Text(s),
                None => D1Type::Null,
            };
            let cadence_param: D1Type = match cadence {
                Some(s) => D1Type::Text(s),
                None => D1Type::Null,
            };
            let currency_param: D1Type = match currency {
                Some(s) => D1Type::Text(s),
                None => D1Type::Null,
            };
            let median_param: D1Type = match &median {
                Some(s) => D1Type::Text(s),
                None => D1Type::Null,
            };
            let occ_param: D1Type = match occurrences {
                Some(n) => D1Type::Integer(n),
                None => D1Type::Null,
            };
            let last_seen_param: D1Type = match last_seen {
                Some(s) => D1Type::Text(s),
                None => D1Type::Null,
            };
            let device_param: D1Type = match u.source_device_id {
                Some(s) => D1Type::Text(s),
                None => D1Type::Null,
            };
            db.prepare(
                "INSERT INTO read_model_recurring_patterns
                    (user_id, id, payload, merchant_key, cadence, currency,
                     median_amount_minor, occurrences, last_seen_at,
                     source_device_id, source_hlc_watermark, refreshed_at,
                     schema_version, calculation_version)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
                 ON CONFLICT (user_id, id) DO UPDATE SET
                    payload              = excluded.payload,
                    merchant_key         = excluded.merchant_key,
                    cadence              = excluded.cadence,
                    currency             = excluded.currency,
                    median_amount_minor  = excluded.median_amount_minor,
                    occurrences          = excluded.occurrences,
                    last_seen_at         = excluded.last_seen_at,
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
                &merchant_param,
                &cadence_param,
                &currency_param,
                &median_param,
                &occ_param,
                &last_seen_param,
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

/// 工具读路径。`currency` / `cadence` 为可选过滤。
pub async fn query_all(
    db: &D1Database,
    user_id: &str,
    currency: Option<&str>,
    cadence: Option<&str>,
) -> Result<Vec<RecurringPatternRow>, AppError> {
    // 拼 SQL 而不是用条件 binding —— SQLite 不支持 `?1 IS NULL OR col = ?1`
    // 在 prepared 阶段优化掉。这里用静态参数计数，安全（参数化）。
    let stmt = match (currency, cadence) {
        (None, None) => db
            .prepare(
                "SELECT id, payload, merchant_key, cadence, currency,
                        median_amount_minor, occurrences, last_seen_at
                 FROM read_model_recurring_patterns
                 WHERE user_id = ?1
                 ORDER BY occurrences DESC, last_seen_at DESC",
            )
            .bind_refs([&D1Type::Text(user_id)])
            .map_err(|e| AppError::Internal(format!("bind: {e}")))?,
        (Some(c), None) => db
            .prepare(
                "SELECT id, payload, merchant_key, cadence, currency,
                        median_amount_minor, occurrences, last_seen_at
                 FROM read_model_recurring_patterns
                 WHERE user_id = ?1 AND currency = ?2
                 ORDER BY occurrences DESC, last_seen_at DESC",
            )
            .bind_refs([&D1Type::Text(user_id), &D1Type::Text(c)])
            .map_err(|e| AppError::Internal(format!("bind: {e}")))?,
        (None, Some(d)) => db
            .prepare(
                "SELECT id, payload, merchant_key, cadence, currency,
                        median_amount_minor, occurrences, last_seen_at
                 FROM read_model_recurring_patterns
                 WHERE user_id = ?1 AND cadence = ?2
                 ORDER BY occurrences DESC, last_seen_at DESC",
            )
            .bind_refs([&D1Type::Text(user_id), &D1Type::Text(d)])
            .map_err(|e| AppError::Internal(format!("bind: {e}")))?,
        (Some(c), Some(d)) => db
            .prepare(
                "SELECT id, payload, merchant_key, cadence, currency,
                        median_amount_minor, occurrences, last_seen_at
                 FROM read_model_recurring_patterns
                 WHERE user_id = ?1 AND currency = ?2 AND cadence = ?3
                 ORDER BY occurrences DESC, last_seen_at DESC",
            )
            .bind_refs([&D1Type::Text(user_id), &D1Type::Text(c), &D1Type::Text(d)])
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
        .map(|r| RecurringPatternRow {
            id: r.id,
            merchant_key: r.merchant_key,
            cadence: r.cadence,
            currency: r.currency,
            median_amount_minor: r.median_amount_minor.and_then(|s| s.parse().ok()),
            occurrences: r.occurrences,
            last_seen_at: r.last_seen_at,
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

// ── helpers ────────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct RowSelect {
    id: String,
    payload: String,
    merchant_key: Option<String>,
    cadence: Option<String>,
    currency: Option<String>,
    median_amount_minor: Option<String>,
    occurrences: Option<u32>,
    last_seen_at: Option<String>,
}

fn payload_str<'a>(p: &'a Value, key: &str) -> Option<&'a str> {
    p.get(key).and_then(|v| v.as_str())
}

/// 接受 minor units 既可能是字符串（Dart Decimal serialise）也可能是 number。
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
