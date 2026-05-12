use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetRefundLinksTool;

pub(crate) const DESCRIPTION: &str = "返回端侧 refundMatcher 检测到的「原交易 ↔ 退款」配对。\
                          数据来自 AI Read Model `refund_links`（Analytical P1，device-sourced）。\
                          payload 含 original_txn_id / refund_txn_id / amount_minor / currency。\
                          典型问题：「哪些退款还在路上」「最近退了多少」「这笔退款对应哪次买入」。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "currency": { "type": "string", "description": "可选；只看某一币种。" }
        }
    })
}

#[async_trait(?Send)]
impl Tool for GetRefundLinksTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_refund_links",
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
        impls::get_refund_links(ctx, &input).await
    }
}
