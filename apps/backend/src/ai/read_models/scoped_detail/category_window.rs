//! `read_category_window` —— Scoped Detail 工具。取代 `get_journal_entries`
//! 的「按类目过滤」用法。
//!
//! 输入约束:
//!  - `category`: 必填
//!  - `from` / `to`: 必填，ISO 日期或时间；窗口 ≤ [`MAX_RANGE_DAYS`] 天
//!  - `limit`: 1..=[`MAX_LIMIT`]，默认 [`DEFAULT_LIMIT`]
//!  - `purpose`: 必填，从 [`crate::ai::context::DisclosurePurpose`] 枚举
//!  - `merchant_substring`: 可选，端侧已 hash 后只能匹配 hash 子串；
//!    Phase 1 仅支持原始 note 子串匹配（hash 是输出端的事）
//!
//! 输出:
//!  - `summary { count, total_minor, currency }`
//!  - `transactions: [{ id, occurred_at, amount_minor, currency,
//!                     merchant_hashed, account_kind, note_excerpt }]`
//!  - `freshness { read_model_hlc, schema_version, calculation_version }`
//!
//! 注意: 不持久化 read model 表 —— Scoped Detail 是按需查询，freshness
//! 直接取 `latest_op_log_hlc(user_id)`。

use std::collections::HashMap;

use chrono::{DateTime, Duration, Utc};
use hmac::{Hmac, Mac};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::Sha256;
use worker::{D1Database, D1Type};

use crate::ai::read_models::projection::{latest_op_log_hlc, now_iso};
use crate::error::AppError;

pub const SCHEMA_VERSION: u32 = 1;
pub const CALCULATION_VERSION: u32 = 1;
pub const MAX_RANGE_DAYS: i64 = 31;
pub const MAX_LIMIT: u32 = 50;
pub const DEFAULT_LIMIT: u32 = 20;
pub const NOTE_EXCERPT_CHARS: usize = 60;

const READ_MODEL_NAME: &str = "scoped_detail/category_window";

/// 验证过的输入。`run` 只接受这一形态，schema 失效情况由调用方拦。
#[derive(Debug, Clone)]
pub struct Input {
    pub category: String,
    pub from: DateTime<Utc>,
    pub to: DateTime<Utc>,
    pub limit: u32,
    pub purpose: String,
    pub merchant_substring: Option<String>,
}

/// 解析 + 验证工具输入；失败返回 `BadRequest` 给 LLM 看到的 tool error。
pub fn parse_input(raw: &Value) -> Result<Input, AppError> {
    let category = raw
        .get("category")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest("category required".into()))?
        .trim()
        .to_string();
    if category.is_empty() {
        return Err(AppError::BadRequest("category cannot be empty".into()));
    }
    let from = parse_iso_required(raw, "from")?;
    let to = parse_iso_required(raw, "to")?;
    if to <= from {
        return Err(AppError::BadRequest("to must be after from".into()));
    }
    let span = to.signed_duration_since(from);
    if span > Duration::days(MAX_RANGE_DAYS) {
        return Err(AppError::BadRequest(format!(
            "range exceeds {MAX_RANGE_DAYS} days; narrow the window or call again"
        )));
    }
    let purpose = raw
        .get("purpose")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest("purpose required".into()))?
        .to_string();
    if !is_known_purpose(&purpose) {
        return Err(AppError::BadRequest(format!(
            "purpose '{purpose}' not in DisclosurePurpose enum"
        )));
    }
    let limit = raw
        .get("limit")
        .and_then(|v| v.as_u64())
        .map(|n| n.min(MAX_LIMIT as u64) as u32)
        .unwrap_or(DEFAULT_LIMIT)
        .max(1);
    let merchant_substring = raw
        .get("merchant_substring")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    Ok(Input {
        category,
        from,
        to,
        limit,
        purpose,
        merchant_substring,
    })
}

/// 工具入口。Worker 持有 D1 + user_id；返回的 Value 直接作为
/// tool_result.output，含 freshness 字段。
pub async fn run(
    db: &D1Database,
    user_id: &str,
    input: &Input,
) -> Result<Value, AppError> {
    let watermark = latest_op_log_hlc(db, user_id)
        .await?
        .unwrap_or_default();

    let entries = load_payloads(db, user_id, "journal_entries").await?;
    let postings = load_payloads(db, user_id, "postings").await?;
    let accounts = load_payloads(db, user_id, "accounts").await?;
    let assets = load_payloads(db, user_id, "assets").await?;

    let result = filter_and_sanitise(
        &entries,
        &postings,
        &accounts,
        &assets,
        input,
        user_id,
    );

    Ok(json!({
        "summary":      result.summary,
        "transactions": result.transactions,
        "freshness":    {
            "read_model":           READ_MODEL_NAME,
            "source_hlc_watermark": watermark,
            "refreshed_at":         now_iso(),
            "schema_version":       SCHEMA_VERSION,
            "calculation_version":  CALCULATION_VERSION,
        },
        "purpose":      input.purpose,
    }))
}

#[derive(Debug)]
pub(crate) struct SanitiseOutput {
    pub summary: Value,
    pub transactions: Vec<Value>,
}

/// 纯函数 —— 取 entries/postings/accounts/assets payload，过滤 + 脱敏。
/// 提取出来好做单元测试。
pub(crate) fn filter_and_sanitise(
    entries: &[(String, Value)],
    postings: &[(String, Value)],
    accounts: &[(String, Value)],
    assets: &[(String, Value)],
    input: &Input,
    user_id: &str,
) -> SanitiseOutput {
    let asset_ids: std::collections::HashSet<&str> =
        assets.iter().map(|(id, _)| id.as_str()).collect();
    let account_kinds: HashMap<&str, String> = accounts
        .iter()
        .map(|(id, p)| {
            let kind = payload_str(p, "type")
                .unwrap_or("unknown")
                .to_string();
            (id.as_str(), kind)
        })
        .collect();

    // entries 过滤: category + 时间窗口
    struct EntryRow<'a> {
        id: &'a str,
        date: DateTime<Utc>,
        note: Option<&'a str>,
    }
    let mut matched: Vec<EntryRow<'_>> = Vec::new();
    for (id, p) in entries {
        let Some(cat) = payload_str(p, "category") else {
            continue;
        };
        if cat != input.category {
            continue;
        }
        let Some(date) = payload_str(p, "date").and_then(parse_iso) else {
            continue;
        };
        if date < input.from || date >= input.to {
            continue;
        }
        let note = payload_str(p, "note");
        // merchant_substring 过滤（在 note 上做，因为 hash 之后没法子串匹配）
        if let Some(ref needle) = input.merchant_substring {
            let n = note.unwrap_or("");
            if !n.to_lowercase().contains(&needle.to_lowercase()) {
                continue;
            }
        }
        matched.push(EntryRow {
            id: id.as_str(),
            date,
            note,
        });
    }
    // 时间倒序，最新的优先
    matched.sort_by(|a, b| b.date.cmp(&a.date));
    let total_count = matched.len();
    matched.truncate(input.limit as usize);

    // 找出每个 entry 的 fiat-leg 金额 + 账户 kind
    let mut postings_by_entry: HashMap<&str, Vec<&Value>> = HashMap::new();
    for (_, p) in postings {
        if let Some(eid) = payload_str(p, "journal_entry_id") {
            postings_by_entry.entry(eid).or_default().push(p);
        }
    }

    let mut transactions: Vec<Value> = Vec::with_capacity(matched.len());
    let mut total_minor: i128 = 0;
    let mut currency_counts: HashMap<String, u32> = HashMap::new();
    for row in &matched {
        let legs = postings_by_entry.get(row.id);
        let mut amount_minor: i128 = 0;
        let mut currency: Option<String> = None;
        let mut account_id: Option<&str> = None;
        if let Some(legs) = legs {
            for p in legs {
                let unit = payload_str(p, "unit").unwrap_or("");
                if asset_ids.contains(unit) {
                    continue;
                }
                let units = payload_num(p, "units").unwrap_or(0.0);
                if units <= 0.0 {
                    continue;
                }
                amount_minor += (units * 100.0).round() as i128;
                if currency.is_none() {
                    currency = Some(unit.to_string());
                }
                if account_id.is_none() {
                    account_id = payload_str(p, "account_id");
                }
            }
        }
        let cur = currency.clone().unwrap_or_default();
        if !cur.is_empty() {
            *currency_counts.entry(cur.clone()).or_insert(0) += 1;
            total_minor += amount_minor;
        }

        let merchant_hashed = row
            .note
            .filter(|s| !s.is_empty())
            .map(|n| hash_merchant(n, user_id));
        let account_kind = account_id
            .and_then(|aid| account_kinds.get(aid))
            .cloned()
            .unwrap_or_else(|| "unknown".into());
        transactions.push(json!({
            "id":              row.id,
            "occurred_at":     row.date.to_rfc3339(),
            "amount_minor":    amount_minor.to_string(),
            "currency":        currency,
            "merchant_hashed": merchant_hashed,
            "account_kind":    account_kind,
            "note_excerpt":    row.note.map(|n| excerpt(n, NOTE_EXCERPT_CHARS)),
        }));
    }

    // summary —— 单一 currency 时给数；混币种时给 by_currency 分布
    let summary = if currency_counts.len() == 1 {
        let (cur, _) = currency_counts.into_iter().next().unwrap();
        json!({
            "count":       total_count,
            "returned":    transactions.len(),
            "total_minor": total_minor.to_string(),
            "currency":    cur,
        })
    } else {
        let by_currency: Vec<Value> = currency_counts
            .into_iter()
            .map(|(c, n)| json!({"currency": c, "count": n}))
            .collect();
        json!({
            "count":       total_count,
            "returned":    transactions.len(),
            "by_currency": by_currency,
        })
    };

    SanitiseOutput {
        summary,
        transactions,
    }
}

// ── helpers ────────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct PayloadRow {
    id: String,
    payload: String,
}

async fn load_payloads(
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
            chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d")
                .ok()
                .and_then(|d| d.and_hms_opt(0, 0, 0))
                .map(|dt| DateTime::<Utc>::from_naive_utc_and_offset(dt, Utc))
        })
}

fn parse_iso_required(raw: &Value, key: &str) -> Result<DateTime<Utc>, AppError> {
    let s = raw
        .get(key)
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest(format!("{key} required")))?;
    parse_iso(s).ok_or_else(|| AppError::BadRequest(format!("{key} not ISO date")))
}

fn is_known_purpose(s: &str) -> bool {
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

/// 用户级稳定 hash —— 同 user 内同 merchant 的 transaction 走同一 hash
/// （让 LLM 能数 distinct merchants），跨用户不可逆向。
///
/// HMAC-SHA256(user_id, merchant) 取前 12 hex char (~48 bit)。
fn hash_merchant(merchant: &str, user_id: &str) -> String {
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

fn excerpt(s: &str, max_chars: usize) -> String {
    let trimmed: String = s.chars().take(max_chars).collect();
    if s.chars().count() > max_chars {
        format!("{trimmed}…")
    } else {
        trimmed
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn entry(id: &str, date: &str, category: &str, note: &str) -> (String, Value) {
        (
            id.into(),
            json!({ "date": date, "category": category, "note": note }),
        )
    }

    fn posting(entry_id: &str, account_id: &str, unit: &str, units: f64) -> (String, Value) {
        (
            format!("p_{entry_id}_{account_id}"),
            json!({
                "journal_entry_id": entry_id,
                "account_id":       account_id,
                "unit":             unit,
                "units":            units,
            }),
        )
    }

    fn account(id: &str, kind: &str) -> (String, Value) {
        (id.into(), json!({ "type": kind }))
    }

    fn input(category: &str, from: &str, to: &str) -> Input {
        Input {
            category: category.into(),
            from: parse_iso(from).unwrap(),
            to: parse_iso(to).unwrap(),
            limit: 20,
            purpose: "drill_down_expense".into(),
            merchant_substring: None,
        }
    }

    #[test]
    fn filters_to_matching_category_only() {
        let entries = vec![
            entry("e1", "2026-04-15T10:00:00Z", "food", "Lunch at noodle"),
            entry("e2", "2026-04-16T10:00:00Z", "transport", "Uber"),
        ];
        let postings = vec![
            posting("e1", "acc_card", "USD", 12.5),
            posting("e2", "acc_card", "USD", 18.0),
        ];
        let accounts = vec![account("acc_card", "credit")];
        let assets: Vec<(String, Value)> = vec![];
        let out = filter_and_sanitise(
            &entries,
            &postings,
            &accounts,
            &assets,
            &input("food", "2026-04-01", "2026-05-01"),
            "user_1",
        );
        assert_eq!(out.transactions.len(), 1);
        assert_eq!(out.transactions[0]["amount_minor"], "1250");
        assert_eq!(out.transactions[0]["account_kind"], "credit");
    }

    #[test]
    fn enforces_date_window() {
        let entries = vec![
            entry("inside", "2026-04-15T10:00:00Z", "food", "x"),
            entry("before", "2026-03-31T23:59:00Z", "food", "x"),
            entry("after", "2026-05-01T00:00:00Z", "food", "x"),
        ];
        let postings = vec![
            posting("inside", "a", "USD", 1.0),
            posting("before", "a", "USD", 1.0),
            posting("after", "a", "USD", 1.0),
        ];
        let accounts = vec![account("a", "cash")];
        let assets: Vec<(String, Value)> = vec![];
        let out = filter_and_sanitise(
            &entries,
            &postings,
            &accounts,
            &assets,
            &input("food", "2026-04-01", "2026-05-01"),
            "user_1",
        );
        let ids: Vec<String> = out
            .transactions
            .iter()
            .map(|t| t["id"].as_str().unwrap().to_string())
            .collect();
        assert_eq!(ids, vec!["inside"]);
    }

    #[test]
    fn merchant_hash_is_stable_per_user() {
        let h1 = hash_merchant("Starbucks 04291", "user_1");
        let h2 = hash_merchant("starbucks 04291", "user_1");
        assert_eq!(h1, h2, "case+whitespace normalised");
        let h_other = hash_merchant("Starbucks 04291", "user_2");
        assert_ne!(h1, h_other, "hash differs per user");
        assert_eq!(h1.len(), 12);
    }

    #[test]
    fn merchant_substring_filter_matches_note() {
        let entries = vec![
            entry("e1", "2026-04-15T10:00:00Z", "food", "STARBUCKS 04291"),
            entry("e2", "2026-04-16T10:00:00Z", "food", "Lunch noodle"),
        ];
        let postings = vec![
            posting("e1", "a", "USD", 4.5),
            posting("e2", "a", "USD", 12.0),
        ];
        let accounts = vec![account("a", "cash")];
        let assets: Vec<(String, Value)> = vec![];
        let mut inp = input("food", "2026-04-01", "2026-05-01");
        inp.merchant_substring = Some("starbucks".into());
        let out = filter_and_sanitise(
            &entries,
            &postings,
            &accounts,
            &assets,
            &inp,
            "user_1",
        );
        assert_eq!(out.transactions.len(), 1);
        assert_eq!(out.transactions[0]["id"], "e1");
    }

    #[test]
    fn limit_is_respected_returns_count_for_total() {
        let entries: Vec<(String, Value)> = (0..30)
            .map(|i| {
                entry(
                    &format!("e{i}"),
                    &format!("2026-04-{:02}T10:00:00Z", (i % 28) + 1),
                    "food",
                    "x",
                )
            })
            .collect();
        let postings: Vec<(String, Value)> = (0..30)
            .map(|i| posting(&format!("e{i}"), "a", "USD", 1.0))
            .collect();
        let accounts = vec![account("a", "cash")];
        let assets: Vec<(String, Value)> = vec![];
        let mut inp = input("food", "2026-04-01", "2026-05-01");
        inp.limit = 10;
        let out = filter_and_sanitise(
            &entries,
            &postings,
            &accounts,
            &assets,
            &inp,
            "user_1",
        );
        assert_eq!(out.transactions.len(), 10);
        assert_eq!(out.summary["count"], 30);
        assert_eq!(out.summary["returned"], 10);
    }

    #[test]
    fn parse_input_rejects_oversize_window() {
        let raw = json!({
            "category": "food",
            "from":     "2026-01-01",
            "to":       "2026-03-01",  // 59 days
            "purpose":  "drill_down_expense",
        });
        let err = parse_input(&raw).unwrap_err();
        assert!(format!("{err:?}").contains("range exceeds"));
    }

    #[test]
    fn parse_input_rejects_unknown_purpose() {
        let raw = json!({
            "category": "food",
            "from":     "2026-04-01",
            "to":       "2026-04-15",
            "purpose":  "exfiltrate_data",
        });
        let err = parse_input(&raw).unwrap_err();
        assert!(format!("{err:?}").contains("DisclosurePurpose"));
    }

    #[test]
    fn parse_input_clamps_limit_to_max() {
        let raw = json!({
            "category": "food",
            "from":     "2026-04-01",
            "to":       "2026-04-15",
            "purpose":  "drill_down_expense",
            "limit":    9999,
        });
        let inp = parse_input(&raw).expect("parse ok");
        assert_eq!(inp.limit, MAX_LIMIT);
    }

    #[test]
    fn parse_input_defaults_limit() {
        let raw = json!({
            "category": "food",
            "from":     "2026-04-01",
            "to":       "2026-04-15",
            "purpose":  "drill_down_expense",
        });
        let inp = parse_input(&raw).expect("parse ok");
        assert_eq!(inp.limit, DEFAULT_LIMIT);
    }

    #[test]
    fn excerpt_truncates_with_ellipsis() {
        let s: String = "a".repeat(100);
        assert_eq!(excerpt(&s, 10).chars().count(), 11); // 10 + ellipsis
        assert!(excerpt(&s, 10).ends_with('…'));
        assert_eq!(excerpt("short", 100), "short");
    }
}
