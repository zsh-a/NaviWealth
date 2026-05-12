use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetAnomalyFlagsTool;

pub(crate) const DESCRIPTION: &str = "返回端侧 detector 检测到的支出 / 现金流异常。\
                          数据来自 AI Read Model `anomaly_flags`（Analytical 层 P1）—— \
                          device-sourced：端侧（如 expenseAnomalyInsightProvider）跑启发式 → \
                          ContextPack.analytical_uploads 上报 → 后端镜像。\
                          payload.kind 包含 monthly_spike / subscription_price_up / cashflow_anomaly 等。\
                          可选 severity_min 过滤（info ≤ warn ≤ critical）。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "severity_min": {
                "type": "string",
                "enum": ["info", "warn", "critical"],
                "description": "最低严重度（含），默认全部。"
            }
        }
    })
}

#[async_trait(?Send)]
impl Tool for GetAnomalyFlagsTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_anomaly_flags",
            access: Access::Read,
            risk: RiskLevel::Suggest,
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
        impls::get_anomaly_flags(ctx, &input).await
    }
}
