use async_trait::async_trait;
use serde_json::{json, Value};

use super::registry::Tool;
use super::ToolCtx;
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::ai::{context::BudgetTier, context::RiskLevel, proposals};
use crate::error::AppError;

pub struct ProposeLiabilityPaymentTool;

pub(crate) const DESCRIPTION: &str =
    "提议一笔负债还款（房贷、信用卡、消费贷等）。返回 plan，前端确认后走还款流程。\
                          liability 通过 liability_id 或 liability_name 指认；金额 > 0。";

pub fn schema() -> crate::ai::adapters::anthropic::wire::ToolSchema {
    crate::ai::adapters::anthropic::wire::ToolSchema {
        name: "propose_liability_payment".into(),
        description: DESCRIPTION.into(),
        input_schema: input_schema(),
    }
}

fn input_schema() -> Value {
    json!({
        "type": "object",
        "required": ["amount"],
        "properties": {
            "liability_id":      { "type": "string" },
            "liability_name":    { "type": "string" },
            "from_account_id":   { "type": "string", "description": "还款来源账户" },
            "from_account_name": { "type": "string" },
            "amount":            { "type": "number", "minimum": 0 },
            "currency":          { "type": "string" },
            "date":              { "type": "string", "description": "ISO-8601" },
            "note":              { "type": "string" }
        }
    })
}

#[async_trait(?Send)]
impl Tool for ProposeLiabilityPaymentTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "propose_liability_payment",
            access: Access::Propose,
            risk: RiskLevel::Propose,
            requires_confirmation: Confirmation::OneTap,
            allowed_context_tier: BudgetTier::Standard,
            allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
            side_effect: SideEffect::DeviceLocalWrite,
            read_model_layer: None,
        }
    }

    fn input_schema(&self) -> Value {
        input_schema()
    }

    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError> {
        proposals::propose_liability_payment(ctx, &input).await
    }
}
