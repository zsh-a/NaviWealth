use async_trait::async_trait;
use serde::Deserialize;
use serde_json::{json, Value};
use worker::D1Type;

use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct ListPaymentAccountsTool;

pub(crate) const DESCRIPTION: &str =
    "列出可用于记录支出的支付账户候选。只在用户要记消费但没有指定支付账户时调用；\
     返回非系统、未归档、未删除的资产侧账户（现金 / 银行 / 券商 / 加密等），可按币种过滤。\
     如果返回空，再询问用户要创建哪种支付账户。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "required": ["purpose"],
        "properties": {
            "purpose": {
                "type": "string",
                "enum": ["record_expense", "account_selection"],
                "description": "调用目的；用于审计和约束模型只在选择支付账户时读取。"
            },
            "currency": {
                "type": "string",
                "description": "可选；按账户币种过滤，例如 CNY。"
            },
            "max_results": {
                "type": "integer",
                "minimum": 1,
                "maximum": 20,
                "default": 8
            }
        }
    })
}

#[async_trait(?Send)]
impl Tool for ListPaymentAccountsTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "list_payment_accounts",
            access: Access::Read,
            risk: RiskLevel::Info,
            requires_confirmation: Confirmation::None,
            allowed_context_tier: BudgetTier::Standard,
            allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
            side_effect: SideEffect::None,
            read_model_layer: None,
        }
    }

    fn input_schema(&self) -> Value {
        input_schema()
    }

    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError> {
        list_payment_accounts(ctx, &input).await
    }
}

#[derive(Deserialize)]
struct PayloadRow {
    id: String,
    payload: String,
}

struct AccountCandidate {
    id: String,
    name: Option<String>,
    account_type: Option<String>,
    currency: Option<String>,
}

async fn list_payment_accounts(ctx: &ToolCtx<'_>, input: &Value) -> Result<Value, AppError> {
    let purpose = input
        .get("purpose")
        .and_then(Value::as_str)
        .ok_or_else(|| AppError::BadRequest("list_payment_accounts: purpose is required".into()))?;
    if !matches!(purpose, "record_expense" | "account_selection") {
        return Err(AppError::BadRequest(format!(
            "list_payment_accounts: unsupported purpose '{purpose}'"
        )));
    }

    let currency_filter = input
        .get("currency")
        .and_then(Value::as_str)
        .map(|s| s.trim().to_ascii_uppercase())
        .filter(|s| !s.is_empty());
    let max_results = input
        .get("max_results")
        .and_then(Value::as_u64)
        .unwrap_or(8)
        .clamp(1, 20) as usize;

    let rows: Vec<PayloadRow> = ctx
        .db
        .prepare(
            "SELECT id, payload FROM accounts \
             WHERE user_id = ?1 AND deleted_at IS NULL AND id NOT LIKE 'system-account:%'",
        )
        .bind_refs([&D1Type::Text(ctx.user_id)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        .all()
        .await
        .map_err(|e| AppError::Internal(format!("d1 all: {e}")))?
        .results()
        .map_err(|e| AppError::Internal(format!("d1 results: {e}")))?;

    let mut accounts: Vec<AccountCandidate> = rows
        .into_iter()
        .filter_map(|row| {
            let payload: Value = serde_json::from_str(&row.payload).ok()?;
            if payload.get("archived").and_then(Value::as_bool) == Some(true) {
                return None;
            }
            if payload.get("category").and_then(Value::as_str) != Some("asset") {
                return None;
            }
            if payload.get("type").and_then(Value::as_str) == Some("asset") {
                return None;
            }
            let currency = payload
                .get("currency")
                .and_then(Value::as_str)
                .map(str::to_string);
            if let Some(filter) = &currency_filter {
                match currency.as_deref() {
                    Some(c) if c.eq_ignore_ascii_case(filter) => {}
                    _ => return None,
                }
            }
            Some(AccountCandidate {
                id: row.id,
                name: payload
                    .get("name")
                    .and_then(Value::as_str)
                    .map(str::to_string),
                account_type: payload
                    .get("type")
                    .and_then(Value::as_str)
                    .map(str::to_string),
                currency,
            })
        })
        .collect();

    accounts.sort_by(|a, b| {
        a.name
            .as_deref()
            .unwrap_or("")
            .cmp(b.name.as_deref().unwrap_or(""))
            .then_with(|| a.id.cmp(&b.id))
    });

    let total = accounts.len();
    let values: Vec<Value> = accounts
        .into_iter()
        .take(max_results)
        .map(|account| {
            json!({
                "id":       account.id,
                "name":     account.name,
                "type":     account.account_type,
                "currency": account.currency,
            })
        })
        .collect();

    Ok(json!({
        "status": "ready",
        "purpose": purpose,
        "currency_filter": currency_filter,
        "total_count": total,
        "truncated": total > values.len(),
        "accounts": values,
        "note": "这些是可作为支出支付来源的账户；如果用户没有指定支付账户，请让用户从候选里选择，或用 account_id 调用 propose_expense。",
    }))
}
