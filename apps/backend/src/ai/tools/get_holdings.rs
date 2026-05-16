use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetHoldingsTool;

pub(crate) const DESCRIPTION: &str =
    "返回当前持仓快照。优先使用客户端 portfolio_snapshot 中的持仓引擎结果；\
                          缺失时从 journal_entries / postings 推导近似值。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "as_of": {
                "type": "string",
                "description": "ISO-8601 截止时刻（含），不传则到当前时间。"
            },
            "base_currency": {
                "type": "string",
                "description": "希望返回的折算基准币种；snapshot 已带 base 值时会使用。"
            }
        }
    })
}

#[async_trait(?Send)]
impl Tool for GetHoldingsTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_holdings",
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
        impls::get_holdings(ctx, &input).await
    }
}
