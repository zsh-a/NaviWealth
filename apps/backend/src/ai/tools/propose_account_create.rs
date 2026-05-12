use async_trait::async_trait;
use serde_json::{json, Value};

use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::ai::proposals;
use crate::error::AppError;

pub struct ProposeAccountCreateTool;

pub(crate) const DESCRIPTION: &str =
    "提议创建一个新账户（券商 / 银行 / 现金 / 实物资产 / 负债）。返回 plan + 预分配 id。\
                          后续 propose_trade / propose_expense 可以引用这个 id。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "required": ["name", "type"],
        "properties": {
            "name":        { "type": "string" },
            "type":        {
                "type": "string",
                "enum": ["brokerage", "bank", "cryptoWallet", "realEstate", "vehicle", "liability", "cash", "other"]
            },
            "currency":    { "type": "string", "default": "CNY" },
            "institution": { "type": "string" },
            "note":        { "type": "string" }
        }
    })
}

#[async_trait(?Send)]
impl Tool for ProposeAccountCreateTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "propose_account_create",
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
        proposals::propose_account_create(ctx, &input).await
    }
}
