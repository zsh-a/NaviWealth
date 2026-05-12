use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct ComputeXirrTool;

pub(crate) const DESCRIPTION: &str = "对指定范围内的现金流计算 XIRR（年化内部收益率）。\
                          backend 实现为单币种简化版：从 postings 中抽取现金流，\
                          以 Newton 法求解贴现率。跨币种精确版本由 postings-derived returns read model 提供。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "scope": {
                "type": "string",
                "enum": ["portfolio", "asset"],
                "default": "portfolio"
            },
            "asset_id": {
                "type": "string",
                "description": "scope=asset 时必填"
            },
            "from": { "type": "string", "description": "ISO-8601 lower bound" },
            "to":   { "type": "string", "description": "ISO-8601 upper bound" },
            "base_currency": {
                "type": "string",
                "description": "需要跨币种汇总时的目标币种；优先使用 portfolio_snapshot 中的 base 折算。"
            }
        }
    })
}

#[async_trait(?Send)]
impl Tool for ComputeXirrTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "compute_xirr",
            access: Access::Read,
            risk: RiskLevel::Info,
            requires_confirmation: Confirmation::None,
            allowed_context_tier: BudgetTier::Standard,
            allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
            side_effect: SideEffect::None,
            read_model_layer: None,
        }
    }

    fn input_schema(&self) -> Value {
        input_schema()
    }

    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError> {
        impls::compute_xirr(ctx, &input).await
    }
}
