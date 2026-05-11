//! 共享的 Scoped Detail 帮助器 —— 三个 `*_window` 工具复用。
//!
//! 包含:
//!  - 解析公约: parse_iso, parse_iso_required, parse_purpose, parse_limit
//!  - 脱敏: hash_merchant (HMAC-SHA256(user_id, merchant)[0..12])
//!  - 工具公约: NOTE_EXCERPT_CHARS, MAX_LIMIT, DEFAULT_LIMIT, MAX_RANGE_DAYS
//!  - 公共 payload helpers
//!
//! 三个 window 工具（category / account / asset）的 schema 是同源的:
//! freshness 元数据 + summary + transactions[]。共享 helper 保证字段
//! 形态完全一致，便于客户端统一渲染。

use chrono::{DateTime, Utc};
use hmac::{Hmac, Mac};
use serde::Deserialize;
use serde_json::Value;
use sha2::Sha256;
use worker::{D1Database, D1Type};

use crate::error::AppError;

pub const SCHEMA_VERSION: u32 = 1;
pub const CALCULATION_VERSION: u32 = 1;
pub const MAX_RANGE_DAYS: i64 = 31;
pub const MAX_LIMIT: u32 = 50;
pub const DEFAULT_LIMIT: u32 = 20;
pub const NOTE_EXCERPT_CHARS: usize = 60;

pub fn parse_iso(s: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|d| d.with_timezone(&Utc))
        .or_else(|| {
            chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d")
                .ok()
                .and_then(|d| d.and_hms_opt(0, 0, 0))
                .map(|dt| DateTime::<Utc>::from_naive_utc_and_offset(dt, Utc))
        })
}

pub fn parse_iso_required(raw: &Value, key: &str) -> Result<DateTime<Utc>, AppError> {
    let s = raw
        .get(key)
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest(format!("{key} required")))?;
    parse_iso(s).ok_or_else(|| AppError::BadRequest(format!("{key} not ISO date")))
}

pub fn parse_purpose(raw: &Value) -> Result<String, AppError> {
    let p = raw
        .get("purpose")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest("purpose required".into()))?;
    if !is_known_purpose(p) {
        return Err(AppError::BadRequest(format!(
            "purpose '{p}' not in DisclosurePurpose enum"
        )));
    }
    Ok(p.to_string())
}

pub fn parse_limit(raw: &Value) -> u32 {
    raw.get("limit")
        .and_then(|v| v.as_u64())
        .map(|n| n.min(MAX_LIMIT as u64) as u32)
        .unwrap_or(DEFAULT_LIMIT)
        .max(1)
}

pub fn is_known_purpose(s: &str) -> bool {
    matches!(
        s,
        "drill_down_expense"
            | "drill_down_investment"
            | "refund_matching"
            | "anomaly_explain"
            | "recurring_detect"
            | "other"
    )
}

/// 用户级稳定 hash — 同 user 内同 merchant → 同 hash（让 LLM 数 distinct），
/// 跨用户不可逆。前 12 hex char ≈ 48 bit，typical 量级零碰撞。
pub fn hash_merchant(merchant: &str, user_id: &str) -> String {
    type HmacSha256 = Hmac<Sha256>;
    let mut mac = HmacSha256::new_from_slice(user_id.as_bytes())
        .expect("HMAC accepts any key length");
    mac.update(merchant.trim().to_lowercase().as_bytes());
    let bytes = mac.finalize().into_bytes();
    bytes
        .iter()
        .take(6)
        .fold(String::with_capacity(12), |mut acc, b| {
            acc.push_str(&format!("{b:02x}"));
            acc
        })
}

pub fn excerpt(s: &str, max_chars: usize) -> String {
    let trimmed: String = s.chars().take(max_chars).collect();
    if s.chars().count() > max_chars {
        format!("{trimmed}…")
    } else {
        trimmed
    }
}

pub fn payload_str<'a>(p: &'a Value, key: &str) -> Option<&'a str> {
    p.get(key).and_then(|v| v.as_str())
}

pub fn payload_num(p: &Value, key: &str) -> Option<f64> {
    p.get(key).and_then(|v| v.as_f64())
}

#[derive(Deserialize)]
struct PayloadRow {
    id: String,
    payload: String,
}

/// 通用 payload 加载器，三个 window 工具共用。
pub async fn load_payloads(
    db: &D1Database,
    user_id: &str,
    table: &str,
) -> Result<Vec<(String, Value)>, AppError> {
    debug_assert!(matches!(
        table,
        "accounts" | "assets" | "journal_entries" | "postings"
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

/// 校验 from < to 且窗口 ≤ MAX_RANGE_DAYS。
pub fn validate_range(
    from: DateTime<Utc>,
    to: DateTime<Utc>,
) -> Result<(), AppError> {
    if to <= from {
        return Err(AppError::BadRequest("to must be after from".into()));
    }
    let span = to.signed_duration_since(from);
    if span > chrono::Duration::days(MAX_RANGE_DAYS) {
        return Err(AppError::BadRequest(format!(
            "range exceeds {MAX_RANGE_DAYS} days; narrow the window or call again"
        )));
    }
    Ok(())
}
