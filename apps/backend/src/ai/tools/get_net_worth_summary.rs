use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetNetWorthSummaryTool;

pub(crate) const DESCRIPTION: &str = "返回最近 N 个月的净现金流累计（月度净资产快照）。\
                          数据来自 AI Read Model `net_worth_snapshot`（Snapshot 层 P0）—— 月粒度，\
                          每月按币种独立累积。Phase 1 不减负债 / 不算资产市值（这两个走 compute_net_worth）。\
                          适合场景：「最近半年净现金流趋势」「上半年现金净流入多少」等月度问题。\
                          需要 day/week 粒度或资产市值时改用 compute_net_worth.";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "months_back": {
                "type": "integer",
                "minimum": 1,
                "maximum": 60,
                "default": 12,
                "description": "返回最近多少个月。默认 12。"
            },
            "currency": {
                "type": "string",
                "description": "可选；只返回某一币种。默认返回所有币种。"
            }
        }
    })
}

#[async_trait(?Send)]
impl Tool for GetNetWorthSummaryTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_net_worth_summary",
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
        impls::get_net_worth_summary(ctx, &input).await
    }
}
