use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetXirrSummaryTool;

pub(crate) const DESCRIPTION: &str = "返回当前 portfolio + 每个有现金流的 asset 的年化 XIRR (全时间窗口)。\
                          数据来自 AI Read Model `xirr_snapshot`（Analytical P2，cloud-projected —— \
                          与 device-sourced 不同，XIRR 是 Newton-Raphson 确定性算法，云端能直接 project）。\
                          每行: scope (portfolio 或 asset_id) + xirr (可能 null：单边/不收敛/数据不足) + \
                          flow_count + primary_currency + multi_currency。\
                          需要自定义时间窗的 XIRR 仍走 compute_xirr (legacy inline path).";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {}
    })
}

#[async_trait(?Send)]
impl Tool for GetXirrSummaryTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_xirr_summary",
            access: Access::Read,
            risk: RiskLevel::Info,
            requires_confirmation: Confirmation::None,
            allowed_context_tier: BudgetTier::Small,
            allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
            side_effect: SideEffect::None,
            read_model_layer: Some(crate::ai::policy::ReadModelLayer::Analytical),
        }
    }

    fn input_schema(&self) -> Value {
        input_schema()
    }

    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError> {
        impls::get_xirr_summary(ctx, &input).await
    }
}
