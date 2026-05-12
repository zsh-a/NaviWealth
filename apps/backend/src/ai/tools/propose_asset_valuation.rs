use async_trait::async_trait;
use serde_json::{json, Value};

use super::registry::Tool;
use super::ToolCtx;
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::ai::{context::BudgetTier, context::RiskLevel, proposals};
use crate::error::AppError;

pub struct ProposeAssetValuationTool;

pub(crate) const DESCRIPTION: &str =
    "提议更新一个手工估值资产（房产 / 车 / 现金 / 银行存款 / 理财）的当前估值。\
                          有市场行情的证券请改用 propose_trade 的 valuationAdjust 类型。";

pub fn schema() -> crate::ai::anthropic::ToolSchema {
    crate::ai::anthropic::ToolSchema {
        name: "propose_asset_valuation".into(),
        description: DESCRIPTION.into(),
        input_schema: input_schema(),
    }
}

fn input_schema() -> Value {
    json!({
        "type": "object",
        "required": ["new_value"],
        "properties": {
            "asset_id":     { "type": "string" },
            "asset_symbol": { "type": "string" },
            "asset_name":   { "type": "string" },
            "new_value":    { "type": "number", "minimum": 0 },
            "currency":     { "type": "string" },
            "date":         { "type": "string", "description": "ISO-8601" },
            "note":         { "type": "string" }
        }
    })
}

#[async_trait(?Send)]
impl Tool for ProposeAssetValuationTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "propose_asset_valuation",
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
        proposals::propose_asset_valuation(ctx, &input).await
    }
}
