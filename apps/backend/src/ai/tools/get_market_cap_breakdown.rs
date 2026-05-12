use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetMarketCapBreakdownTool;

pub(crate) const DESCRIPTION: &str =
    "按市值分类（large/mid/small/unknown）聚合当前股票持仓的记账成本。\
                          分类来自 asset.metadata_json.market_cap，缺失时归入 unknown。";

fn input_schema() -> Value {
    json!({"type": "object", "properties": {}})
}

#[async_trait(?Send)]
impl Tool for GetMarketCapBreakdownTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_market_cap_breakdown",
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
        impls::get_breakdown(ctx, impls::BreakdownDim::MarketCap).await
    }
}
