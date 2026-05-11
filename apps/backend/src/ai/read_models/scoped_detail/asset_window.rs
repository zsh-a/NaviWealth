//! `read_asset_window` —— Scoped Detail 工具，按资产 + 窗口 drill-down 交易腿。
//!
//! 与 `category_window` / `account_window` 同形：必填 filter + 硬限额 +
//! sanitised fields。这里以 `asset_id` 为主键，返回的是**资产腿**而不是
//! 现金腿（用户问"AAPL 这个月有几次买卖"，看的是数量变动 + 单价）。
//!
//! 输入:
//!  - `asset_id`: 必填
//!  - `from` / `to`: 必填，≤ 31 天
//!  - `purpose`: 必填，DisclosurePurpose enum
//!  - `limit`: 1..=50，默认 20
//!
//! 输出: `summary { count, returned, net_qty_delta, currency }` +
//! `transactions[{ id, occurred_at, qty_delta, cost_per_unit,
//! currency, side }]` + `freshness`。
//!
//! 与 category/account 的脱敏区别：asset 维度本身不涉及 merchant，
//! 因此没有 merchant_hashed；返回字段都是数值 + 类型分类，天然脱敏。

use std::collections::HashMap;

use chrono::DateTime;
use chrono::Utc;
use serde_json::{json, Value};
use worker::D1Database;

use crate::ai::read_models::projection::{latest_op_log_hlc, now_iso};
use crate::error::AppError;

use super::common::{
    load_payloads, parse_iso_required, parse_limit, parse_purpose,
    payload_num, payload_str, validate_range, CALCULATION_VERSION,
    SCHEMA_VERSION,
};

const READ_MODEL_NAME: &str = "scoped_detail/asset_window";

#[derive(Debug, Clone)]
pub struct Input {
    pub asset_id: String,
    pub from: DateTime<Utc>,
    pub to: DateTime<Utc>,
    pub limit: u32,
    pub purpose: String,
}

pub fn parse_input(raw: &Value) -> Result<Input, AppError> {
    let asset_id = raw
        .get("asset_id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest("asset_id required".into()))?
        .trim()
        .to_string();
    if asset_id.is_empty() {
        return Err(AppError::BadRequest("asset_id cannot be empty".into()));
    }
    let from = parse_iso_required(raw, "from")?;
    let to = parse_iso_required(raw, "to")?;
    validate_range(from, to)?;
    let purpose = parse_purpose(raw)?;
    let limit = parse_limit(raw);
    Ok(Input {
        asset_id,
        from,
        to,
        limit,
        purpose,
    })
}

pub async fn run(
    db: &D1Database,
    user_id: &str,
    input: &Input,
) -> Result<Value, AppError> {
    let watermark = latest_op_log_hlc(db, user_id).await?.unwrap_or_default();

    let entries = load_payloads(db, user_id, "journal_entries").await?;
    let postings = load_payloads(db, user_id, "postings").await?;

    let result = filter_and_extract(&entries, &postings, input);

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
        "asset_id":     input.asset_id,
    }))
}

pub(crate) struct ExtractOutput {
    pub summary: Value,
    pub transactions: Vec<Value>,
}

pub(crate) fn filter_and_extract(
    entries: &[(String, Value)],
    postings: &[(String, Value)],
    input: &Input,
) -> ExtractOutput {
    // entry_id → date
    let mut entry_date: HashMap<&str, DateTime<Utc>> = HashMap::new();
    for (id, p) in entries {
        if let Some(d) = payload_str(p, "date").and_then(super::common::parse_iso) {
            entry_date.insert(id.as_str(), d);
        }
    }

    struct Hit<'a> {
        entry_id: &'a str,
        qty_delta: f64,
        cost_per_unit: Option<f64>,
        currency: Option<&'a str>,
        date: DateTime<Utc>,
    }
    let mut hits: Vec<Hit<'_>> = Vec::new();
    for (_, p) in postings {
        let Some(unit) = payload_str(p, "unit") else {
            continue;
        };
        if unit != input.asset_id {
            continue;
        }
        let Some(entry_id) = payload_str(p, "journal_entry_id") else {
            continue;
        };
        let Some(date) = entry_date.get(entry_id).copied() else {
            continue;
        };
        if date < input.from || date >= input.to {
            continue;
        }
        let qty = payload_num(p, "units").unwrap_or(0.0);
        if qty == 0.0 {
            continue;
        }
        let cost_per_unit = payload_num(p, "cost_per_unit")
            .or_else(|| payload_num(p, "price_per_unit"));
        let currency = payload_str(p, "cost_currency")
            .or_else(|| payload_str(p, "price_currency"));
        hits.push(Hit {
            entry_id,
            qty_delta: qty,
            cost_per_unit,
            currency,
            date,
        });
    }
    hits.sort_by(|a, b| b.date.cmp(&a.date));
    let total_count = hits.len();
    hits.truncate(input.limit as usize);

    let mut transactions: Vec<Value> = Vec::with_capacity(hits.len());
    let mut net_qty_delta = 0.0f64;
    let mut currency_seen: Option<String> = None;
    let mut mixed_currency = false;
    for h in &hits {
        net_qty_delta += h.qty_delta;
        if let Some(c) = h.currency {
            match &currency_seen {
                None => currency_seen = Some(c.to_string()),
                Some(seen) if seen != c => mixed_currency = true,
                _ => {}
            }
        }
        let side = if h.qty_delta > 0.0 { "buy" } else { "sell" };
        transactions.push(json!({
            "id":             h.entry_id,
            "occurred_at":    h.date.to_rfc3339(),
            "qty_delta":      h.qty_delta,
            "side":           side,
            "cost_per_unit":  h.cost_per_unit,
            "currency":       h.currency,
        }));
    }

    let summary = if mixed_currency {
        json!({
            "count":         total_count,
            "returned":      transactions.len(),
            "net_qty_delta": net_qty_delta,
            "mixed_currency": true,
        })
    } else {
        json!({
            "count":         total_count,
            "returned":      transactions.len(),
            "net_qty_delta": net_qty_delta,
            "currency":      currency_seen,
        })
    };

    ExtractOutput {
        summary,
        transactions,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::read_models::scoped_detail::common::parse_iso;
    use serde_json::json;

    fn entry(id: &str, date: &str) -> (String, Value) {
        (id.into(), json!({ "date": date }))
    }

    fn asset_posting(
        entry_id: &str,
        asset_id: &str,
        qty: f64,
        cost: f64,
        currency: &str,
    ) -> (String, Value) {
        (
            format!("p_{entry_id}_{asset_id}_{qty}"),
            json!({
                "journal_entry_id": entry_id,
                "unit":             asset_id,
                "units":            qty,
                "cost_per_unit":    cost,
                "cost_currency":    currency,
            }),
        )
    }

    fn input(asset_id: &str, from: &str, to: &str) -> Input {
        Input {
            asset_id: asset_id.into(),
            from: parse_iso(from).unwrap(),
            to: parse_iso(to).unwrap(),
            limit: 20,
            purpose: "drill_down_investment".into(),
        }
    }

    #[test]
    fn filters_to_named_asset_legs_only() {
        let entries = vec![
            entry("e1", "2026-04-15T10:00:00Z"),
            entry("e2", "2026-04-16T10:00:00Z"),
        ];
        let postings = vec![
            asset_posting("e1", "AAPL", 10.0, 150.0, "USD"),
            asset_posting("e2", "TSLA", 5.0, 200.0, "USD"),
        ];
        let out = filter_and_extract(
            &entries,
            &postings,
            &input("AAPL", "2026-04-01", "2026-05-01"),
        );
        assert_eq!(out.transactions.len(), 1);
        assert_eq!(out.transactions[0]["id"], "e1");
        assert_eq!(out.transactions[0]["side"], "buy");
    }

    #[test]
    fn sells_marked_with_side_and_negative_qty() {
        let entries = vec![entry("e1", "2026-04-15T10:00:00Z")];
        let postings = vec![asset_posting("e1", "AAPL", -5.0, 180.0, "USD")];
        let out = filter_and_extract(
            &entries,
            &postings,
            &input("AAPL", "2026-04-01", "2026-05-01"),
        );
        assert_eq!(out.transactions[0]["side"], "sell");
        assert_eq!(out.transactions[0]["qty_delta"], -5.0);
    }

    #[test]
    fn net_qty_delta_sums_signed() {
        let entries = vec![
            entry("buy_1", "2026-04-15T10:00:00Z"),
            entry("buy_2", "2026-04-16T10:00:00Z"),
            entry("sell", "2026-04-17T10:00:00Z"),
        ];
        let postings = vec![
            asset_posting("buy_1", "AAPL", 10.0, 150.0, "USD"),
            asset_posting("buy_2", "AAPL", 5.0, 160.0, "USD"),
            asset_posting("sell", "AAPL", -3.0, 180.0, "USD"),
        ];
        let out = filter_and_extract(
            &entries,
            &postings,
            &input("AAPL", "2026-04-01", "2026-05-01"),
        );
        assert_eq!(out.transactions.len(), 3);
        assert_eq!(out.summary["net_qty_delta"], 12.0);
    }

    #[test]
    fn falls_back_to_price_fields() {
        let p = (
            "p1".into(),
            json!({
                "journal_entry_id": "e1",
                "unit":             "AAPL",
                "units":            10.0,
                "price_per_unit":   125.0,
                "price_currency":   "USD",
            }),
        );
        let entries = vec![entry("e1", "2026-04-15T10:00:00Z")];
        let out = filter_and_extract(
            &entries,
            &[p],
            &input("AAPL", "2026-04-01", "2026-05-01"),
        );
        assert_eq!(out.transactions[0]["cost_per_unit"], 125.0);
        assert_eq!(out.transactions[0]["currency"], "USD");
    }

    #[test]
    fn ignores_zero_qty_legs() {
        let entries = vec![entry("e1", "2026-04-15T10:00:00Z")];
        let postings = vec![asset_posting("e1", "AAPL", 0.0, 150.0, "USD")];
        let out = filter_and_extract(
            &entries,
            &postings,
            &input("AAPL", "2026-04-01", "2026-05-01"),
        );
        assert!(out.transactions.is_empty());
    }

    #[test]
    fn parse_input_rejects_missing_asset_id() {
        let raw = json!({
            "from":    "2026-04-01",
            "to":      "2026-04-30",
            "purpose": "drill_down_investment",
        });
        let err = parse_input(&raw).unwrap_err();
        assert!(format!("{err:?}").contains("asset_id"));
    }
}
