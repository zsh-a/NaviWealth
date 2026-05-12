//! `read_account_window` —— Scoped Detail 工具，按账户 + 窗口 drill-down。
//!
//! 与 `category_window` 同形：必填 filter + 硬限额 + sanitised fields。
//! 区别只在 filter 维度 —— 这里以 `account_id` 为主键。
//!
//! 输入:
//!  - `account_id`: 必填
//!  - `from` / `to`: 必填，≤ 31 天
//!  - `purpose`: 必填，DisclosurePurpose enum
//!  - `limit`: 1..=50，默认 20
//!  - `category`: 可选，按类目二次过滤
//!  - `min_amount_minor` / `max_amount_minor`: 可选
//!
//! 输出: `summary { count, returned, total_minor, currency }` +
//! `transactions[{ id, occurred_at, amount_minor, currency,
//! merchant_hashed, category, note_excerpt }]` + `freshness`。
//!
//! 与 Snapshot 层不同：现读 + sanitise，无 read_model 表。

use std::collections::HashMap;

use chrono::DateTime;
use chrono::Utc;
use serde_json::{json, Value};
use worker::D1Database;

use crate::ai::read_models::projection::{latest_op_log_hlc, now_iso};
use crate::error::AppError;

use super::common::{
    excerpt, hash_merchant, load_payloads, parse_iso_required, parse_limit, parse_purpose,
    payload_num, payload_str, validate_range, CALCULATION_VERSION, NOTE_EXCERPT_CHARS,
    SCHEMA_VERSION,
};

const READ_MODEL_NAME: &str = "scoped_detail/account_window";

#[derive(Debug, Clone)]
pub struct Input {
    pub account_id: String,
    pub from: DateTime<Utc>,
    pub to: DateTime<Utc>,
    pub limit: u32,
    pub purpose: String,
    pub category: Option<String>,
    pub min_amount_minor: Option<i64>,
    pub max_amount_minor: Option<i64>,
}

pub fn parse_input(raw: &Value) -> Result<Input, AppError> {
    let account_id = raw
        .get("account_id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest("account_id required".into()))?
        .trim()
        .to_string();
    if account_id.is_empty() {
        return Err(AppError::BadRequest("account_id cannot be empty".into()));
    }
    let from = parse_iso_required(raw, "from")?;
    let to = parse_iso_required(raw, "to")?;
    validate_range(from, to)?;
    let purpose = parse_purpose(raw)?;
    let limit = parse_limit(raw);
    let category = raw
        .get("category")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let min_amount_minor = raw.get("min_amount_minor").and_then(|v| v.as_i64());
    let max_amount_minor = raw.get("max_amount_minor").and_then(|v| v.as_i64());
    Ok(Input {
        account_id,
        from,
        to,
        limit,
        purpose,
        category,
        min_amount_minor,
        max_amount_minor,
    })
}

pub async fn run(db: &D1Database, user_id: &str, input: &Input) -> Result<Value, AppError> {
    let watermark = latest_op_log_hlc(db, user_id).await?.unwrap_or_default();

    let entries = load_payloads(db, user_id, "journal_entries").await?;
    let postings = load_payloads(db, user_id, "postings").await?;
    let accounts = load_payloads(db, user_id, "accounts").await?;

    let result = filter_and_sanitise(&entries, &postings, &accounts, input, user_id);

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
        "account_id":   input.account_id,
    }))
}

pub(crate) struct SanitiseOutput {
    pub summary: Value,
    pub transactions: Vec<Value>,
}

pub(crate) fn filter_and_sanitise(
    entries: &[(String, Value)],
    postings: &[(String, Value)],
    accounts: &[(String, Value)],
    input: &Input,
    user_id: &str,
) -> SanitiseOutput {
    // 确认账户存在 + 拿 kind（用于 sanitised 输出标签）
    let account_kind: Option<String> = accounts
        .iter()
        .find(|(id, _)| id.as_str() == input.account_id)
        .and_then(|(_, p)| payload_str(p, "type").map(str::to_string));

    // entries → (date, category, note) for downstream merge.
    struct EntryMeta<'a> {
        date: DateTime<Utc>,
        category: Option<&'a str>,
        note: Option<&'a str>,
    }
    let mut entry_meta: HashMap<&str, EntryMeta<'_>> = HashMap::new();
    for (id, p) in entries {
        let Some(d) = payload_str(p, "date").and_then(super::common::parse_iso) else {
            continue;
        };
        entry_meta.insert(
            id.as_str(),
            EntryMeta {
                date: d,
                category: payload_str(p, "category"),
                note: payload_str(p, "note"),
            },
        );
    }

    // 过滤 postings: 必须 (account_id == input.account_id) + 时间窗内
    struct Hit<'a> {
        entry_id: &'a str,
        amount_minor: i128,
        currency: &'a str,
        date: DateTime<Utc>,
        category: Option<&'a str>,
        note: Option<&'a str>,
    }
    let mut hits: Vec<Hit<'_>> = Vec::new();
    for (_, p) in postings {
        let Some(account_id) = payload_str(p, "account_id") else {
            continue;
        };
        if account_id != input.account_id {
            continue;
        }
        let Some(entry_id) = payload_str(p, "journal_entry_id") else {
            continue;
        };
        let Some(meta) = entry_meta.get(entry_id) else {
            continue;
        };
        if meta.date < input.from || meta.date >= input.to {
            continue;
        }
        if let Some(ref cat_filter) = input.category {
            match meta.category {
                Some(c) if c == cat_filter => {}
                _ => continue,
            }
        }
        let Some(unit) = payload_str(p, "unit") else {
            continue;
        };
        let units = payload_num(p, "units").unwrap_or(0.0);
        let amount_minor = (units * 100.0).round() as i128;
        if let Some(min_v) = input.min_amount_minor {
            if (amount_minor as i64) < min_v {
                continue;
            }
        }
        if let Some(max_v) = input.max_amount_minor {
            if (amount_minor as i64) > max_v {
                continue;
            }
        }
        hits.push(Hit {
            entry_id,
            amount_minor,
            currency: unit,
            date: meta.date,
            category: meta.category,
            note: meta.note,
        });
    }
    hits.sort_by(|a, b| b.date.cmp(&a.date));
    let total_count = hits.len();
    hits.truncate(input.limit as usize);

    let mut transactions: Vec<Value> = Vec::with_capacity(hits.len());
    let mut total_abs: i128 = 0;
    let mut currency_seen: Option<String> = None;
    let mut mixed_currency = false;
    for h in &hits {
        total_abs += h.amount_minor.abs();
        match &currency_seen {
            None => currency_seen = Some(h.currency.to_string()),
            Some(c) if c != h.currency => mixed_currency = true,
            _ => {}
        }
        let merchant_hashed = h
            .note
            .filter(|s| !s.is_empty())
            .map(|n| hash_merchant(n, user_id));
        transactions.push(json!({
            "id":              h.entry_id,
            "occurred_at":     h.date.to_rfc3339(),
            "amount_minor":    h.amount_minor.to_string(),
            "currency":        h.currency,
            "merchant_hashed": merchant_hashed,
            "category":        h.category,
            "note_excerpt":    h.note.map(|n| excerpt(n, NOTE_EXCERPT_CHARS)),
        }));
    }

    let summary = if mixed_currency {
        json!({
            "count":    total_count,
            "returned": transactions.len(),
            "mixed_currency": true,
            "account_kind":   account_kind,
        })
    } else {
        json!({
            "count":         total_count,
            "returned":      transactions.len(),
            "total_minor":   total_abs.to_string(),
            "currency":      currency_seen,
            "account_kind":  account_kind,
        })
    };

    SanitiseOutput {
        summary,
        transactions,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::read_models::scoped_detail::common::parse_iso;
    use serde_json::json;

    fn entry(id: &str, date: &str, category: &str, note: &str) -> (String, Value) {
        (
            id.into(),
            json!({ "date": date, "category": category, "note": note }),
        )
    }

    fn posting(entry_id: &str, account_id: &str, unit: &str, units: f64) -> (String, Value) {
        (
            format!("p_{entry_id}_{account_id}_{units}"),
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

    fn input(account_id: &str, from: &str, to: &str) -> Input {
        Input {
            account_id: account_id.into(),
            from: parse_iso(from).unwrap(),
            to: parse_iso(to).unwrap(),
            limit: 20,
            purpose: "drill_down_expense".into(),
            category: None,
            min_amount_minor: None,
            max_amount_minor: None,
        }
    }

    #[test]
    fn filters_to_named_account_only() {
        let entries = vec![
            entry("e1", "2026-04-15T10:00:00Z", "food", "lunch"),
            entry("e2", "2026-04-16T10:00:00Z", "food", "dinner"),
        ];
        let postings = vec![
            posting("e1", "acc_visa", "USD", -12.5),
            posting("e2", "acc_amex", "USD", -25.0),
        ];
        let accounts = vec![account("acc_visa", "credit"), account("acc_amex", "credit")];
        let out = filter_and_sanitise(
            &entries,
            &postings,
            &accounts,
            &input("acc_visa", "2026-04-01", "2026-05-01"),
            "user_1",
        );
        assert_eq!(out.transactions.len(), 1);
        assert_eq!(out.transactions[0]["id"], "e1");
    }

    #[test]
    fn enforces_date_window() {
        let entries = vec![
            entry("inside", "2026-04-15T10:00:00Z", "food", "x"),
            entry("before", "2026-03-31T23:59:00Z", "food", "x"),
            entry("after", "2026-05-01T00:00:00Z", "food", "x"),
        ];
        let postings = vec![
            posting("inside", "acc_visa", "USD", -1.0),
            posting("before", "acc_visa", "USD", -1.0),
            posting("after", "acc_visa", "USD", -1.0),
        ];
        let accounts = vec![account("acc_visa", "credit")];
        let out = filter_and_sanitise(
            &entries,
            &postings,
            &accounts,
            &input("acc_visa", "2026-04-01", "2026-05-01"),
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
    fn category_filter_narrows_results() {
        let entries = vec![
            entry("e_food", "2026-04-15T10:00:00Z", "food", "lunch"),
            entry("e_uber", "2026-04-16T10:00:00Z", "transport", "ride"),
        ];
        let postings = vec![
            posting("e_food", "acc_visa", "USD", -10.0),
            posting("e_uber", "acc_visa", "USD", -15.0),
        ];
        let accounts = vec![account("acc_visa", "credit")];
        let mut inp = input("acc_visa", "2026-04-01", "2026-05-01");
        inp.category = Some("food".into());
        let out = filter_and_sanitise(&entries, &postings, &accounts, &inp, "user_1");
        assert_eq!(out.transactions.len(), 1);
        assert_eq!(out.transactions[0]["category"], "food");
    }

    #[test]
    fn limit_truncates_but_count_reflects_total() {
        let entries: Vec<(String, Value)> = (0..15)
            .map(|i| {
                entry(
                    &format!("e{i}"),
                    &format!("2026-04-{:02}T10:00:00Z", (i % 28) + 1),
                    "food",
                    "x",
                )
            })
            .collect();
        let postings: Vec<(String, Value)> = (0..15)
            .map(|i| posting(&format!("e{i}"), "acc_visa", "USD", -1.0))
            .collect();
        let accounts = vec![account("acc_visa", "credit")];
        let mut inp = input("acc_visa", "2026-04-01", "2026-05-01");
        inp.limit = 5;
        let out = filter_and_sanitise(&entries, &postings, &accounts, &inp, "user_1");
        assert_eq!(out.transactions.len(), 5);
        assert_eq!(out.summary["count"], 15);
        assert_eq!(out.summary["returned"], 5);
    }

    #[test]
    fn surfaces_account_kind_in_summary() {
        let entries = vec![entry("e1", "2026-04-15T10:00:00Z", "food", "x")];
        let postings = vec![posting("e1", "acc_savings", "USD", -1.0)];
        let accounts = vec![account("acc_savings", "bank")];
        let out = filter_and_sanitise(
            &entries,
            &postings,
            &accounts,
            &input("acc_savings", "2026-04-01", "2026-05-01"),
            "user_1",
        );
        assert_eq!(out.summary["account_kind"], "bank");
    }

    #[test]
    fn mixed_currency_marked_in_summary() {
        let entries = vec![
            entry("e_usd", "2026-04-15T10:00:00Z", "food", "x"),
            entry("e_cny", "2026-04-16T10:00:00Z", "food", "x"),
        ];
        let postings = vec![
            posting("e_usd", "acc", "USD", -10.0),
            posting("e_cny", "acc", "CNY", -70.0),
        ];
        let accounts = vec![account("acc", "credit")];
        let out = filter_and_sanitise(
            &entries,
            &postings,
            &accounts,
            &input("acc", "2026-04-01", "2026-05-01"),
            "user_1",
        );
        assert_eq!(out.summary["mixed_currency"], true);
        assert!(out.summary.get("total_minor").is_none());
    }

    #[test]
    fn parse_input_rejects_oversize_window() {
        let raw = json!({
            "account_id": "acc",
            "from":       "2026-01-01",
            "to":         "2026-03-01",
            "purpose":    "drill_down_expense",
        });
        let err = parse_input(&raw).unwrap_err();
        assert!(format!("{err:?}").contains("range exceeds"));
    }

    #[test]
    fn parse_input_rejects_empty_account_id() {
        let raw = json!({
            "account_id": "   ",
            "from":       "2026-04-01",
            "to":         "2026-04-30",
            "purpose":    "drill_down_expense",
        });
        let err = parse_input(&raw).unwrap_err();
        assert!(format!("{err:?}").contains("account_id"));
    }
}
