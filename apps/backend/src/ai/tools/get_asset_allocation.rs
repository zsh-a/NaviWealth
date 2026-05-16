use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetAssetAllocationTool;

pub(crate) const DESCRIPTION: &str = "按 asset.type（stock / etf / crypto / cash / ...）+ currency 双键聚合\
                          当前持仓的 cost_basis_minor。数据来自 AI Read Model \
                          `asset_allocation_snapshot`（Snapshot 层 P1，cloud-projected）。\
                          weight 在同 currency 内归一（sum==1 within currency），\
                          跨币种不直接相加（云端没有 FX 源）。\
                          典型问题：「我的股票/加密占比」「USD 仓位最大头是哪类」「股票总成本多少」。\
                          单位是 **成本** 而非市值；市值需配合端侧价格数据计算。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "bucket_dim": {
                "type": "string",
                "enum": ["asset_type"],
                "default": "asset_type",
                "description": "桶维度。当前只有 asset_type。预留 industry / region。"
            }
        }
    })
}

#[async_trait(?Send)]
impl Tool for GetAssetAllocationTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_asset_allocation",
            access: Access::Read,
            risk: RiskLevel::Info,
            requires_confirmation: Confirmation::None,
            allowed_context_tier: BudgetTier::Small,
            allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
            side_effect: SideEffect::None,
            read_model_layer: Some(crate::ai::policy::ReadModelLayer::Snapshot),
        }
    }

    fn input_schema(&self) -> Value {
        input_schema()
    }

    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError> {
        impls::get_asset_allocation(ctx, &input).await
    }
}
