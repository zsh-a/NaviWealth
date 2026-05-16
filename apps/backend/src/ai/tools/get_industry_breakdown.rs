use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetIndustryBreakdownTool;

pub(crate) const DESCRIPTION: &str =
    "按 asset.industry 分组聚合当前股票/ETF 持仓的记账成本，返回每个行业的占比与币种。";

fn input_schema() -> Value {
    json!({"type": "object", "properties": {}})
}

#[async_trait(?Send)]
impl Tool for GetIndustryBreakdownTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_industry_breakdown",
            access: Access::Read,
            risk: RiskLevel::Info,
            requires_confirmation: Confirmation::None,
            allowed_context_tier: BudgetTier::Standard,
            allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
            side_effect: SideEffect::None,
            read_model_layer: Some(crate::ai::policy::ReadModelLayer::Snapshot),
        }
    }

    fn input_schema(&self) -> Value {
        input_schema()
    }

    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError> {
        let _ = input;
        impls::get_breakdown(ctx, impls::BreakdownDim::Industry).await
    }
}
