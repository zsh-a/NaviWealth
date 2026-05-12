use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct ComputeNetWorthTool;

pub(crate) const DESCRIPTION: &str =
    "净资产时间序列：在指定区间内按粒度采样，每个采样点上把账户的累计现金流减去负债余额。\
                          返回 list of {date, value, currency}。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "from":        { "type": "string", "description": "ISO-8601 起始（含）" },
            "to":          { "type": "string", "description": "ISO-8601 结束（含）" },
            "granularity": { "type": "string", "enum": ["day", "week", "month"], "default": "month" },
            "base_currency": {
                "type": "string",
                "description": "需要跨币种汇总时的目标币种；优先使用 portfolio_snapshot 中的当前 base 市值。"
            }
        }
    })
}

#[async_trait(?Send)]
impl Tool for ComputeNetWorthTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "compute_net_worth",
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
        impls::compute_net_worth(ctx, &input).await
    }
}
