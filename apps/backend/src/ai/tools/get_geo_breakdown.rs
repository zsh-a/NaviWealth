use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetGeoBreakdownTool;

pub(crate) const DESCRIPTION: &str =
    "按 asset.region 分组聚合当前持仓的记账成本，返回每个地区的占比。";

fn input_schema() -> Value {
    json!({"type": "object", "properties": {}})
}

#[async_trait(?Send)]
impl Tool for GetGeoBreakdownTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_geo_breakdown",
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
        impls::get_breakdown(ctx, impls::BreakdownDim::Region).await
    }
}
