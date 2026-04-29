//! Write-side proposal builders for the AI assistant (FIR-66).
//!
//! These power the `propose_*` family of LLM tools. The design rule is that
//! the model is **never** allowed to write to the user's data directly —
//! every `propose_*` tool returns a structured *plan* describing the
//! intended mutation. The mobile client renders the plan in a confirmation
//! UI; only after the human taps "确认" does it call the existing
//! repository (`TransactionRepository`, `AccountRepository`, etc.) to
//! actually persist the row.
//!
//! Each builder follows the same shape:
//!
//! - Resolve any soft references the model passed (e.g. `account_name` →
//!   account row in D1, `asset_symbol` → asset row).
//! - If a reference is ambiguous, return a `needs_clarification` plan with
//!   `candidates` listing each match. The conversation prompt instructs the
//!   model to ask the user to pick — `propose_*` is intentionally
//!   side-effect free, so re-asking costs nothing.
//! - If the inputs are unambiguous, return a `ready` plan whose `payload`
//!   matches the canonical entity shape stored in the materialised sync
//!   tables (see `apps/backend/migrations/0002_sync_schema.sql`). The mobile
//!   client maps these straight onto its Drift entities.
//!
//! Plans always carry:
//! - `proposal_id` — fresh UUIDv4. The client echoes this back when the user
//!   confirms, so we (and the model, in a follow-up turn) can correlate the
//!   confirmation.
//! - `kind` — discriminator for the union of plan shapes.
//! - `status` — `"ready"` or `"needs_clarification"`.
//! - `summary_zh` — short Chinese sentence the UI renders next to the
//!   confirm button. Composed server-side to keep the model from inventing
//!   numbers.
//! - `warnings` — anything the dispatcher had to default or guess (e.g.
//!   "trade_date defaulted to today"). Surfaces back to the user.
//! - `missing` — fields the model still owes us. Used for required inputs
//!   that the dispatcher cannot infer (e.g. expense `amount`).
//! - `candidates` — populated when `status = needs_clarification`.
//!
//! The actual writes still go through the mobile-side repositories
//! (`TradeEntryService.buildPlan` → `TransactionRepository.recordTrade`,
//! etc.) — see FIR-45 / FIR-63 / FIR-64 for the persistence layer this
//! integrates with.

use chrono::{DateTime, Utc};
use serde_json::{json, Value};
use uuid::Uuid;
use worker::{D1Database, D1Type};

use super::tools::ToolCtx;
use crate::error::AppError;

/// Closed list of expense categories supported in v1. Mirrors FIR-64's
/// initial taxonomy. `other` is a bucket for "我先记上，类目以后再说" so the
/// flow doesn't deadlock when the user really doesn't want to pick one.
const EXPENSE_CATEGORIES: &[(&str, &str)] = &[
    ("food", "餐饮"),
    ("transport", "交通"),
    ("housing", "房租"),
    ("entertainment", "娱乐"),
    ("medical", "医疗"),
    ("education", "教育"),
    ("shopping", "购物"),
    ("travel", "旅行"),
    ("other", "其它"),
];

/// Account types we let `propose_account_create` introduce. Restricted to
/// the values the mobile `AccountType` enum accepts so the proposal can be
/// applied without a downstream migration.
const ACCOUNT_TYPES: &[&str] = &[
    "brokerage",
    "bank",
    "cryptoWallet",
    "realEstate",
    "vehicle",
    "liability",
    "cash",
    "other",
];

/// Asset types whose value is updated by hand (no market backfill). Only
/// these are valid targets for `propose_asset_valuation`. Mirrors
/// `kManualValuationAssetTypes` on the mobile side.
const MANUAL_VALUATION_ASSET_TYPES: &[&str] = &[
    "cash",
    "realEstate",
    "vehicle",
    "bankDepositTerm",
    "bankDepositDemand",
    "wealthProduct",
];

/// Build the `propose_trade` plan.
///
/// Resolves the asset (by id or symbol/name) and the account (by id or
/// name) against D1. If either reference is ambiguous, returns a
/// clarification plan with `candidates`; otherwise returns a `ready` plan
/// whose `payload` matches the `Transaction` entity shape so the client can
/// hand it straight to `TradeEntryService.buildPlan`.
pub async fn propose_trade(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    let tx_type = require_str(input, "type")?;
    if !matches!(
        tx_type,
        "buy" | "sell" | "transferIn" | "transferOut" | "valuationAdjust"
    ) {
        return Err(AppError::BadRequest(format!(
            "propose_trade: unsupported transaction type '{tx_type}'"
        )));
    }
    let qty = require_num(input, "quantity")?;
    if qty <= 0.0 {
        return Err(AppError::BadRequest(
            "propose_trade: quantity must be > 0".into(),
        ));
    }
    let price = optional_num(input, "price");
    let fee = optional_num(input, "fee").unwrap_or(0.0);
    let tax = optional_num(input, "tax").unwrap_or(0.0);
    let note = optional_str(input, "note");

    let mut warnings: Vec<String> = Vec::new();

    let asset_match = resolve_asset(
        ctx.db,
        ctx.user_id,
        optional_str(input, "asset_id"),
        optional_str(input, "asset_symbol"),
        optional_str(input, "asset_name"),
    )
    .await?;
    let asset = match asset_match {
        Resolved::One(v) => v,
        Resolved::Many(candidates) => {
            return Ok(needs_clarification(
                "trade",
                "asset",
                "存在多个匹配的资产，请让用户选择具体哪一个。",
                candidates,
            ));
        }
        Resolved::None => {
            return Ok(needs_clarification(
                "trade",
                "asset",
                "未找到匹配的资产。可以请用户确认股票代码 / 名称，或先 propose_account_create + propose_asset_valuation 录入。",
                Vec::new(),
            ));
        }
    };

    let account_match = resolve_account(
        ctx.db,
        ctx.user_id,
        optional_str(input, "account_id"),
        optional_str(input, "account_name"),
    )
    .await?;
    let account = match account_match {
        Resolved::One(v) => v,
        Resolved::Many(candidates) => {
            return Ok(needs_clarification(
                "trade",
                "account",
                "存在多个匹配的账户，请让用户选择具体哪一个。",
                candidates,
            ));
        }
        Resolved::None => {
            return Ok(needs_clarification(
                "trade",
                "account",
                "未找到匹配的账户。先用 propose_account_create 创建一个，或让用户提供准确账户名。",
                Vec::new(),
            ));
        }
    };

    // Currency: prefer explicit input, fall back to the account currency, then
    // the asset currency. Record which one we used.
    let currency = optional_str(input, "currency")
        .map(str::to_string)
        .or_else(|| account.payload_str("currency").map(str::to_string))
        .or_else(|| asset.payload_str("currency").map(str::to_string))
        .unwrap_or_else(|| {
            warnings.push("currency 未指定，已默认 USD".into());
            "USD".into()
        });

    // Date: optional. If absent we don't fabricate one; clients render today
    // as a UI default. Empty `trade_date` is also a strong hint to the model
    // to reconfirm with the user, so we surface a warning.
    let trade_date = optional_str(input, "trade_date").map(str::to_string);
    if trade_date.is_none() {
        warnings.push("trade_date 未指定，前端将默认显示今天，请用户确认。".into());
    } else if let Some(d) = &trade_date {
        if parse_iso(d).is_none() {
            return Err(AppError::BadRequest(format!(
                "propose_trade: trade_date '{d}' is not RFC3339"
            )));
        }
    }

    if price.is_none() {
        warnings.push(
            "price 未指定，前端将根据 MarketDataService 回填交易日收盘价（用户可覆盖）。".into(),
        );
    }

    let payload = json!({
        "type":              tx_type,
        "asset_id":          asset.id,
        "asset_symbol":      asset.payload_str("symbol"),
        "asset_name":        asset.payload_str("name"),
        "account_id":        account.id,
        "account_name":      account.payload_str("name"),
        "quantity":          qty,
        "price":             price,
        "fee":               fee,
        "tax":               tax,
        "currency":          currency,
        "trade_date":        trade_date,
        "note":              note,
    });

    let summary = format!(
        "{action} {symbol}{qty}{price_phrase}{fee_phrase}（{account}）",
        action = match tx_type {
            "buy" => "买入",
            "sell" => "卖出",
            "transferIn" => "转入",
            "transferOut" => "转出",
            "valuationAdjust" => "估值调整",
            _ => tx_type,
        },
        symbol = asset
            .payload_str("symbol")
            .or_else(|| asset.payload_str("name"))
            .unwrap_or("(unknown)"),
        qty = format_args_qty(qty),
        price_phrase = match price {
            Some(p) => format!(" @ {p}"),
            None => String::new(),
        },
        fee_phrase = if fee > 0.0 {
            format!("，含手续费 {fee}")
        } else {
            String::new()
        },
        account = account.payload_str("name").unwrap_or("(unnamed account)"),
    );

    Ok(ready_plan("trade", summary, payload, warnings, Vec::new()))
}

/// Build the `propose_expense` plan.
///
/// Validates `category` against the closed list. Unknown / fuzzy values
/// trigger a `needs_clarification` response with the top-3 closest
/// candidates so the model can ask the user to pick.
pub async fn propose_expense(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    let amount = require_num(input, "amount")?;
    if amount <= 0.0 {
        return Err(AppError::BadRequest(
            "propose_expense: amount must be > 0".into(),
        ));
    }
    let raw_category = optional_str(input, "category");
    let note = optional_str(input, "note");

    let mut warnings: Vec<String> = Vec::new();

    let category = match raw_category {
        Some(c) => match match_expense_category(c) {
            CategoryMatch::Exact(slug) => slug.to_string(),
            CategoryMatch::Ambiguous(top3) => {
                let candidates: Vec<Value> = top3
                    .iter()
                    .map(|(slug, label)| {
                        json!({
                            "id":    slug,
                            "label": label,
                        })
                    })
                    .collect();
                return Ok(needs_clarification(
                    "expense",
                    "category",
                    format!(
                        "无法在 {} 个内置类目中确定 '{}'，请让用户从下面三个里选一个。",
                        EXPENSE_CATEGORIES.len(),
                        c
                    ),
                    candidates,
                ));
            }
        },
        None => {
            warnings.push("category 未指定，已默认归入「其它」（用户可在确认页改）。".into());
            "other".into()
        }
    };

    let account = match resolve_account(
        ctx.db,
        ctx.user_id,
        optional_str(input, "account_id"),
        optional_str(input, "account_name"),
    )
    .await?
    {
        Resolved::One(a) => Some(a),
        Resolved::Many(candidates) => {
            return Ok(needs_clarification(
                "expense",
                "account",
                "存在多个匹配的账户，请让用户选择具体哪一个。",
                candidates,
            ));
        }
        Resolved::None => {
            // Account is optional for an expense — user might not have linked
            // payment account yet. Let the client default to whatever account
            // it picks at confirm time, but warn so the model knows it owes
            // the user a follow-up question if it matters.
            warnings.push("account 未指定或未匹配；前端会让用户在确认页选择支付账户。".into());
            None
        }
    };

    let currency = optional_str(input, "currency")
        .map(str::to_string)
        .or_else(|| {
            account
                .as_ref()
                .and_then(|a| a.payload_str("currency"))
                .map(str::to_string)
        })
        .unwrap_or_else(|| {
            warnings.push("currency 未指定，已默认 CNY".into());
            "CNY".into()
        });

    let date = optional_str(input, "date").map(str::to_string);
    if let Some(d) = &date {
        if parse_iso(d).is_none() {
            return Err(AppError::BadRequest(format!(
                "propose_expense: date '{d}' is not RFC3339"
            )));
        }
    } else {
        warnings.push("date 未指定，前端将默认为今天。".into());
    }

    let payload = json!({
        "type":         "expense",
        "amount":       amount,
        "category":     category,
        "currency":     currency,
        "account_id":   account.as_ref().map(|a| a.id.clone()),
        "account_name": account.as_ref().and_then(|a| a.payload_str("name")),
        "date":         date,
        "note":         note,
    });

    let category_label = EXPENSE_CATEGORIES
        .iter()
        .find(|(slug, _)| *slug == category)
        .map(|(_, label)| *label)
        .unwrap_or("其它");
    let summary = format!(
        "记一笔{category_label}支出 {amount} {currency}{account_phrase}",
        account_phrase = match account.as_ref().and_then(|a| a.payload_str("name")) {
            Some(name) => format!("（{name}）"),
            None => String::new(),
        }
    );

    Ok(ready_plan(
        "expense",
        summary,
        payload,
        warnings,
        Vec::new(),
    ))
}

/// Build the `propose_liability_payment` plan.
pub async fn propose_liability_payment(
    ctx: &ToolCtx<'_>,
    input: &Value,
) -> Result<Value, AppError> {
    let amount = require_num(input, "amount")?;
    if amount <= 0.0 {
        return Err(AppError::BadRequest(
            "propose_liability_payment: amount must be > 0".into(),
        ));
    }
    let note = optional_str(input, "note");

    let mut warnings: Vec<String> = Vec::new();

    let liability = match resolve_liability(
        ctx.db,
        ctx.user_id,
        optional_str(input, "liability_id"),
        optional_str(input, "liability_name"),
    )
    .await?
    {
        Resolved::One(l) => l,
        Resolved::Many(candidates) => {
            return Ok(needs_clarification(
                "liability_payment",
                "liability",
                "存在多个匹配的负债，请让用户选择具体哪一笔。",
                candidates,
            ));
        }
        Resolved::None => {
            return Ok(needs_clarification(
                "liability_payment",
                "liability",
                "未找到匹配的负债。请让用户先在「负债」里录入这笔贷款 / 信用卡。",
                Vec::new(),
            ));
        }
    };

    // The payment may be served from a different account (e.g. paying the
    // mortgage from a savings account). Resolve when supplied, but it's
    // optional — the client UI will default to the liability's bound account
    // if any.
    let from_account = match resolve_account(
        ctx.db,
        ctx.user_id,
        optional_str(input, "from_account_id"),
        optional_str(input, "from_account_name"),
    )
    .await?
    {
        Resolved::One(a) => Some(a),
        Resolved::Many(candidates) => {
            return Ok(needs_clarification(
                "liability_payment",
                "from_account",
                "存在多个匹配的还款账户，请让用户选择具体哪一个。",
                candidates,
            ));
        }
        Resolved::None => {
            warnings.push("from_account 未指定，前端会让用户在确认页选择还款来源账户。".into());
            None
        }
    };

    let currency = optional_str(input, "currency")
        .map(str::to_string)
        .or_else(|| liability.payload_str("currency").map(str::to_string))
        .unwrap_or_else(|| {
            warnings.push("currency 未指定，已默认 CNY".into());
            "CNY".into()
        });

    let date = optional_str(input, "date").map(str::to_string);
    if let Some(d) = &date {
        if parse_iso(d).is_none() {
            return Err(AppError::BadRequest(format!(
                "propose_liability_payment: date '{d}' is not RFC3339"
            )));
        }
    } else {
        warnings.push("date 未指定，前端将默认为今天。".into());
    }

    let payload = json!({
        "type":              "liabilityPayment",
        "liability_id":      liability.id,
        "liability_name":    liability.payload_str("name"),
        "from_account_id":   from_account.as_ref().map(|a| a.id.clone()),
        "from_account_name": from_account.as_ref().and_then(|a| a.payload_str("name")),
        "amount":            amount,
        "currency":          currency,
        "date":              date,
        "note":              note,
    });

    let summary = format!(
        "向「{name}」还款 {amount} {currency}",
        name = liability.payload_str("name").unwrap_or("(unnamed)")
    );

    Ok(ready_plan(
        "liability_payment",
        summary,
        payload,
        warnings,
        Vec::new(),
    ))
}

/// Build the `propose_account_create` plan.
pub async fn propose_account_create(_ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    let name = require_str(input, "name")?;
    if name.trim().is_empty() {
        return Err(AppError::BadRequest(
            "propose_account_create: name must not be blank".into(),
        ));
    }
    let acct_type = require_str(input, "type")?;
    if !ACCOUNT_TYPES.contains(&acct_type) {
        return Ok(needs_clarification(
            "account_create",
            "type",
            format!("'{acct_type}' 不是合法的账户类型，请让用户从这些里选："),
            ACCOUNT_TYPES
                .iter()
                .map(|t| json!({"id": t, "label": t}))
                .collect(),
        ));
    }
    let currency = optional_str(input, "currency")
        .map(str::to_string)
        .unwrap_or_else(|| "CNY".into());
    let institution = optional_str(input, "institution");
    let note = optional_str(input, "note");

    let mut warnings: Vec<String> = Vec::new();
    if optional_str(input, "currency").is_none() {
        warnings.push("currency 未指定，已默认 CNY".into());
    }

    // Pre-allocate the entity id so the client and any follow-up
    // proposals (e.g. `propose_trade` referencing the just-created account)
    // can refer to it without a round trip.
    let new_id = Uuid::new_v4().to_string();

    let payload = json!({
        "id":          new_id,
        "name":        name,
        "type":        acct_type,
        "currency":    currency,
        "institution": institution,
        "note":        note,
    });

    let summary = format!("创建账户「{name}」（{acct_type} / {currency}）");

    Ok(ready_plan(
        "account_create",
        summary,
        payload,
        warnings,
        Vec::new(),
    ))
}

/// Build the `propose_asset_valuation` plan — only valid for assets whose
/// price is updated manually (cash, real estate, vehicle, deposits, wealth
/// products). Securities go through `propose_trade` with
/// `type=valuationAdjust`.
pub async fn propose_asset_valuation(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    let new_value = require_num(input, "new_value")?;
    if new_value < 0.0 {
        return Err(AppError::BadRequest(
            "propose_asset_valuation: new_value must be ≥ 0".into(),
        ));
    }
    let mut warnings: Vec<String> = Vec::new();

    let asset = match resolve_asset(
        ctx.db,
        ctx.user_id,
        optional_str(input, "asset_id"),
        optional_str(input, "asset_symbol"),
        optional_str(input, "asset_name"),
    )
    .await?
    {
        Resolved::One(a) => a,
        Resolved::Many(candidates) => {
            return Ok(needs_clarification(
                "asset_valuation",
                "asset",
                "存在多个匹配的资产，请让用户选择具体哪一个。",
                candidates,
            ));
        }
        Resolved::None => {
            return Ok(needs_clarification(
                "asset_valuation",
                "asset",
                "未找到匹配的资产。如果是新资产，请先用 propose_account_create 建立资产 / 账户。",
                Vec::new(),
            ));
        }
    };

    if let Some(asset_type) = asset.payload_str("type") {
        if !MANUAL_VALUATION_ASSET_TYPES.contains(&asset_type) {
            return Err(AppError::BadRequest(format!(
                "propose_asset_valuation: '{asset_type}' 不支持手工估值（请改用 propose_trade type=valuationAdjust）"
            )));
        }
    }

    let currency = optional_str(input, "currency")
        .map(str::to_string)
        .or_else(|| asset.payload_str("currency").map(str::to_string))
        .unwrap_or_else(|| {
            warnings.push("currency 未指定，已默认 CNY".into());
            "CNY".into()
        });

    let date = optional_str(input, "date").map(str::to_string);
    if let Some(d) = &date {
        if parse_iso(d).is_none() {
            return Err(AppError::BadRequest(format!(
                "propose_asset_valuation: date '{d}' is not RFC3339"
            )));
        }
    } else {
        warnings.push("date 未指定，前端将默认为今天。".into());
    }

    let payload = json!({
        "type":         "asset_valuation",
        "asset_id":     asset.id,
        "asset_name":   asset.payload_str("name").or_else(|| asset.payload_str("symbol")),
        "new_value":    new_value,
        "currency":     currency,
        "date":         date,
        "note":         optional_str(input, "note"),
    });

    let summary = format!(
        "更新「{name}」估值为 {new_value} {currency}",
        name = asset
            .payload_str("name")
            .or_else(|| asset.payload_str("symbol"))
            .unwrap_or("(unnamed asset)")
    );

    Ok(ready_plan(
        "asset_valuation",
        summary,
        payload,
        warnings,
        Vec::new(),
    ))
}

// ---------------------------------------------------------------------------
// Reference resolution. Returns Many for ambiguous matches so the dispatcher
// can ask the user to disambiguate before any write happens.
// ---------------------------------------------------------------------------

/// A row pulled from a materialised sync table along with its parsed JSON
/// payload. Kept thin — most callers only need `id` and a couple of payload
/// fields.
pub struct EntityRow {
    pub id: String,
    pub payload: Value,
}

impl EntityRow {
    fn payload_str(&self, key: &str) -> Option<&str> {
        self.payload.get(key).and_then(|v| v.as_str())
    }
}

enum Resolved {
    One(EntityRow),
    Many(Vec<Value>),
    None,
}

#[derive(serde::Deserialize)]
struct PayloadRow {
    id: String,
    payload: String,
}

async fn load_table(
    db: &D1Database,
    user_id: &str,
    table: &str,
) -> Result<Vec<EntityRow>, AppError> {
    let sql = format!(
        "SELECT id, payload FROM {table} \
         WHERE user_id = ?1 AND deleted_at IS NULL"
    );
    let rows: Vec<PayloadRow> = db
        .prepare(&sql)
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        .all()
        .await
        .map_err(|e| AppError::Internal(format!("d1 all: {e}")))?
        .results()
        .map_err(|e| AppError::Internal(format!("d1 results: {e}")))?;
    Ok(rows
        .into_iter()
        .map(|r| EntityRow {
            id: r.id,
            payload: serde_json::from_str(&r.payload).unwrap_or(Value::Null),
        })
        .collect())
}

async fn resolve_account(
    db: &D1Database,
    user_id: &str,
    by_id: Option<&str>,
    by_name: Option<&str>,
) -> Result<Resolved, AppError> {
    let rows = load_table(db, user_id, "accounts").await?;
    Ok(narrow_rows(rows, by_id, by_name, |r, n| {
        r.payload_str("name").is_some_and(|x| name_matches(x, n))
    }))
}

async fn resolve_liability(
    db: &D1Database,
    user_id: &str,
    by_id: Option<&str>,
    by_name: Option<&str>,
) -> Result<Resolved, AppError> {
    let rows = load_table(db, user_id, "liabilities").await?;
    Ok(narrow_rows(rows, by_id, by_name, |r, n| {
        r.payload_str("name").is_some_and(|x| name_matches(x, n))
    }))
}

async fn resolve_asset(
    db: &D1Database,
    user_id: &str,
    by_id: Option<&str>,
    by_symbol: Option<&str>,
    by_name: Option<&str>,
) -> Result<Resolved, AppError> {
    let rows = load_table(db, user_id, "assets").await?;
    if let Some(id) = by_id {
        if let Some(r) = rows.into_iter().find(|r| r.id == id) {
            return Ok(Resolved::One(r));
        }
        return Ok(Resolved::None);
    }
    let needle = by_symbol.or(by_name);
    let Some(needle) = needle else {
        return Ok(Resolved::None);
    };
    let matches: Vec<EntityRow> = rows
        .into_iter()
        .filter(|r| {
            r.payload_str("symbol")
                .is_some_and(|x| name_matches(x, needle))
                || r.payload_str("name")
                    .is_some_and(|x| name_matches(x, needle))
        })
        .collect();
    Ok(match matches.len() {
        0 => Resolved::None,
        1 => Resolved::One(matches.into_iter().next().unwrap()),
        _ => Resolved::Many(
            matches
                .into_iter()
                .take(8)
                .map(|r| {
                    json!({
                        "id":     r.id,
                        "symbol": r.payload_str("symbol"),
                        "name":   r.payload_str("name"),
                        "type":   r.payload_str("type"),
                    })
                })
                .collect(),
        ),
    })
}

fn narrow_rows<F>(
    rows: Vec<EntityRow>,
    by_id: Option<&str>,
    by_name: Option<&str>,
    name_filter: F,
) -> Resolved
where
    F: Fn(&EntityRow, &str) -> bool,
{
    if let Some(id) = by_id {
        if let Some(r) = rows.into_iter().find(|r| r.id == id) {
            return Resolved::One(r);
        }
        return Resolved::None;
    }
    let Some(needle) = by_name else {
        return Resolved::None;
    };
    let matches: Vec<EntityRow> = rows
        .into_iter()
        .filter(|r| name_filter(r, needle))
        .collect();
    match matches.len() {
        0 => Resolved::None,
        1 => Resolved::One(matches.into_iter().next().unwrap()),
        _ => Resolved::Many(
            matches
                .into_iter()
                .take(8)
                .map(|r| {
                    json!({
                        "id":   r.id,
                        "name": r.payload_str("name"),
                        "type": r.payload_str("type"),
                    })
                })
                .collect(),
        ),
    }
}

/// Case-insensitive contains-or-equals match. Good enough for the kind of
/// fuzzy matching users do verbally ("Citi" → "Citibank Checking"); the
/// candidate-list path catches any genuine ambiguity.
fn name_matches(haystack: &str, needle: &str) -> bool {
    let h = haystack.to_lowercase();
    let n = needle.to_lowercase();
    h == n || h.contains(&n) || n.contains(&h)
}

// ---------------------------------------------------------------------------
// Categories — fuzzy match against the closed list with top-3 fallback.
// ---------------------------------------------------------------------------

enum CategoryMatch {
    Exact(&'static str),
    Ambiguous(Vec<(&'static str, &'static str)>),
}

fn match_expense_category(input: &str) -> CategoryMatch {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return CategoryMatch::Ambiguous(top3_categories(trimmed));
    }
    let lc = trimmed.to_lowercase();

    // Exact slug or label match.
    for (slug, label) in EXPENSE_CATEGORIES {
        if slug.eq_ignore_ascii_case(trimmed) || *label == trimmed {
            return CategoryMatch::Exact(slug);
        }
    }
    // Single substring match — accept it as exact.
    let substrings: Vec<&(&str, &str)> = EXPENSE_CATEGORIES
        .iter()
        .filter(|(slug, label)| {
            slug.to_lowercase().contains(&lc)
                || label.contains(trimmed)
                || lc.contains(&slug.to_lowercase())
        })
        .collect();
    if substrings.len() == 1 {
        return CategoryMatch::Exact(substrings[0].0);
    }
    CategoryMatch::Ambiguous(top3_categories(trimmed))
}

fn top3_categories(_seed: &str) -> Vec<(&'static str, &'static str)> {
    // We don't have an embedding model in the Worker. Return the first three
    // generic catch-all categories — the model has the conversation context
    // and can pick the best one to suggest. Always include `other` so the
    // user has an escape hatch.
    vec![
        EXPENSE_CATEGORIES[0],
        EXPENSE_CATEGORIES[6],
        *EXPENSE_CATEGORIES.last().unwrap(),
    ]
}

// ---------------------------------------------------------------------------
// Plan envelope helpers.
// ---------------------------------------------------------------------------

fn ready_plan(
    kind: &str,
    summary_zh: String,
    payload: Value,
    warnings: Vec<String>,
    missing: Vec<String>,
) -> Value {
    json!({
        "proposal_id": Uuid::new_v4().to_string(),
        "kind":        kind,
        "status":      "ready",
        "summary_zh":  summary_zh,
        "payload":     payload,
        "warnings":    warnings,
        "missing":     missing,
        "candidates":  Value::Null,
        "note":        "前端必须显示 summary_zh 给用户确认；只有用户明确点确认后才走 Repository。",
    })
}

fn needs_clarification(
    kind: &str,
    field: &str,
    reason: impl Into<String>,
    candidates: Vec<Value>,
) -> Value {
    json!({
        "proposal_id":      Uuid::new_v4().to_string(),
        "kind":             kind,
        "status":           "needs_clarification",
        "ambiguous_field":  field,
        "reason":           reason.into(),
        "candidates":       candidates,
        "note":             "请向用户提一个具体问题来澄清此字段；不要替用户做选择。",
    })
}

// ---------------------------------------------------------------------------
// Input plumbing.
// ---------------------------------------------------------------------------

fn require_str<'a>(v: &'a Value, key: &str) -> Result<&'a str, AppError> {
    v.get(key)
        .and_then(|x| x.as_str())
        .ok_or_else(|| AppError::BadRequest(format!("missing or non-string field '{key}'")))
}

fn optional_str<'a>(v: &'a Value, key: &str) -> Option<&'a str> {
    v.get(key)
        .and_then(|x| x.as_str())
        .filter(|s| !s.is_empty())
}

fn require_num(v: &Value, key: &str) -> Result<f64, AppError> {
    optional_num(v, key)
        .ok_or_else(|| AppError::BadRequest(format!("missing or non-numeric field '{key}'")))
}

fn optional_num(v: &Value, key: &str) -> Option<f64> {
    match v.get(key)? {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.parse().ok(),
        _ => None,
    }
}

fn parse_iso(s: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|d| d.with_timezone(&Utc))
}

fn format_args_qty(qty: f64) -> String {
    if (qty - qty.round()).abs() < 1e-9 {
        format!(" {} 股", qty as i64)
    } else {
        format!(" {qty}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn match_expense_category_exact_slug() {
        assert!(matches!(
            match_expense_category("food"),
            CategoryMatch::Exact("food")
        ));
    }

    #[test]
    fn match_expense_category_exact_label() {
        assert!(matches!(
            match_expense_category("餐饮"),
            CategoryMatch::Exact("food")
        ));
    }

    #[test]
    fn match_expense_category_unknown_returns_three_candidates() {
        match match_expense_category("玄学") {
            CategoryMatch::Ambiguous(c) => assert_eq!(c.len(), 3),
            _ => panic!("expected ambiguous"),
        }
    }

    #[test]
    fn name_matches_is_case_insensitive_substring() {
        assert!(name_matches("Citibank Checking", "citi"));
        assert!(name_matches("茅台", "茅台"));
        assert!(!name_matches("Chase", "Citi"));
    }

    #[test]
    fn ready_plan_round_trip() {
        let p = ready_plan(
            "trade",
            "买入 AAPL 100 股".into(),
            json!({"x": 1}),
            vec!["price defaulted".into()],
            vec![],
        );
        assert_eq!(p["status"], "ready");
        assert_eq!(p["kind"], "trade");
        assert!(p["proposal_id"].as_str().unwrap().len() == 36);
        assert!(p["candidates"].is_null());
    }

    #[test]
    fn needs_clarification_carries_candidates() {
        let p = needs_clarification(
            "trade",
            "asset",
            "ambiguous",
            vec![json!({"id": "a1", "name": "AAA"})],
        );
        assert_eq!(p["status"], "needs_clarification");
        assert_eq!(p["ambiguous_field"], "asset");
        assert_eq!(p["candidates"].as_array().unwrap().len(), 1);
    }
}
