use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetCashflowBucketsTool;

pub(crate) const DESCRIPTION: &str = "返回最近 N 个月的现金 inflow / outflow 分桶。\
                          数据来自 AI Read Model `cashflow_buckets`（Snapshot 层 P1）—— \
                          月粒度，每月按币种独立累加 inflow (units > 0) 与 outflow (abs(units < 0))，\
                          各自带笔数。与 net_worth_snapshot 互补：本工具回答\
                          「钱从哪来、往哪去」，net_worth 回答「累计净走向」。\
                          典型问题：「上个月主要支出方向」「每月平均收入多少」「这季度有几次大额支出」。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "months_back": {
                "type": "integer",
                "minimum": 1,
                "maximum": 24,
                "default": 6,
                "description": "返回最近多少个月。默认 6。"
            },
            "currency": {
                "type": "string",
                "description": "可选；只返回某一币种。默认所有币种。"
            }
        }
    })
}

#[async_trait(?Send)]
impl Tool for GetCashflowBucketsTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_cashflow_buckets",
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
        impls::get_cashflow_buckets(ctx, &input).await
    }
}
