use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetRiskAlertsTool;

pub(crate) const DESCRIPTION: &str =
    "扫描当前持仓集中度并返回风险预警列表：单一资产或单一行业占比 > 20% 即触发 warning。";

fn input_schema() -> Value {
    json!({"type": "object", "properties": {}})
}

#[async_trait(?Send)]
impl Tool for GetRiskAlertsTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_risk_alerts",
            access: Access::Read,
            risk: RiskLevel::Suggest,
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
        impls::get_risk_alerts(ctx).await
    }
}
